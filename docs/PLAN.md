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
- **OS**: macOS (Mission Control対応)
- **Swift**: バージョン 6.2以降
- **Xcode Command Line Tools**: Swiftコンパイラ
- **Git**: バージョン 2.5以降（git worktree対応）
- **ghq**: リポジトリ管理ツール
- **gh**: GitHub CLI
- **VS Code**: エディタ
- **ブラウザ**: Chrome, Safari, Firefox等
- **macOS Mission Control**: 仮想デスクトップ機能
- **Accessibility権限**: Mission Control操作に必要

### 3.2 事前設定
- ghqによるリポジトリ管理が設定済み
- VS Codeがコマンドラインから起動可能（`code`コマンド）
- GitHub CLIが認証設定済み（`gh auth login`で認証完了）
- **macOS権限の許可**:
  - **Accessibility権限**（必須）:
    - システム設定 > プライバシーとセキュリティ > アクセシビリティ
    - **アプリケーションバンドル（`ReviewSetup.app`）** を許可リストに追加
    - Mission Control UI操作、ウィンドウ配置に必要
    - **注意**: 単体の実行バイナリ（`.build/release/review-setup`）はアクセシビリティ設定に追加できないため、必ず `.app` 形式を使用すること
  - **入力監視権限**（デスクトップ移動に必要）:
    - システム設定 > プライバシーとセキュリティ > 入力監視
    - アプリケーションバンドル（`ReviewSetup.app`）を許可リストに追加
    - キーボードショートカット（Control + 矢印）のシミュレーションに必要
  - 初回実行時にダイアログが表示される

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
WORKTREE_PATH="${REPO_PATH}/../${repo}.worktrees/${WORKTREE_NAME}"

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

**Swift + Accessibility API方式**

従来のAppleScript + キーボードショートカット方式ではなく、Accessibility APIを使用してDockプロセスのUI要素を直接操作します。

```swift
// MissionControlManagerクラスによる実装
func createNewDesktop() throws {
    // 1. Mission Controlを起動
    openMissionControl()

    // 2. DockアプリケーションのAccessibility要素を取得
    guard let dockApp = NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.apple.dock"
    ).first else {
        throw NSError(domain: "MissionControl", code: 1)
    }

    let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)

    // 3. Mission Controlグループを再帰的に探索
    var missionControlGroup: AXUIElement?
    findMissionControlGroup(in: dockElement, result: &missionControlGroup)

    // 4. "デスクトップを追加" / "add desktop" ボタンを探索
    let addButton = findAddDesktopButton(in: missionControlGroup)

    // 5. ボタンをプレス
    AXUIElementPerformAction(addButton, kAXPressAction as CFString)

    // 6. Mission Controlを閉じる
    openMissionControl()
}
```

**利点**:
- キーボードショートカットに依存せず、より確実
- 言語設定（日本語/英語）に対応（ボタンのdescriptionで判定）
- Mission Controlのレイアウト変更に強い
- キー入力タイミングの調整が不要

#### 5.3.2 作成したデスクトップへ移動

**Swift + CGEvent API方式**

CGEventを使用してキーボードショートカット（Control + 右矢印）をシミュレートします。

