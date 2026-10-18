#!/bin/bash
# Builds dist/CleanSheet.app (ad-hoc signed, no Apple account needed) and checks the 100 MB limit.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="dist/CleanSheet.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/CleanSheet "$APP/Contents/MacOS/CleanSheet"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>CleanSheet</string>
<key>CFBundleDisplayName</key><string>CleanSheet</string>
<key>CFBundleIdentifier</key><string>studio.pbw.cleansheet</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleExecutable</key><string>CleanSheet</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSDesktopFolderUsageDescription</key><string>To measure disk usage and find duplicates in folders you choose.</string>
<key>NSDocumentsFolderUsageDescription</key><string>To measure disk usage and find duplicates in folders you choose.</string>
<key>NSDownloadsFolderUsageDescription</key><string>To list old .dmg installers.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
SIZE_MB=$(du -sm "$APP" | cut -f1)
echo "App size: ${SIZE_MB} MB (limit: 100 MB)"
[ "$SIZE_MB" -lt 100 ] || { echo "ERRO: over 100 MB"; exit 1; }
