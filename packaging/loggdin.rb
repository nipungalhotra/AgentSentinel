cask "loggdin" do
  version "1.0.0"
  sha256 :no_check # Replace with sha256 checksum of GitHub release asset

  url "https://github.com/nipungalhotra/AgentSentinel/releases/download/v#{version}/Loggdin.dmg"
  name "loggdin"
  desc "Autonomous AI Agent Security Gate & Biometric Permission Notch for macOS"
  homepage "https://github.com/nipungalhotra/AgentSentinel"

  depends_on macos: ">= :sonoma"

  app "Loggdin.app"

  postflight do
    system_command "#{appdir}/Loggdin.app/Contents/MacOS/loggdin",
                   args: ["--install-all"],
                   sudo: false
  end

  uninstall quit:      "com.antigravity.loggdin",
            launchctl: "com.antigravity.loggdin"

  zap trash: [
    "~/Library/Application Support/AgentSentinel",
    "/tmp/sentinel.sock",
    "/tmp/sentinel_dedup.json",
  ]
end
