# PRレビュー環境自動セットアップワークフロー 設計資料

## 1. 概要

本設計は、GitHub Pull Request（PR）のレビュー作業を効率化するための自動環境セットアップワークフローです。PR URLを入力するだけで、レビューに最適な作業環境を自動構築します。

## 2. 目的

- PRレビュー開始時の環境構築作業を自動化
- 毎回同じレイアウトでレビュー環境を構築し、作業効率を向上
- git worktreeを活用した安全なレビュー環境の提供
- マルチタスク環境での作業分離

## 3. 前提条件

### 3.1 必要なツール・環境
- **OS**: macOS
- **Git**: バージョン 2.5以降（git worktree対応）
- **ghq**: リポジトリ管理ツール
- **gh**: GitHub CLI
- **VS Code**: エディタ
- **ブラウザ**: Chrome, Safari, Firefox等
- **macOS Mission Control**: 仮想デスクトップ機能

### 3.2 事前設定
- ghqによるリポジトリ管理が設定済み
- VS Codeがコマンドラインから起動可能（`code`コマンド）
- GitHub CLIが認証設定済み（`gh auth login`で認証完了）

## 4. システム構成

```
┌─────────────────────────────────────────────────────────┐
│  入力: PR URL                                            │
│  例: https://github.com/owner/repo/pull/123             │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Step 1: PR情報解析                                      │
│  - owner, repo, PR番号を抽出                            │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Step 2: Worktree作成                                    │
│  - ghq管理下のリポジトリパスを特定                      │
│  - PR番号ベースのworktree作成                           │
│  - 指定ファイルのコピー処理                             │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Step 3: 仮想デスクトップ作成                            │
│  - 現在のデスクトップの右側に新規作成                   │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Step 4: アプリケーション配置                            │
│  - 左1/3: ブラウザ（PR表示）                            │
│  - 中央1/3: VS Code（worktree）                         │
│  - 右1/3: （将来拡張用）                                │
└─────────────────────────────────────────────────────────┘
```

## 5. 処理フロー詳細

### 5.1 PR URL解析
```
入力: https://github.com/owner/repo/pull/123

解析結果:
- owner: owner
- repository: repo
- pr_number: 123
- branch情報（GitHub API経由で取得）
```

### 5.2 Git Worktree作成

#### 5.2.1 リポジトリパス特定
```bash
# ghqのルートディレクトリ取得
GHQ_ROOT=$(ghq root)

# リポジトリパス構築
REPO_PATH="${GHQ_ROOT}/github.com/${owner}/${repo}"
```

#### 5.2.2 Worktree作成
```bash
# worktreeディレクトリ名
WORKTREE_NAME="pr-${pr_number}"
WORKTREE_PATH="${REPO_PATH}/../${WORKTREE_NAME}"

cd "${REPO_PATH}"

# 空のworktreeを作成
git worktree add "${WORKTREE_PATH}"

# worktree内でPRをチェックアウト
# gh pr checkoutが以下を自動実行：
# - PRのブランチをフェッチ
# - ブランチをチェックアウト
# - リモート追跡ブランチを設定（git pull可能な状態）
cd "${WORKTREE_PATH}"
gh pr checkout ${pr_number}

# 確認：リモート追跡ブランチが設定されている
# git branch -vv で確認可能
# 出力例: * feature-branch abc1234 [origin/feature-branch] コミットメッセージ
```

**gh pr checkoutの利点**:
- GitHub API呼び出しが不要（gh内部で処理）
- リモート追跡ブランチが自動設定され、git pullが可能
- 認証管理が不要（ghの認証を利用）
- エラーハンドリングが簡潔

#### 5.2.3 指定ファイルのコピー
```bash
# .gitignoreされているが必要なファイルをコピー
# 設定ファイルで指定されたファイルリストを処理

COPY_FILES=(
  ".env.local"
  "config/local.yml"
  # 他の必要なファイル
)

for file in "${COPY_FILES[@]}"; do
  if [ -f "${REPO_PATH}/${file}" ]; then
    cp "${REPO_PATH}/${file}" "${WORKTREE_PATH}/${file}"
  fi
done
```

