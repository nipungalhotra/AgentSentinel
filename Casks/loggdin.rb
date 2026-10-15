cask "loggdin" do
  version "1.2.0"
  sha256 "79f9745e181836b6fa611d1181b02cbcd663a1613ce24982b46b7e3a24a9e5db"

  url "https://github.com/nipungalhotra/AgentSentinel/releases/download/v#{version}/loggdin-v#{version}.dmg"
  name "loggdin"
  desc "Universal Liquid Glass Permission Gate for AI Coding Agents"
  homepage "https://github.com/nipungalhotra/AgentSentinel"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Loggdin.app"
  binary "#{appdir}/Loggdin.app/Contents/MacOS/loggdin", target: "loggdin"

  postflight do
    # Deploy CLI to ~/.local/bin and configure universal hooks
    system_command "/bin/sh",
                   args: ["-c", "mkdir -p #{ENV["HOME"]}/.local/bin && curl -fsSL https://raw.githubusercontent.com/nipungalhotra/AgentSentinel/main/bin/loggdin -o #{ENV["HOME"]}/.local/bin/loggdin && chmod +x #{ENV["HOME"]}/.local/bin/loggdin && ln -sf #{ENV["HOME"]}/.local/bin/loggdin #{ENV["HOME"]}/.local/bin/sentinel"]
  end

  uninstall quit: "com.antigravity.loggdin"

  zap trash: [
    "~/Library/Application Support/AgentSentinel",
    "~/Library/Application Support/Loggdin",
    "~/Library/Preferences/com.antigravity.loggdin.plist"
  ]
end
