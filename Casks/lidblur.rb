cask "lidblur" do
  version "0.1.0"
  sha256 "e314c0df8ac06cc0d06a2356bbfb5254010659ca9d6b782a56a2fa6a0c510270"

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
