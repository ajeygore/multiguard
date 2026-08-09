#!/bin/bash
set -e

ASSETS_DIR="Resources/Assets.xcassets/AppIcon.appiconset"
SVG="Resources/AppIcon.svg"

if command -v magick >/dev/null 2>&1; then
    MAGICK=magick
else
    MAGICK=convert
fi

mkdir -p "$ASSETS_DIR"

SIZES=(16 32 128 256 512)
for size in "${SIZES[@]}"; do
    $MAGICK "$SVG" -background none -resize "${size}x${size}" "${ASSETS_DIR}/icon_${size}x${size}.png"
    $MAGICK "$SVG" -background none -resize "$((size * 2))x$((size * 2))" "${ASSETS_DIR}/icon_${size}x${size}@2x.png"
done

# Build a .icns file for standalone app bundles (asset catalogs need full Xcode; iconutil works with CLT)
ICONSET_DIR="/tmp/MultiGuard.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
for size in "${SIZES[@]}"; do
    cp "${ASSETS_DIR}/icon_${size}x${size}.png" "$ICONSET_DIR/icon_${size}x${size}.png"
    cp "${ASSETS_DIR}/icon_${size}x${size}@2x.png" "$ICONSET_DIR/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET_DIR" -o "Resources/MultiGuard.icns"
rm -rf "$ICONSET_DIR"

cat > "${ASSETS_DIR}/Contents.json" <<EOF
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "Generated app icons in $ASSETS_DIR"
