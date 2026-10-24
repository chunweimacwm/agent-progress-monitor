import Foundation

/// 介面語言：自動（跟系統）、繁體中文、English。設定存在 UserDefaults 的 "language"。
public enum AppLanguage: String, CaseIterable, Sendable {
    case auto, zh, en

    public static var setting: AppLanguage {
        get { UserDefaults.standard.string(forKey: "language").flatMap(AppLanguage.init) ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "language") }
    }

    public static var isChinese: Bool {
        switch setting {
        case .zh: true
        case .en: false
        case .auto: Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }

    public var title: String {
        switch self {
        case .auto: L("自動（跟系統）", "Auto (system)")
        case .zh: "繁體中文"
        case .en: "English"
        }
    }
}

/// 依目前語言回傳中文或英文
public func L(_ zh: String, _ en: String) -> String {
    AppLanguage.isChinese ? zh : en
}
