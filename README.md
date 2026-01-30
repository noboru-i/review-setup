# review-setup

[WIP]
macOSのMission Controlを操作し、Accessibility APIを使って新しい仮想デスクトップを自動作成するSwift CLIツール。

## 必要環境

- macOS 13以降
- Swift 6.2以降
- アクセシビリティ権限（システム設定 > プライバシーとセキュリティ > アクセシビリティ）

## ビルド・実行

```bash
swift build          # ビルド
swift run            # 実行（ビルド＋実行）
swift build -c release  # リリースビルド
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
