#!/bin/bash
# Builds AeroSpace with patches/*.patch applied; with --install, swaps it into
# /Applications/AeroSpace.app (the original bundle is backed up first).
#
# bar-state.patch: pushes what the bar shows (workspaces with their monitor,
# visibility, focus and apps) to ~/.config/vsndbar over
# /tmp/bobko.aerospace-$USER-bar.sock: the current state on connect, then one
# JSON line per model change — no process per event.
#
# switch-flicker.patch: on a workspace switch AeroSpace moves every window via
# the accessibility API, asynchronously on one thread per app, and raises the
# focused window last. So a switch could show an empty desktop (old windows
# hidden before the new ones arrived) or the wrong window on top for a frame.
# The patch raises + places the target window before anything else is queued
# (and, in accordion layouts, lets its app finish that before the siblings are
# placed, ≤100ms), and hides the old windows only once the new ones are in
# place (≤150ms) — bottom-up where they overlap, so no lower window is ever
# revealed (≤80ms).
#
# back-and-forth.patch: `workspace --auto-back-and-forth N` pressed on N goes
# back to the previously focused workspace only if it still exists (upstream
# re-creates an empty one that was garbage collected).
#
# peek-on-hold.patch: a binding with `workspace --peek-on-hold N` held longer
# than `peekHoldThreshold` shows N only until its key is released, then goes
# back: workspace and window, what each monitor showed, the mouse, the
# back-and-forth history. A tap is unchanged; another binding or any focus
# change meanwhile keeps N.
#
# menu-bar.patch: a monitor's usable area ignores the menu bar (only the notch
# strip and the Dock count), so windows stay put when `vsndbar toggle` shows
# the system menu bar instead of the glass bar (gaps.outer.top clears it).
#
# monitors.patch: a hidden empty workspace belongs to the main monitor (so
# `workspace N` for a workspace the bar doesn't show opens it there), and a
# monitor that reconnects shows the workspace it showed before.
#
# queries.patch: `list-*` answer straight from the model instead of running a
# whole session (layout of every workspace + AX poll of every app) per query;
# the bar asks a few times per workspace switch. `list-windows` fetches window
# titles (an AX call per window) only when the format uses them.
#
# window-hiding.patch: AeroSpace hides windows in a bottom corner of their
# monitor, so with a monitor right below (an iPad above the laptop) hidden
# windows showed up on it. The patch picks the corner (bottom or top — beside
# the monitor, top aligned) where a hidden window covers the least of the other
# monitors.
#
# Signing uses the local "aerospace-local-codesign" certificate (login
# keychain, trusted for code signing), so the Accessibility grant survives
# rebuilds. Without it the build falls back to ad-hoc signing, and macOS asks
# for Accessibility again after every install: System Settings → Privacy &
# Security → Accessibility → AeroSpace.
#
# Usage: ./build.sh [--install | --restore] [git-ref]
#   default ref: the commit of the installed aerospace CLI
set -euo pipefail

install=0
restore_only=0
if [[ "${1:-}" == "--install" ]]; then install=1; shift; fi
if [[ "${1:-}" == "--restore" ]]; then restore_only=1; shift; fi

# AeroSpace doesn't remember which workspace each window was on across a
# restart (everything lands on the focused one), so installs snapshot the
# arrangement first and restore it once the new build is running.
LAYOUT_SNAPSHOT="$HOME/.cache/aerospace-layout.txt"

save_layout() {
  {
    echo "focus $(aerospace list-workspaces --focused) $(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null)"
    aerospace list-windows --all --format '%{window-id} %{workspace} %{window-layout}'
    aerospace list-workspaces --all --format 'monitor %{workspace} %{monitor-id} %{workspace-is-visible}'
  } > "$LAYOUT_SNAPSHOT.tmp" && mv "$LAYOUT_SNAPSHOT.tmp" "$LAYOUT_SNAPSHOT"
}

