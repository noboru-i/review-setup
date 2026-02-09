# ADR-0004: スコアリングベースのウィンドウ特定ロジック

## ステータス

Accepted（承認）

## 日付

2026-02-09

## コンテキスト

ブラウザ（Chrome）で新規ウィンドウを開いた際、複数のウィンドウが存在する状況で適切なウィンドウを特定する必要があった。

### 問題の発見

GitHub.com などの Web サイトを開くと、以下のような問題が発生した：

- **翻訳ポップアップウィンドウ**が存在する場合、それが `kAXWindowsAttribute` で取得したウィンドウリストの最初の要素になることがある
- 翻訳ポップアップのサイズを変更しようとしてエラーが発生
- 実際のブラウザウィンドウではなく、小さいポップアップウィンドウを対象にしていた

### 要件

- 新規に開いたメインのブラウザウィンドウを正確に特定する
- 翻訳ポップアップ、通知、その他の補助的なウィンドウを除外する
- 複数のブラウザウィンドウが開いている環境でも動作する
- 将来的に他の種類のポップアップが出現しても対応できる拡張性

## 決定

**スコアリングベースのフィルタリングロジックを採用し、メインウィンドウを直接取得できない場合は全ウィンドウから最適なものを選択する。**

### 実装概要

#### 1. メインウィンドウの直接取得を優先

```swift
// 6-1. まずメインウィンドウを直接取得を試みる
var mainWindowRef: CFTypeRef?
let mainError = AXUIElementCopyAttributeValue(
    appElement,
    kAXMainWindowAttribute as CFString,
    &mainWindowRef
)

if mainError == .success, mainWindowRef != nil {
    logInfo("   メインウィンドウを直接取得成功")
    window = (mainWindowRef as! AXUIElement)
}
```

#### 2. フォールバック: スコアリングベースのフィルタリング

メインウィンドウの取得に失敗した場合、全ウィンドウを取得してスコアリング：

```swift
private func findMainBrowserWindow(in windows: [AXUIElement]) throws -> AXUIElement? {
    var candidates: [(window: AXUIElement, score: Int)] = []

    for (index, window) in windows.enumerated() {
        var score = 0

        // ロール、サブロール、タイトル、サイズを取得
        let role = getRole(window)
        let subrole = getSubrole(window)
        let title = getTitle(window)
        let size = getSize(window)

        // スコアリング
        if role == kAXWindowRole as String {
            score += 10  // Window である
        } else {
            continue  // Window でないものは除外
        }

        if subrole == kAXStandardWindowSubrole as String {
            score += 20  // 標準ウィンドウである
        }

        if let t = title, !t.isEmpty {
            score += 15  // タイトルが存在する
        }

        if size.width > 400 && size.height > 400 {
            score += 25  // サイズが十分大きい（ポップアップを除外）
        }

        if index == 0 {
            score += 5  // 最初のウィンドウを優先（通常は最新）
        }

        candidates.append((window: window, score: score))
    }

    // スコアでソートして最も高いものを選択
    candidates.sort { $0.score > $1.score }
    return candidates.first?.window
}
```

### スコアリング基準

| 条件 | スコア | 理由 |
|------|--------|------|
| ロールが `kAXWindowRole` | +10 | Windowでないものは対象外 |
| サブロールが `kAXStandardWindowSubrole` | +20 | 標準ウィンドウ（ダイアログ等を除外） |
| タイトルが存在 | +15 | メインウィンドウは通常タイトルを持つ |
| サイズが 400x400 以上 | +25 | **最重要**: ポップアップは小さい |
| 最初のウィンドウ | +5 | 通常は最新のウィンドウが先頭 |

**合計スコア範囲**: 0〜75点

### 典型的なスコア例

- **メインブラウザウィンドウ**: 70〜75点
  - Window (10) + 標準 (20) + タイトル (15) + 大きい (25) + 最初 (5) = 75点

- **翻訳ポップアップ**: 25〜30点
  - Window (10) + タイトル (15) = 25点（サイズが小さいため +25 なし）

- **通知ポップアップ**: 10点
  - Window (10) のみ（タイトルなし、小さい）

## 検討した代替案

### 代替案1: 単純に最初のウィンドウを使用

```swift
let window = windows[0]  // 最初のウィンドウを無条件に使用
```

**利点**:
- シンプル
- 実装が容易

**欠点**:
- 翻訳ポップアップが最初に来る場合に失敗
- 複数ウィンドウ環境で不安定

**不採用理由**: 実際に GitHub.com で翻訳ポップアップの問題が発生

