import Foundation

/// Базовый URL API. Приоритет: launch-аргумент `-SONIFY_API_BASE_URL`, env-переменная схемы,
/// Info.plist, затем localhost.
enum AppConfig {
    static var apiBaseURL: URL {
        if let arg = UserDefaults.standard.string(forKey: "SONIFY_API_BASE_URL"), let url = URL(string: arg) {
            return url
        }
        if let env = ProcessInfo.processInfo.environment["SONIFY_API_BASE_URL"], let url = URL(string: env) {
            return url
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "SONIFY_API_BASE_URL") as? String,
           let url = URL(string: plist) {
            return url
        }
        return URL(string: "http://127.0.0.1:8080/api/v1")!
    }

    static let requestTimeout: TimeInterval = 15
    static let maxRetries = 2
}
