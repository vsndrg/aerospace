#!/usr/bin/env bash
set -euo pipefail

SKETCHYBAR="/opt/homebrew/opt/sketchybar/bin/sketchybar"
if [[ ! -x "$SKETCHYBAR" ]]; then
  SKETCHYBAR="sketchybar"
fi

BAR_JSON="$("$SKETCHYBAR" --query bar)"

# В разных версиях hidden может быть "on/off" или true/false — проверяем оба варианта.
if echo "$BAR_JSON" | grep -Eq '"hidden"[[:space:]]*:[[:space:]]*("on"|true)'; then
  "$SKETCHYBAR" --bar hidden=off
else
  "$SKETCHYBAR" --bar hidden=on
fi
