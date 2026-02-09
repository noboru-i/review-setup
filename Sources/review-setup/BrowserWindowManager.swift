import Cocoa
import ApplicationServices

// ブラウザウィンドウを管理するクラス
class BrowserWindowManager {

    // ブラウザを起動して配置（左1/3）
    func openBrowserAndArrange(url: String, position: LayoutPosition = .left) throws {
        logInfo("=== ブラウザ配置処理開始 ===")

        // 1. URLを検証
        guard URL(string: url) != nil else {
            logError("URLが無効です: \(url)")
            throw NSError(domain: "BrowserWindowManager", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(url)"])
        }

        logInfo("1. URLを検証: \(url)")

        // 2. Chrome を新規ウィンドウで起動
        logInfo("2. Chromeを新規ウィンドウで起動中...")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [
            "-na", "Google Chrome",
            "--args",
            "--new-window",
            url
        ]

        do {
            try task.run()
            task.waitUntilExit()
            logInfo("   Chrome起動コマンド実行完了")
        } catch {
            logError("   Chrome起動失敗 - \(error.localizedDescription)")
            throw NSError(domain: "BrowserWindowManager", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to launch Chrome: \(error.localizedDescription)"])
        }

        // 3. Chromeウィンドウが完全に開くまで待機
        logInfo("3. Chromeウィンドウの起動を待機中（2.5秒）...")
        Thread.sleep(forTimeInterval: 2.5)

        // 4. Chromeプロセスを取得
        logInfo("4. Chromeプロセスを検索中...")
        guard let chromeApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.google.Chrome"
        }) else {
            logError("   Chromeプロセスが見つかりません")
            throw NSError(domain: "BrowserWindowManager", code: 3,
                         userInfo: [NSLocalizedDescriptionKey: "Chrome not found. Google Chromeがインストールされているか確認してください。"])
        }

        logInfo("   Chrome検出成功 (PID: \(chromeApp.processIdentifier))")

        // 5. Accessibility要素を取得
        logInfo("5. Accessibility要素を取得中...")
        let appElement = AXUIElementCreateApplication(chromeApp.processIdentifier)

        // 6. メインウィンドウを取得（翻訳ポップアップなどを除外）
        logInfo("6. メインウィンドウを取得中...")

        // 6-1. まずメインウィンドウを直接取得を試みる
        var mainWindowRef: CFTypeRef?
        let mainError = AXUIElementCopyAttributeValue(
            appElement,
            kAXMainWindowAttribute as CFString,
            &mainWindowRef
        )

        var window: AXUIElement?

        if mainError == .success, mainWindowRef != nil {
            logInfo("   メインウィンドウを直接取得成功")
            window = (mainWindowRef as! AXUIElement)
        } else {
            // 6-2. 全ウィンドウを取得してフィルタリング
            logInfo("   全ウィンドウリストから検索中...")
            var windowsRef: CFTypeRef?
            let windowsError = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &windowsRef
            )

            logDebug("   ウィンドウ取得結果: \(windowsError.rawValue) (0=success)")

            guard windowsError == .success else {
                logError("   ウィンドウ取得失敗 (error: \(windowsError.rawValue)) - アクセシビリティ権限を確認してください")
                throw NSError(domain: "BrowserWindowManager", code: 4,
                             userInfo: [NSLocalizedDescriptionKey: "Failed to get windows (error: \(windowsError.rawValue)). アクセシビリティ権限を確認してください。"])
            }

            guard let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
                logError("   ウィンドウが空またはキャスト失敗")
                throw NSError(domain: "BrowserWindowManager", code: 4,
                             userInfo: [NSLocalizedDescriptionKey: "Window list is empty. アクセシビリティ権限を確認してください。"])
            }

            logInfo("   ウィンドウ取得成功: 全\(windows.count)個")

            // 標準のブラウザウィンドウのみをフィルタリング
            window = try findMainBrowserWindow(in: windows)
        }

        guard let targetWindow = window else {
            logError("   メインウィンドウが見つかりません")
            throw NSError(domain: "BrowserWindowManager", code: 4,
                         userInfo: [NSLocalizedDescriptionKey: "Main window not found"])
        }

        // ウィンドウの現在の位置とサイズを取得
        WindowOperations.logWindowInfo(targetWindow, prefix: "   現在のウィンドウ")

        // 7. スクリーン解像度を取得
        logInfo("7. スクリーン情報を取得中...")
        guard let screen = NSScreen.main else {
            logError("   メインスクリーンが見つかりません")
            throw NSError(domain: "BrowserWindowManager", code: 5,
                         userInfo: [NSLocalizedDescriptionKey: "Screen not found"])
        }
        let screenFrame = screen.visibleFrame

        logDebug("   画面サイズ: \(screenFrame.width) x \(screenFrame.height)")
        logDebug("   画面位置: (\(screenFrame.minX), \(screenFrame.minY))")

        // 8. ウィンドウ位置とサイズを計算
        logInfo("8. 配置位置を計算中...")
        let (x, y, width, height) = WindowOperations.calculateWindowFrame(
            screenFrame: screenFrame,
            position: position
        )

        // 9. ウィンドウ位置とサイズを設定
        logInfo("9. ウィンドウ位置を設定中...")
        try WindowOperations.setWindowPosition(targetWindow, x: x, y: y)
        logInfo("   位置設定成功")

        logInfo("10. ウィンドウサイズを設定中...")
        try WindowOperations.setWindowSize(targetWindow, width: width, height: height)
        logInfo("   サイズ設定成功")

        // 設定後の確認
        WindowOperations.logWindowInfo(targetWindow, prefix: "   設定後の")

        logInfo("=== ✓ Chromeウィンドウ配置完了 ===")
        logInfo("")
    }

    // メインブラウザウィンドウを検索（翻訳ポップアップなどを除外）
    private func findMainBrowserWindow(in windows: [AXUIElement]) throws -> AXUIElement? {
        logInfo("   ウィンドウをフィルタリング中...")

        var candidates: [(window: AXUIElement, score: Int)] = []

        for (index, window) in windows.enumerated() {
            var score = 0

            // ロールを確認
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String

            // サブロールを確認
            var subroleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef)
            let subrole = subroleRef as? String

            // タイトルを確認
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String

            // サイズを確認
            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
            var size = CGSize.zero
            if let sizeValue = sizeRef {
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            }

            logDebug("     ウィンドウ[\(index)]: role=\(role ?? "nil"), subrole=\(subrole ?? "nil"), title=\(title ?? "nil"), size=\(size.width)x\(size.height)")

            // フィルタリング条件
            // 1. ロールがWindow
            if role == kAXWindowRole as String {
                score += 10
            } else {
                continue // Windowでないものは除外
            }

            // 2. サブロールが標準ウィンドウ
            if subrole == kAXStandardWindowSubrole as String {
                score += 20
            }

            // 3. タイトルが存在する
            if let t = title, !t.isEmpty {
                score += 15
            }

            // 4. サイズが十分大きい（翻訳ポップアップは小さい）
            if size.width > 400 && size.height > 400 {
                score += 25
            }

            // 5. 最初のウィンドウを優先（通常は最新）
            if index == 0 {
                score += 5
            }

            logDebug("     → スコア: \(score)")
            candidates.append((window: window, score: score))
        }

        // スコアでソートして最も高いものを選択
        candidates.sort { $0.score > $1.score }

        if let best = candidates.first {
            logInfo("   最適なウィンドウを選択 (スコア: \(best.score))")
            return best.window
        }

        logError("   適切なウィンドウが見つかりませんでした")
        return nil
    }
}
