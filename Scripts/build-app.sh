#!/usr/bin/env bash
# Builds "IPA Beam.app" (universal: Apple Silicon + Intel) into ./build
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="IPA Beam"
EXECUTABLE="IPABeam"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
ARCHS=${ARCHS:-"arm64 x86_64"}

ARCH_FLAGS=()
for arch in $ARCHS; do ARCH_FLAGS+=(--arch "$arch"); done

echo "▸ Kompiliere ($ARCHS) …"
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

echo "▸ Erzeuge App-Bundle …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -d "$ROOT/Resources/AppIcon.iconset" ]; then
  iconutil -c icns "$ROOT/Resources/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▸ Signiere (ad-hoc) …"
codesign --force --deep --sign - "$APP"

echo "▸ Packe ZIP …"
rm -f "$BUILD_DIR/IPA-Beam.zip"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/IPA-Beam.zip"

echo "✓ Fertig: $APP"
