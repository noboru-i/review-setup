# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

プロジェクト概要・ビルド方法・必要環境は [README.md](./README.md) を参照。

## Architecture

モジュール構成（`Sources/review-setup/`）:

- **`Logger.swift`** — OSLogベースのロガー関数（`logInfo()`, `logError()`, `logDebug()`）
- **`MissionControlManager.swift`** — Accessibility API (`AXUIElement`) を使ってDockプロセス内のMission Control UIを再帰探索し、「デスクトップを追加」ボタンを押す
- **`WindowManager.swift`** — Chromeブラウザを起動し、Accessibility APIを使ってウィンドウを画面の左/中央/右1/3に配置
- **`ReviewSetupApp.swift`** — エントリーポイント（`@main`）

使用フレームワーク: `Cocoa`, `ApplicationServices`, `OSLog`

Swift Package Manager (swift-tools-version: 6.2) を使用。外部依存なし。
