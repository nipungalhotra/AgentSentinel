cask "loggdin" do
  version "1.2.3"
  sha256 "a44672a3aad68ff259886b7611d2dfe34b93f4d7690d59d9632d800cf67bb3dd"

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