### 5.3 仮想デスクトップ管理

#### 5.3.1 新規デスクトップ作成
```applescript
tell application "System Events"
    -- Mission Controlを起動
    do shell script "open -a 'Mission Control'"
    delay 0.5
    
    -- 新規デスクトップを追加（右側に）
    key code 124 using {control down}  -- 右矢印
    delay 0.3
    keystroke "+" using {option down}
    delay 0.5
    
    -- Mission Controlを閉じる
    key code 53  -- ESC
end tell
```

#### 5.3.2 作成したデスクトップへ移動
```applescript
tell application "System Events"
    key code 124 using {control down}  -- 右へ移動
end tell
```

### 5.4 アプリケーション配置

#### 5.4.1 ブラウザ起動と配置（左1/3）

**複数ウィンドウ環境への対応**

既存のChromeウィンドウが複数開いている可能性を考慮し、新規ウィンドウを作成してそれを操作対象とします。

```applescript
tell application "Google Chrome"
    -- 新規ウィンドウで開く
    make new window
    set URL of active tab of front window to "${PR_URL}"
    delay 1.5  -- ウィンドウが完全に開くまで待機
end tell

tell application "System Events"
    tell process "Google Chrome"
        -- front window（最前面=今開いたウィンドウ）を対象に配置
        set position of front window to {0, 0}
        set size of front window to {screen_width / 3, screen_height}
    end tell
end tell
```

**代替案：URLでウィンドウを特定する方法**

```applescript
tell application "Google Chrome"
    make new window
    set URL of active tab of front window to "${PR_URL}"
    delay 1.5
    
    -- 対象ウィンドウをURLで特定
    set targetWindow to null
    repeat with w in windows
        if URL of active tab of w contains "${REPO_PATH}" then
            set targetWindow to w
            exit repeat
        end if
    end repeat
end tell

tell application "System Events"
    tell process "Google Chrome"
        if targetWindow is not null then
            set position of targetWindow to {0, 0}
            set size of targetWindow to {screen_width / 3, screen_height}
        end if
    end tell
end tell
```

#### 5.4.2 VS Code起動と配置（中央1/3）

**複数ウィンドウ環境への対応**

既存のVS Codeウィンドウが複数開いている可能性を考慮し、新規ウィンドウとして起動してそれを操作対象とします。

```bash
# VS Codeを新規ウィンドウとして起動（-nオプション）
code -n "${WORKTREE_PATH}"
```

```applescript
tell application "System Events"
    tell process "Code"
        -- 起動直後のウィンドウ表示待機
        delay 2
        
        -- front window（最前面=今開いたウィンドウ）を対象に配置
        set position of front window to {screen_width / 3, 0}
        set size of front window to {screen_width / 3, screen_height}
    end tell
end tell
```

**代替案：ウィンドウタイトルで特定する方法**

worktreeのディレクトリ名（pr-{番号}）がウィンドウタイトルに含まれることを利用して特定します。

```applescript
tell application "System Events"
    tell process "Code"
        delay 2  -- ウィンドウが完全に開くまで待機
        
        -- worktreeパスを含むウィンドウを検索
        repeat with w in windows
            if name of w contains "pr-${pr_number}" then
                set position of w to {screen_width / 3, 0}
                set size of w to {screen_width / 3, screen_height}
                exit repeat
            end if
        end repeat
    end tell
end tell
```

**注意事項**
- `-n` オプションを使用することで、常に新規ウィンドウで開く
- `delay 2` により、VS Codeが完全に起動してウィンドウが表示されるのを待つ
- ウィンドウタイトルによる特定は、VS Codeのバージョンやテーマによって動作が異なる可能性があるため、`front window`方式を推奨

