# review-setup

GitHub Pull Request（PR）のレビュー作業を効率化するための自動環境セットアップワークフロー。PR URLを入力するだけで、レビューに最適な作業環境を自動構築します。

## 概要

PRレビュー時の環境構築作業を自動化し、毎回同じレイアウトでレビュー環境を構築することで作業効率を向上させます。

**主な機能:**
- ✅ **実装済**: Mission Controlによる新しい仮想デスクトップの自動作成
- ✅ **実装済**: デスクトップ間の自動移動
- ✅ **実装済**: Git worktreeを活用したPRレビュー環境の構築
- 🚧 **未実装**: ブラウザとVS Codeの自動配置（画面分割）
- 🚧 **未実装**: 設定ファイルによるカスタマイズ機能

## 必要環境

### システム要件
- **OS**: macOS 13以降
- **Swift**: 6.2以降
- **Xcode Command Line Tools**: Swiftコンパイラ

### 必要なツール
- **Git**: 2.5以降（git worktree対応）
- **ghq**: リポジトリ管理ツール
- **gh**: GitHub CLI（認証設定済み: `gh auth login`）
- **VS Code**: エディタ（`code`コマンドがパスに追加済み）

### macOS権限
- **Accessibility権限**（必須）:
  - システム設定 > プライバシーとセキュリティ > アクセシビリティ
  - `ReviewSetup.app` を許可リストに追加
  - Mission Control UI操作、ウィンドウ配置に必要
  - **注意**: 単体の実行バイナリ（`.build/release/review-setup`）はアクセシビリティ設定に追加できないため、必ず `.app` 形式を使用すること
- **入力監視権限**（デスクトップ移動に必要）:
  - システム設定 > プライバシーとセキュリティ > 入力監視
  - `ReviewSetup.app` を許可リストに追加
  - キーボードショートカット（Control + 矢印）のシミュレーションに必要

## セットアップ

### 1. リポジトリのクローン

```bash
git clone https://github.com/noboru-i/review-setup.git
cd review-setup
```

### 2. アプリケーションバンドルの作成

macOSのアクセシビリティ設定に追加するには、.app形式が必要です。

```bash
# アプリケーションバンドルを作成
make app

# ~/Applications にインストール（推奨）
make install
```

### 3. アクセシビリティ権限の付与

1. システム設定 > プライバシーとセキュリティ > アクセシビリティ を開く
2. 鍵アイコンをクリックして変更を許可
3. 「+」ボタンで `~/Applications/ReviewSetup.app` を追加
4. システム設定 > プライバシーとセキュリティ > 入力監視 でも同様に追加

### 4. シェルスクリプトの設定

```bash
# シェルスクリプトに実行権限付与
chmod +x bin/setup-pr-review.sh

# PATHに追加（.zshrcまたは.bashrc）
export PATH="$PATH:/path/to/review-setup/bin"
```

## 使用方法

### PRレビュー環境のセットアップ

```bash
# PR URLを指定して実行
setup-pr-review.sh https://github.com/owner/repo/pull/123
```

**処理フロー:**
1. PR情報解析（owner、repo、PR番号を抽出）
2. Git worktree作成（`pr-123` ディレクトリにPRブランチをチェックアウト）
3. 指定ファイルのコピー（`.env.local`等の.gitignoreされたファイル）
4. 🚧 新しい仮想デスクトップの作成（Mission Control）
5. 🚧 ブラウザ起動と配置（画面左1/3にPR表示）
6. 🚧 VS Code起動と配置（画面中央1/3にworktree表示）

### レビュー完了後のクリーンアップ

```bash
# 🚧 未実装: cleanup-pr-review.sh pr-123
```

## アーキテクチャ

### プロジェクト構成

```
review-setup/
├── Package.swift                           # Swift Package Manager設定
├── Sources/
│   └── review-setup/
│       └── review_setup.swift              # メイン実装
│           ├── MissionControlManager       # デスクトップ作成・移動（実装済）
│           └── ReviewSetupApp (@main)      # エントリーポイント（実装済）
├── Resources/
│   └── Info.plist                          # アプリケーションバンドル用メタデータ
├── Makefile                                # アプリケーションバンドル作成用
├── bin/
│   ├── setup-pr-review.sh                  # メインスクリプト（実装済）
│   └── lib/
│       ├── github.sh                       # GitHub API操作（実装済）
│       ├── worktree.sh                     # Git worktree操作（実装済）
│       └── logging.sh                      # ログ出力（実装済）
└── docs/
    └── PLAN.md                             # 設計資料
```

### 技術スタック

