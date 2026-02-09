import Cocoa
import ApplicationServices

// ウィンドウ操作の共通ユーティリティ
struct WindowOperations {

    // ウィンドウ位置を設定
    static func setWindowPosition(_ window: AXUIElement, x: CGFloat, y: CGFloat) throws {
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
            throw NSError(domain: "WindowOperations", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to set window position (error: \(error.rawValue)). アクセシビリティ権限を確認してください。"])
        }
    }

    // ウィンドウサイズを設定
    static func setWindowSize(_ window: AXUIElement, width: CGFloat, height: CGFloat) throws {
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
            throw NSError(domain: "WindowOperations", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to set window size (error: \(error.rawValue)). アクセシビリティ権限を確認してください。"])
        }
    }

    // ウィンドウ位置とサイズを計算
    static func calculateWindowFrame(
        screenFrame: CGRect,
        position: LayoutPosition
    ) -> (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
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

        return (x, y, width, height)
    }

    // ウィンドウの現在の位置とサイズをログ出力
    static func logWindowInfo(_ window: AXUIElement, prefix: String) {
        var posRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)

        if let posValue = posRef {
            var point = CGPoint.zero
            AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
            logInfo("\(prefix)位置: (\(point.x), \(point.y))")
        }

        if let sizeValue = sizeRef {
            var size = CGSize.zero
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            logInfo("\(prefix)サイズ: (\(size.width) x \(size.height))")
        }
    }
}
