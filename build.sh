#!/bin/zsh
set -euo pipefail
quota_project="${0:A:h}"
quota_bundle="$quota_project/build/QuotaGlass.app"
quota_widget="$quota_bundle/Contents/PlugIns/Cotas Widget.appex"
quota_widget_cache="$HOME/Library/Application Support/QuotaGlass/widget.json"
mkdir -p "$quota_bundle/Contents/MacOS" "$quota_bundle/Contents/Resources" "$quota_project/.build/module-cache"
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macosx27.0 \
  -module-cache-path "$quota_project/.build/module-cache" \
  "$quota_project"/Sources/*.swift -o "$quota_bundle/Contents/MacOS/QuotaGlass" \
  -framework AppKit -framework SwiftUI -framework WebKit -framework WidgetKit -framework CoreGraphics
mkdir -p "$quota_widget/Contents/MacOS" "$quota_widget/Contents/Resources/brands"
python3 "$quota_project/scripts/prepare-widgetkit-overlay.py" "$quota_project/.build/widgetkit-overlay"
xcrun swiftc -swift-version 5 -parse-as-library -O -application-extension -target arm64-apple-macosx27.0 \
  -I "$quota_project/.build/widgetkit-overlay" \
  -module-cache-path "$quota_project/.build/module-cache" \
  "$quota_project/Sources/Models.swift" "$quota_project/Sources/WidgetSelection.swift" \
  "$quota_project/Sources/ResetIndicators.swift" "$quota_project/Sources/WidgetSnapshot.swift" "$quota_project/WidgetExtension/QuotaWidget.swift" \
  -o "$quota_widget/Contents/MacOS/CotasWidget" -framework AppKit -framework SwiftUI -framework WidgetKit -framework Foundation \
  -Xlinker -e -Xlinker _NSExtensionMain
printf '%s\n' "$quota_widget_cache" > "$quota_bundle/Contents/Resources/widget-data-path.txt"
cp "$quota_bundle/Contents/Resources/widget-data-path.txt" "$quota_widget/Contents/Resources/widget-data-path.txt"
cp "$quota_project/Resources/providers.json" "$quota_bundle/Contents/Resources/providers.json"
mkdir -p "$quota_bundle/Contents/Resources/brands"
for quota_logo in openai-black openai-white claude gemini-vector; do
  cp "$quota_project/Resources/brands/$quota_logo.svg" "$quota_bundle/Contents/Resources/brands/$quota_logo.svg"
  cp "$quota_project/Resources/brands/$quota_logo.svg" "$quota_widget/Contents/Resources/brands/$quota_logo.svg"
done
cat > "$quota_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>QuotaGlass</string>
<key>CFBundleIdentifier</key><string>app.quotaglass.mac</string>
<key>CFBundleName</key><string>QuotaGlass</string>
<key>CFBundleDisplayName</key><string>QuotaGlass</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>QuotaGlass</string><key>CFBundleURLSchemes</key><array><string>quotaglass</string></array></dict></array>
</dict></plist>
PLIST
cat > "$quota_widget/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CotasWidget</string>
<key>CFBundleIdentifier</key><string>app.quotaglass.mac.Widget</string>
<key>CFBundleName</key><string>Cotas Widget</string>
<key>CFBundleDisplayName</key><string>Cotas</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>NSExtension</key><dict><key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string></dict>
</dict></plist>
PLIST
quota_sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
python3 - "$quota_sdk_version" "$quota_bundle/Contents/Info.plist" "$quota_widget/Contents/Info.plist" <<'PY'
import plistlib,sys
for path in sys.argv[2:]:
    with open(path, 'rb') as source:
        metadata = plistlib.load(source)
    metadata.update({'CFBundleSupportedPlatforms': ['MacOSX'], 'DTPlatformName': 'macosx',
                     'DTPlatformVersion': sys.argv[1], 'DTSDKName': 'macosx' + sys.argv[1]})
    with open(path, 'wb') as output:
        plistlib.dump(metadata, output)
PY
python3 - "$quota_widget_cache" "$quota_project/.build/widget.entitlements" <<'PY'
import plistlib,sys
with open(sys.argv[2], 'wb') as output:
    plistlib.dump({'com.apple.security.app-sandbox': True,
                  'com.apple.security.temporary-exception.files.absolute-path.read-only': [sys.argv[1]]}, output)
PY
codesign --force --sign - --entitlements "$quota_project/.build/widget.entitlements" "$quota_widget"
codesign --force --sign - "$quota_bundle"
printf 'Aplicativo criado: %s\n' "$quota_bundle"
