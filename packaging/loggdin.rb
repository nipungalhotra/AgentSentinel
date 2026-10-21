cask "loggdin" do
  version "1.2.0"
  sha256 :no_check # Updated upon GitHub release tag

  url "https://github.com/nipungalhotra/AgentSentinel/releases/download/v#{version}/Loggdin.dmg"
  name "loggdin"
  desc "Universal Liquid Glass Permission Gate for AI Coding Agents"
  homepage "https://github.com/nipungalhotra/AgentSentinel"

  auto_updates true
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
