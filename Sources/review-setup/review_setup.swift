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

class MissionControlManager {
    
    // Mission Controlを起動
    func openMissionControl() {
        // openコマンドでMission Controlを起動
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Mission Control"]
        task.launch()
        task.waitUntilExit()

        // Mission Controlが完全に表示されるまで待機
        Thread.sleep(forTimeInterval: 1.0)
    }
    
    // 新しいデスクトップを作成
    func createNewDesktop() throws {
        // 1. Mission Controlを起動
        openMissionControl()
        
        // 2. Dockアプリケーションへの参照を取得
        guard let dockApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first else {
            throw NSError(domain: "MissionControl", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Dock not found"])
        }
        
        // 3. Dockのアクセシビリティ要素を取得
        let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        
        // 4. "Mission Control"グループを探す
        var missionControlGroup: AXUIElement?
        try findMissionControlGroup(in: dockElement, result: &missionControlGroup)
        
        guard let mcGroup = missionControlGroup else {
            throw NSError(domain: "MissionControl", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Mission Control group not found"])
        }
        
        // 5. フォーカスディスプレイのboundsを取得
        let displayBounds = focusedDisplayBounds()
        logger.info("[DEBUG] フォーカスディスプレイ bounds: \(String(describing: displayBounds))")

        // 6. すべての"add desktop"ボタンを探す
        var addButtons: [AXUIElement] = []
        findAllAddDesktopButtons(in: mcGroup, buttons: &addButtons)
        logger.info("[DEBUG] 見つかったadd desktopボタン数: \(addButtons.count)")

        for (i, button) in addButtons.enumerated() {
            let pos = getElementPosition(button)
            let size = getElementSize(button)
            logger.info("[DEBUG] ボタン[\(i)] position: \(String(describing: pos)), size: \(String(describing: size))")
        }

        guard !addButtons.isEmpty else {
            throw NSError(domain: "MissionControl", code: 4,
                         userInfo: [NSLocalizedDescriptionKey: "Add button not found"])
        }

        // 7. フォーカスディスプレイ内のボタンを選択
        let targetButton: AXUIElement
        if let bounds = displayBounds, addButtons.count > 1 {
            targetButton = addButtons.first { button in
                if let pos = getElementPosition(button) {
                    let contained = bounds.contains(pos)
                    logger.info("[DEBUG] ボタン position \(String(describing: pos)) が bounds \(String(describing: bounds)) に含まれるか: \(contained)")
                    return contained
                }
                logger.info("[DEBUG] ボタンの位置を取得できず")
                return false
            } ?? addButtons[0]
        } else {
            targetButton = addButtons[0]
            logger.info("[DEBUG] ボタンが1つのみ、またはディスプレイ検出失敗のため先頭を使用")
        }

        logger.info("[DEBUG] 選択されたボタン: \(String(describing: targetButton))")

        // 8. ボタンをクリック
        try performPress(on: targetButton)
        
        // 9. デスクトップ作成の完了を待機
        Thread.sleep(forTimeInterval: 0.5)

        // 10. Mission Controlを閉じる（トグル動作）
        openMissionControl()

        // 11. Mission Controlが完全に閉じるまで待機
        Thread.sleep(forTimeInterval: 0.8)
    }
    
    // Mission Controlグループを探す
    private func findMissionControlGroup(in element: AXUIElement,
                                         result: inout AXUIElement?) throws {
        var childrenRef: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        )

        guard error == .success,
              let children = childrenRef as? [AXUIElement] else {
            return
        }

        for child in children {
            // タイトルを確認
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(
                child,
                kAXTitleAttribute as CFString,
                &titleRef
            )

            // デバッグ: 見つかった要素を出力
            if let title = titleRef as? String {
                print("見つかった要素: \(title)")
            }

            if let title = titleRef as? String,
               title == "Mission Control" {
                result = child
                return
            }

            // 再帰的に探索
            try findMissionControlGroup(in: child, result: &result)
            if result != nil {
                return
            }
        }
    }
    
    // すべての"add desktop"ボタンを探す
    private func findAllAddDesktopButtons(in element: AXUIElement, buttons: inout [AXUIElement]) {
        var childrenRef: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        )

        guard error == .success,
              let children = childrenRef as? [AXUIElement] else {
            return
        }

        for child in children {
            var descRef: CFTypeRef?
            AXUIElementCopyAttributeValue(
                child,
                kAXDescriptionAttribute as CFString,
                &descRef
            )

            if let description = descRef as? String,
               description.contains("デスクトップを追加") ||
               description.contains("add desktop") {
                buttons.append(child)
            }

            // 再帰的に探索
            findAllAddDesktopButtons(in: child, buttons: &buttons)
        }
    }

