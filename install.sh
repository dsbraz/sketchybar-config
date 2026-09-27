#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ "$(uname -m)" != arm64 ]; then
  echo "This configuration targets Apple Silicon (/opt/homebrew)." >&2
  exit 1
fi
mkdir -p bin
clang -O2 -Wall -Wextra src/system_usage.c -o bin/system_usage
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
asset=sketchybar-now-playing-aarch64-apple-darwin
curl -fL "https://github.com/wthrajat/sketchybar-now-playing/releases/download/v0.4.3/$asset.tar.gz" -o "$work/package.tar.gz"
printf '%s  %s\n' 3a97570734b4423609a722b7886dd0a39ba71b025b5fb5c79e081e1d2cb161e0 "$work/package.tar.gz" | shasum -a 256 -c -
tar -xzf "$work/package.tar.gz" -C "$work"
install -m 755 "$work/$asset/bin/sketchybar-now-playing" bin/sketchybar-now-playing
install -m 644 "$work/$asset/LICENSE" bin/sketchybar-now-playing.LICENSE
echo "Helpers ready. Start with: brew services start sketchybar"
