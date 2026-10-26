cask "lidblur" do
  version "0.1.0"
  sha256 "d0aee1842b56d1db6b4a116ee211ce43913234fe861e075909e51d2ea2fabece"

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
