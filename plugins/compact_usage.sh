#!/bin/sh
# Normalize in the collector, then push both histories in one bar transaction.
samples=$("$CONFIG_DIR/bin/system_usage" --normalized) || exit 1
read -r cpu gpu <<EOF
$samples
EOF

set --
for metric in cpu gpu; do
  case "$metric" in cpu) value=$cpu ;; gpu) value=$gpu ;; esac
  case "$value" in
    0.[0-9][0-9][0-9][0-9]|1.0000) set -- "$@" --push "$metric" "$value" ;;
    *) continue ;; # Unavailable or malformed values must not become zero.
  esac
done

# Repeated samples still advance graph history, even if utilization is unchanged.
if [ "$#" -gt 0 ]; then sketchybar "$@"; fi
