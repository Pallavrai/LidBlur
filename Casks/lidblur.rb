cask "lidblur" do
  version "0.1.1"
  sha256 "2a415be3aa1e9a88bbb93f2173ea2c0c7819c7b588e0684f9f2643c9478256c2"

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
