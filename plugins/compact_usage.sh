#!/bin/sh
read -r cpu memory <<EOF
$("$CONFIG_DIR/bin/system_usage")
EOF
sketchybar --set cpu label="${cpu:--}%" --set memory label="${memory:--}%"