restore_layout() {
  [[ -s "$LAYOUT_SNAPSHOT" ]] || return 0
  # wait until the server answers and sees the snapshot's windows (needs
  # Accessibility); it finds apps' windows one by one, so the first window
  # isn't enough (the rest stayed on the focused workspace). ≤10s: windows
  # closed meanwhile never show up.
  local want known
  want="$(awk '$1 ~ /^[0-9]+$/ {print $1}' "$LAYOUT_SNAPSHOT" | sort)"
  for _ in {1..40}; do
    # (fails until the server answers, which must not end the script under set -e)
    known="$(aerospace list-windows --all --format '%{window-id}' 2>/dev/null | sort || true)"
    [[ -n "$known" && -z "$(comm -23 <(echo "$want") <(echo "$known"))" ]] && break
    sleep 0.25
  done
  local focus_ws="" focus_win="" id ws layout visible=()
  while read -r id ws layout; do
    if [[ "$id" == "focus" ]]; then focus_ws="$ws"; focus_win="$layout"; continue; fi
    [[ "$id" == "monitor" ]] && continue
    aerospace move-node-to-workspace --window-id "$id" "$ws" 2>/dev/null || true
  done < "$LAYOUT_SNAPSHOT"
  while read -r id ws layout; do
    [[ "$id" == "focus" || "$id" == "monitor" || -z "$layout" ]] && continue
    aerospace layout --window-id "$id" "$layout" 2>/dev/null || true
  done < "$LAYOUT_SNAPSHOT"
  # Workspaces back on their monitors ("monitor <ws> <monitor-id> <visible>"),
  # then each monitor shows what it showed before.
  local monitor is_visible
  while read -r id ws monitor is_visible; do
    [[ "$id" == "monitor" ]] || continue
    aerospace move-workspace-to-monitor --workspace "$ws" "$monitor" 2>/dev/null || true
    [[ "$is_visible" == true ]] && visible+=("$ws")
  done < "$LAYOUT_SNAPSHOT"
  # (bash 3.2 calls an empty "${visible[@]}" unbound under set -u)
  for ws in ${visible[@]+"${visible[@]}"}; do aerospace workspace "$ws" 2>/dev/null || true; done
  [[ -n "$focus_ws" ]] && aerospace workspace "$focus_ws" 2>/dev/null || true
  [[ -n "$focus_win" ]] && aerospace focus --window-id "$focus_win" 2>/dev/null || true
}

if [[ $restore_only == 1 ]]; then
  restore_layout
  echo "restored window arrangement from $LAYOUT_SNAPSHOT"
  exit 0
fi

APP=/Applications/AeroSpace.app
BACKUP="$HOME/.cache/aerospace-original.app"
SRC="$HOME/.cache/aerospace-src"
DIR="$(cd "$(dirname "$0")" && pwd)"

# version + commit of the installed (brew) client, so client and server match
read -r _ _ _ _ VERSION HASH < <(aerospace --version | head -1)
REF="${1:-$HASH}"

if [[ ! -d "$SRC/.git" ]]; then
  git clone -q https://github.com/nikitabobko/AeroSpace "$SRC"
fi
# fetch only when the commit isn't here yet (builds work offline)
git -C "$SRC" cat-file -e "$REF^{commit}" 2>/dev/null \
  || git -C "$SRC" fetch -q origin "$REF" 2>/dev/null || git -C "$SRC" fetch -q origin
git -C "$SRC" checkout -q --force "$REF"
git -C "$SRC" clean -qfdx -e .build

