# Copy into the separate tap repository github.com/<user>/homebrew-lidblur; scripts/release.sh prints version and sha256.
cask "lidblur" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE_SH"

  url "https://github.com/pallavrai/LidBlur/releases/download/v#{version}/LidBlur-#{version}.dmg"
  name "LidBlur"
  desc "Blurs and dims the MacBook screen as the lid closes"
  homepage "https://github.com/pallavrai/LidBlur"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "LidBlur.app"

  uninstall quit: "com.pallavrai.lidblur"

  zap trash: "~/Library/Preferences/com.pallavrai.lidblur.plist"
end
