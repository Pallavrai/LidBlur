cask "lidblur" do
  version "0.1.4"
  sha256 "4a44f84042ce6f2d9e479cf53ce48c4e95e00b59c8802d47681e203462046e8f"

  url "https://github.com/Pallavrai/LidBlur/releases/download/v#{version}/LidBlur-#{version}.dmg"
  name "LidBlur"
  desc "Blurs and dims the MacBook screen as the lid closes"
  homepage "https://github.com/Pallavrai/LidBlur"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "LidBlur.app"

  uninstall quit: "com.pallavrai.lidblur"

  zap trash: "~/Library/Preferences/com.pallavrai.lidblur.plist"
end
