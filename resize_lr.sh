mkdir -p ~/.config/aerospace
cat > ~/.config/aerospace/resize_lr.sh <<'PY'
#!/usr/bin/env python3
# Resize helper for AeroSpace: h/l behavior depends on whether focused window
# is on the left or right. Change INC to tweak nudge amount (pixels).
import json, subprocess, sys, shlex

INC = 20  # pixels per press, change to taste

def run(cmd):
    return subprocess.check_output(cmd, text=True)

# get windows on focused workspace as JSON
try:
    raw = run(["aerospace", "list-windows", "--workspace", "focused", "--json"])
except subprocess.CalledProcessError:
    sys.exit(0)

try:
    windows = json.loads(raw)
except Exception:
    sys.exit(0)

if isinstance(windows, dict):
    windows = [windows]

# find focused window object (best-effort)
focused = None
for w in windows:
    if w.get("focused") or w.get("is_focused") or w.get("focused_window"):
        focused = w
        break
if focused is None and windows:
    # fallback: try to detect by comparing accessibility or choose first
    focused = windows[0]

def geom_of(w):
    # AeroSpace JSON uses either 'geometry' or 'frame' etc. try common names.
    for k in ("geometry", "frame", "bounds"):
        g = w.get(k)
        if isinstance(g, dict) and ("x" in g or "left" in g):
            return g
    return None

fg = geom_of(focused)
if fg is None:
    sys.exit(0)

# normalize geometry fields
def get_xywh(g):
    x = g.get("x", g.get("left", 0))
    w = g.get("width", g.get("w", g.get("width", 0)))
    return float(x), float(w)

fx, fw = get_xywh(fg)
fcx = fx + fw/2.0

# find nearest neighbour and whether it is left or right
best_dist = float("inf")
nearest_side = None
for w in windows:
    if w is focused:
        continue
    g = geom_of(w)
    if g is None:
        continue
    ox, ow = get_xywh(g)
    ocx = ox + ow/2.0
    d = abs(ocx - fcx)
    if d < best_dist:
        best_dist = d
        nearest_side = "left" if ocx < fcx else "right"

# If no neighbour found, do nothing
if nearest_side is None:
    sys.exit(0)

# decide resize for 'h' (left key). When nearest is right => we are right pane => h should grow (+)
# When nearest is left => we are left pane => h should shrink (-)
if nearest_side == "right":
    # h => grow, l => shrink
    resize_h = "+%d" % INC
    resize_l = "-%d" % INC
else:
    # nearest is left: h => shrink, l => grow
    resize_h = "-%d" % INC
    resize_l = "+%d" % INC

# Which key invoked this script? AeroSpace doesn't pass it automatically,
# we'll accept an optional arg: 'h' or 'l'. If missing, default to 'h'.
key = sys.argv[1] if len(sys.argv) > 1 else "h"
if key == "h":
    subprocess.call(["aerospace", "resize", "width", resize_h])
else:
    subprocess.call(["aerospace", "resize", "width", resize_l])
PY

chmod +x ~/.config/aerospace/resize_lr.sh