## 6. 技術要件

### 6.1 スクリプト構成

```
pr-review-setup/
├── bin/
│   ├── setup-pr-review.sh       # メインスクリプト
│   └── lib/
│       ├── github.sh            # GitHub API操作
│       ├── worktree.sh          # Git worktree操作
│       ├── desktop.sh           # デスクトップ管理
│       └── layout.sh            # ウィンドウレイアウト
├── config/
│   ├── config.yml               # 設定ファイル
│   └── copy-files.txt           # コピー対象ファイルリスト
└── applescript/
    ├── create-desktop.scpt      # デスクトップ作成
    └── arrange-windows.scpt     # ウィンドウ配置
```

### 6.2 複数ウィンドウ環境への対応方針

本ワークフローは、ChromeやVS Codeで既に複数のウィンドウが開かれている環境を前提とします。

**基本方針**
1. **新規ウィンドウの作成**: 既存ウィンドウに影響を与えないよう、常に新規ウィンドウを作成
2. **front windowの活用**: 新規作成直後の `front window` を操作対象とする
3. **適切な待機時間**: ウィンドウが完全に表示されるまで `delay` を設ける

**実装上の注意点**
- Chrome: `make new window` で新規ウィンドウを作成
- VS Code: `code -n` オプションで新規ウィンドウとして起動
- 待機時間: Chrome 1.5秒、VS Code 2秒を推奨（環境により調整が必要）
- `window 1` や `window 2` といったインデックス指定は避ける（順序が保証されないため）

**ウィンドウ特定の優先順位**
1. **推奨**: `front window` - 最も確実で簡潔
2. **代替**: URLやタイトルで特定 - より厳密だが複雑
3. **非推奨**: インデックス指定 - 複数ウィンドウ環境では不安定

### 6.2.1 lib/github.sh 実装例
```bash
#!/bin/bash

# PR URLからPR情報を取得（gh CLI使用）
parse_pr_url() {
    local pr_url="$1"

    # gh コマンドでPR情報を一括取得
    local pr_info=$(gh pr view "${pr_url}" --json number,headRepository -q '{number, owner: .headRepository.owner.login, repo: .headRepository.name}')

    PR_NUMBER=$(echo "${pr_info}" | jq -r '.number')
    PR_OWNER=$(echo "${pr_info}" | jq -r '.owner')
    PR_REPO=$(echo "${pr_info}" | jq -r '.repo')

    export PR_NUMBER PR_OWNER PR_REPO

    log "PR情報取得: ${PR_OWNER}/${PR_REPO}#${PR_NUMBER}"
}

# Worktree作成（gh pr checkout使用）
create_worktree_with_pr() {
    local pr_number="$1"
    local repo_path="$2"

    local worktree_name="pr-${pr_number}"
    local worktree_path="${repo_path}/../${worktree_name}"

    cd "${repo_path}"

    # 空のworktreeを作成
    if ! git worktree add "${worktree_path}"; then
        log_error "Worktree作成に失敗しました"
        return 1
    fi

    # PRをチェックアウト（リモート追跡設定自動）
    cd "${worktree_path}"
    if ! gh pr checkout "${pr_number}"; then
        log_error "PR ${pr_number} のチェックアウトに失敗しました"
        log_error "PRが存在するか、マージ済みでないか確認してください"

        # クリーンアップ
        cd "${repo_path}"
        git worktree remove "${worktree_path}" --force
        return 1
    fi

    export WORKTREE_PATH="${worktree_path}"

    log "Worktree作成完了: ${worktree_path}"
    log "ブランチ: $(git branch --show-current)"
    log "リモート追跡: $(git config branch.$(git branch --show-current).remote)/$(git config branch.$(git branch --show-current).merge | sed 's|refs/heads/||')"
}
```

### 6.3 設定ファイル形式（config.yml）

