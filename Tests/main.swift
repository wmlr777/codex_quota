import Foundation
func decode(_ json: String) throws -> QuotaResponse { try JSONDecoder().decode(QuotaResponse.self, from: Data(json.utf8)) }
func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
let preferred = try decode(#"{"rateLimits":{"primary":{"usedPercent":1}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":68,"windowDurationMins":300},"secondary":{"usedPercent":31,"windowDurationMins":10080}}}}"#)
check(preferred.codex?.primary?.remaining == 32, "Prefer named Codex bucket")
check(preferred.codex?.secondary?.remaining == 69, "Weekly remaining")
check(preferred.codex?.primary?.label == "5 小时", "Window duration")
check(preferred.codex?.secondary?.label == "1 周", "Weekly duration")
let missing = try decode(#"{"rateLimits":{"primary":{},"secondary":null}}"#)
check(missing.codex?.primary?.remaining == nil, "Missing usage must not mean 100%")
let other = try decode(#"{"rateLimits":{"primary":{"usedPercent":1}},"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":90}}}}"#)
check(other.codex == nil, "Never present unrelated quota as Codex")
let clamped = try decode(#"{"rateLimits":{"primary":{"usedPercent":110},"secondary":{"usedPercent":-10}}}"#)
check(clamped.codex?.primary?.remaining == 0, "Lower clamp")
check(clamped.codex?.secondary?.remaining == 100, "Upper clamp")
print("6 quota decoding scenarios passed")
