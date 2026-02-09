# ADR-0003: OSLog を使用したログ出力

## ステータス

Accepted（承認）

## 日付

2026-02-09

## コンテキスト

ReviewSetup はアプリケーションバンドル（`.app`）として実行されるため、標準出力が表示されず、デバッグが困難だった。以下の要件を満たすログシステムが必要だった：

- アプリケーションバンドル実行時でもログを確認できる
- リアルタイムでログを監視できる
- ログレベル（info、debug、error）で分類できる
- システムログと統合され、Console.app で確認できる
- パフォーマンスへの影響が少ない

## 決定

**OSLog（Unified Logging System）のみを採用する。**

### 実装概要

```swift
import OSLog

// Loggerインスタンスの作成
let logger = Logger(subsystem: "com.example.review-setup", category: "WindowManager")

// ログヘルパー関数
func log(_ message: String, type: OSLogType = .default) {
    // OSLogに出力（privacy: .public で動的な値も表示）
    logger.log(level: type, "\(message, privacy: .public)")
}

// ログレベル別ヘルパー
func logInfo(_ message: String) {
    log(message, type: .info)
}

func logDebug(_ message: String) {
    log(message, type: .debug)
}

func logError(_ message: String) {
    log(message, type: .error)
}
```

### ログの確認方法

1. **Console.app**（推奨）
   ```bash
   open -a Console
   # 検索: "com.example.review-setup" または "ReviewSetup"
   ```

2. **コマンドライン（リアルタイム）**
   ```bash
   log stream --predicate 'subsystem == "com.example.review-setup"' --level info
   ```

3. **過去のログを確認**
   ```bash
   log show --predicate 'subsystem == "com.example.review-setup"' --last 1h
   ```

## 検討した代替案

### 代替案1: NSLog のみ使用

```swift
NSLog("[ReviewSetup] %@", message)
```

**利点**:
- シンプルで古くから利用可能
- Console.app で確認可能

**欠点**:
- ログレベルの区別ができない
- パフォーマンスがOSLogより劣る
- 構造化ログ（structured logging）ができない
- プライバシー保護機能がない

**不採用理由**: OSLog がより高機能で現代的なため

### 代替案2: ファイル出力のみ

```swift
// /tmp/review-setup.log に直接書き込み
```

**利点**:
- シンプル
- 権限不要
- 確実にログが残る

**欠点**:
- Console.app と統合されない
- リアルタイム監視が不便（`tail -f` が必要）
- システムログと分離される
- ログレベルの標準化が必要

**不採用理由**: システムログと統合されないため、デバッグ体験が劣る

### 代替案3: os_log（C API）

```swift
import os.log

os_log("Message: %{public}@", log: OSLog.default, type: .info, message)
```

**利点**:
- OSLog の機能を利用可能
- 歴史が長い

**欠点**:
- Swift の `Logger` API より煩雑
- 文字列補間の構文が複雑
- Swift 5.3 以降では `Logger` が推奨

**不採用理由**: `Logger` の方がSwiftらしく、簡潔

## 結果

### 採用した方式の利点

1. **システム統合**: macOS の統合ログシステムに統合される
2. **Console.app**: GUI でログレベル別に色分け表示、フィルタリングが容易
3. **パフォーマンス**: NSLog より高速、バッファリングされる
4. **プライバシー保護**: `privacy: .public` で明示的に指定しない限り、動的な値は隠される
5. **構造化ログ**: subsystem と category で分類可能
6. **ログレベル**: `.info`, `.debug`, `.error` などで重要度を指定可能
7. **デバッグ体験**: リアルタイム監視、過去ログの検索が容易

### privacy: .public の使用

OSLog はデフォルトでプライバシー保護のため動的な値を `<private>` として隠す。本プロジェクトでは以下の理由で `privacy: .public` を指定：

- デバッグ目的のログであり、機密情報を扱わない
- エラーコード、URL、PID、ウィンドウ情報などを確認する必要がある
- ローカル環境での開発・デバッグが主目的

**注意**: 将来的に機密情報をログに含める場合は、個別に `privacy: .private` を使用すること。

### ファイル出力を削除した理由

当初は補助的に `/tmp/review-setup.log` にも出力していたが、以下の理由で削除：

1. **OSLog で十分**: `log stream` と `log show` コマンドで全ての要件を満たせる
2. **二重管理の回避**: 同じログを2箇所に書き込む必要がない
3. **コードの簡潔性**: ファイル処理のコードが不要になり、シンプルになる
4. **ディスク容量**: `/tmp` へのログ蓄積を避けられる
5. **Unix ツール**: OSLog も `log show` で出力すれば `grep` などで処理可能

OSLog のコマンドラインツールで十分な機能が提供されるため、独自のファイル出力は不要と判断した。

### トレードオフ

1. **OSLog への依存**: macOS 10.12 未満では利用不可（本プロジェクトは macOS 13.0+ を要求）
2. **Console.app の習熟**: ファイルベースのログより習熟が必要（ただし、より強力）
3. **プライバシー**: `privacy: .public` により全ての値が表示される（意図的）

### 将来の拡張性

- **プロダクション版**: 本番環境では `privacy: .private` をデフォルトにすることを検討
- **リモートログ**: 将来的にクラッシュレポートやテレメトリーを送信する場合は、OSLog のエクスポート機能を活用
- **ログのエクスポート**: `log collect` コマンドでログをアーカイブして保存・共有可能

## 参考資料

- [Apple Developer Documentation: Logger](https://developer.apple.com/documentation/os/logger)
- [Apple Developer Documentation: Generating Log Messages from Your Code](https://developer.apple.com/documentation/os/logging/generating_log_messages_from_your_code)
- [WWDC 2020: Explore logging in Swift](https://developer.apple.com/videos/play/wwdc2020/10168/)
- [WWDC 2016: Unified Logging and Activity Tracing](https://developer.apple.com/videos/play/wwdc2016/721/)
- [Using the Console.app](https://support.apple.com/guide/console/welcome/mac)
