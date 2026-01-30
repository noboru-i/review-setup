import Cocoa
import ApplicationServices

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
        
        // 5. "add desktop"ボタンを探す
        let addButton = try findAddDesktopButton(in: mcGroup)
        
        // 6. ボタンをクリック
        try performPress(on: addButton)
        
        // 7. 少し待機
        Thread.sleep(forTimeInterval: 0.3)
        
        // 8. Mission Controlを閉じる（トグル動作）
        openMissionControl()
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
    
    // "add desktop"ボタンを探す
    private func findAddDesktopButton(in element: AXUIElement) throws -> AXUIElement {
        var childrenRef: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        )
        
        guard error == .success,
              let children = childrenRef as? [AXUIElement] else {
            throw NSError(domain: "MissionControl", code: 3)
        }
        
        // すべての子要素を探索
        for child in children {
            // ボタンのdescriptionを確認
            var descRef: CFTypeRef?
            AXUIElementCopyAttributeValue(
                child,
                kAXDescriptionAttribute as CFString,
                &descRef
            )
            
            if let description = descRef as? String,
               description.contains("デスクトップを追加") ||
               description.contains("add desktop") {
                return child
            }
            
            // 再帰的に探索
            if let button = try? findAddDesktopButton(in: child) {
                return button
            }
        }
        
        throw NSError(domain: "MissionControl", code: 4,
                     userInfo: [NSLocalizedDescriptionKey: "Add button not found"])
    }
    
    // ボタンをクリック
    private func performPress(on element: AXUIElement) throws {
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        
        guard error == .success else {
            throw NSError(domain: "MissionControl", code: 5,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to press button"])
        }
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
        } catch {
            print("エラー: \(error.localizedDescription)")
        }
    }
}
