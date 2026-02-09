import Foundation

// エントリーポイント
@main
struct ReviewSetupApp {
    static func main() {
        logInfo("ReviewSetup 起動")
        logInfo("Console.app で「com.example.review-setup」または「ReviewSetup」で検索")
        logInfo("または: log stream --predicate 'subsystem == \"com.example.review-setup\"' --level info")
        logInfo("")

        let windowManager = WindowManager()
        do {
            try windowManager.openBrowserAndArrange(url: "https://github.com", position: .left)
            logInfo("✓✓✓ 処理完了 ✓✓✓")
        } catch {
            logError("!!! エラー発生 !!!")
            logError("エラー内容: \(error.localizedDescription)")
            exit(1)
        }


        // // コマンドライン引数を解析
        // if arguments.contains("--arrange-browser") {
        //     // ブラウザ配置モード
        //     let urlIndex = arguments.firstIndex(of: "--arrange-browser")! + 1
        //     let url = urlIndex < arguments.count ? arguments[urlIndex] : "https://github.com"

        //     let windowManager = WindowManager()
        //     do {
        //         try windowManager.openBrowserAndArrange(url: url, position: .left)
        //         print("✓ ブラウザを左1/3に配置しました")
        //     } catch {
        //         print("エラー: \(error.localizedDescription)")
        //         exit(1)
        //     }
        // } else {
        //     // デフォルト: デスクトップ作成モード
        //     let manager = MissionControlManager()
        //     do {
        //         try manager.createNewDesktop()
        //         print("新しいデスクトップを作成しました")

        //         // 作成したデスクトップへ移動
        //         manager.moveToNextDesktop()
        //         print("新しいデスクトップへ移動しました")
        //     } catch {
        //         print("エラー: \(error.localizedDescription)")
        //         exit(1)
        //     }
        // }
    }
}
