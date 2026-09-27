#!/bin/sh
snapshot=$(/opt/homebrew/bin/hs -c '
  local app = hs.application.frontmostApplication()
  if not app then return end
  local win = app:focusedWindow()
  local title = win and win:title() or ""
  if title == "" then title = app:name() end
  print(hs.json.encode({app=app:name(), title=title}))
' 2>/dev/null | sed -n '/^{/p')
app=$(printf '%s' "$snapshot" | /usr/bin/jq -er '.app') || exit 0
title=$(printf '%s' "$snapshot" | /usr/bin/jq -er '.title') || exit 0
sketchybar --set "$NAME" label="$title" icon.background.image="app.$app"