```swift
func moveToNextDesktop() {
    // Control + 右矢印キーのシミュレーション
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

**注意**: CGEventを使用するには、アクセシビリティ権限に加えて入力監視権限が必要です。

### 5.4 アプリケーション配置

#### 5.4.1 ブラウザ起動と配置（左1/3）

**Swift + Accessibility API方式**

NSWorkspaceでブラウザを起動し、Accessibility APIでウィンドウを配置します。

```swift
class WindowManager {
    func openBrowserAndArrange(url: String, position: LayoutPosition) throws {
        // 1. ブラウザを起動してURLを開く
        guard let urlObj = URL(string: url) else {
            throw NSError(domain: "WindowManager", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        // デフォルトブラウザで開く
        NSWorkspace.shared.open(urlObj)

        // または特定のブラウザで開く場合
        // NSWorkspace.shared.open([urlObj],
        //     withApplicationAt: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
        //     configuration: NSWorkspace.OpenConfiguration())

        // ブラウザウィンドウが開くまで待機
        Thread.sleep(forTimeInterval: 2.0)

        // 2. ブラウザプロセスを取得
        let browserApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.google.Chrome" ||
            $0.bundleIdentifier == "com.apple.Safari" ||
            $0.bundleIdentifier == "org.mozilla.firefox"
        }

        guard let browserApp = browserApps.first else {
            throw NSError(domain: "WindowManager", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Browser not found"])
        }

        // 3. Accessibility要素を取得
        let appElement = AXUIElementCreateApplication(browserApp.processIdentifier)

        // 4. 最前面のウィンドウを取得
        var windowRef: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        )

        guard error == .success, let window = windowRef else {
            throw NSError(domain: "WindowManager", code: 3,
                         userInfo: [NSLocalizedDescriptionKey: "Window not found"])
        }

        // 5. スクリーン解像度を取得
        guard let screen = NSScreen.main else {
            throw NSError(domain: "WindowManager", code: 4)
        }
        let screenFrame = screen.visibleFrame

        // 6. ウィンドウ位置とサイズを設定（左1/3）
        let width = screenFrame.width / 3
        let height = screenFrame.height
        let x = screenFrame.minX
        let y = screenFrame.minY

        try setWindowPosition(window as! AXUIElement, x: x, y: y)
        try setWindowSize(window as! AXUIElement, width: width, height: height)
    }

    private func setWindowPosition(_ window: AXUIElement, x: CGFloat, y: CGFloat) throws {
        var position = CGPoint(x: x, y: y)
        let positionValue = AXValueCreate(.cgPoint, &position)!

        let error = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            positionValue
        )

        guard error == .success else {
            throw NSError(domain: "WindowManager", code: 5)
        }
    }

    private func setWindowSize(_ window: AXUIElement, width: CGFloat, height: CGFloat) throws {
        var size = CGSize(width: width, height: height)
        let sizeValue = AXValueCreate(.cgSize, &size)!

        let error = AXUIElementSetAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            sizeValue
        )

        guard error == .success else {
            throw NSError(domain: "WindowManager", code: 6)
        }
    }
}

