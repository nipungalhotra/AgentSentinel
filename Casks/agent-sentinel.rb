cask "agent-sentinel" do
  version "1.2.0"
  sha256 "79f9745e181836b6fa611d1181b02cbcd663a1613ce24982b46b7e3a24a9e5db"

  url "https://github.com/nipungalhotra/AgentSentinel/releases/download/v#{version}/loggdin-v#{version}.dmg"
  name "Agent Sentinel"
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
    "~/Library/Preferences/com.antigravity.agentsentinel.plist",
    "~/.loggdin"
  ]
end
