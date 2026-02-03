# ADR-0001: CGEvent API を使用した仮想デスクトップ切り替え

## ステータス

Superseded by [ADR-0002](0002-use-applescript-for-space-switching.md)（ADR-0002により置き換え）

## 日付

2026-02-02

## コンテキスト

PRレビュー環境自動セットアップワークフローでは、Mission Control で新規デスクトップを作成した後、その作成されたデスクトップに移動する必要がある。

macOS では仮想デスクトップ（Spaces）の切り替えに関する公式な公開APIが提供されていないため、以下の要件を満たす実装方法を検討する必要があった：

- 新規作成したデスクトップ（現在のデスクトップの右隣）に移動する
- App Store への提出可能性を維持する（私的APIを避ける）
- 実装がシンプルで保守しやすい
- 将来の macOS バージョンでも動作する可能性が高い

## 決定

**CGEvent API を使用してキーボードショートカット（Control + 右矢印）をシミュレートする方式を採用する。**

### 実装概要

```swift
func moveToNextDesktop() {
    let rightArrowKeyCode: CGKeyCode = 124

    // Controlキーを押す
    let controlDown = CGEvent(
        keyboardEventSource: nil,
        virtualKey: 59, // Control key
        keyDown: true
    )
    controlDown?.flags = .maskControl
    controlDown?.post(tap: .cghidEventTap)

    // 右矢印キーを押す
    let keyDown = CGEvent(
        keyboardEventSource: nil,
        virtualKey: rightArrowKeyCode,
        keyDown: true
    )
    keyDown?.flags = .maskControl
    keyDown?.post(tap: .cghidEventTap)

    // 右矢印キーを離す
    let keyUp = CGEvent(
        keyboardEventSource: nil,
        virtualKey: rightArrowKeyCode,
        keyDown: false
    )
    keyUp?.flags = .maskControl
    keyUp?.post(tap: .cghidEventTap)

    // Controlキーを離す
    let controlUp = CGEvent(
        keyboardEventSource: nil,
        virtualKey: 59,
        keyDown: false
    )
    controlUp?.post(tap: .cghidEventTap)

    // デスクトップ切り替えアニメーション待機
    Thread.sleep(forTimeInterval: 0.5)
}
```

### 必要な権限

- **入力監視権限**（Input Monitoring）: CGEvent でキーボード入力をシミュレートするために必要
- システム設定 > プライバシーとセキュリティ > 入力監視

## 検討した代替案

### 代替案1: Hammerspoon 方式（Accessibility API + Mission Control UI 操作）

Hammerspoon が採用している方式：

```lua
-- Mission Control を開く
openMissionControl()

-- Dock の Mission Control UI から spaces list を取得
local mcSpacesList = findSpacesSubgroup("mc.spaces.list", screenID)

-- 目的のスペースの UI 要素に AXPress アクションを実行
child:performAction("AXPress")
```

**利点**:
- 公開 API のみ使用（App Store 提出可能）
- 特定のスペース ID に直接ジャンプ可能（5つ先のスペースでも1回で移動）

**欠点**:
- Mission Control を開くため視覚的フィードバックが大きい
- 実装が複雑（UI 要素の探索、待機時間の調整）
- Mission Control の UI 構造変更に脆弱

**不採用理由**: 本プロジェクトでは常に「1つ右隣のデスクトップ」に移動するため、複雑な実装を行うメリットがない

### 代替案2: 私的 API 方式（CoreGraphics SkyLight）

CoreGraphics の非公開 API を使用する方式：

```swift
// 私的 API（ヘッダーファイルを自分で定義）
CGSManagedDisplaySetCurrentSpace(cid, display, spaceID)
```

**利点**:
- 直接的で高速
- 視覚的フィードバックなし
- 特定のスペース ID に直接移動可能

**欠点**:
- **App Store 提出不可**
- 将来の macOS で動作しなくなる可能性が高い
- ヘッダーファイルを自分で定義する必要がある
- Apple の規約違反のリスク

**不採用理由**: App Store 提出可能性を維持したい、将来の互換性リスクが高い

### 代替案3: SpaceSwitcher 方式（透明ウィンドウ + フォーカス）

各スペースに透明ウィンドウを配置し、そのウィンドウにフォーカスすることでスペース移動：

**利点**:
- 公開 API のみ使用
- 比較的シンプル

**欠点**:
- 事前準備が必要（各スペースにウィンドウを配置）
- 新規作成したスペースには即座に対応できない
- 本プロジェクトのユースケースに不適合

**不採用理由**: 新規作成したデスクトップには透明ウィンドウが存在しないため、本要件に適用不可能

## 結果

### 採用した方式の利点

1. **要件に最適**: 新規作成したデスクトップは常に「現在のデスクトップの右隣」にあるため、1つ右に移動すれば良い
2. **シンプル**: 実装がシンプルで理解しやすい
3. **安全**: 公開 API のみ使用するため、将来の macOS でも動作する可能性が高い
4. **視覚的に自然**: ユーザーが手動でキーボードショートカットを押すのと同じ動作
5. **保守性**: コード量が少なく、依存関係が明確

### トレードオフ

1. **権限要件**: 入力監視権限が必要（ただし Accessibility 権限と合わせて初回実行時に説明可能）
2. **移動制限**: 1つ隣のスペースにしか移動できない（本プロジェクトでは問題にならない）
3. **ショートカット依存**: ユーザーがシステムのキーボードショートカット設定を変更している場合は動作しない（ただし標準設定での動作を想定）

### 将来の拡張性

将来的に「特定のスペース ID に直接ジャンプしたい」という要件が発生した場合は、Hammerspoon 方式の採用を再検討する。その場合でも、以下の条件を満たす場合に限る：

- そのような機能の需要が明確にある
- 実装の複雑さを許容できる
- Mission Control の視覚的フィードバックを許容できる

## 参考資料

- [Hammerspoon hs.spaces Documentation](https://www.hammerspoon.org/docs/hs.spaces.html)
- [Hammerspoon spaces.lua Implementation](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/spaces/spaces.lua)
- [CGSInternal Space Header](https://github.com/NUIKit/CGSInternal/blob/master/CGSSpace.h)
- [SpaceSwitcher on GitHub](https://github.com/bigbearlabs/SpaceSwitcher)
- [alt-tab-macos Spaces.swift](https://github.com/lwouis/alt-tab-macos/blob/master/src/logic/Spaces.swift)
- [Apple Developer Forums: Can spaces be switched programmatically?](https://developer.apple.com/forums/thread/654690)
- [Accessibility, Windows, and Spaces in OS X](https://ianyh.com/blog/accessibility-windows-and-spaces-in-os-x/)
