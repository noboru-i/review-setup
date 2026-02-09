import Cocoa
import ApplicationServices

// ウィンドウ配置を管理するクラス
class WindowManager {

    enum LayoutPosition {
        case left, center, right
    }

    // ブラウザを起動して配置（左1/3）
    func openBrowserAndArrange(url: String, position: LayoutPosition = .left) throws {
        logInfo("=== ブラウザ配置処理開始 ===")

        // 1. URLを検証
        guard URL(string: url) != nil else {
            logError("URLが無効です: \(url)")
            throw NSError(domain: "WindowManager", code: 1,
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
            throw NSError(domain: "WindowManager", code: 2,
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
            throw NSError(domain: "WindowManager", code: 3,
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
                throw NSError(domain: "WindowManager", code: 4,
                             userInfo: [NSLocalizedDescriptionKey: "Failed to get windows (error: \(windowsError.rawValue)). アクセシビリティ権限を確認してください。"])
            }

            guard let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
                logError("   ウィンドウが空またはキャスト失敗")
                throw NSError(domain: "WindowManager", code: 4,
                             userInfo: [NSLocalizedDescriptionKey: "Window list is empty. アクセシビリティ権限を確認してください。"])
            }

            logInfo("   ウィンドウ取得成功: 全\(windows.count)個")

            // 標準のブラウザウィンドウのみをフィルタリング
            window = try findMainBrowserWindow(in: windows)
        }

        guard let targetWindow = window else {
            logError("   メインウィンドウが見つかりません")
            throw NSError(domain: "WindowManager", code: 4,
                         userInfo: [NSLocalizedDescriptionKey: "Main window not found"])
        }

        // ウィンドウの現在の位置とサイズを取得
        var currentPosRef: CFTypeRef?
        AXUIElementCopyAttributeValue(targetWindow, kAXPositionAttribute as CFString, &currentPosRef)
        var currentSizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(targetWindow, kAXSizeAttribute as CFString, &currentSizeRef)

        if let posValue = currentPosRef {
            var point = CGPoint.zero
            AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
            logDebug("   現在のウィンドウ位置: (\(point.x), \(point.y))")
        }

        if let sizeValue = currentSizeRef {
            var size = CGSize.zero
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            logDebug("   現在のウィンドウサイズ: (\(size.width) x \(size.height))")
        }

        // 7. スクリーン解像度を取得
        logInfo("7. スクリーン情報を取得中...")
        guard let screen = NSScreen.main else {
            logError("   メインスクリーンが見つかりません")
            throw NSError(domain: "WindowManager", code: 5,
                         userInfo: [NSLocalizedDescriptionKey: "Screen not found"])
        }
        let screenFrame = screen.visibleFrame

        logDebug("   画面サイズ: \(screenFrame.width) x \(screenFrame.height)")
        logDebug("   画面位置: (\(screenFrame.minX), \(screenFrame.minY))")

        // 8. ウィンドウ位置とサイズを計算
        logInfo("8. 配置位置を計算中...")
        let (x, width): (CGFloat, CGFloat)
        switch position {
        case .left:
            x = screenFrame.minX
            width = screenFrame.width / 3
            logInfo("   配置: 左1/3")
        case .center:
            x = screenFrame.minX + screenFrame.width / 3
            width = screenFrame.width / 3
            logInfo("   配置: 中央1/3")
        case .right:
            x = screenFrame.minX + screenFrame.width * 2 / 3
            width = screenFrame.width / 3
            logInfo("   配置: 右1/3")
        }

        let height = screenFrame.height
        let y = screenFrame.minY

        logDebug("   目標位置: (\(x), \(y))")
        logDebug("   目標サイズ: (\(width) x \(height))")

        // 9. ウィンドウ位置とサイズを設定
        logInfo("9. ウィンドウ位置を設定中...")
        try setWindowPosition(targetWindow, x: x, y: y)
        logInfo("   位置設定成功")

        logInfo("10. ウィンドウサイズを設定中...")
        try setWindowSize(targetWindow, width: width, height: height)
        logInfo("   サイズ設定成功")

        // 設定後の確認
        var newPosRef: CFTypeRef?
        AXUIElementCopyAttributeValue(targetWindow, kAXPositionAttribute as CFString, &newPosRef)
        var newSizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(targetWindow, kAXSizeAttribute as CFString, &newSizeRef)

        if let posValue = newPosRef {
            var point = CGPoint.zero
            AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
            logInfo("   設定後の位置: (\(point.x), \(point.y))")
        }

        if let sizeValue = newSizeRef {
            var size = CGSize.zero
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            logInfo("   設定後のサイズ: (\(size.width) x \(size.height))")
        }

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

    // ウィンドウ位置を設定
    private func setWindowPosition(_ window: AXUIElement, x: CGFloat, y: CGFloat) throws {
        var position = CGPoint(x: x, y: y)
        let positionValue = AXValueCreate(.cgPoint, &position)!

        let error = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            positionValue
        )

        if error != .success {
            logError("      位置設定エラー: \(error.rawValue)")
            logDebug("      0=success, -25200=invalid UIElement, -25201=illegal argument, -25202=invalid UIElementObserver")
            logDebug("      -25203=cannot complete, -25204=attribute unsupported, -25205=action unsupported")
            logDebug("      -25206=not implemented, -25207=not in this application, -25208=no value, -25209=value illegal")
            logDebug("      -25210=timeout, -25211=illegal index")
            throw NSError(domain: "WindowManager", code: 5,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to set window position (error: \(error.rawValue)). アクセシビリティ権限を確認してください。"])
        }
    }

    // ウィンドウサイズを設定
    private func setWindowSize(_ window: AXUIElement, width: CGFloat, height: CGFloat) throws {
        var size = CGSize(width: width, height: height)
        let sizeValue = AXValueCreate(.cgSize, &size)!

        let error = AXUIElementSetAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            sizeValue
        )

        if error != .success {
            logError("      サイズ設定エラー: \(error.rawValue)")
            logDebug("      0=success, -25200=invalid UIElement, -25201=illegal argument, -25202=invalid UIElementObserver")
            logDebug("      -25203=cannot complete, -25204=attribute unsupported, -25205=action unsupported")
            logDebug("      -25206=not implemented, -25207=not in this application, -25208=no value, -25209=value illegal")
            logDebug("      -25210=timeout, -25211=illegal index")
            throw NSError(domain: "WindowManager", code: 6,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to set window size (error: \(error.rawValue)). アクセシビリティ権限を確認してください。"])
        }
    }
}
