# review-setup

[WIP]
macOSのMission Controlを操作し、Accessibility APIを使って新しい仮想デスクトップを自動作成するSwift CLIツール。

## 必要環境

- macOS 13以降
- Swift 6.2以降
- アクセシビリティ権限（システム設定 > プライバシーとセキュリティ > アクセシビリティ）
  - **重要**: アクセシビリティ権限を付与するには、アプリケーションバンドル（.app形式）が必要です

## ビルド・実行

### 開発時（単体バイナリ）

```bash
swift build          # ビルド
swift run            # 実行（ビルド＋実行）
swift build -c release  # リリースビルド
```

### アプリケーションバンドルの作成（推奨）

macOSのアクセシビリティ設定に追加するには、.app形式が必要です。

```bash
# アプリケーションバンドルを作成
make app

# ~/Applications にインストール
make install

# クリーンアップ
make clean
```

インストール後、以下の手順でアクセシビリティ権限を付与してください:

1. システム設定 > プライバシーとセキュリティ > アクセシビリティ を開く
2. 鍵アイコンをクリックして変更を許可
3. 「+」ボタンで `~/Applications/ReviewSetup.app` を追加
4. システム設定 > プライバシーとセキュリティ > 入力監視 でも同様に追加

### 実行

```bash
# アプリケーションバンドル経由で実行
~/Applications/ReviewSetup.app/Contents/MacOS/review-setup
```

## 仕組み

1. Mission Controlを起動
2. DockプロセスのAccessibility APIを通じてUI要素を再帰探索
3. 「デスクトップを追加」ボタンを検出してクリック
4. Mission Controlを閉じる

ボタン検索は日本語（「デスクトップを追加」）と英語（"add desktop"）の両方に対応しています。

## 開発

開発の詳細は [CLAUDE.md](./CLAUDE.md) を参照してください。

## License

[MIT](./LICENSE)
