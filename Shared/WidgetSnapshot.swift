import Foundation
import AppIntents

struct WidgetSnapshot: Codable {
    var primaryRemaining: Int?
    var secondaryRemaining: Int?
    var primaryMinutes: Int?
    var secondaryMinutes: Int?
    var primaryReset: Double?
    var secondaryReset: Double?
    var updatedAt: Date?
    var failed: Bool
    // Optional fields preserve compatibility with existing on-disk snapshots.
    var refreshStartedAt: Date?
    var refreshFinishedAt: Date?

    enum RefreshStatus: Equatable {
        case empty, refreshing, succeeded, failed, stale
    }
    static let refreshTimeout: TimeInterval = 35
    func refreshStatus(at date: Date) -> RefreshStatus {
        if let started = refreshStartedAt,
           refreshFinishedAt == nil || refreshFinishedAt! < started {
            return date.timeIntervalSince(started) < Self.refreshTimeout ? .refreshing : .failed
        }
        if failed { return .failed }
        guard let updatedAt else { return .empty }
        return date.timeIntervalSince(updatedAt) > 180 ? .stale : .succeeded
    }

    static let empty = WidgetSnapshot(failed: false)
    func isStale(at date: Date) -> Bool {
        refreshStatus(at: date) == .failed || (updatedAt.map { date.timeIntervalSince($0) > 180 } ?? true)
    }
}

enum WidgetCache {
    static var fileURL: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "QuotaAppGroup") as? String,
              !group.isEmpty, !group.contains("$("),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return container.appendingPathComponent("quota-widget.json")
    }
    static func read() -> WidgetSnapshot {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = fileURL else { return false }
        do {
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            return true
        } catch { return false }
    }
}

// WidgetKit performs this foreground intent in the host app's process. The
// handler waits for the actual request, so the automatic post-intent timeline
// reload reads the completed result rather than an old snapshot.
@MainActor
enum WidgetRefreshAction {
    static var handler: (() async -> Void)?
    static func run() async {
        if let handler {
            await handler()
        } else {
            var snapshot = WidgetCache.read()
            snapshot.failed = true
            snapshot.refreshFinishedAt = .now
            _ = WidgetCache.write(snapshot)
        }
    }
}

struct RefreshQuotaIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Codex quota"
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await WidgetRefreshAction.run()
        return .result()
    }
}
