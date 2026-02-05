# 実装計画: 5.2 Git Worktree作成

## 概要

PLAN.md セクション5.2に基づき、PR URLからgit worktreeを作成するシェルスクリプト群を実装する。
ファイルコピー（5.2.3）はgit hookで対応済みのためスキップ。

## 方針

PLAN.mdの設計に従い、**シェルスクリプト**で実装する。
- Shell: PR解析・worktree管理・ワークフロー制御
- Swift: デスクトップ作成・ウィンドウ配置（既存）

## 作成ファイル

```
bin/
  setup-pr-review.sh          # メインスクリプト（エントリーポイント）
  lib/
    logging.sh                 # ログユーティリティ
    github.sh                  # PR URL解析
    worktree.sh                # Git worktree操作
```

## 各ファイルの実装内容

### 1. `bin/lib/logging.sh`

- `init_logging()` — ログディレクトリ `~/.pr-review-setup/logs/` を作成、ログファイルパスを設定
- `log()` — `[YYYY-MM-DD HH:MM:SS] message` 形式でstdout + ログファイルに出力
- `log_error()` — 同形式で `ERROR:` 付きでstderr + ログファイルに出力

### 2. `bin/lib/github.sh`

- `validate_pr_url(pr_url)` — 正規表現で `https://github.com/{owner}/{repo}/pull/{number}` 形式を検証
- `parse_pr_url(pr_url)` — URLからowner/repo/numberを抽出し、`gh pr view`でPR存在を確認。`PR_NUMBER`, `PR_OWNER`, `PR_REPO`をexport

jq不要: URLパースで情報取得、`gh pr view`は存在確認のみに使用。

### 3. `bin/lib/worktree.sh`

- `find_repo_path(owner, repo)` — `ghq root`でルート取得、`${ghq_root}/github.com/${owner}/${repo}`を構築。`REPO_PATH`をexport
- `create_worktree_with_pr(pr_number, repo_path, repo_name)` — worktree作成とPRチェックアウト。`WORKTREE_PATH`をexport

Worktreeパス: `${REPO_PATH}/../${repo_name}.worktrees/pr-${pr_number}`（commit 26ecbd4の方針に準拠）

処理フロー:
1. 既存worktreeがあれば再利用
2. `git worktree add --detach` で作成（不要なブランチ作成を回避）
3. `gh pr checkout ${pr_number}` でPRブランチをチェックアウト
4. 失敗時はworktreeをクリーンアップ

### 4. `bin/setup-pr-review.sh`

```bash
#!/bin/bash
set -euo pipefail
```

処理フロー:
1. 前提条件チェック（gh, ghq, git の存在、gh認証確認）
2. PR URL解析（parse_pr_url）
3. リポジトリパス特定（find_repo_path）
4. Worktree作成（create_worktree_with_pr）
5. 結果出力

引数なしの場合はUsageを表示して終了。

## エラーハンドリング

| ケース | 対処 |
|--------|------|
| 無効なPR URL | validate_pr_urlで検出、エラーメッセージ表示 |
| gh未認証 | 前提条件チェックで検出、`gh auth login`を案内 |
| PR未存在/マージ済み | `gh pr view`で検出 |
| リポジトリ未クローン | `ghq get`を案内 |
| Worktree既存 | 既存worktreeを再利用 |
| `gh pr checkout`失敗 | worktreeをクリーンアップして終了 |

## 検証方法

```bash
# スクリプト実行権限付与
chmod +x bin/setup-pr-review.sh

# 正常系: 実際のPR URLで実行
bin/setup-pr-review.sh https://github.com/owner/repo/pull/123

# 異常系テスト
bin/setup-pr-review.sh                                          # Usage表示
bin/setup-pr-review.sh https://example.com/bad                  # URL検証エラー
bin/setup-pr-review.sh https://github.com/owner/repo/pull/99999 # PR未存在エラー
```
