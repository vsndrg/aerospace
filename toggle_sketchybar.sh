#!/usr/bin/env bash
# cmd-shift-b: hide / show the bar. The bar is drawn by the sketchybar helper
# daemon (sketchybar's own bar stays hidden); Lua flips its state.
set -euo pipefail

SKETCHYBAR="/opt/homebrew/opt/sketchybar/bin/sketchybar"
if [[ ! -x "$SKETCHYBAR" ]]; then
  SKETCHYBAR="sketchybar"
fi

"$SKETCHYBAR" --trigger bar_toggle
