#!/bin/sh

if pgrep -x "Google Chrome" >/dev/null; then
  osascript -e 'tell application "Google Chrome" to make new window'
else
  open -a "Google Chrome"
fi

