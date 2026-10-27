import AppKit
import SwiftUI
import WidgetKit
import OSLog

final class QuotaStore: ObservableObject {
    @Published var quota: QuotaBucket?
    @Published var updated: Date?
    @Published var error: String?
    @Published var loading = false
    @Published var panelHeight: CGFloat = 420
    var changed: (() -> Void)?
    let client = QuotaClient()
    private var refreshStartedAt: Date?
    private var refreshFinishedAt: Date?
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []

    @MainActor
    func refreshAndWait() async {
        await withCheckedContinuation { continuation in
            refreshWaiters.append(continuation)
            refresh()
        }
    }

    private func publishWidgetSnapshot() {
        // Preserve the last snapshot on a cold launch while the new query runs.
        var snapshot = WidgetCache.read()
        if let quota {
            snapshot.primaryRemaining = quota.primary?.remaining
            snapshot.secondaryRemaining = quota.secondary?.remaining
            snapshot.primaryMinutes = quota.primary?.windowDurationMins
            snapshot.secondaryMinutes = quota.secondary?.windowDurationMins
            snapshot.primaryReset = quota.primary?.resetsAt
            snapshot.secondaryReset = quota.secondary?.resetsAt
        }
        snapshot.updatedAt = updated ?? snapshot.updatedAt
        snapshot.failed = error != nil
        snapshot.refreshStartedAt = refreshStartedAt
        snapshot.refreshFinishedAt = refreshFinishedAt
        if WidgetCache.write(snapshot) {
            WidgetCenter.shared.reloadTimelines(ofKind: "CodexQuotaDesktopWidget")
        }
    }
    func refresh() {
        guard !loading else { return }
        loading = true
        refreshStartedAt = .now
        publishWidgetSnapshot()
        changed?()
        client.fetch { [weak self] result in
            guard let self else { return }
            self.loading = false
            switch result {
            case .success(let quota): self.quota = quota; self.updated = Date(); self.error = nil
            case .failure(let error): self.error = error.localizedDescription
            }
            self.refreshFinishedAt = .now
            self.publishWidgetSnapshot()
            let waiters = self.refreshWaiters
            self.refreshWaiters.removeAll()
            waiters.forEach { $0.resume() }
            self.changed?()
        }
    }
    var stale: Bool { error != nil || (updated.map { Date().timeIntervalSince($0) > 120 } ?? false) }
    var title: String {
        guard let quota else { return loading ? "◉ …" : "◉ —" }
        let primary = quota.primary?.remaining.map { "\($0)%" } ?? "—"
        let secondary = quota.secondary?.remaining.map { "\($0)%" } ?? "—"
        let label = quota.secondary?.windowDurationMins == 10080 ? L10n.text("周", "wk") : (quota.secondary?.label ?? L10n.text("长期", "long"))
        return "\(stale ? "⚠︎" : "◉") \(primary) · \(label) \(secondary)"
    }
}

struct WindowCard: View {
    let window: QuotaWindow?
    let fallback: String
    var tint: Color { (window?.remaining ?? 100) <= 10 ? .red : ((window?.remaining ?? 100) <= 25 ? .orange : .accentColor) }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(window?.label ?? fallback).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(window?.remaining.map { "\($0)%" } ?? "—").font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(L10n.text("剩余", "left")).font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(window?.remaining ?? 0), total: 100).tint(tint)
            if let reset = window?.resetsAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let seconds = max(0, Int(reset - context.date.timeIntervalSince1970))
                    let hours = seconds / 3600
                    let minutes = seconds % 3600 / 60
                    Text(seconds == 0 ? L10n.text("已到重置时间，等待服务更新", "Reset due; waiting for server update") : L10n.text("\(hours) 小时 \(minutes) 分钟后重置", "Resets in \(hours)h \(minutes)m"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(Date(timeIntervalSince1970: reset), format: .dateTime.month().day().hour().minute())
                    .font(.caption2).foregroundStyle(.tertiary)
            } else { Text(L10n.text("暂无重置信息", "Reset time unavailable")).font(.caption).foregroundStyle(.secondary) }
        }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}
