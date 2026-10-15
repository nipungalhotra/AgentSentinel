cask "agent-sentinel" do
  version "1.2.0"
  sha256 "f26c84b0c01881a740c61f6b72eaf2852c4a9d4191c0d9ba72a428bf5c3a95ce"

  url "https://github.com/nipungalhotra/AgentSentinel/releases/download/v#{version}/AgentSentinel-v#{version}.dmg"
  name "Agent Sentinel"
  desc "Universal Liquid Glass Permission Gate for AI Coding Agents"
  homepage "https://github.com/nipungalhotra/AgentSentinel"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "AgentSentinel.app"
  binary "#{appdir}/AgentSentinel.app/Contents/MacOS/AgentSentinel", target: "sentinel-daemon"

  postflight do
    # Deploy CLI to ~/.local/bin and configure universal hooks
    system_command "/bin/sh",
                   args: ["-c", "mkdir -p #{ENV["HOME"]}/.local/bin && curl -fsSL https://raw.githubusercontent.com/nipungalhotra/AgentSentinel/main/bin/sentinel -o #{ENV["HOME"]}/.local/bin/sentinel && chmod +x #{ENV["HOME"]}/.local/bin/sentinel"]
  end

  uninstall quit: "com.antigravity.agentsentinel"

  zap trash: [
    "~/Library/Application Support/AgentSentinel",
    "~/Library/Preferences/com.antigravity.agentsentinel.plist"
  ]
end
