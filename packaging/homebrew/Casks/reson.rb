cask "reson" do
  version "0.6.0"
  sha256 "ef74783366bb1fbdf8c5f26d49bcaff5402a2ffe7220b5e543ec9ca7385ae505"

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
