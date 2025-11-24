#!/bin/bash
# Build script that creates a macOS app bundle with icon

set -e

APP_NAME="Pioneer"
BUILD_DIR=".build"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Building ${APP_NAME}..."

# Build the Swift package
swift build -c release

# Create app bundle structure
echo "Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy the executable
EXECUTABLE_PATH="${BUILD_DIR}/release/${APP_NAME}"
if [ -f "${EXECUTABLE_PATH}" ]; then
    cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/${APP_NAME}"
    chmod +x "${MACOS_DIR}/${APP_NAME}"
else
    echo "Error: Executable not found at ${EXECUTABLE_PATH}"
    exit 1
fi

# Copy icon if it exists (check multiple possible locations)
ICON_PATH=""
if [ -f "Pioneer.png" ]; then
    ICON_PATH="Pioneer.png"
elif [ -f "Resources/Pioneer.png" ]; then
    ICON_PATH="Resources/Pioneer.png"
elif [ -f "Pioneer.icon/Assets/Pioneer@3x.png" ]; then
    ICON_PATH="Pioneer.icon/Assets/Pioneer@3x.png"
fi

if [ -n "${ICON_PATH}" ]; then
    # Convert PNG to ICNS if iconutil is available
    ICONSET_DIR="${RESOURCES_DIR}/${APP_NAME}.iconset"
    mkdir -p "${ICONSET_DIR}"
    
    # Create different sizes from the source PNG
    if command -v sips &> /dev/null; then
        sips -z 16 16 "${ICON_PATH}" --out "${ICONSET_DIR}/icon_16x16.png" 2>/dev/null || cp "${ICON_PATH}" "${ICONSET_DIR}/icon_16x16.png"
        sips -z 32 32 "${ICON_PATH}" --out "${ICONSET_DIR}/icon_16x16@2x.png" 2>/dev/null || cp "${ICON_PATH}" "${ICONSET_DIR}/icon_16x16@2x.png"
        sips -z 32 32 "${ICON_PATH}" --out "${ICONSET_DIR}/icon_32x32.png" 2>/dev/null || cp "${ICON_PATH}" "${ICONSET_DIR}/icon_32x32.png"
        sips -z 64 64 "${ICON_PATH}" --out "${ICONSET_DIR}/icon_32x32@2x.png" 2>/dev/null || cp "${ICON_PATH}" "${ICONSET_DIR}/icon_32x32@2x.png"
        sips -z 128 128 "${ICON_PATH}" --out "${ICONSET_DIR}/icon_128x128.png" 2>/dev/null || cp "${ICON_PATH}" "${ICONSET_DIR}/icon_128x128.png"
        sips -z 256 256 "${ICON_PATH}" --out "${ICONSET_DIR}/icon_128x128@2x.png" 2>/dev/null || cp "${ICON_PATH}" "${ICONSET_DIR}/icon_128x128@2x.png"
        sips -z 256 256 "${ICON_PATH}" --out "${ICONSET_DIR}/icon_256x256.png" 2>/dev/null || cp "${ICON_PATH}" "${ICONSET_DIR}/icon_256x256.png"
        sips -z 512 512 "${ICON_PATH}" --out "${ICONSET_DIR}/icon_256x256@2x.png" 2>/dev/null || cp "${ICON_PATH}" "${ICONSET_DIR}/icon_256x256@2x.png"
        sips -z 512 512 "${ICON_PATH}" --out "${ICONSET_DIR}/icon_512x512.png" 2>/dev/null || cp "${ICON_PATH}" "${ICONSET_DIR}/icon_512x512.png"
        sips -z 1024 1024 "${ICON_PATH}" --out "${ICONSET_DIR}/icon_512x512@2x.png" 2>/dev/null || cp "${ICON_PATH}" "${ICONSET_DIR}/icon_512x512@2x.png"
        
        # Create ICNS file
        if command -v iconutil &> /dev/null; then
            iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/${APP_NAME}.icns"
            rm -rf "${ICONSET_DIR}"
            echo "Created app icon: ${RESOURCES_DIR}/${APP_NAME}.icns"
        else
            # Fallback: just copy the PNG
            cp "${ICON_PATH}" "${RESOURCES_DIR}/${APP_NAME}.png"
            echo "Copied app icon: ${RESOURCES_DIR}/${APP_NAME}.png"
        fi
    else
        # Fallback: just copy the PNG
        cp "${ICON_PATH}" "${RESOURCES_DIR}/${APP_NAME}.png"
        echo "Copied app icon: ${RESOURCES_DIR}/${APP_NAME}.png"
    fi
else
    echo "Warning: Pioneer.png not found. App will be created without custom icon."
fi

# Create Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.pioneer.${APP_NAME}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.0.2</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2024 Pioneer. All rights reserved.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
EOF

if [ -f "${RESOURCES_DIR}/${APP_NAME}.icns" ]; then
    cat >> "${CONTENTS_DIR}/Info.plist" << EOF
    <key>CFBundleIconFile</key>
    <string>${APP_NAME}.icns</string>
EOF
elif [ -f "${RESOURCES_DIR}/${APP_NAME}.png" ]; then
    cat >> "${CONTENTS_DIR}/Info.plist" << EOF
    <key>CFBundleIconFile</key>
    <string>${APP_NAME}.png</string>
EOF
fi

cat >> "${CONTENTS_DIR}/Info.plist" << EOF
</dict>
</plist>
EOF

echo "App bundle created: ${APP_BUNDLE}"
echo "You can now run it with: open ${APP_BUNDLE}"

