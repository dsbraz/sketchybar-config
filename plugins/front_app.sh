#!/bin/sh
snapshot=$(/opt/homebrew/bin/hs -c '
  local app = hs.application.frontmostApplication()
  if not app then return end
  local win = app:focusedWindow()
  local title = win and win:title() or ""
  if title == "" then title = app:name() end
  local menuWidth
  pcall(function()
    local menu = hs.axuielement.applicationElement(app):attributeValue("AXMenuBar")
    if not menu then return end
    local first, right
    for _, item in ipairs(menu:attributeValue("AXChildren") or {}) do
      local p = item:attributeValue("AXPosition")
      local s = item:attributeValue("AXSize")
      if p and s and s.w > 0 then
        first = first or p
        right = math.max(right or 0, p.x + s.w)
      end
    end
    if not first then return end
    for _, screen in ipairs(hs.screen.allScreens()) do
      local f = screen:fullFrame()
      if first.x >= f.x and first.x < f.x + f.w
          and first.y >= f.y and first.y < f.y + f.h then
        menuWidth = math.ceil(right - f.x)
        break
      end
    end
  end)
  print(hs.json.encode({app=app:name(), title=title, menu_width=menuWidth}))
' 2>/dev/null | sed -n '/^{/p')
app=$(printf '%s' "$snapshot" | /usr/bin/jq -er '.app') || exit 0
title=$(printf '%s' "$snapshot" | /usr/bin/jq -er '.title') || exit 0
# A zero-layout-width anchor starts at the left edge. Its empty icon supplies
# the measured menu extent without moving the visible items. The bracket spans
# whichever is wider: native menus or our title. No on-screen coordinates needed.
menu_width=$(printf '%s' "$snapshot" | /usr/bin/jq -er '.menu_width // empty') || menu_width=""
if [ -n "$menu_width" ]; then
  sketchybar --set menu_cover_end "icon.width=$menu_width" \
    --set "${NAME:-front_app}" label="$title" icon.background.image="app.$app"
else
  sketchybar --set "${NAME:-front_app}" label="$title" icon.background.image="app.$app"
fi
