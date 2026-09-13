import AppKit
import SwiftUI

final class QuotaStore: ObservableObject {
    @Published var quota: QuotaBucket?
    @Published var updated: Date?
    @Published var error: String?
    @Published var loading = false
    var changed: (() -> Void)?
    let client = QuotaClient()
    func refresh() {
        guard !loading else { return }
        loading = true; changed?()
        client.fetch { [weak self] result in
            guard let self else { return }
            self.loading = false
            switch result {
            case .success(let quota): self.quota = quota; self.updated = Date(); self.error = nil
            case .failure(let error): self.error = error.localizedDescription
            }
            self.changed?()
        }
    }
    var stale: Bool { error != nil || (updated.map { Date().timeIntervalSince($0) > 120 } ?? false) }
    var title: String {
        guard let quota else { return loading ? "◉ …" : "◉ —" }
        let primary = quota.primary?.remaining.map { "\($0)%" } ?? "—"
        let secondary = quota.secondary?.remaining.map { "\($0)%" } ?? "—"
        let label = quota.secondary?.windowDurationMins == 10080 ? "周" : (quota.secondary?.label ?? "长期")
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
                Text("剩余").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(window?.remaining ?? 0), total: 100).tint(tint)
            if let reset = window?.resetsAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let seconds = max(0, Int(reset - context.date.timeIntervalSince1970))
                    let hours = seconds / 3600
                    let minutes = seconds % 3600 / 60
                    Text(seconds == 0 ? "已到重置时间，等待服务更新" : "\(hours > 0 ? "\(hours) 小时 " : "")\(minutes) 分钟后重置")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(Date(timeIntervalSince1970: reset), format: .dateTime.month().day().hour().minute())
                    .font(.caption2).foregroundStyle(.tertiary)
            } else { Text("暂无重置信息").font(.caption).foregroundStyle(.secondary) }
        }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}
struct QuotaPanel: View {
    @ObservedObject var store: QuotaStore
    let chooseBinary: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "chart.bar.xaxis").font(.title3).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex Quota").font(.headline)
                    Text("订阅额度 · \(store.quota?.planType?.capitalized ?? "Codex")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.loading { ProgressView().controlSize(.small) }
            }
            WindowCard(window: store.quota?.primary, fallback: "短期额度")
            WindowCard(window: store.quota?.secondary, fallback: "每周额度")
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let updated = store.updated {
                    Text("\(store.stale ? "上次成功" : "更新于") \(updated.formatted(date: .omitted, time: .standard))")
                } else { Text("等待读取额度") }
                Spacer()
                Text("每 60 秒刷新")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("刷新", systemImage: "arrow.clockwise") { store.refresh() }.disabled(store.loading)
                Spacer()
                Menu {
                    Button("打开 Codex") {
                        for path in ["/Applications/Codex.app", "/Applications/ChatGPT.app"] where FileManager.default.fileExists(atPath: path) {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path)); break
                        }
                    }
                    Button("选择 Codex 可执行文件…", action: chooseBinary)
                    Divider()
                    Button("退出") { NSApp.terminate(nil) }
                } label: { Image(systemName: "gearshape") }.menuStyle(.borderlessButton).frame(width: 24)
            }.controlSize(.small)
        }.padding(18).frame(width: 330)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = QuotaStore()
    var item: NSStatusItem!
    let popover = NSPopover()
    var timer: Timer?
    var wakeObserver: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        item.button?.target = self; item.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: QuotaPanel(store: store, chooseBinary: { [weak self] in self?.chooseBinary() }))
        store.changed = { [weak self] in self?.updateTitle() }
        updateTitle(); store.refresh()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.store.refresh() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.store.refresh() }
    }
    func updateTitle() {
        item.button?.title = store.title
        item.button?.toolTip = "Codex 剩余额度\(store.stale ? "（上次读取失败）" : "")"
    }
    @objc func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if store.updated == nil || Date().timeIntervalSince(store.updated!) > 60 { store.refresh() }
        }
    }
    func chooseBinary() {
        popover.performClose(nil)
        let panel = NSOpenPanel(); panel.title = "选择 codex 可执行文件"; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, FileManager.default.isExecutableFile(atPath: url.path) {
            UserDefaults.standard.set(url.path, forKey: "codexPath"); store.refresh()
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
