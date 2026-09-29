#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --package-path src/sketchybar-toggle
mkdir -p bin
install -m 755 src/sketchybar-toggle/.build/release/sketchybar-toggle bin/sketchybar-toggle

# LaunchServices gives the helper its own Accessibility identity.
app_dir="bin/SketchyBar Helper.app/Contents"
mkdir -p "$app_dir/MacOS"
install -m 755 bin/sketchybar-toggle "$app_dir/MacOS/sketchybar-toggle"
cat > "$app_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.dsbraz.sketchybar.helper</string>
<key>CFBundleName</key><string>SketchyBar Helper</string>
<key>CFBundleExecutable</key><string>sketchybar-toggle</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --identifier com.dsbraz.sketchybar.helper "bin/SketchyBar Helper.app"