private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
struct QuotaPanel: View {
    @ObservedObject var store: QuotaStore
    let chooseBinary: () -> Void
    let hideMenuBar: () -> Void
    let contentHeightChanged: (CGFloat) -> Void
    var body: some View {
        ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "chart.bar.xaxis").font(.title3).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex Quota").font(.headline)
                    Text("\(L10n.text("订阅额度", "Subscription quota")) · \(store.quota?.planType?.capitalized ?? "Codex")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.loading { ProgressView().controlSize(.small) }
            }
            WindowCard(window: store.quota?.primary, fallback: L10n.text("短期额度", "Short-term quota"))
            WindowCard(window: store.quota?.secondary, fallback: L10n.text("每周额度", "Weekly quota"))
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let updated = store.updated {
                    Text("\(store.stale ? L10n.text("上次成功", "Last success") : L10n.text("更新于", "Updated")) \(updated.formatted(date: .omitted, time: .standard))")
                } else { Text(L10n.text("等待读取额度", "Waiting for quota")) }
                Spacer()
                Text(L10n.text("每 60 秒刷新", "Refreshes every 60s"))
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button(L10n.text("刷新", "Refresh"), systemImage: "arrow.clockwise") { store.refresh() }.disabled(store.loading)
                Spacer()
                Menu {
                    Button(L10n.text("打开 Codex", "Open Codex")) {
                        for path in ["/Applications/Codex.app", "/Applications/ChatGPT.app"] where FileManager.default.fileExists(atPath: path) {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path)); break
                        }
                    }
                    Button(L10n.text("选择 Codex 可执行文件…", "Choose Codex executable…"), action: chooseBinary)
                    Divider()
                    Button(L10n.text("隐藏菜单栏图标（保持后台运行）", "Hide menu bar icon (keep running)"), action: hideMenuBar)
                    Button(L10n.text("退出", "Quit")) { NSApp.terminate(nil) }
                } label: { Image(systemName: "gearshape") }.menuStyle(.borderlessButton).frame(width: 24)
            }.controlSize(.small)
        }.padding(18).frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: PanelHeightKey.self, value: geometry.size.height)
            })
        }.frame(width: 350, height: store.panelHeight, alignment: .top)
            .onPreferenceChange(PanelHeightKey.self, perform: contentHeightChanged)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = QuotaStore()
    var item: NSStatusItem!
    let popover = NSPopover()
    var measuredContentHeight: CGFloat = 420
    var timer: Timer?
    var wakeObserver: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification: Notification) {
        WidgetRefreshAction.handler = { [weak store] in
            await store?.refreshAndWait()
        }
        NSApp.setActivationPolicy(.accessory)
        createStatusItem(visible: !UserDefaults.standard.bool(forKey: "hideMenuBarIcon"))
        popover.behavior = .transient
        let host = NSHostingController(rootView: QuotaPanel(
            store: store,
            chooseBinary: { [weak self] in self?.chooseBinary() },
            hideMenuBar: { [weak self] in self?.setMenuBarVisible(false) },
            contentHeightChanged: { [weak self] height in
                guard height.isFinite, height > 0 else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.measuredContentHeight = ceil(height)
                    self.resizePopover()
                }
            }
        ))
        // Size explicitly from the natural content height, capped to the screen.
        // Disable automatic hosting sizing to avoid competing resize mechanisms.
        host.sizingOptions = []
        popover.contentViewController = host
        popover.contentSize = NSSize(width: 350, height: store.panelHeight)
        store.changed = { [weak self] in self?.updateTitle() }
        updateTitle(); store.refresh()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.store.refresh() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.store.refresh() }
    }
    private let menuLog = Logger(subsystem: "local.codex.quota", category: "MenuBar")
    private func createStatusItem(visible: Bool) {
        if let existing = item { NSStatusBar.system.removeStatusItem(existing) }
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item = statusItem
        statusItem.isVisible = visible
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        updateTitle()
        menuLog.info("Created menu bar item; requested visibility: \(visible)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak statusItem] in
            guard let self, let statusItem, let button = statusItem.button else { return }
            let window = button.window
            let frame = window.map { NSStringFromRect($0.frame) } ?? "none"
            let screen = window?.screen.map { NSStringFromRect($0.frame) } ?? "none"
            self.menuLog.info("Status item diagnostic: itemVisible=\(statusItem.isVisible), windowVisible=\(window?.isVisible ?? false), frame=\(frame, privacy: .public), screen=\(screen, privacy: .public)")
        }
    }
    func setMenuBarVisible(_ visible: Bool) {
        if !visible { popover.performClose(nil) }
        UserDefaults.standard.set(!visible, forKey: "hideMenuBarIcon")
        item.isVisible = visible
        // The process, quota timer and WidgetKit cache continue running.
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Recreate the status item instead of relying on an existing item that
        // macOS may no longer display after it was hidden or reorganized.
        popover.performClose(nil)
        UserDefaults.standard.set(false, forKey: "hideMenuBarIcon")
        createStatusItem(visible: true)
        menuLog.info("Application reopened; menu bar item recreated")
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.popover.isShown else { return }
            self.toggle()
        }
        return false
    }
    func updateTitle() {
        item.button?.title = store.title
        item.button?.toolTip = L10n.text("Codex 剩余额度", "Codex remaining quota") + (store.stale ? L10n.text("（上次读取失败）", " (last read failed)") : "")
    }
    func resizePopover() {
        let availableHeight = max(100, (item.button?.window?.screen?.visibleFrame.height ?? 600) - 40)
        let height = min(measuredContentHeight, availableHeight)
        guard abs(store.panelHeight - height) > 0.5 else { return }
        store.panelHeight = height
        popover.contentSize = NSSize(width: 350, height: height)
    }
    @objc func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            resizePopover()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if store.updated == nil || Date().timeIntervalSince(store.updated!) > 60 { store.refresh() }
        }
    }
    func chooseBinary() {
        popover.performClose(nil)
        let panel = NSOpenPanel(); panel.title = L10n.text("选择 codex 可执行文件", "Choose the codex executable"); panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if QuotaClient.isExecutableFile(url.path) {
            UserDefaults.standard.set(url.path, forKey: "codexPath"); store.refresh()
        } else {
            let alert = NSAlert()
            alert.messageText = L10n.text("请选择可执行文件", "Select an executable file")
            alert.informativeText = L10n.text("请选择名为 codex 的程序文件，而不是 .app 应用或文件夹。", "Choose the codex program file, not an .app bundle or folder.")
            alert.runModal()
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "codexquota" && $0.host == "refresh" }) {
            store.refresh()
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); store.client.stop()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}

if CommandLine.arguments.contains("--probe") {
    let client = QuotaClient()
    client.fetch { result in
        switch result {
        case .success(let quota):
            print("Codex: primary=\(quota.primary?.remaining.map(String.init) ?? "unavailable")%, secondary=\(quota.secondary?.remaining.map(String.init) ?? "unavailable")%")
            exit(0)
        case .failure(let error): fputs(error.localizedDescription + "\n", stderr); exit(1)
        }
    }
    RunLoop.main.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
