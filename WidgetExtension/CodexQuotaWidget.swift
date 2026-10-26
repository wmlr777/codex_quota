import SwiftUI
import WidgetKit
import AppIntents

struct QuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}
struct QuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: .now, snapshot: .empty)
    }
    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(QuotaEntry(date: .now, snapshot: WidgetCache.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let now = Date(), snapshot = WidgetCache.read()
        var entries = [QuotaEntry(date: now, snapshot: snapshot)]
        // End a stuck refresh indicator if the app stops before replying.
        if let started = snapshot.refreshStartedAt,
           snapshot.refreshStatus(at: now) == .refreshing {
            entries.append(QuotaEntry(date: started.addingTimeInterval(WidgetSnapshot.refreshTimeout), snapshot: snapshot))
        }
        // Mark old snapshots stale even when the menu bar app has stopped.
        if let updated = snapshot.updatedAt {
            let staleDate = updated.addingTimeInterval(181)
            if staleDate > now { entries.append(QuotaEntry(date: staleDate, snapshot: snapshot)) }
        }
        entries.sort { $0.date < $1.date }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
}

struct QuotaWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: QuotaEntry
    private func label(_ minutes: Int?, fallback: String) -> String {
        guard let minutes else { return fallback }
        if minutes % 10080 == 0 { return L10n.text("\(minutes / 10080) 周", "\(minutes / 10080) wk") }
        if minutes % 60 == 0 { return L10n.text("\(minutes / 60) 小时", "\(minutes / 60) hr") }
        return L10n.text("\(minutes) 分钟", "\(minutes) min")
    }
    private func meter(_ remaining: Int?, label: String, reset: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(remaining.map { "\($0)%" } ?? "—")
                    .font(.system(size: family == .systemSmall ? 20 : 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill((remaining ?? 100) <= 10 ? Color.red : Color.blue)
                        .frame(width: geometry.size.width * Double(max(0, min(100, remaining ?? 0))) / 100)
                }
            }
            .frame(height: 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(remaining.map { "\($0)%" } ?? L10n.text("暂无数据", "Unavailable"))
            if family == .systemMedium, let reset {
                Text(Date(timeIntervalSince1970: reset), format: .dateTime.month().day().hour().minute())
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private var status: WidgetSnapshot.RefreshStatus { entry.snapshot.refreshStatus(at: entry.date) }
    private var statusSymbol: String {
        switch status {
        case .refreshing: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .stale: return "clock.badge.exclamationmark"
        case .empty: return "info.circle"
        }
    }
    private var statusText: String {
        switch status {
        case .refreshing: return L10n.text("正在更新…", "Updating…")
        case .failed: return L10n.text("更新失败 · 点击重试", "Update failed · Tap to retry")
        case .empty: return L10n.text("点击刷新以同步额度", "Tap refresh to sync quota")
        case .stale: return L10n.text("数据待更新 · 点击刷新", "Out of date · Tap to refresh")
        case .succeeded: return L10n.text("更新成功", "Up to date")
        }
    }
    private var lastRefreshText: String {
        guard let date = entry.snapshot.updatedAt else {
            return L10n.text("上次刷新：尚未成功", "Last update: Never")
        }
        let time = Calendar.current.isDate(date, inSameDayAs: entry.date)
            ? date.formatted(date: .omitted, time: .standard)
            : date.formatted(.dateTime.month().day().hour().minute())
        return L10n.text("上次刷新：\(time)", "Last update: \(time)")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Codex Quota")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button(intent: RefreshQuotaIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(status == .refreshing ? 360 : 0))
                        .animation(.easeInOut(duration: 0.8), value: entry.snapshot.refreshStartedAt)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 24)
                    .foregroundStyle(Color.accentColor)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                .disabled(status == .refreshing)
                .accessibilityLabel(L10n.text("刷新额度", "Refresh quota"))
            }
            let layout = family == .systemSmall ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 18))
            layout {
                meter(entry.snapshot.primaryRemaining,
                      label: label(entry.snapshot.primaryMinutes, fallback: L10n.text("短期", "Short-term")),
                      reset: entry.snapshot.primaryReset)
                meter(entry.snapshot.secondaryRemaining,
                      label: label(entry.snapshot.secondaryMinutes, fallback: L10n.text("每周", "Weekly")),
                      reset: entry.snapshot.secondaryReset)
            }
            .invalidatableContent()
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Image(systemName: statusSymbol)
                        .contentTransition(.symbolEffect(.replace))
                    Text(statusText).lineLimit(1).minimumScaleFactor(0.8)
                }
                .foregroundStyle(status == .failed || status == .stale ? Color.orange : Color.secondary)
                .invalidatableContent()
                .animation(.easeInOut(duration: 0.25), value: status)
                // Keep the last successful data timestamp visible during refresh
                // and after failure, instead of replacing it with status text.
                Text(lastRefreshText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .monospacedDigit()
            }
            .font(family == .systemSmall ? .system(size: 9) : .caption2)
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "codexquota://refresh"))
    }
}

@main
struct CodexQuotaDesktopWidget: Widget {
    let kind = "CodexQuotaDesktopWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaProvider()) { QuotaWidgetView(entry: $0) }
            .configurationDisplayName("Codex Quota")
            .description(L10n.text("查看 Codex 短期与每周剩余额度。", "See your short-term and weekly Codex quota."))
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
