# ADR-0002: AppleScript を使用した仮想デスクトップ切り替え

## ステータス

Accepted（承認済み）

Supersedes [ADR-0001](0001-use-cgevent-for-space-switching.md)

## 日付

2026-02-03

## コンテキスト

[ADR-0001](0001-use-cgevent-for-space-switching.md) では CGEvent API を使用してキーボードショートカット（Control + 右矢印）をシミュレートする方式を採用したが、実装時に以下の問題が発生した：

### 発生した問題

CGEvent を使用した複数のアプローチを試したが、いずれも**Controlキーが正しく送信されず、右矢印キーのみが入力される**という問題が発生した。

#### 試したアプローチ

**アプローチ1**: 修飾キーフラグのみを設定
```swift
let keyDown = CGEvent(
    keyboardEventSource: eventSource,
    virtualKey: rightArrowKeyCode,
    keyDown: true
)
keyDown.flags = .maskControl
keyDown.post(tap: .cghidEventTap)
```
**結果**: Controlキーが認識されず、右矢印のみが入力された

**アプローチ2**: フラグ変更イベント（`.flagsChanged`）を使用
```swift
// Controlキーを押す
let controlDown = CGEvent(source: eventSource)
controlDown.flags = .maskControl
controlDown.type = .flagsChanged
controlDown.post(tap: .cghidEventTap)

// 右矢印キーを押す
let keyDown = CGEvent(
    keyboardEventSource: eventSource,
    virtualKey: rightArrowKeyCode,
    keyDown: true
)
keyDown.flags = .maskControl
keyDown.post(tap: .cghidEventTap)
```
**結果**: Controlキーが認識されず、右矢印のみが入力された

**アプローチ3**: Controlキーコードで個別のキーイベントを送信
```swift
let controlKeyCode: CGKeyCode = 59
let controlDown = CGEvent(
    keyboardEventSource: nil,
    virtualKey: controlKeyCode,
    keyDown: true
)
controlDown?.post(tap: .cghidEventTap)
```
**結果**: 依然として動作せず

### 原因の推測

- macOS のセキュリティ機能により、CGEvent による修飾キーのシミュレーションが制限されている可能性
- システムレベルのキーボードショートカット（Mission Control関連）には、より高レベルのAPIが必要な可能性
- アクセシビリティ権限だけでは不十分で、追加の権限や設定が必要な可能性

これらの試行錯誤の結果、より確実な方法として AppleScript の採用を決定した。

## 決定

**AppleScript の System Events を使用してキーボードショートカット（Control + 右矢印）を送信する方式を採用する。**

### 実装概要

```swift
func moveToNextDesktop() {
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
```

### 必要な権限

- **アクセシビリティ権限**（Accessibility）: System Events を制御するために必要
- システム設定 > プライバシーとセキュリティ > アクセシビリティ

（注: CGEvent方式で必要だった「入力監視権限」は不要になった）

## 検討した代替案

### 代替案1: CGEvent API（ADR-0001で採用済み）

**実装の試行**: 前述の通り、3つの異なるアプローチを試したが、いずれもControlキーが正しく送信されなかった。

**不採用理由**:
- 実装時に動作しないことが判明
- 複数のアプローチを試したが問題を解決できなかった
- デバッグやトラブルシューティングが困難

### 代替案2: Hammerspoon 方式（Accessibility API + Mission Control UI 操作）

ADR-0001 で検討済みの方式。Mission Control を開いて UI 要素を直接操作する。

**不採用理由**:
- AppleScript方式がシンプルで確実に動作するため、より複雑な実装を行うメリットがない
- ADR-0001 で述べた理由（実装の複雑さ、UI構造変更への脆弱性）も依然として有効

### 代替案3: 私的 API 方式（CoreGraphics SkyLight）

ADR-0001 で検討済み。

**不採用理由**: ADR-0001 と同じ（App Store 提出不可、将来の互換性リスク）

## 結果

### 採用した方式の利点

1. **確実に動作**: AppleScript の System Events は macOS のシステムレベルのキーボード操作を確実に実行できる
2. **シンプルな実装**: CGEvent の複雑なイベント処理が不要。わずか数行で実装可能
3. **保守性**: AppleScript はシンプルで可読性が高く、将来の保守が容易
4. **公式サポート**: Apple が公式にサポートする方法であり、将来の macOS でも動作する可能性が高い
5. **権限要件の簡素化**: アクセシビリティ権限のみで動作（CGEvent方式で必要だった入力監視権限が不要）
6. **実績**: AppleScript による自動化は macOS で長年使用されており、安定性が高い

### トレードオフ

1. **AppleScript への依存**: AppleScript エンジンに依存するため、理論的には将来のmacOSで非推奨になる可能性がある（ただし現時点では問題なし）
2. **パフォーマンス**: CGEvent よりわずかにオーバーヘッドがある可能性（実用上は問題ないレベル）
3. **デバッグ**: AppleScript のエラー情報が限定的な場合がある

### ADR-0001 からの変更点

| 項目 | ADR-0001（CGEvent） | ADR-0002（AppleScript） |
|------|---------------------|------------------------|
| 実装の複雑さ | 中（複数のイベント処理が必要） | 低（わずか数行） |
| 動作確実性 | 低（実装時に動作せず） | 高（確実に動作） |
| 必要な権限 | 入力監視権限 | アクセシビリティ権限 |
| コード行数 | 約40行 | 約20行 |
| 保守性 | 中（イベント処理の理解が必要） | 高（シンプルで明確） |

### 将来の考慮事項

- AppleScript が将来の macOS で非推奨になった場合は、再度 CGEvent 方式を再検証するか、新しい API が提供されているか確認する
- ただし、AppleScript は macOS の自動化において中心的な役割を果たしており、近い将来に廃止される可能性は低いと考えられる

## 教訓

1. **早期の実装検証の重要性**: アーキテクチャ決定時に簡易的なプロトタイプを作成することで、理論上は可能でも実装時に問題が発生するケースを早期に発見できる
2. **シンプルさの価値**: より低レベルなAPI（CGEvent）よりも、高レベルなAPI（AppleScript）の方が確実に動作し、保守も容易な場合がある
3. **代替案の検討**: 最初の実装方針が動作しない場合に備えて、複数の代替案を事前に検討しておくことが重要

## 参考資料

- [NSAppleScript - Apple Developer Documentation](https://developer.apple.com/documentation/foundation/nsapplescript)
- [System Events - AppleScript Language Guide](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/introduction/ASLR_intro.html)
- [Key Codes - Apple Technical Note TN2187](https://eastmanreference.com/complete-list-of-applescript-key-codes)
- ADR-0001: CGEvent API を使用した仮想デスクトップ切り替え
