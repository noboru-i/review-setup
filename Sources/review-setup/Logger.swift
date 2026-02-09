import Cocoa
import ApplicationServices
import OSLog

// OSLogを使用したロガー
let logger = Logger(subsystem: "com.example.review-setup", category: "WindowManager")

// ログヘルパー（OSLog使用）
// privacy: .public を指定して、動的な値も表示されるようにする
func log(_ message: String, type: OSLogType = .default) {
    // OSLogに出力（Console.appで確認可能）
    // \(message, privacy: .public) で動的な値を公開
    logger.log(level: type, "\(message, privacy: .public)")
}

// ログレベル付きヘルパー
func logDebug(_ message: String) {
    log(message, type: .debug)
}

func logInfo(_ message: String) {
    log(message, type: .info)
}

func logError(_ message: String) {
    log(message, type: .error)
}
