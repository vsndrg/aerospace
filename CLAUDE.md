# CLAUDE.md

AeroSpace config (`aerospace.toml`) plus the patches the app is built with. It is the window-manager half of
[vsnd-setup](https://github.com/vsndrg/vsnd-setup) (local checkout: `~/.config/vsnd-setup`), which pins a commit of
this repo and installs it together with the bar ([vsndbar](https://github.com/vsndrg/vsndbar), `~/.config/vsndbar`).

## Layout

- `aerospace.toml` — the live config. Reload with `aerospace reload-config` (or `cmd-shift-c`); no rebuild needed
  unless it uses something a patch adds.
- `patches/*.patch` — against AeroSpace **0.20.3-Beta** (`6dde91ba`). `patches/build.sh` builds and installs them.
  Each patch is described in the header of `build.sh` and in the README's Patches table: keep both in sync.
- `open_chrome.sh` is bound to `cmd-b`. `resize_lr.sh` and `toggle_sketchybar.sh` are leftovers that nothing uses.

## Working on a patch

The source tree is `~/.cache/aerospace-src`. **`build.sh` runs `git checkout --force` + `git clean` there and then
applies every patch**, so edits that are only in that tree are lost on the next build. The `.patch` files are the
source of truth.

1. Run `patches/build.sh` (without `--install`) so the tree is pristine + all patches.
2. Edit the Swift sources there. Mark changes to upstream code with `// Patch (<name>): …`; new code goes in its own
   file.
3. Build it: `cd ~/.cache/aerospace-src && env -u DEVELOPER_DIR swift build -c release --product AeroSpaceApp`.
   Only the Command Line Tools are needed, not Xcode. SourceKit's "No such module 'Common'" in the editor is noise.
4. Regenerate the `.patch` from the tree. Never hand-edit or `sed` a `.patch` file.
   - Patches are applied **in alphabetical order, one after another**. A file that an earlier patch also touches
     must be diffed against the tree *with the earlier patches applied*: save a copy of that file before editing
     it, then `git diff --no-index` the copy against the edited file and fix the paths to `a/…`/`b/…`.
   - A new file: `git diff --no-index -- /dev/null <file>`.
5. Check that the whole set applies to a pristine tree: `git archive HEAD` of the source into a scratch directory,
   `git init`, `git apply` every patch in order, then compare the files with `~/.cache/aerospace-src`.
6. Install: `patches/build.sh --install`. It quits AeroSpace, swaps the binary into `/Applications/AeroSpace.app`
   (the pristine bundle stays in `~/.cache/aerospace-original.app`), restarts it and puts the windows back on their
   workspaces from `~/.cache/aerospace-layout.txt`.
   - Run it with its output going to a log. If the run gets interrupted after the restart, every window ends up on
     the focused workspace, and the next `--install` saves *that* as the snapshot. Check with
     `aerospace list-windows --all --format '%{workspace} %{app-name}'`; `patches/build.sh --restore` re-applies
     the snapshot.

Swift gotcha: inside a type, a global with the same name as one of the type's members (`focus`,
`prevFocusedWorkspaceDate`) has to be written as `AppBundle.<name>`.

## Testing key bindings

Physical keys aren't available, but synthesized ones trigger AeroSpace's Carbon hotkeys. A small Swift tool that
posts `CGEvent` key down/up with `.maskCommand` (cmd = keycode 55; the digits: 1 = 18, 3 = 20, 5 = 23), compiled
with `swiftc` in the scratchpad, can press, hold and release. Check the result with
`aerospace list-workspaces --focused`. Synthesized events don't autorepeat, and there is only one monitor here:
anything that depends on either (cross-monitor behavior, the mouse) needs the user to test it by hand.

## Conventions

- A tunable number lives in **one** named, documented constant in the patch's code. The config, `build.sh` and the
  README refer to it by name and never repeat the value.
- Commit subjects: `<area>: <what it does now>`, lowercase, no period. Examples: `build.sh: …`, `cmd-N again: …`,
  `monitors: …`. The body explains why.
- Comments in `aerospace.toml` say what a binding does for the user and name the patch it relies on.

## After pushing: vsnd-setup

vsnd-setup installs the commit of this repo that it pins, so a change only reaches it after a bump:

```sh
~/.config/vsnd-setup/bump.sh --push
```

It pins the newest pushed commits of this repo and vsndbar and prints the `aerospace.toml` bindings that changed.
Those need to be reflected by hand in:

- the Keys table in vsnd-setup's `README.md`;
- `PATCHED_ONLY_FLAGS` in vsnd-setup's `install.sh`: config flags only the patched build knows (currently
  `--peek-on-hold`). Stock AeroSpace rejects the whole config over one unknown flag, and `install.sh uninstall`
  removes these flags when it puts the stock app back.
