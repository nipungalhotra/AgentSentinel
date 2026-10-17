import Foundation
import AppKit

struct SnapshotEntry: Identifiable, Codable {
    var id: UUID = UUID()
    let originalPath: String
    let snapshotPath: String
    let timestamp: Date
    let agentName: String

    var filename: String {
        URL(fileURLWithPath: originalPath).lastPathComponent
    }

    var timeAgo: String {
        let seconds = Int(Date().timeIntervalSince(timestamp))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }
}

@MainActor @Observable
final class SnapshotManager {
    static let shared = SnapshotManager()

    private(set) var snapshots: [SnapshotEntry] = []
    private let snapshotsDir: URL
    private let fileManager = FileManager.default

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AgentSentinel", isDirectory: true)
        snapshotsDir = appSupport.appendingPathComponent("snapshots", isDirectory: true)
        try? fileManager.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
        loadFromDisk()
    }

    var latestSnapshot: SnapshotEntry? {
        snapshots.first
    }

    func createSnapshot(for originalPath: String, agent: String = "Agent") -> SnapshotEntry? {
        guard fileManager.fileExists(atPath: originalPath) else { return nil }

        let id = UUID()
        let filename = URL(fileURLWithPath: originalPath).lastPathComponent
        let targetFile = snapshotsDir.appendingPathComponent("\(id.uuidString)_\(filename)")

        do {
            try? fileManager.removeItem(at: targetFile)
            try fileManager.copyItem(atPath: originalPath, toPath: targetFile.path)

            let entry = SnapshotEntry(
                id: id,
                originalPath: originalPath,
                snapshotPath: targetFile.path,
                timestamp: Date(),
                agentName: agent
            )
            snapshots.insert(entry, at: 0)
            if snapshots.count > 30 {
                if let old = snapshots.popLast() {
                    try? fileManager.removeItem(atPath: old.snapshotPath)
                }
            }
            saveToDisk()
            return entry
        } catch {
            return nil
        }
    }

    @discardableResult
    func undoLatest() -> SnapshotEntry? {
        guard let latest = snapshots.first else { return nil }
        return restore(entry: latest)
    }

    @discardableResult
    func restore(entry: SnapshotEntry) -> SnapshotEntry? {
        guard fileManager.fileExists(atPath: entry.snapshotPath) else { return nil }

        do {
            if fileManager.fileExists(atPath: entry.originalPath) {
                try? fileManager.removeItem(atPath: entry.originalPath)
            }
            try fileManager.copyItem(atPath: entry.snapshotPath, toPath: entry.originalPath)

            snapshots.removeAll { $0.id == entry.id }
            try? fileManager.removeItem(atPath: entry.snapshotPath)
            saveToDisk()

            // Deliver feedback notification
            let notif = NSUserNotification()
            notif.title = "Action Undone"
            notif.informativeText = "Restored \(entry.filename) to state before \(entry.agentName)'s edit."
            NSUserNotificationCenter.default.deliver(notif)
            SoundEngine.shared.playAllow()

            return entry
        } catch {
            return nil
        }
    }

    private func saveToDisk() {
        let metaURL = snapshotsDir.appendingPathComponent("index.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshots) {
            try? data.write(to: metaURL)
        }
    }

    private func loadFromDisk() {
        let metaURL = snapshotsDir.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: metaURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([SnapshotEntry].self, from: data) {
            self.snapshots = loaded.filter { fileManager.fileExists(atPath: $0.snapshotPath) }
        }
    }
}
