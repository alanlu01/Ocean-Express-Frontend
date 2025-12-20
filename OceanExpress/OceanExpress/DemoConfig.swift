import Foundation

enum DemoConfig {
    private static let storageKey = "demo_mode_enabled"

    /// 是否啟用 demo 模式：優先環境變數 DEMO_MODE（true/1/yes），否則讀取 UserDefaults 持久化設定。
    static var isEnabled: Bool {
        let env = ProcessInfo.processInfo.environment["DEMO_MODE"]?.lowercased() ?? ""
        if env == "1" || env == "true" || env == "yes" { return true }
        return UserDefaults.standard.bool(forKey: storageKey)
    }

    /// 是否為 demo 帳號登入（僅 demo-token 時才視為假資料模式）
    static var isDemoAccount: Bool {
        guard isEnabled else { return false }
        return UserDefaults.standard.string(forKey: "auth_token") == "demo-token"
    }

    static func setDemo(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: storageKey)
    }
}
