#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --package-path src/sketchybar-toggle
mkdir -p bin
install -m 755 src/sketchybar-toggle/.build/release/sketchybar-toggle bin/sketchybar-toggle
