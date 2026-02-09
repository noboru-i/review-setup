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

    // VS Codeを起動して配置
    func openVSCodeAndArrange(path: String, position: LayoutPosition = .center) throws {
        logInfo("=== VS Code配置処理開始 ===")

        // 1. パスを検証
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            logError("パスが存在しません: \(path)")
            throw NSError(domain: "WindowManager", code: 7,
                         userInfo: [NSLocalizedDescriptionKey: "Path does not exist: \(path)"])
        }

        logInfo("1. パスを検証: \(path)")

        // 2. codeコマンドのパスを解決
        logInfo("2. codeコマンドのパスを解決中...")
        let codePath = try resolveCodeCommand()
        logInfo("   codeコマンド検出: \(codePath)")

        // 3. VS Codeを新規ウィンドウで起動
        logInfo("3. VS Codeを新規ウィンドウで起動中...")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: codePath)
        task.arguments = ["-n", path]

        do {
            try task.run()
            task.waitUntilExit()
            logInfo("   VS Code起動コマンド実行完了")
        } catch {
            logError("   VS Code起動失敗 - \(error.localizedDescription)")
            throw NSError(domain: "WindowManager", code: 8,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to launch VS Code: \(error.localizedDescription)"])
        }

        // 4. VS Codeウィンドウが完全に開くまで待機
        logInfo("4. VS Codeウィンドウの起動を待機中（3.0秒）...")
        Thread.sleep(forTimeInterval: 3.0)

        // 5. VS Codeプロセスを取得
        logInfo("5. VS Codeプロセスを検索中...")
        guard let vscodeApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.microsoft.VSCode"
        }) else {
            logError("   VS Codeプロセスが見つかりません")
            throw NSError(domain: "WindowManager", code: 9,
                         userInfo: [NSLocalizedDescriptionKey: "VS Code not found. VS Codeがインストールされているか確認してください。"])
        }

        logInfo("   VS Code検出成功 (PID: \(vscodeApp.processIdentifier))")

        // 6. Accessibility要素を取得
        logInfo("6. Accessibility要素を取得中...")
        let appElement = AXUIElementCreateApplication(vscodeApp.processIdentifier)

        // 7. ウィンドウを取得
        logInfo("7. ウィンドウを取得中...")
        let window = try getVSCodeWindow(appElement: appElement, targetPath: path)

        // 8. スクリーン解像度を取得
        logInfo("8. スクリーン情報を取得中...")
        guard let screen = NSScreen.main else {
            logError("   メインスクリーンが見つかりません")
            throw NSError(domain: "WindowManager", code: 10,
                         userInfo: [NSLocalizedDescriptionKey: "Screen not found"])
        }
        let screenFrame = screen.visibleFrame

        logDebug("   画面サイズ: \(screenFrame.width) x \(screenFrame.height)")
        logDebug("   画面位置: (\(screenFrame.minX), \(screenFrame.minY))")

        // 9. ウィンドウ位置とサイズを計算
        logInfo("9. 配置位置を計算中...")
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

        // 10. ウィンドウ位置とサイズを設定
        logInfo("10. ウィンドウ位置を設定中...")
        try setWindowPosition(window, x: x, y: y)
        logInfo("   位置設定成功")

        logInfo("11. ウィンドウサイズを設定中...")
        try setWindowSize(window, width: width, height: height)
        logInfo("   サイズ設定成功")

        // 設定後の確認
        var newPosRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &newPosRef)
        var newSizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &newSizeRef)

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

        logInfo("=== ✓ VS Codeウィンドウ配置完了 ===")
        logInfo("")
    }

    // codeコマンドのパスを解決
    private func resolveCodeCommand() throws -> String {
        let possiblePaths = [
            "/usr/local/bin/code",
            "/opt/homebrew/bin/code",
            "/usr/bin/code"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // PATHから検索
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["code"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty {
                    return output
                }
            }
        } catch {
            logError("   whichコマンド実行失敗: \(error.localizedDescription)")
        }

        logError("   codeコマンドが見つかりません")
        throw NSError(domain: "WindowManager", code: 11,
                     userInfo: [NSLocalizedDescriptionKey: "code command not found. VS Codeのコマンドラインツールがインストールされているか確認してください。"])
    }

    // VS Codeウィンドウを取得（フォーカスウィンドウまたはタイトル検索）
    private func getVSCodeWindow(appElement: AXUIElement, targetPath: String) throws -> AXUIElement {
        // 方法1: フォーカスされたウィンドウを取得
        var focusedWindowRef: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowRef
        )

        if focusedError == .success, focusedWindowRef != nil {
            logInfo("   フォーカスウィンドウを直接取得成功")
            return (focusedWindowRef as! AXUIElement)
        }

        // 方法2: フォールバック - タイトルでウィンドウを検索
        logInfo("   フォーカスウィンドウ取得失敗、タイトル検索にフォールバック...")
        return try arrangeVSCodeWindowByTitle(appElement: appElement, targetPath: targetPath)
    }

    // タイトルでVS Codeウィンドウを検索
    private func arrangeVSCodeWindowByTitle(appElement: AXUIElement, targetPath: String) throws -> AXUIElement {
        var windowsRef: CFTypeRef?
        let windowsError = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )

        guard windowsError == .success else {
            logError("   ウィンドウ取得失敗 (error: \(windowsError.rawValue))")
            throw NSError(domain: "WindowManager", code: 12,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to get windows (error: \(windowsError.rawValue))"])
        }

        guard let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            logError("   ウィンドウが空")
            throw NSError(domain: "WindowManager", code: 12,
                         userInfo: [NSLocalizedDescriptionKey: "Window list is empty"])
        }

        logInfo("   ウィンドウ取得成功: 全\(windows.count)個")

        // パス名を含むウィンドウを検索
        let pathBaseName = URL(fileURLWithPath: targetPath).lastPathComponent

        for (index, window) in windows.enumerated() {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)

            if let title = titleRef as? String {
                logDebug("   ウィンドウ[\(index)]: タイトル=\(title)")

                // タイトルにパス名が含まれているかチェック
                if title.contains(pathBaseName) || title.contains(targetPath) {
                    logInfo("   マッチするウィンドウを発見: \(title)")
                    return window
                }
            }
        }

        // 見つからない場合は最初のウィンドウを使用
        logInfo("   パスに一致するウィンドウが見つからないため、最初のウィンドウを使用")
        return windows[0]
    }
}
