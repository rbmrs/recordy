#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
ARCHS="${ARCHS:-arm64 x86_64}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
APP_DIR="${APP_DIR:-$OUTPUT_DIR/Recordy.app}"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

echo "Building Recordy ($CONFIGURATION, archs: $ARCHS)…"

# Build each architecture as a separate single-arch slice. This uses SwiftPM's
# native build system, which works under plain Command Line Tools — unlike a
# multi-arch (`--arch a --arch b`) build, which requires full Xcode's xcbuild.
# The slices are merged into a universal binary with lipo below.
SLICES=()
for ARCH in ${(s: :)ARCHS}; do
  echo "  • $ARCH"
  swift build \
    --configuration "$CONFIGURATION" \
    --product recordy \
    --arch "$ARCH"
  SLICE="$(swift build --configuration "$CONFIGURATION" --arch "$ARCH" --show-bin-path)/recordy"
  if [[ ! -x "$SLICE" ]]; then
    echo "Build succeeded but the $ARCH executable was not found at:"
    echo "$SLICE"
    exit 1
  fi
  SLICES+=("$SLICE")
done

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "Merging slices into a universal binary…"
lipo -create "${SLICES[@]}" -output "$MACOS_DIR/recordy"

cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

chmod 755 "$MACOS_DIR/recordy"

echo "Signing Recordy.app with a stable local requirement…"
codesign \
  --force \
  --sign - \
  --identifier com.rafaelbm.Recordy \
  --requirements '=designated => identifier "com.rafaelbm.Recordy"' \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
plutil -lint "$CONTENTS_DIR/Info.plist"

echo
echo "Built:"
echo "$APP_DIR"
lipo -info "$MACOS_DIR/recordy"