```yaml
# Worktree設定（GitHub認証はgh CLIを使用）
worktree:
  naming_pattern: "pr-{pr_number}"
  cleanup_on_merge: true
  
# ファイルコピー設定
copy_files:
  patterns:
    - ".env.local"
    - ".env.development"
    - "config/local.yml"
    - "config/secrets/*.key"
  # リポジトリごとの個別設定も可能
  per_repository:
    "owner/repo":
      - "custom/config.json"

# レイアウト設定
layout:
  browser:
    position: "left"
    width_ratio: 0.33
  vscode:
    position: "center"
    width_ratio: 0.33
  terminal:  # 将来的な拡張用
    position: "right"
    width_ratio: 0.34
    
# デスクトップ設定
desktop:
  auto_switch: true
  desktop_name_pattern: "PR-{pr_number}"
```

### 6.4 コピー対象ファイルリスト（copy-files.txt）

```
# 基本的な環境設定ファイル
.env.local
.env.development.local

# アプリケーション設定
config/local.yml
config/database.yml

# 認証情報（必要な場合のみ）
# config/secrets/*.key

# IDE設定
.vscode/settings.json
```

## 7. エラーハンドリング

### 7.1 想定されるエラーケース

| エラーケース | 対処方法 |
|------------|---------|
| 無効なPR URL | URL形式をバリデーション、エラーメッセージ表示 |
| リポジトリが存在しない | ghq getで取得を提案 |
| PRブランチが削除済み | エラーメッセージ、マージ済みか確認 |
| Worktreeが既に存在 | 既存worktreeの利用を確認、または削除して再作成 |
| 権限エラー（GitHub API） | gh auth statusで認証状態を確認、gh auth loginで再認証 |
| デスクトップ作成失敗 | 現在のデスクトップで継続するか確認 |

### 7.2 ログ出力

```bash
# ログファイル
LOG_FILE="${HOME}/.pr-review-setup/logs/$(date +%Y%m%d).log"

# ログ関数
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "${LOG_FILE}" >&2
}
```

## 8. 実装例（メインスクリプト）

```bash
#!/bin/bash

set -euo pipefail

# 設定読み込み
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/github.sh"
source "${SCRIPT_DIR}/lib/worktree.sh"
source "${SCRIPT_DIR}/lib/desktop.sh"
source "${SCRIPT_DIR}/lib/layout.sh"

# メイン処理
main() {
    local pr_url="$1"
    
    log "PRレビュー環境セットアップ開始: ${pr_url}"
    
    # Step 1: PR情報解析
    log "Step 1: PR情報を解析中..."
    parse_pr_url "${pr_url}"
    local owner="${PR_OWNER}"
    local repo="${PR_REPO}"
    local pr_number="${PR_NUMBER}"
    
    # Step 2: Worktree作成（gh pr checkout使用）
    log "Step 2: Git worktreeを作成中..."
    create_worktree_with_pr "${pr_number}" "${repo_path}"
    local worktree_path="${WORKTREE_PATH}"
    
    # Step 2.1: ファイルコピー
    log "Step 2.1: 指定ファイルをコピー中..."
    copy_ignored_files "${owner}" "${repo}" "${worktree_path}"
    
    # Step 3: 仮想デスクトップ作成
    log "Step 3: 新規仮想デスクトップを作成中..."
    create_new_desktop
    
    # Step 4: アプリケーション配置
    log "Step 4: アプリケーションを配置中..."
    arrange_browser "${pr_url}"
    arrange_vscode "${worktree_path}"
    
    log "セットアップ完了！"
    log "Worktree: ${worktree_path}"
    log "PR URL: ${pr_url}"
}

# 使用方法チェック
if [ $# -eq 0 ]; then
    echo "使用方法: $0 <PR_URL>"
    echo "例: $0 https://github.com/owner/repo/pull/123"
    exit 1
fi

main "$1"
```

## 9. 使用方法

### 9.1 初回セットアップ

