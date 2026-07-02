# Homebrew Cask for Recordy — a native macOS screen recorder scoped to a region.
#
# Install:
#   brew tap rbmrs/recordy https://github.com/rbmrs/recordy
#   brew trust rbmrs/recordy   # required on Homebrew 6.0+
#   brew install --cask recordy
#
# The 2-arg `brew tap` form is required because the repo is named `recordy`,
# not `homebrew-recordy`. See https://docs.brew.sh/Taps.

cask "recordy" do
  version "0.1.4"
  sha256 "1909d45381b18fff746a20d9946e5d6d8e92c3b5eb3303b2bc6ea80c841f6af0"

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