enum LayoutPosition {
    case left, center, right
}
```

**利点**:
- 複数のブラウザ（Chrome、Safari、Firefox）に対応
- デフォルトブラウザを使用可能
- ウィンドウの正確な位置・サイズ設定
- エラーハンドリングが明確

#### 5.4.2 VS Code起動と配置（中央1/3）

**Swift + Process + Accessibility API方式**

Processでコマンドラインから起動し、Accessibility APIでウィンドウを配置します。

```swift
extension WindowManager {
    func openVSCodeAndArrange(path: String, position: LayoutPosition) throws {
        // 1. VS Codeを新規ウィンドウで起動
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/local/bin/code")
        task.arguments = ["-n", path]  // -n: 新規ウィンドウ

        try task.run()

        // VS Codeウィンドウが開くまで待機
        Thread.sleep(forTimeInterval: 2.5)

        // 2. VS Codeプロセスを取得
        guard let vscodeApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.microsoft.VSCode"
        }) else {
            throw NSError(domain: "WindowManager", code: 7,
                         userInfo: [NSLocalizedDescriptionKey: "VS Code not found"])
        }

        // 3. Accessibility要素を取得
        let appElement = AXUIElementCreateApplication(vscodeApp.processIdentifier)

        // 4. 最前面のウィンドウを取得（最後に開いたウィンドウ）
        var windowRef: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        )

        guard error == .success, let window = windowRef else {
            // フォーカスされたウィンドウがない場合、全ウィンドウから検索
            try arrangeVSCodeWindowByTitle(appElement, searchPath: path, position: position)
            return
        }

        // 5. スクリーン解像度を取得
        guard let screen = NSScreen.main else {
            throw NSError(domain: "WindowManager", code: 8)
        }
        let screenFrame = screen.visibleFrame

        // 6. ウィンドウ位置とサイズを設定（中央1/3）
        let width = screenFrame.width / 3
        let height = screenFrame.height
        let x = screenFrame.minX + width  // 左1/3の右側
        let y = screenFrame.minY

        try setWindowPosition(window as! AXUIElement, x: x, y: y)
        try setWindowSize(window as! AXUIElement, width: width, height: height)
    }

    // ウィンドウタイトルで特定する代替方法
    private func arrangeVSCodeWindowByTitle(
        _ appElement: AXUIElement,
        searchPath: String,
        position: LayoutPosition
    ) throws {
        var windowsRef: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )

        guard error == .success,
              let windows = windowsRef as? [AXUIElement] else {
            throw NSError(domain: "WindowManager", code: 9)
        }

        // パス名（pr-XXX）を含むウィンドウを検索
        let pathComponent = URL(fileURLWithPath: searchPath).lastPathComponent

        for window in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(
                window,
                kAXTitleAttribute as CFString,
                &titleRef
            )

            if let title = titleRef as? String,
               title.contains(pathComponent) {
                // ウィンドウを配置
                guard let screen = NSScreen.main else { continue }
                let screenFrame = screen.visibleFrame
                let width = screenFrame.width / 3
                let height = screenFrame.height
                let x = screenFrame.minX + width
                let y = screenFrame.minY

                try? setWindowPosition(window, x: x, y: y)
                try? setWindowSize(window, width: width, height: height)
                return
            }
        }

        throw NSError(domain: "WindowManager", code: 10,
                     userInfo: [NSLocalizedDescriptionKey: "VS Code window not found"])
    }
}
```

**注意事項**:
- `code`コマンドのパスは環境により異なる（`/usr/local/bin/code`、`/opt/homebrew/bin/code`等）
- `which code`で確認するか、設定ファイルで指定可能にする
- VS Codeの起動に時間がかかる場合は待機時間を調整
- フォーカスされたウィンドウがない場合、タイトル検索にフォールバック

## 6. 技術要件

### 6.1 プロジェクト構成

**Swiftプロジェクト構成**

```
review-setup/
├── Package.swift                           # Swift Package Manager設定
├── Sources/
│   └── review-setup/
│       └── review_setup.swift              # メイン実装
│           ├── MissionControlManager       # デスクトップ作成・移動
│           ├── WindowManager               # ブラウザ/VS Code配置
│           └── ReviewSetupApp (@main)      # エントリーポイント、CLI引数解析
├── Resources/
│   └── Info.plist                          # アプリケーションバンドル用メタデータ
├── Makefile                                # アプリケーションバンドル作成用
├── bin/
│   ├── setup-pr-review.sh                  # メインスクリプト (Shell)
│   └── lib/
│       ├── github.sh                       # GitHub API操作
│       └── worktree.sh                     # Git worktree操作
├── config/
│   ├── config.yml                          # 設定ファイル
│   └── copy-files.txt                      # コピー対象ファイルリスト
└── docs/
    └── PLAN.md                             # 設計資料
