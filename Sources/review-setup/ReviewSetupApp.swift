import Foundation

// エントリーポイント
@main
struct ReviewSetupApp {
    static func main() {
        logInfo("ReviewSetup 起動")
        logInfo("Console.app で「com.example.review-setup」または「ReviewSetup」で検索")
        logInfo("または: log stream --predicate 'subsystem == \"com.example.review-setup\"' --level info")
        logInfo("")

        // VS Code起動とウィンドウ配置のテスト
        let windowManager = WindowManager()

        // テスト用: 指定されたworktreeパスでVS Codeを起動
        let testPath = "/Users/noboruishikura/ghq/github.com/noboru-i/review-setup.worktrees/sample-worktree"

        do {
            try windowManager.openVSCodeAndArrange(path: testPath, position: .center)
            logInfo("✓✓✓ VS Code配置処理完了 ✓✓✓")
        } catch {
            logError("!!! エラー発生 !!!")
            logError("エラー内容: \(error.localizedDescription)")
            exit(1)
        }
    }
}
