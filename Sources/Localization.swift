import Foundation

// Follow macOS preferred languages, including an app-specific language override.
// Chinese and English are supported; other languages fall back to English.
enum L10n {
    static func usesChinese(_ languages: [String]) -> Bool {
        for language in languages {
            let code = language.lowercased()
            if code == "zh" || code.hasPrefix("zh-") { return true }
            if code == "en" || code.hasPrefix("en-") { return false }
        }
        return false
    }
    static var isChinese: Bool { usesChinese(Locale.preferredLanguages) }
    static func text(_ chinese: String, _ english: String) -> String { isChinese ? chinese : english }
}