```

**Swiftコードの責務**:
- デスクトップ作成（Mission Control UI操作）
- デスクトップ間移動（キーボードショートカットシミュレーション）
- ブラウザ起動とウィンドウ配置（Accessibility API）
- VS Code起動とウィンドウ配置（Process + Accessibility API）
- CLI引数に基づく動作切り替え（`--create-desktop`, `--arrange-browser`, `--arrange-vscode`等）

**Shellスクリプトの責務**:
- PR情報の解析とgh CLI連携
- Git worktreeの作成・管理
- 設定ファイルの読み込みとファイルコピー
- 全体のワークフロー制御とエラーハンドリング

**技術スタック**:
- **Swift 6.2+**: Mission Control操作、ウィンドウ管理の実装言語
- **Accessibility API (AXUIElement)**: UI要素の探索と操作、ウィンドウ配置
- **CGEvent API**: キーボードショートカットのシミュレーション（デスクトップ移動）
- **Cocoa (NSWorkspace)**: アプリケーションの起動とURL処理
- **Bash/Shell**: PR情報取得、worktree管理、全体フロー制御
- **gh CLI**: GitHub PR情報取得とチェックアウト

### 6.2 複数ウィンドウ環境への対応方針（Swift実装）

本ワークフローは、ChromeやVS Codeで既に複数のウィンドウが開かれている環境を前提とします。

**基本方針**
1. **新規ウィンドウの作成**: 既存ウィンドウに影響を与えないよう、常に新規ウィンドウを作成
2. **フォーカスウィンドウの活用**: Accessibility APIの`kAXFocusedWindowAttribute`で最前面ウィンドウを取得
3. **適切な待機時間**: ウィンドウが完全に表示されるまで`Thread.sleep()`で待機

**Swift実装上の注意点**
- **ブラウザ**: `NSWorkspace.shared.open(url)`でURLを開く（新規ウィンドウは自動）
- **VS Code**: `Process()`で`code -n`を実行し新規ウィンドウとして起動
- **待機時間**: ブラウザ 2.0秒、VS Code 2.5秒を推奨（環境により調整が必要）
- **ウィンドウ属性**: Accessibility APIで`kAXPositionAttribute`と`kAXSizeAttribute`を設定

**ウィンドウ特定の優先順位**
1. **推奨**: `kAXFocusedWindowAttribute` - 最も確実で簡潔
2. **代替**: `kAXWindowsAttribute`で全ウィンドウを取得し、タイトルで検索 - より厳密だが複雑
3. **非推奨**: 配列インデックス指定 - 複数ウィンドウ環境では不安定

**必要な権限**
- **Accessibility権限**: ウィンドウの位置・サイズ変更に必須
- **入力監視権限**: キーボードショートカット（デスクトップ移動）に必須

### 6.2.1 アプリケーションバンドルの作成

macOSのアクセシビリティ設定では、単体の実行バイナリではなく**アプリケーションバンドル（.app）形式**を想定しています。以下の手順でバンドルを作成します。

#### Info.plist の作成

`Resources/Info.plist` を以下の内容で作成:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>review-setup</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.review-setup</string>
    <key>CFBundleName</key>
    <string>ReviewSetup</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>Mission Control操作とウィンドウ配置のためにアクセシビリティ権限が必要です</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>デスクトップ切り替えのために入力監視権限が必要です</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
```

#### アプリケーションバンドル構造

```
ReviewSetup.app/
  Contents/
    Info.plist
    MacOS/
      review-setup          # Swiftビルド済みバイナリ
```

#### Makefile によるビルド自動化

`Makefile` を作成:

```makefile
.PHONY: build app install clean

APP_NAME = ReviewSetup
BUNDLE = $(APP_NAME).app
CONTENTS = $(BUNDLE)/Contents
MACOS = $(CONTENTS)/MacOS
RESOURCES = $(CONTENTS)/Resources

build:
	swift build -c release

app: build
	mkdir -p $(MACOS)
	mkdir -p $(RESOURCES)
	cp .build/release/review-setup $(MACOS)/
	cp Resources/Info.plist $(CONTENTS)/

install: app
	rm -rf ~/Applications/$(BUNDLE)
	cp -R $(BUNDLE) ~/Applications/

clean:
	rm -rf $(BUNDLE)
	swift package clean
```

使用方法:
```bash
# アプリケーションバンドルを作成
make app

# ~/Applications にインストール
make install

# クリーンアップ
make clean
```

### 6.2.2 lib/github.sh 実装例
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
    local worktree_path="${repo_path}/../${repo}.worktrees/${worktree_name}"

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
    
    # Step 3: 仮想デスクトップ作成（.appバンドル内のバイナリ使用）
    log "Step 3: 新規仮想デスクトップを作成中..."
    "${SCRIPT_DIR}/../ReviewSetup.app/Contents/MacOS/review-setup"

    # Step 4: アプリケーション配置（.appバンドル内のバイナリ使用）
    log "Step 4: アプリケーションを配置中..."
    "${SCRIPT_DIR}/../ReviewSetup.app/Contents/MacOS/review-setup" \
        --arrange-browser "${pr_url}" \
        --arrange-vscode "${worktree_path}"
    
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
# リポジトリのクローン
git clone https://github.com/yourusername/review-setup.git
cd review-setup

# アプリケーションバンドルの作成
make app

# ~/Applications にインストール（推奨）
make install

# または /Applications にインストール（管理者権限が必要）
# sudo cp -R ReviewSetup.app /Applications/

