cask "lidblur" do
  version "0.1.2"
  sha256 "a2f9350c4edc6816a580da91a3c6676764bdef2a1717b5ad06958b0e87dc421f"

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
