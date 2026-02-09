import Cocoa
import ApplicationServices

// ウィンドウ配置の位置を表す列挙型
enum LayoutPosition {
    case left, center, right
}

// ウィンドウ配置を管理するクラス（ファサード）
class WindowManager {
    private let browserManager = BrowserWindowManager()
    private let vscodeManager = VSCodeWindowManager()

    // ブラウザを起動して配置（左1/3）
    func openBrowserAndArrange(url: String, position: LayoutPosition = .left) throws {
        try browserManager.openBrowserAndArrange(url: url, position: position)
    }

    // VS Codeを起動して配置
    func openVSCodeAndArrange(path: String, position: LayoutPosition = .center) throws {
        try vscodeManager.openVSCodeAndArrange(path: path, position: position)
    }
}
