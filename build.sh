#!/bin/bash
# Builds "USUFU Prep.app" — a universal (Intel + Apple Silicon) macOS app.
# Owned by United States Universities For Ukraine.
# Requires only the Xcode Command Line Tools; no Xcode project, no dependencies.
set -e
cd "$(dirname "$0")"

APP_NAME="USUFU Prep"
# **Unchanged by the rename, on purpose.** macOS keys window state, the
# accessibility and file-access permissions a student has already granted, and
# everything in `UserDefaults` to the bundle identifier. A new one is a new app
# to the system, and all of that is forgotten. See `Brand.appName`.
BUNDLE_ID="org.usufu.satprep"
# Taken from the latest tag so the About panel and the packaged zip agree.
VERSION="$(git describe --tags --abbrev=0 2>/dev/null || echo v1.0)"
VERSION="${VERSION#v}"
MIN_MACOS="13.0"
BUILD_DIR="build"
DEST="$BUILD_DIR/$APP_NAME.app"

# The bundle is assembled in a temp directory rather than in place. If the
# project lives in iCloud Drive (or any file-provider folder), the system keeps
# re-attaching com.apple.FinderInfo to the bundle, and codesign refuses to sign
# anything carrying it. Staging outside that folder sidesteps the problem.
STAGE="$(mktemp -d)"
APP="$STAGE/$APP_NAME.app"
trap 'rm -rf "$STAGE"' EXIT

echo "→ Cleaning"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Pick an SDK this compiler can actually use. From the macOS 27 SDK on, SwiftUI's
# `@State` is a macro whose plugin ships only with full Xcode, so on Command Line
# Tools alone the newest SDK fails every view with "plugin for module
# 'SwiftUIMacros' not found". Probe with a one-line view and fall back newest
# first. An SDKROOT already set is respected untouched.
if [ -z "${SDKROOT:-}" ]; then
    PROBE="$(mktemp -d)"
    printf 'import SwiftUI\nstruct P: View { @State var x = 0; var body: some View { Text("") } }\n' > "$PROBE/p.swift"
    if ! swiftc -typecheck -target arm64-apple-macosx$MIN_MACOS "$PROBE/p.swift" 2>/dev/null; then
        for sdk in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.sdk 2>/dev/null | sort -rV); do
            if SDKROOT="$sdk" swiftc -typecheck -target arm64-apple-macosx$MIN_MACOS "$PROBE/p.swift" 2>/dev/null; then
                export SDKROOT="$sdk"
                echo "→ Default SDK cannot expand SwiftUI macros; using $(basename "$sdk")"
                break
            fi
        done
    fi
    rm -rf "$PROBE"
fi

echo "→ Compiling (arm64)"
swiftc -target arm64-apple-macosx$MIN_MACOS -parse-as-library -O \
    Sources/*.swift -o "$BUILD_DIR/app-arm64"

echo "→ Compiling (x86_64)"
swiftc -target x86_64-apple-macosx$MIN_MACOS -parse-as-library -O \
    Sources/*.swift -o "$BUILD_DIR/app-x86_64"

echo "→ Creating universal binary"
lipo -create "$BUILD_DIR/app-arm64" "$BUILD_DIR/app-x86_64" \
    -output "$APP/Contents/MacOS/$APP_NAME"
rm -f "$BUILD_DIR/app-arm64" "$BUILD_DIR/app-x86_64"

echo "→ Copying the organisation's artwork"
cp Resources/*.png "$APP/Contents/Resources/"
# The Learn articles. Flat in Resources/ because `Bundle.main.url(
# forResource:withExtension:)` looks there; the source tree keeps them in a
# folder so thirty files do not sit beside the seal.
cp Resources/Articles/*.json "$APP/Contents/Resources/"
# Hand-made figure artwork, when there is any. Flat, for the same
# `Bundle.main.url(forResource:)` reason the articles are.
cp Resources/Articles/figures/*.png "$APP/Contents/Resources/" 2>/dev/null || true

echo "→ Building icon"
swiftc -O Tools/makeicon.swift -o "$BUILD_DIR/makeicon" 2>/dev/null
"$BUILD_DIR/makeicon" "$BUILD_DIR/AppIcon.iconset" Resources/usufu-seal.png >/dev/null
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$BUILD_DIR/AppIcon.iconset" "$BUILD_DIR/makeicon"

echo "→ Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© United States Universities For Ukraine. Advancing Excellence, Ensuring Success.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>PDF</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSItemContentTypes</key><array><string>com.adobe.pdf</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "→ Signing (ad-hoc, so Gatekeeper lets it run locally)"
xattr -cr "$APP"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP" && echo "  signature verified"

echo "→ Installing"
ditto "$APP" "$DEST"

echo ""
echo "✓ Built $DEST"
echo ""
echo "  Run it:      open '$DEST'"
echo "  Install it:  cp -R '$DEST' /Applications/"
