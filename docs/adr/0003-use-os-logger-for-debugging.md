# ADR-0003: デバッグログに os.Logger を使用する

## ステータス

Accepted（承認済み）

## 日付

2026-02-03

## コンテキスト

複数ディスプレイ対応の実装デバッグにあたり、アプリケーションの内部状態（ディスプレイ情報、AX要素の座標など）を確認する手段が必要になった。

本プロジェクトは `.app` バンドルとして配布・実行される。`.app` バンドルをダブルクリックで起動した場合、`print()` の出力先（stdout）はどこにも接続されておらず、ログを確認する手段がない。

## 決定

**デバッグログの出力に `os.Logger` を使用する。**

### 実装概要

```swift
import os

private let logger = Logger(subsystem: "review-setup", category: "MissionControl")

// 使用例
logger.info("[DEBUG] マウス位置 (CG座標): \(String(describing: mouseLocation))")
```

### ログの確認方法

Console.app（コンソール.app）を開き、以下の手順でフィルタする：

1. プロセス名 `review-setup` でフィルタ
2. または Subsystem `review-setup` でフィルタ
3. 「アクション」>「情報メッセージを含める」を有効にする

## 検討した代替案

### 代替案1: print() + ターミナルからバイナリ直接実行

`.app` 内のバイナリをターミナルから直接実行する方式：

```sh
~/Applications/ReviewSetup.app/Contents/MacOS/review-setup
```

**利点**:
- 実装変更不要
- ターミナルに直接出力される

**欠点**:
- 通常の使用方法（.app ダブルクリック）ではログが見えない
- デバッグのためだけに実行方法を変える必要がある

**不採用理由**: 通常の実行方法でもログを確認できる方が実用的

### 代替案2: ファイルへのログ出力

ログをファイルに書き出す方式。

**利点**:
- 確実にログが残る

**欠点**:
- ファイルパスの管理が必要
- ログローテーションの考慮が必要
- macOS 標準のログ基盤を活用できない

**不採用理由**: os.Logger が macOS 標準のログ基盤であり、Console.app との統合が優れている

## 結果

- `.app` として実行しても Console.app でログを確認可能になった
- `Logger` の文字列補間では `CustomStringConvertible` に準拠していない型（`CGPoint`, `CGRect`, `AXUIElement` 等）は `String(describing:)` で変換する必要がある
- ログレベルは `info` を使用（`debug` はデフォルトで Console.app に表示されないため）
