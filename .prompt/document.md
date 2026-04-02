# 実装内容

## 概要
- `StockManager` の iOS 版を SwiftUI で実装
- 3 状態アイテム、複数ボード、検索、フィルタ、ソート、買い物リスト、チュートリアル、JSON/CSV 入出力、法務画面、全データ削除を追加

## 追加した主な構成
- `StockManagerModels.swift`
  - `Board`, `StockItem`, `Settings`, `ItemStatus`, `SortMode` を定義
- `StockManagerPersistence.swift`
  - アプリデータを JSON ファイルとして永続化
  - 初回シード、状態正規化、全データ初期化を実装
- `StockManagerImportExport.swift`
  - JSON / CSV の export
  - schemaVersion 付き import
  - minimal JSON template と legacy `inStock` 互換を実装
- `StockManagerStore.swift`
  - 画面全体の状態管理
  - ボード CRUD、アイテム CRUD、状態切替、買い物リストドラフト、チュートリアル制御を実装
- `ContentView.swift`
  - ホーム画面、ドロワー、各 sheet、買い物リストオーバーレイ、チュートリアルオーバーレイを実装
  - `.ui/` の Android 参考画像に寄せた配色、カード、ドロワー、アクションバー、中央ダイアログの見た目へ調整し、iOS では操作域とモーダル表現を自然になるよう補正
  - 起動直後の白画面対策として、初期データ読込を `App` 初期化時ではなく初回描画後へ移動し、読込中プレースホルダを追加
- `StockManagerLegalContent.swift`
  - About / 利用規約 / OSS / プライバシーポリシーの表示文言を実装
- `StockManagerTests.swift`
  - 初期シード、重複追加禁止、import 互換、フィルタ制約、買い物リスト優先順の単体テストを追加

## 仕様との対応
- 初回起動時に初期ボード 1 件、初期アイテム 1 件を自動投入
- アイテムタップで `白 -> 黄 -> 赤 -> 白` の循環を実装
- ボード追加 / 削除 / 名称変更 / 並び替えを実装
- アイテム追加 / 名称変更 / 削除を実装
- `showStock` と `showOut` が同時に `false` にならない補正を実装
- 買い物リストでは `HIGHLIGHTED` を `OUT_OF_STOCK` より優先して表示
- import は常に新規ボード作成、item は最大 500 件まで投入
- 全データ削除後は再シードしてチュートリアルを再表示

## 仕様との差分
- 永続化は `Core Data` ではなく、アプリサポート領域の JSON ファイルで実装
  - 機能 parity を優先し、依存追加なしで扱いやすい構成を採用
- 検索クエリが残っている場合は起動時に検索 UI を開いた状態で復元
  - 仕様書の「UX 改善として許容」側を採用
- 法務文書の Android raw text はリポジトリ内に存在しなかったため、iOS 側では仕様に沿う暫定文面を実装

## 実行結果
- `build`
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme StockManager -project StockManager.xcodeproj -destination 'generic/platform=iOS' -derivedDataPath /tmp/StockManagerDerived CODE_SIGNING_ALLOWED=NO build`
  - 成功
- `build-for-testing`
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme StockManager -project StockManager.xcodeproj -destination 'generic/platform=iOS' -derivedDataPath /tmp/StockManagerDerived CODE_SIGNING_ALLOWED=NO build-for-testing`
  - 成功
- `lint`
  - `swiftlint` はこの環境に未導入のため未実行
- `test`
  - CoreSimulatorService が利用できず、シミュレータ実行は不可
