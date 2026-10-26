import Foundation
func decode(_ json: String) throws -> QuotaResponse { try JSONDecoder().decode(QuotaResponse.self, from: Data(json.utf8)) }
func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
let preferred = try decode(#"{"rateLimits":{"primary":{"usedPercent":1}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":68,"windowDurationMins":300},"secondary":{"usedPercent":31,"windowDurationMins":10080}}}}"#)
check(preferred.codex?.primary?.remaining == 32, "Prefer named Codex bucket")
check(preferred.codex?.secondary?.remaining == 69, "Weekly remaining")
check(preferred.codex?.primary?.label == L10n.text("5 小时", "5 hr"), "Window duration")
check(preferred.codex?.secondary?.label == L10n.text("1 周", "1 wk"), "Weekly duration")
let missing = try decode(#"{"rateLimits":{"primary":{},"secondary":null}}"#)
check(missing.codex?.primary?.remaining == nil, "Missing usage must not mean 100%")
let other = try decode(#"{"rateLimits":{"primary":{"usedPercent":1}},"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":90}}}}"#)
check(other.codex == nil, "Never present unrelated quota as Codex")
let clamped = try decode(#"{"rateLimits":{"primary":{"usedPercent":110},"secondary":{"usedPercent":-10}}}"#)
check(clamped.codex?.primary?.remaining == 0, "Lower clamp")
check(clamped.codex?.secondary?.remaining == 100, "Upper clamp")
print("6 quota decoding scenarios passed")

check(L10n.usesChinese(["zh-Hans-CN", "en-US"]), "Chinese system language")
check(!L10n.usesChinese(["en-GB", "zh-Hans"]), "Respect English preference")
check(!L10n.usesChinese(["fr-FR"]), "Unsupported language falls back to English")
check(L10n.usesChinese(["ja-JP", "zh-Hant-TW", "en"]), "Next supported language")
print("Language preference checks passed")

check(!QuotaClient.isExecutableFile(FileManager.default.temporaryDirectory.path), "Reject searchable directories as executables")
check(QuotaClient.isExecutableFile("/bin/sh"), "Accept executable files")
check(!QuotaClient.isExecutableFile("/nonexistent/codex"), "Reject missing executable")
print("Executable path validation passed")

let now = Date()
let freshWidget = WidgetSnapshot(primaryRemaining: 72, secondaryRemaining: 85, updatedAt: now, failed: false)
check(!freshWidget.isStale(at: now), "Fresh widget snapshot")
check(freshWidget.isStale(at: now.addingTimeInterval(181)), "Widget becomes stale when host stops")
check(WidgetSnapshot.empty.isStale(at: now), "Missing cache is unavailable")
check(WidgetSnapshot(updatedAt: now, failed: true).isStale(at: now), "Failed refresh is stale")
let roundTrip = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(freshWidget))
check(roundTrip.primaryRemaining == 72 && roundTrip.secondaryRemaining == 85, "Shared snapshot round trip")
print("Widget snapshot tests passed")

var refreshing = freshWidget
refreshing.refreshStartedAt = now
refreshing.refreshFinishedAt = now.addingTimeInterval(-60)
check(refreshing.refreshStatus(at: now) == .refreshing, "A new refresh supersedes an old result")
check(refreshing.refreshStatus(at: now.addingTimeInterval(35)) == .failed, "Interrupted refresh expires instead of spinning forever")
refreshing.refreshFinishedAt = now.addingTimeInterval(2)
check(refreshing.refreshStatus(at: now.addingTimeInterval(2)) == .succeeded, "Successful completion clears updating state")
refreshing.failed = true
check(refreshing.refreshStatus(at: now.addingTimeInterval(2)) == .failed, "Failed update is shown even with cached quota")
check(refreshing.primaryRemaining == 72, "Failed refresh preserves last successful quota")
let legacySnapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(#"{"primaryRemaining":50,"failed":false}"#.utf8))
check(legacySnapshot.refreshStartedAt == nil && legacySnapshot.refreshFinishedAt == nil, "Old snapshot format remains readable")
check(WidgetSnapshot.empty.refreshStatus(at: now) == .empty, "Empty state is distinct from failure")
check(freshWidget.refreshStatus(at: now.addingTimeInterval(181)) == .stale, "Old data is distinct from request failure")
print("Widget refresh lifecycle tests passed")
