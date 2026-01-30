# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

プロジェクト概要・ビルド方法・必要環境は [README.md](./README.md) を参照。

## Architecture

単一ファイル構成（`Sources/review-setup/review_setup.swift`）:

- **`MissionControlManager`** — Accessibility API (`AXUIElement`) を使ってDockプロセス内のMission Control UIを再帰探索し、「デスクトップを追加」ボタンを押す
- **`ReviewSetupApp`** (`@main`) — エントリーポイント

使用フレームワーク: `Cocoa`, `ApplicationServices`

Swift Package Manager (swift-tools-version: 6.2) を使用。外部依存なし。
