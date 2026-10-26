cask "reson" do
  version "0.5.3"
  sha256 "6b75845915a0fedaa84909bb1ccef9a924eae97d0ff4d4fe17fd22c418adff49"

  url "https://github.com/olivecarney/reson/releases/download/v#{version}/Reson-#{version}-macos-arm64.dmg"
  name "reson"
  desc "Lightweight native local music player"
  homepage "https://github.com/olivecarney/reson"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Reson.app", target: "reson.app"

  caveats <<~EOS
    reson is ad-hoc signed and is not Apple-notarized.
    macOS may require approval in System Settings > Privacy & Security.
    Uninstalling this cask preserves your library, playlists and preferences.
  EOS
end