```bash
# スクリプトのインストール
git clone https://github.com/yourusername/pr-review-setup.git
cd pr-review-setup

# 実行権限付与
chmod +x bin/setup-pr-review.sh

# PATHに追加（.zshrcまたは.bashrc）
export PATH="$PATH:/path/to/pr-review-setup/bin"

# 設定ファイル編集
cp config/config.yml.example config/config.yml
vi config/config.yml  # GitHub tokenなど設定
```

### 9.2 日常的な使用

```bash
# PRレビュー環境を起動
setup-pr-review.sh https://github.com/owner/repo/pull/123

# レビュー完了後のクリーンアップ
cleanup-pr-review.sh pr-123
```

## 10. クリーンアップ処理

### 10.1 Worktreeの削除

```bash
#!/bin/bash

cleanup_worktree() {
    local worktree_name="$1"
    local repo_path="$2"
    
    cd "${repo_path}"
    
    # worktree削除
    git worktree remove "${worktree_name}"
    
    # ブランチ削除（オプション）
    git branch -D "pr-${pr_number}" 2>/dev/null || true
    
    log "Worktree ${worktree_name} を削除しました"
}
```

## 11. 今後の拡張性

### 11.1 Phase 2: 追加機能候補

- **自動テスト実行**: worktree作成後、自動でテストを実行
- **差分ハイライト**: PRの変更ファイルをVS Codeで自動的に開く
- **コメント連携**: PR上のコメントをVS Code内で確認
- **ターミナル配置**: 右1/3領域にターミナルを配置
- **マルチPR対応**: 複数のPRを同時にレビュー
- **Slack通知**: レビュー開始/完了をSlackに通知

### 11.2 Phase 3: 高度な機能

- **AIアシスト**: Claudeによるコードレビュー支援
- **依存関係チェック**: 変更による影響範囲の自動分析
- **パフォーマンス計測**: worktree環境でのベンチマーク実行
- **Docker連携**: コンテナ環境での動作確認

## 12. セキュリティ考慮事項

### 12.1 認証情報の管理

- GitHub Personal Access Tokenは環境変数で管理
- コピーする設定ファイルに機密情報が含まれる場合は暗号化を検討
- .gitignoreされたファイルのコピーはホワイトリスト方式

### 12.2 アクセス制御

- スクリプトは個人のホームディレクトリ内で実行
- 他ユーザーからの読み取りを制限（chmod 700）

## 13. パフォーマンス最適化

### 13.1 並列処理

```bash
# GitHub API呼び出しとworktree作成を並列化
{
    fetch_pr_details &
    PID1=$!
    
    setup_worktree_directory &
    PID2=$!
    
    wait $PID1 $PID2
}
```

### 13.2 キャッシング

- PR情報のローカルキャッシュ（一定期間）
- ghqリポジトリパスのキャッシュ

## 14. トラブルシューティング

### 14.1 よくある問題

**Q: gh pr checkoutでエラーが発生する**
```bash
# 認証状態を確認
gh auth status

# 認証が切れている場合は再認証
gh auth login

# PRが存在するか確認
gh pr view ${pr_number}
```

**Q: デスクトップ作成がうまくいかない**
```bash
# macOSのアクセシビリティ権限を確認
# システム設定 > プライバシーとセキュリティ > アクセシビリティ
# ターミナルまたはスクリプト実行アプリを追加
```

**Q: VS Codeが正しい位置に配置されない**
```bash
# ディスプレイ解像度の取得がうまくいっていない可能性
# layout.shのscreen_width, screen_height計算を確認
```

## 15. 参考資料

- [Git Worktree Documentation](https://git-scm.com/docs/git-worktree)
- [ghq - GitHub](https://github.com/x-motemen/ghq)
- [macOS AppleScript Guide](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/)
- [GitHub REST API - Pull Requests](https://docs.github.com/en/rest/pulls/pulls)

---

**作成日**: 2026年1月29日  
**バージョン**: 1.0  
**ステータス**: 設計完了
