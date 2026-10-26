cask "reson" do
  version "0.5.4"
  sha256 "ea9e354ab87fda5cf28f6e747fc461f5d246a75575e54caf2b42a940b0d997ba"

  url "https://github.com/olivecarney/reson/releases/download/v#{version}/reson-#{version}-macos-arm64.dmg"
  name "reson"
  desc "Lightweight native local music player"
  homepage "https://github.com/olivecarney/reson"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "reson.app"

  caveats <<~EOS
    reson is ad-hoc signed and is not Apple-notarized.
    macOS may require approval in System Settings > Privacy & Security.
    Uninstalling this cask preserves your library, playlists and preferences.
  EOS
end