# アプリケーションバンドルの確認
ls -la ~/Applications/ReviewSetup.app

# シェルスクリプトに実行権限付与
chmod +x bin/setup-pr-review.sh

# PATHに追加（.zshrcまたは.bashrc）
export PATH="$PATH:/path/to/review-setup/bin"

# 設定ファイル編集
cp config/config.yml.example config/config.yml
vi config/config.yml  # 必要に応じて設定

# Accessibility権限の付与
# 1. システム設定 > プライバシーとセキュリティ > アクセシビリティ を開く
# 2. 鍵アイコンをクリックして変更を許可
# 3. 「+」ボタンで ~/Applications/ReviewSetup.app を追加
# 4. システム設定 > プライバシーとセキュリティ > 入力監視 でも同様に追加
# 5. 初回実行時にダイアログが表示される場合は許可する
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

**Swift実装での拡張**:
- **ターミナル配置**: 右1/3領域にターミナルアプリを配置（Accessibility API）
- **カスタムレイアウト**: 設定ファイルでウィンドウ分割比率を変更可能に
- **マルチディスプレイ対応**: 外部ディスプレイへの配置オプション
- **デスクトップ名設定**: Mission Control APIでデスクトップに名前を設定
- **アプリケーション選択**: ブラウザ（Chrome/Safari/Firefox）の選択機能

**Shell実装での拡張**:
- **自動テスト実行**: worktree作成後、自動でテストを実行
- **差分ハイライト**: PRの変更ファイルをVS Codeで自動的に開く（`code -d`）
- **コメント連携**: gh CLIでPRコメントを取得して表示
- **マルチPR対応**: 複数のPRを同時にレビュー（複数デスクトップ作成）
- **Slack通知**: レビュー開始/完了をSlackに通知

### 11.2 Phase 3: 高度な機能

- **AIアシスト**: Claudeによるコードレビュー支援
- **依存関係チェック**: 変更による影響範囲の自動分析
- **パフォーマンス計測**: worktree環境でのベンチマーク実行
- **Docker連携**: コンテナ環境での動作確認
- **Swift Package化**: review-setup をライブラリとして他のツールから利用可能に

## 12. セキュリティ考慮事項

### 12.1 認証情報の管理

- **GitHub認証**: gh CLIの認証情報を使用（Personal Access Token不要）
- コピーする設定ファイルに機密情報が含まれる場合は暗号化を検討
- .gitignoreされたファイルのコピーはホワイトリスト方式

### 12.2 macOS権限とアクセス制御

**Accessibility権限の影響範囲**:
- Accessibility APIは他のアプリケーションのUI要素にアクセス可能
- ウィンドウ位置・サイズの取得と変更のみに使用
- 機密情報の読み取りは行わない

**入力監視権限の影響範囲**:
- CGEvent APIはキーボード入力のシミュレーションが可能
- Control + 矢印キーのみをシミュレート
- ユーザー入力のキャプチャは行わない

**実行ファイルの管理**:
- アプリケーションバンドル（`.app`）は `~/Applications` または `/Applications` に配置
- 他ユーザーからの読み取りを制限する場合は `chmod 700 ReviewSetup.app`
- **コード署名（Code Signing）** を推奨:
  - 署名なしの場合、初回起動時にGatekeeperの警告が表示される
  - `codesign --sign "Developer ID Application" ReviewSetup.app` で署名
  - App Store配布でない場合は「開発者として確認」で回避可能
- `.app` バンドルの配布には注意（アクセシビリティ権限が必要なため）

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

### 13.3 Swift実装の最適化

**起動速度の改善**:
```bash
# リリースビルドの最適化
swift build -c release -Xswiftc -O

# バイナリサイズの削減（strip symbols）
strip .build/release/review-setup
```

**待機時間の調整**:
- Mission Control表示待機: 1.0秒（デフォルト）
- ブラウザ起動待機: 2.0秒（デフォルト）
- VS Code起動待機: 2.5秒（デフォルト）
- 環境に応じて設定ファイルで調整可能にする

**Accessibility API呼び出しの最適化**:
- 再帰的UI探索の深さ制限
- タイムアウト設定（無限ループ防止）
- エラー時の早期リターン

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

