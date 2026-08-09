#!/bin/bash
set -e

APP_NAME="MultiGuard"
HELPER_NAME="MultiGuardHelper"
BUNDLE_DIR="$APP_NAME.app"
TEAM_ID="${DEVELOPER_ID:-}"

if [ -z "$TEAM_ID" ]; then
    echo "WARNING: DEVELOPER_ID is not set. The app will be ad-hoc signed and SMJobBless will not work."
    echo "To enable the privileged helper, set DEVELOPER_ID to your Apple Developer Team ID:"
    echo "  DEVELOPER_ID=ABCD123456 ./scripts/build-app.sh"
fi

echo "Building $APP_NAME and $HELPER_NAME..."
swift build

echo "Packaging $BUNDLE_DIR..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"
mkdir -p "$BUNDLE_DIR/Contents/Library/LaunchServices"
mkdir -p "$BUNDLE_DIR/Contents/Library/LaunchDaemons"

cp ".build/debug/$APP_NAME" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"
cp ".build/debug/$HELPER_NAME" "$BUNDLE_DIR/Contents/Library/LaunchServices/$HELPER_NAME"
cp "Resources/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"
cp "Resources/HelperInfo.plist" "$BUNDLE_DIR/Contents/Library/LaunchServices/$HELPER_NAME.plist"
cp "Resources/com.multiguard.helper.plist" "$BUNDLE_DIR/Contents/Library/LaunchDaemons/com.multiguard.helper.plist"

if [ -f "Resources/MultiGuard.icns" ]; then
    cp "Resources/MultiGuard.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
fi

# Replace TEAM_ID placeholder with actual team ID if provided.
if [ -n "$TEAM_ID" ]; then
    sed -i '' "s/TEAM_ID/$TEAM_ID/g" "$BUNDLE_DIR/Contents/Info.plist"
    sed -i '' "s/TEAM_ID/$TEAM_ID/g" "$BUNDLE_DIR/Contents/Library/LaunchServices/$HELPER_NAME.plist"
fi

chmod +x "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$BUNDLE_DIR/Contents/Library/LaunchServices/$HELPER_NAME"

# Code signing
if [ -n "$TEAM_ID" ]; then
    echo "Signing helper and app with Developer ID..."
    codesign --force --options runtime --sign "Developer ID Application: $TEAM_ID" \
        "$BUNDLE_DIR/Contents/Library/LaunchServices/$HELPER_NAME"
    codesign --force --options runtime --sign "Developer ID Application: $TEAM_ID" \
        "$BUNDLE_DIR"
else
    echo "Ad-hoc signing helper and app..."
    codesign --force --sign - "$BUNDLE_DIR/Contents/Library/LaunchServices/$HELPER_NAME"
    codesign --force --sign - "$BUNDLE_DIR"
fi

echo "Created $BUNDLE_DIR"
echo "Launch with: open '$BUNDLE_DIR'"
