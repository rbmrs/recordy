#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(plutil -extract CFBundleShortVersionString raw -o - "$ROOT_DIR/Resources/Info.plist")}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
RELEASE_DIR="${RELEASE_DIR:-$OUTPUT_DIR/release}"
BUILD_DIR="${BUILD_DIR:-$OUTPUT_DIR/build}"

rm -rf "$RELEASE_DIR" "$BUILD_DIR"
mkdir -p "$RELEASE_DIR"

# Build one universal (arm64 + x86_64) app bundle.
VERSION="$VERSION" OUTPUT_DIR="$BUILD_DIR" "$ROOT_DIR/scripts/build-app.sh"

# Normalize timestamps so the archive is reproducible across runs.
find "$BUILD_DIR/Recordy.app" -exec touch -t 202001010000 {} +

ZIP_NAME="Recordy-$VERSION.zip"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"
echo "Packaging $ZIP_NAME…"
(
  cd "$BUILD_DIR"
  zip -qry -X "$ZIP_PATH" "Recordy.app"
)

SHA="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "$SHA  $ZIP_NAME" > "$RELEASE_DIR/SHA256SUMS.txt"

# Generate the tap-ready cask. The main repo doubles as the Homebrew tap, so the
# release workflow copies this file over Casks/recordy.rb on main.
CASK_PATH="$RELEASE_DIR/recordy.rb"
cat > "$CASK_PATH" <<EOF
# Homebrew Cask for Recordy — a native macOS screen recorder scoped to a region.
#
# Install:
#   brew tap rbmrs/recordy https://github.com/rbmrs/recordy
#   brew trust rbmrs/recordy   # required on Homebrew 6.0+
#   brew install --cask recordy
#
# The 2-arg \`brew tap\` form is required because the repo is named \`recordy\`,
# not \`homebrew-recordy\`. See https://docs.brew.sh/Taps.

cask "recordy" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/rbmrs/recordy/releases/download/v#{version}/Recordy-#{version}.zip"
  name "Recordy"
  desc "Screen recorder scoped to a region"
  homepage "https://github.com/rbmrs/recordy"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Recordy.app"

  # Recordy is ad-hoc signed (no Apple Developer ID). Stripping the quarantine
  # xattr stops Gatekeeper from blocking the unsigned app on first launch. Safe
  # because the user explicitly opted into this tap.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Recordy.app"],
                   sudo: false
  end

  zap trash: "~/Library/Preferences/com.rafaelbm.Recordy.plist"

  caveats <<~CAVEATS
    Recordy asks for Screen Recording permission on first capture.

    This build is unsigned (no Apple Developer ID). macOS ties the
    Screen Recording grant to this specific build's signature, so
    upgrading may require re-granting the permission.
  CAVEATS
end
EOF

echo
echo "Release artifacts:"
ls -1 "$RELEASE_DIR"
echo
echo "SHA-256:"
cat "$RELEASE_DIR/SHA256SUMS.txt"
echo
echo "Cask generated at:"
echo "$CASK_PATH"