for p in "$DIR"/*.patch; do
  git -C "$SRC" apply "$p"
done

cat > "$SRC/Sources/Common/versionGenerated.swift" <<EOF
// FILE IS GENERATED BY generate.sh
public let aeroSpaceAppVersion = "$VERSION"
EOF
cat > "$SRC/Sources/Common/gitHashGenerated.swift" <<EOF
// FILE IS GENERATED BY generate.sh
public let gitHash = "$(git -C "$SRC" rev-parse HEAD)"
public let gitShortHash = "$(git -C "$SRC" rev-parse --short HEAD)"
EOF

# Command Line Tools are enough (no Xcode license needed).
# Remove the previous binary first: .build survives `git clean`, so a failed
# build must not leave an old binary looking like a fresh one.
BIN="$SRC/.build/release/AeroSpaceApp"
rm -f "$BIN"
LOG="$(mktemp)"
if ! (cd "$SRC" && env -u DEVELOPER_DIR swift build -c release --product AeroSpaceApp) >"$LOG" 2>&1; then
  grep -E "error" "$LOG" >&2 || tail -20 "$LOG" >&2
  echo "build failed (full log: $LOG)" >&2
  exit 1
fi
rm -f "$LOG"
[[ -x "$BIN" ]] || { echo "build produced no binary" >&2; exit 1; }
echo "built $BIN ($VERSION + patches)"

[[ $install == 1 ]] || exit 0

# A bundle signed by upstream is pristine: (re)take the backup from it, if it
# is the version being built (the binary is swapped into it).
bundle_version() { defaults read "$1/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true; }
signature="$(codesign -dvv "$APP" 2>&1 || true)"
if [[ "$signature" == *"Authority=aerospace-codesign-certificate"* && "$(bundle_version "$APP")" == "$VERSION" ]]; then
  rm -rf "$BACKUP" && cp -R "$APP" "$BACKUP"
fi
if [[ ! -d "$BACKUP" || "$(bundle_version "$BACKUP")" != "$VERSION" ]]; then
  echo "no pristine AeroSpace.app $VERSION to build on (expected at $BACKUP)" >&2
  exit 1
fi

IDENTITY="aerospace-local-codesign"
if ! security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
  echo "warning: no '$IDENTITY' certificate, signing ad-hoc" >&2
  IDENTITY="-"
fi
prev_signature="$(codesign -dvv "$APP" 2>&1 || true)"

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGE="$STAGE_DIR/AeroSpace.app"
cp -R "$BACKUP" "$STAGE"
cp "$BIN" "$STAGE/Contents/MacOS/AeroSpace"
codesign --force --sign "$IDENTITY" "$STAGE" 2>/dev/null
codesign --verify --deep --strict "$STAGE"

save_layout || true
old_pid="$(pgrep -x AeroSpace || true)"
osascript -e 'quit app "AeroSpace"' 2>/dev/null || true
for _ in {1..50}; do pgrep -xq AeroSpace || break; sleep 0.1; done
pkill -x AeroSpace 2>/dev/null || true
for _ in {1..30}; do pgrep -xq AeroSpace || break; sleep 0.1; done
pkill -9 -x AeroSpace 2>/dev/null || true
for _ in {1..20}; do pgrep -xq AeroSpace || break; sleep 0.1; done
if pgrep -xq AeroSpace; then
  echo "the running AeroSpace won't quit; nothing was changed" >&2
  exit 1
fi

rm -rf "$APP"
mv "$STAGE" "$APP"
# A grant is tied to the signer: reset it only when the signer changes (or on
# ad-hoc, where every build is a new identity), so macOS asks again cleanly.
if [[ "$IDENTITY" == "-" || "$prev_signature" != *"Authority=$IDENTITY"* ]]; then
  tccutil reset Accessibility bobko.aerospace >/dev/null 2>&1 || true
  regrant=1
fi
# the first launch can race with the old instance shutting down; a freshly
# signed binary's first launch also takes a few seconds (seen > 6s)
new_pid=""
for _ in 1 2 3; do
  open "$APP" || true
  for _ in {1..50}; do
    new_pid="$(pgrep -x AeroSpace || true)"
    [[ -n "$new_pid" && "$new_pid" != "$old_pid" ]] && break 2
    sleep 0.2
  done
done
if [[ -z "${new_pid:-}" || "$new_pid" == "$old_pid" ]]; then
  echo "installed $APP, but it did not start — open it manually" >&2
  exit 1
fi
if [[ -n "${regrant:-}" ]]; then
  echo "installed $APP — grant Accessibility to AeroSpace when macOS asks,"
  echo "then run: $0 --restore   (puts windows back on their workspaces)"
else
  restore_layout
  echo "installed $APP (Accessibility grant kept, window arrangement restored)"
fi
