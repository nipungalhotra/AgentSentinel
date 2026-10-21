cask "agent-sentinel" do
  version "1.2.0"
  sha256 "bf5a2227fb44a3f4328be591c93d5cbdd8eecd3d252cf1b05e2f76e125333632"

  url "https://github.com/nipungalhotra/AgentSentinel/releases/download/v#{version}/Loggdin-v#{version}.dmg"
  name "Agent Sentinel"
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
    "~/Library/Preferences/com.antigravity.agentsentinel.plist",
    "~/.loggdin"
  ]
end
