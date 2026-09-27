#!/bin/sh
# APFS volumes share the container; count all occupied container space.
percentage=$(diskutil info -plist /System/Volumes/Data |
  plutil -convert json -o - -- - |
  /usr/bin/jq -er 'select(.APFSContainerSize > 0) |
    100 * (1 - .APFSContainerFree / .APFSContainerSize) | round') || exit 0
sketchybar --set ssd label="$percentage%"
