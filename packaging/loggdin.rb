cask "loggdin" do
  version "1.2.1"
  sha256 "d8236f9b2b647453d69d5451cec7c8d91883f41320e7e8316fdf96b877107a18"

  url "https://github.com/nipungalhotra/AgentSentinel/releases/download/v#{version}/loggdin-v#{version}.dmg"
  name "loggdin"
  desc "Universal Liquid Glass Permission Gate for AI Coding Agents"
  homepage "https://github.com/nipungalhotra/AgentSentinel"

  depends_on macos: ">= :sonoma"

  app "Loggdin.app"
  binary "#{appdir}/Loggdin.app/Contents/Resources/bin/loggdin", target: "loggdin"
  binary "#{appdir}/Loggdin.app/Contents/Resources/bin/sentinel", target: "sentinel"

  uninstall quit:      "com.antigravity.loggdin",
            launchctl: "com.antigravity.loggdin"

  zap trash: [
    "~/Library/Application Support/AgentSentinel",
    "~/Library/Application Support/Loggdin",
    "~/Library/Preferences/com.antigravity.loggdin.plist",
    "~/.loggdin"
  ]
end