**Q: アクセシビリティ設定に追加できない**
```bash
# 問題: 単体の実行バイナリ（.build/release/review-setup）は
#       アクセシビリティ設定の許可リストに追加できない

# 解決策: アプリケーションバンドル（.app）を使用する
make app
make install

# システム設定で ~/Applications/ReviewSetup.app を追加する
```

**Q: デスクトップ作成がうまくいかない**
```bash
# 1. macOSのアクセシビリティ権限を確認
# システム設定 > プライバシーとセキュリティ > アクセシビリティ
# ReviewSetup.app を許可リストに追加

# 2. アプリケーションバンドルが正しく作成されているか確認
ls -la ~/Applications/ReviewSetup.app/Contents/MacOS/review-setup

# 3. Mission Controlが正常に動作するか確認
open -a "Mission Control"

# 4. デバッグ実行
~/Applications/ReviewSetup.app/Contents/MacOS/review-setup
# エラーメッセージを確認
```

**Q: VS Codeが正しい位置に配置されない**
```bash
# 1. VS Codeが完全に起動しているか確認
# 起動に時間がかかる場合、待機時間を延ばす

# 2. code コマンドのパスを確認
which code

# 3. マルチディスプレイ環境の場合
# NSScreen.mainが正しいディスプレイを取得しているか確認
```

**Q: 権限エラーが発生する**
```bash
# Accessibility権限の確認
# システム設定 > プライバシーとセキュリティ > アクセシビリティ
# ReviewSetup.app を許可リストに追加
# ※ 単体バイナリ（.build/release/review-setup）では追加できない

# 入力監視権限の確認（デスクトップ移動が失敗する場合）
# システム設定 > プライバシーとセキュリティ > 入力監視
# ReviewSetup.app を許可リストに追加

# 権限を変更した後、アプリケーションを再起動
```

**Q: Swiftバイナリのビルドが失敗する**
```bash
# Swift バージョンの確認
swift --version
# 必要: Swift 6.2以上

# Xcode Command Line Tools のインストール
xcode-select --install

# クリーンビルド
make clean
make app
```

**Q: アプリを開けない（Gatekeeper警告）**
```bash
# 署名されていないアプリの場合、初回起動時に警告が表示される

# 解決策1: 右クリック > 開く で起動
# （「開発者を確認できないため開けません」を回避）

# 解決策2: コード署名を行う（開発者証明書が必要）
codesign --sign "Developer ID Application" ReviewSetup.app

# 解決策3: Gatekeeperを一時的に無効化（非推奨）
sudo spctl --master-disable
# 使用後は必ず再度有効化: sudo spctl --master-enable
```

## 15. 参考資料

- [Git Worktree Documentation](https://git-scm.com/docs/git-worktree)
- [ghq - GitHub](https://github.com/x-motemen/ghq)
- [macOS Accessibility API](https://developer.apple.com/documentation/applicationservices/axuielement)
- [Swift Documentation](https://www.swift.org/documentation/)
- [GitHub CLI (gh)](https://cli.github.com/)
- [GitHub REST API - Pull Requests](https://docs.github.com/en/rest/pulls/pulls)

---

**作成日**: 2026年1月29日
**最終更新**: 2026年2月2日
**バージョン**: 1.2
**ステータス**: 設計完了（Swift実装版 + .app対応）

## 変更履歴

### v1.2 (2026-02-02)
- アプリケーションバンドル（.app形式）対応を追加
- Info.plist とMakefile の追加
- アクセシビリティ権限の付与手順を .app ベースに更新
- トラブルシューティングに「アクセシビリティに追加できない」FAQを追加
- コード署名に関する記述を追加

### v1.1 (2026-02-02)
- AppleScriptベースの実装からSwift + Accessibility APIへ移行
- Mission Control操作、ウィンドウ配置をすべてSwiftで実装
- CGEvent APIによるデスクトップ移動機能を追加
- NSWorkspaceによるアプリケーション起動を追加
- セキュリティ、パフォーマンス最適化に関する記述を追加

### v1.0 (2026-01-29)
- 初期設計（AppleScriptベース）
