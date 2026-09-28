#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
lock="/private/tmp/sketchybar-spaces-${UID}.lock"
mkdir "$lock" 2>/dev/null || exit 0
trap 'rmdir "$lock" 2>/dev/null' EXIT

snapshot=$(/opt/homebrew/bin/hs -c 'print(hs.json.encode({spaces=hs.spaces.allSpaces(),active=hs.spaces.activeSpaces()}))' 2>/dev/null | sed -n '/^{/p')
displays=$(sketchybar --query displays) || exit 0
layout=$(jq -cen --argjson snapshot "$snapshot" --argjson displays "$displays" '
  [$displays | sort_by(."arrangement-id")[] | .UUID as $uuid |
   $snapshot.spaces[$uuid][] | {active:(. == $snapshot.active[$uuid])}]') || exit 0
count=$(printf '%s' "$layout" | jq -er 'length | select(. > 0)') || exit 0
current=$(sketchybar --query bar | jq -er '.items') || exit 0
args=()
order=()
for ((sid=1; sid<=count; sid++)); do
  name="space.$sid"
  order+=("$name")
  if ! printf '%s' "$current" | jq -e --arg name "$name" 'index($name) != null' >/dev/null; then
    selected=$(printf '%s' "$layout" | jq -r --argjson index "$((sid-1))" '.[$index].active')
    args+=(--add space "$name" left --set "$name" "space=$sid" "icon=$sid"
      icon.color=0xfff5f5f7 icon.padding_left=9 icon.padding_right=9
      label.drawing=off background.color=0xff3b99fc "background.drawing=$selected"
      "script=$CONFIG_DIR/plugins/space.sh")
  fi
done
while IFS= read -r name; do
  [ "${name#space.}" -gt "$count" ] && args+=(--remove "$name")
done < <(printf '%s' "$current" | jq -r '.[] | select(test("^space\\.[0-9]+$"))')

if [ "${#args[@]}" -gt 0 ]; then
  sketchybar "${args[@]}" --reorder apple "${order[@]}" front_app
fi
