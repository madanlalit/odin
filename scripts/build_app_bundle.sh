#!/bin/bash
set -e

REPO_ROOT="$(pwd)"
RELEASE_DIR="${REPO_ROOT}/apps/macos/Odin/.build/arm64-apple-macosx/release"
DIST_DIR="${REPO_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/Odin.app"

echo "=== Packaging Odin.app ==="
# 1. Create standard macOS App folder structure
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# 2. Copy Executable
cp "${RELEASE_DIR}/Odin" "${APP_BUNDLE}/Contents/MacOS/Odin"

# 3. Copy Resource Bundle
cp -R "${RELEASE_DIR}/Odin_Odin.bundle" "${APP_BUNDLE}/Contents/Resources/"

# 3b. Copy Python environment directly from build folder into Odin.app Resources
echo "=== Copying Python runtime, site-packages, and sources to Odin.app ==="
cp -R "${REPO_ROOT}/.build/python-runtime/python" "${APP_BUNDLE}/Contents/Resources/"
cp -R "${REPO_ROOT}/.build/site-packages" "${APP_BUNDLE}/Contents/Resources/"
cp -R "${REPO_ROOT}/.build/src" "${APP_BUNDLE}/Contents/Resources/"

# 4. Compile and Copy App Icon
echo "=== Compiling App Icon ==="
ICONSET_DIR="${REPO_ROOT}/.build/AppIcon.iconset"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"
cp "${REPO_ROOT}/apps/macos/Odin/Sources/Odin/Assets.xcassets/AppIcon.appiconset"/*.png "${ICONSET_DIR}/"
iconutil -c icns "${ICONSET_DIR}" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
rm -rf "${ICONSET_DIR}"

# 5. Create Info.plist
cat <<EOF > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Odin</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.odin.desktop</string>
    <key>CFBundleName</key>
    <string>Odin</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# 5b. Codesign the entire App Bundle ad-hoc to seal the bundle and resources
echo "=== Codesigning Odin.app ad-hoc ==="
codesign --force --deep --sign - "${APP_BUNDLE}"

# 6. Create macOS Disk Image (DMG) for drag-and-drop installer
echo "=== Building macOS Disk Image (DMG) ==="
DMG_ROOT="${REPO_ROOT}/.build/dmg_root"
rm -rf "${DMG_ROOT}"
mkdir -p "${DMG_ROOT}"

# Copy the app to the DMG root
cp -R "${APP_BUNDLE}" "${DMG_ROOT}/"
# Create a symlink to /Applications in the DMG root
ln -sf /Applications "${DMG_ROOT}/Applications"

# Set custom icon for the mounted volume
cp "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" "${DMG_ROOT}/.VolumeIcon.icns"
SetFile -a C "${DMG_ROOT}"

# Build the DMG
rm -f "${DIST_DIR}/Odin.dmg"
hdiutil create -volname "Odin" -srcfolder "${DMG_ROOT}" -ov -format UDZO "${DIST_DIR}/Odin.dmg"

# Set custom icon for the DMG file itself
echo "=== Setting custom icon for the DMG file ==="
uv run python -c "
from AppKit import NSWorkspace, NSImage
import sys
ws = NSWorkspace.sharedWorkspace()
img = NSImage.alloc().initWithContentsOfFile_('${APP_BUNDLE}/Contents/Resources/AppIcon.icns')
success = ws.setIcon_forFile_options_(img, '${DIST_DIR}/Odin.dmg', 0)
if not success:
    print('Warning: Failed to set DMG file icon.')
"

# Clean up temp DMG root
rm -rf "${DMG_ROOT}"

# Clean up intermediate Odin.app and Applications symlink inside dist/
# keeping ONLY the final Odin.dmg installer
echo "=== Cleaning up intermediate dist files ==="
rm -rf "${APP_BUNDLE}"
rm -f "${DIST_DIR}/Applications"

echo "=== Odin.dmg Packaged Successfully inside 'dist/' ==="
