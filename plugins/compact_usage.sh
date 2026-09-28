#!/bin/sh
read -r cpu gpu <<EOF
$("$CONFIG_DIR/bin/system_usage")
EOF

# Graph samples use a fixed 0..1 scale for percentage usage.
for metric in cpu gpu; do
  case "$metric" in cpu) value=$cpu ;; gpu) value=$gpu ;; esac
  sample=$(LC_ALL=C awk -v value="$value" 'BEGIN {
    if (value !~ /^[0-9]+([.][0-9]+)?$/) exit 1
    value /= 100
    if (value > 1) value = 1
    printf "%.4f", value
  }') || continue
  sketchybar --push "$metric" "$sample"
done