    // AX要素の画面上の位置を取得
    private func getElementPosition(_ element: AXUIElement) -> CGPoint? {
        var posRef: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &posRef
        )
        guard error == .success else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
        return point
    }

    // マウスカーソルのあるディスプレイのboundsを取得（CG座標系）
    private func focusedDisplayBounds() -> CGRect? {
        guard let mouseEvent = CGEvent(source: nil) else {
            logger.info("[DEBUG] CGEvent生成失敗")
            return nil
        }
        let mouseLocation = mouseEvent.location
        logger.info("[DEBUG] マウス位置 (CG座標): \(String(describing: mouseLocation))")

        // 全ディスプレイ一覧を出力
        let maxDisplays: UInt32 = 16
        var allDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var totalCount: UInt32 = 0
        CGGetActiveDisplayList(maxDisplays, &allDisplays, &totalCount)
        for i in 0..<Int(totalCount) {
            let id = allDisplays[i]
            let bounds = CGDisplayBounds(id)
            let isMain = CGDisplayIsMain(id) != 0
            logger.info("[DEBUG] ディスプレイ[\(i)] id=\(id) bounds=\(String(describing: bounds)) isMain=\(isMain)")
        }

        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(mouseLocation, 1, &displayID, &count)
        logger.info("[DEBUG] マウスのあるディスプレイ: id=\(displayID), count=\(count)")

        guard count > 0 else { return nil }
        return CGDisplayBounds(displayID)
    }

    // AX要素のサイズを取得
    private func getElementSize(_ element: AXUIElement) -> CGSize? {
        var sizeRef: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeRef
        )
        guard error == .success else { return nil }
        var size = CGSize.zero
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return size
    }
    
    // ボタンをクリック
    private func performPress(on element: AXUIElement) throws {
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)

        guard error == .success else {
            throw NSError(domain: "MissionControl", code: 5,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to press button"])
        }
    }

    // 作成したデスクトップへ移動
    func moveToNextDesktop() {
        // AppleScriptを使用してControl + 右矢印を送信
        // キーコード124は右矢印キー
        let script = """
        tell application "System Events"
            key code 124 using control down
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else {
            print("AppleScriptの作成に失敗しました")
            return
        }

        var errorInfo: NSDictionary?
        appleScript.executeAndReturnError(&errorInfo)

        if let error = errorInfo {
            print("AppleScript実行エラー: \(error)")
            return
        }

        // デスクトップ切り替えアニメーション待機
        Thread.sleep(forTimeInterval: 0.5)
    }

}

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

// エントリーポイント
@main
struct ReviewSetupApp {
    static func main() {
        logInfo("ReviewSetup 起動")
        logInfo("Console.app で「com.example.review-setup」または「ReviewSetup」で検索")
        logInfo("または: log stream --predicate 'subsystem == \"com.example.review-setup\"' --level info")
        logInfo("")

        let windowManager = WindowManager()
        do {
            try windowManager.openBrowserAndArrange(url: "https://github.com", position: .left)
            logInfo("✓✓✓ 処理完了 ✓✓✓")
        } catch {
            logError("!!! エラー発生 !!!")
            logError("エラー内容: \(error.localizedDescription)")
            exit(1)
        }


        // // コマンドライン引数を解析
        // if arguments.contains("--arrange-browser") {
        //     // ブラウザ配置モード
        //     let urlIndex = arguments.firstIndex(of: "--arrange-browser")! + 1
        //     let url = urlIndex < arguments.count ? arguments[urlIndex] : "https://github.com"

        //     let windowManager = WindowManager()
        //     do {
        //         try windowManager.openBrowserAndArrange(url: url, position: .left)
        //         print("✓ ブラウザを左1/3に配置しました")
        //     } catch {
        //         print("エラー: \(error.localizedDescription)")
        //         exit(1)
        //     }
        // } else {
        //     // デフォルト: デスクトップ作成モード
        //     let manager = MissionControlManager()
        //     do {
        //         try manager.createNewDesktop()
        //         print("新しいデスクトップを作成しました")

        //         // 作成したデスクトップへ移動
        //         manager.moveToNextDesktop()
        //         print("新しいデスクトップへ移動しました")
        //     } catch {
        //         print("エラー: \(error.localizedDescription)")
        //         exit(1)
        //     }
        // }
    }
}
