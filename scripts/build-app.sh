#!/bin/bash
# Gera dist/PbW Code Engine.app (assinatura ad-hoc, sem conta Apple) e confere o limite de 100 MB.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="dist/PbW Code Engine.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PbWCodeEngine "$APP/Contents/MacOS/PbWCodeEngine"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>PbW Code Engine</string>
<key>CFBundleDisplayName</key><string>PbW Code Engine</string>
<key>CFBundleIdentifier</key><string>studio.pbw.codeengine</string>
<key>CFBundleExecutable</key><string>PbWCodeEngine</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSDesktopFolderUsageDescription</key><string>Para medir o uso de disco e achar duplicatas nas pastas que você escolher.</string>
<key>NSDocumentsFolderUsageDescription</key><string>Para medir o uso de disco e achar duplicatas nas pastas que você escolher.</string>
<key>NSDownloadsFolderUsageDescription</key><string>Para listar instaladores .dmg antigos.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
SIZE_MB=$(du -sm "$APP" | cut -f1)
echo "Tamanho do app: ${SIZE_MB} MB (limite: 100 MB)"
[ "$SIZE_MB" -lt 100 ] || { echo "ERRO: passou de 100 MB"; exit 1; }
