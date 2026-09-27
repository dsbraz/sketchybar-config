#!/bin/sh
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
BIN="$CONFIG_DIR/bin/sketchybar-now-playing"

# Display only: no mouse actions or native-panel integration.
case "$SENDER" in mouse.*) exit 0 ;; esac
if [ "$SENDER" = now_playing_change ]; then
  title=$TITLE
  artist=$ARTIST
  playing=$PLAYING
else
  snapshot=$("$BIN" get --json 2>/dev/null) || exit 0
  title=$(printf '%s' "$snapshot" | jq -r '.title // empty')
  artist=$(printf '%s' "$snapshot" | jq -r '.artist // empty')
  playing=$(printf '%s' "$snapshot" | jq -r '.playing // false')
fi

if [ -z "$title" ] || [ "$title" = 'Play Something' ]; then
  sketchybar --set now_playing drawing=off
  exit 0
fi
label=$title
[ -n "$artist" ] && label="$title · $artist"
color=0xffa1a1aa
[ "$playing" = true ] && color=0xfff5f5f7
sketchybar --set now_playing drawing=on label="$label" label.color="$color"