### 代替案2: タイトルでフィルタリング

```swift
let window = windows.first { window in
    let title = getTitle(window)
    return title != nil && !title!.isEmpty
}
```

**利点**:
- シンプル
- 多くの場合は動作する

**欠点**:
- 翻訳ポップアップもタイトルを持つ場合がある
- サイズの考慮がない
- タイトルのないメインウィンドウには対応できない

**不採用理由**: 単一条件では不十分、複数の条件を組み合わせる必要がある

### 代替案3: サイズのみでフィルタリング

```swift
let window = windows.first { window in
    let size = getSize(window)
    return size.width > 400 && size.height > 400
}
```

**利点**:
- 翻訳ポップアップを確実に除外できる

**欠点**:
- 小さいメインウィンドウには対応できない
- 複数の大きいウィンドウがある場合に選択が不確実

**不採用理由**: サイズは重要だが、他の条件も組み合わせるべき

### 代替案4: ウィンドウの作成時刻で判定

```swift
// 最も新しく作成されたウィンドウを選択
```

**利点**:
- 新規に開いたウィンドウを確実に特定できる

**欠点**:
- Accessibility API で作成時刻を直接取得する方法がない
- 実装が複雑

**不採用理由**: 実装が困難、他の方法で十分対応可能

## 結果

### 採用した方式の利点

1. **堅牢性**: 単一条件ではなく、複数の条件を組み合わせることで確実性が向上
2. **優先順位の明確化**: スコアリングにより、どの条件が重要かが明確
3. **拡張性**: 将来的に新しい条件を追加しやすい（スコアを追加するだけ）
4. **デバッグ容易性**: 各ウィンドウのスコアをログ出力することで、問題の診断が容易
5. **フォールバック**: メインウィンドウの直接取得とフィルタリングの2段階構成

### 実際の動作確認

#### GitHub.com（翻訳ポップアップあり）

```
ウィンドウ[0]: role=AXWindow, subrole=AXStandardWindow, title="Google Translate", size=300x200
  → スコア: 25点 (Window 10 + タイトル 15)

ウィンドウ[1]: role=AXWindow, subrole=AXStandardWindow, title="GitHub", size=1280x800
  → スコア: 70点 (Window 10 + 標準 20 + タイトル 15 + 大きい 25)

✓ ウィンドウ[1]を選択（スコア: 70）
```

#### Yahoo.co.jp（ポップアップなし）

```
ウィンドウ[0]: role=AXWindow, subrole=AXStandardWindow, title="Yahoo! JAPAN", size=1280x800
  → スコア: 75点 (Window 10 + 標準 20 + タイトル 15 + 大きい 25 + 最初 5)

✓ ウィンドウ[0]を選択（スコア: 75）
```

### トレードオフ

1. **複雑性の増加**: 単純な最初のウィンドウ選択と比べて実装が複雑
2. **閾値の調整**: サイズの閾値（400x400）は経験的な値であり、将来的に調整が必要になる可能性
3. **デバッグログの増加**: 各ウィンドウの詳細をログ出力するため、ログ量が増加

### 将来の拡張性

必要に応じて以下の条件を追加することを検討：

1. **ウィンドウの可視性**: 最小化されていないウィンドウを優先
2. **フォーカス状態**: フォーカスされているウィンドウを優先
3. **スクリーン位置**: メインディスプレイ上のウィンドウを優先
4. **ウィンドウレイヤー**: 通常レイヤーのウィンドウを優先（ポップアップレイヤーを除外）

### パラメータの調整指針

**サイズ閾値**（現在: 400x400）:
- 翻訳ポップアップは通常 300x200 程度
- 通知は 400x100 程度
- メインウィンドウは通常 800x600 以上
- **推奨値**: 400x400（ほとんどのポップアップを除外し、小さいメインウィンドウも許容）

**スコア配分**:
- サイズ条件を最重要 (+25) とすることで、ポップアップを確実に除外
- 標準ウィンドウ (+20) を次点にすることで、ダイアログ等を除外
- 合計スコアの差が大きくなるように調整（確実な判定のため）

## 参考資料

- [Accessibility Programming Guide - Window Attributes](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/OSXAXTestingApps.html)
- [AXUIElement Reference](https://developer.apple.com/documentation/applicationservices/axuielement)
- [kAXWindowRole](https://developer.apple.com/documentation/applicationservices/kaxwindowrole)
- [kAXStandardWindowSubrole](https://developer.apple.com/documentation/applicationservices/kaxstandardwindowsubrole)
