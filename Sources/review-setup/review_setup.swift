import Cocoa
import ApplicationServices
import os

private let logger = Logger(subsystem: "review-setup", category: "MissionControl")

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

// エントリーポイント
@main
struct ReviewSetupApp {
    static func main() {
        let manager = MissionControlManager()
        do {
            try manager.createNewDesktop()
            print("新しいデスクトップを作成しました")

            // 作成したデスクトップへ移動
            manager.moveToNextDesktop()
            print("新しいデスクトップへ移動しました")
        } catch {
            print("エラー: \(error.localizedDescription)")
        }
    }
}
