cask "reson" do
  version "0.5.2"
  sha256 "8e8187a2d598eb7822e1b56f9da02aeb6b53af28688551279b1b3839e3875aca"

  url "https://github.com/olivecarney/reson/releases/download/v#{version}/Reson-#{version}-macos-arm64.dmg"
  name "Reson"
  desc "Lightweight native local music player"
  homepage "https://github.com/olivecarney/reson"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Reson.app"

  caveats <<~EOS
    Reson is ad-hoc signed and is not Apple-notarized.
    macOS may require approval in System Settings > Privacy & Security.
    Uninstalling this cask preserves your library, playlists and preferences.
  EOS
end
