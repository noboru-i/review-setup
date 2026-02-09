import Cocoa
import ApplicationServices

// VS Codeウィンドウを管理するクラス
class VSCodeWindowManager {

    // VS Codeを起動して配置
    func openVSCodeAndArrange(path: String, position: LayoutPosition = .center) throws {
        logInfo("=== VS Code配置処理開始 ===")

        // 1. パスを検証
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            logError("パスが存在しません: \(path)")
            throw NSError(domain: "VSCodeWindowManager", code: 1,
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
            throw NSError(domain: "VSCodeWindowManager", code: 2,
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
            throw NSError(domain: "VSCodeWindowManager", code: 3,
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
            throw NSError(domain: "VSCodeWindowManager", code: 4,
                         userInfo: [NSLocalizedDescriptionKey: "Screen not found"])
        }
        let screenFrame = screen.visibleFrame

        logDebug("   画面サイズ: \(screenFrame.width) x \(screenFrame.height)")
        logDebug("   画面位置: (\(screenFrame.minX), \(screenFrame.minY))")

        // 9. ウィンドウ位置とサイズを計算
        logInfo("9. 配置位置を計算中...")
        let (x, y, width, height) = WindowOperations.calculateWindowFrame(
            screenFrame: screenFrame,
            position: position
        )

        // 10. ウィンドウ位置とサイズを設定
        logInfo("10. ウィンドウ位置を設定中...")
        try WindowOperations.setWindowPosition(window, x: x, y: y)
        logInfo("   位置設定成功")

        logInfo("11. ウィンドウサイズを設定中...")
        try WindowOperations.setWindowSize(window, width: width, height: height)
        logInfo("   サイズ設定成功")

        // 設定後の確認
        WindowOperations.logWindowInfo(window, prefix: "   設定後の")

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
        throw NSError(domain: "VSCodeWindowManager", code: 5,
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
            throw NSError(domain: "VSCodeWindowManager", code: 6,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to get windows (error: \(windowsError.rawValue))"])
        }

        guard let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            logError("   ウィンドウが空")
            throw NSError(domain: "VSCodeWindowManager", code: 6,
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