**実装済:**
- **Swift 6.2+**: Mission Control操作、ウィンドウ管理の実装言語
- **Accessibility API (AXUIElement)**: UI要素の探索と操作
- **AppleScript**: キーボードショートカットのシミュレーション（デスクトップ移動）
- **Bash/Shell**: PR情報取得、worktree管理、全体フロー制御
- **gh CLI**: GitHub PR情報取得とチェックアウト

**未実装（計画中）:**
- **Cocoa (NSWorkspace)**: アプリケーションの起動とURL処理
- **CGEvent API**: キーボードショートカットのシミュレーション（AppleScriptの代替案）
- **WindowManager**: ブラウザ/VS Code配置

## 実装状況

### ✅ 実装済み機能

- [x] Mission Controlによる新しいデスクトップの作成
- [x] 作成したデスクトップへの自動移動
- [x] PR URLからPR情報を解析（`gh pr view`使用）
- [x] Git worktreeの作成とPRブランチのチェックアウト（`gh pr checkout`使用）
- [x] ログ出力機能

### 🚧 未実装機能（Issueで管理中）

- [ ] ブラウザ起動とウィンドウ配置（画面左1/3）[#1](https://github.com/noboru-i/review-setup/issues/1)
- [ ] VS Code起動とウィンドウ配置（画面中央1/3）[#2](https://github.com/noboru-i/review-setup/issues/2)
- [ ] メインワークフロースクリプトの完成（デスクトップ作成・アプリ配置の統合）[#3](https://github.com/noboru-i/review-setup/issues/3)
- [ ] GitHub操作ライブラリとWorktree管理ライブラリの拡張（ファイルコピー機能等）[#4](https://github.com/noboru-i/review-setup/issues/4)
- [ ] 設定ファイルの実装（`config.yml`, `copy-files.txt`）[#5](https://github.com/noboru-i/review-setup/issues/5)
- [ ] クリーンアップスクリプトの実装（`cleanup-pr-review.sh`）[#6](https://github.com/noboru-i/review-setup/issues/6)

## 開発

### ビルド方法

```bash
# 開発時（単体バイナリ）
swift build          # ビルド
swift run            # 実行（ビルド＋実行）
swift build -c release  # リリースビルド

# アプリケーションバンドルの作成
make app             # .appバンドルを作成
make install         # ~/Applications にインストール
make clean           # クリーンアップ
```

### 実行

```bash
# アプリケーションバンドル経由で実行
~/Applications/ReviewSetup.app/Contents/MacOS/review-setup
```

### 仕組み（Mission Control操作）

1. Mission Controlを起動（`open -a "Mission Control"`）
2. DockプロセスのAccessibility APIを通じてUI要素を再帰探索
3. 「デスクトップを追加」ボタンを検出してクリック
4. Mission Controlを閉じる
5. AppleScriptでControl + 右矢印キーを送信してデスクトップを移動

ボタン検索は日本語（「デスクトップを追加」）と英語（"add desktop"）の両方に対応しています。

詳細は [CLAUDE.md](./CLAUDE.md) および [docs/PLAN.md](./docs/PLAN.md) を参照してください。

## トラブルシューティング

### Q: アクセシビリティ設定に追加できない

**問題**: 単体の実行バイナリ（`.build/release/review-setup`）はアクセシビリティ設定の許可リストに追加できない

**解決策**: アプリケーションバンドル（.app）を使用する
```bash
make app
make install
# システム設定で ~/Applications/ReviewSetup.app を追加する
```

### Q: gh pr checkoutでエラーが発生する

```bash
# 認証状態を確認
gh auth status

# 認証が切れている場合は再認証
gh auth login

# PRが存在するか確認
gh pr view 123
```

### Q: アプリを開けない（Gatekeeper警告）

署名されていないアプリの場合、初回起動時に警告が表示されます。

**解決策1**: 右クリック > 開く で起動

**解決策2**: コード署名を行う（開発者証明書が必要）
```bash
codesign --sign "Developer ID Application" ReviewSetup.app
```

## 今後の拡張性

### Phase 2: 追加機能候補
- ターミナル配置（右1/3領域）
- カスタムレイアウト設定
- マルチディスプレイ対応
- デスクトップ名設定
- 自動テスト実行
- PRコメント連携

詳細は [docs/PLAN.md](./docs/PLAN.md) のセクション 11を参照してください。

## 参考資料

- [Git Worktree Documentation](https://git-scm.com/docs/git-worktree)
- [ghq - GitHub](https://github.com/x-motemen/ghq)
- [macOS Accessibility API](https://developer.apple.com/documentation/applicationservices/axuielement)
- [Swift Documentation](https://www.swift.org/documentation/)
- [GitHub CLI (gh)](https://cli.github.com/)

## License

[MIT](./LICENSE)
