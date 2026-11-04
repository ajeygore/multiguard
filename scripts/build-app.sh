#!/bin/bash
# Build, package and sign MultiGuard.app.
#
#   ./scripts/build-app.sh            # produce ./MultiGuard.app
#   ./scripts/build-app.sh --install  # also install to /Applications and launch it
set -e

APP_NAME="MultiGuard"
HELPER_NAME="MultiGuardHelper"
OUTPUT="$APP_NAME.app"
INSTALL_DIR="/Applications"
TEAM_ID="${DEVELOPER_ID:-}"

INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

if [ -z "$TEAM_ID" ]; then
    echo "WARNING: DEVELOPER_ID is not set. The app will be ad-hoc signed and SMJobBless will not work."
    echo "To enable the privileged helper, set DEVELOPER_ID to your Apple Developer Team ID:"
    echo "  DEVELOPER_ID=ABCD123456 ./scripts/build-app.sh"
fi

echo "Building $APP_NAME and $HELPER_NAME..."
swift build

# Assemble and sign outside the repo. When the repo lives in an iCloud-synced folder
# (e.g. ~/Documents), the file provider attaches com.apple.FinderInfo and
# com.apple.fileprovider.* attributes to the bundle that `xattr -c` cannot remove, and
# codesign rejects them ("resource fork, Finder information, or similar detritus").
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
BUNDLE_DIR="$STAGING/$APP_NAME.app"

echo "Packaging $APP_NAME.app..."
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

xattr -cr "$BUNDLE_DIR"

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
codesign --verify --deep --strict "$BUNDLE_DIR"

rm -rf "$OUTPUT"
ditto "$BUNDLE_DIR" "$OUTPUT"
echo "Created $OUTPUT"

if [ "$INSTALL" = 1 ]; then
    TARGET="$INSTALL_DIR/$APP_NAME.app"
    echo "Installing to $TARGET..."
    osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null || break
        sleep 0.5
    done
    pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    rm -rf "$TARGET"
    ditto "$BUNDLE_DIR" "$TARGET"
    codesign --verify --deep --strict "$TARGET"
    open "$TARGET"
    echo "Installed and launched $TARGET"
else
    echo "Launch with: open '$OUTPUT'"
fi
