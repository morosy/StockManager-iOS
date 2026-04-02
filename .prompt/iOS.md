# StockManager iOS移行仕様書

## 1. この文書の目的

本書は、既存の Android 版 `StockManager` を Swift + Xcode で iOS アプリとして再実装するための移行仕様書である。
対象読者は、iOS 側の設計・実装を担当する AI エージェントまたは開発者である。

この文書では次を扱う。

- Android 版アプリの機能概要
- 画面構成と各 UI の役割
- データモデル、永続化、ビジネスロジック
- JSON / CSV インポート・エクスポート仕様
- チュートリアル、法務画面、データ初期化などの周辺機能
- Android 固有実装を iOS でどう置き換えるか
- iOS 実装時の推奨アーキテクチャと実装順

本書は「見た目を完全に同一にする」ことを目的にするものではなく、「同じ機能・同じ意味・同じ主要体験」を iOS ネイティブに移植することを目的にする。

---

## 2. アプリ概要

### 2.1 コンセプト

`StockManager` は、家庭内在庫を「ホワイトボード上のマグネット」のように管理するアプリである。  
ユーザーは複数のボードを作成し、各ボードに複数のアイテムを配置する。各アイテムは 3 状態を循環する。

- `IN_STOCK` = 白系カード
- `HIGHLIGHTED` = 黄系カード
- `OUT_OF_STOCK` = 赤系カード

この 3 状態は実装上は次の enum 相当で扱う。

- `0`: `IN_STOCK`
- `1`: `HIGHLIGHTED`
- `2`: `OUT_OF_STOCK`

ユーザー向けの意味づけは固定ではなく、例えば以下のように使える。

- 在庫あり / 要確認 / 在庫なし
- 予備あり / 残少 / 切れ
- 白 / 黄 / 赤

### 2.2 アプリの基本構造

アプリ全体は実質 1 画面構成で、以下の要素を重ねて使う。

- ホーム画面
- 左サイドのボードドロワー
- アイテム追加/編集モーダル
- ボード追加/削除/名称変更 UI
- 買い物リストオーバーレイ
- チュートリアルオーバーレイ
- About / 利用規約 / OSS / プライバシーポリシー画面
- 全データ削除確認ダイアログ

Android 版には画面遷移らしいナビゲーションスタックはほぼなく、単一の root 画面上でオーバーレイを開閉している。  
iOS 版も `NavigationStack` を主軸に複雑な遷移を作る必要はなく、単一 root + sheets / overlays 構成で十分である。

---

## 3. Android 版の実装要約

### 3.1 使用技術

- Kotlin
- Jetpack Compose
- Material 3
- Room
- Coroutines / Flow
- Android SplashScreen API
- Activity Result API

### 3.2 Android の構造

- `MainActivity` で `StockManagerScreen()` を表示
- `StockManagerViewModel` が画面全体の状態を集約
- `StockRepository` が DB と import/export を担当
- `Room` DB に `boards`, `stock_items`, `settings` を保存
- UI は Compose の単一 screen に多数の overlay composable を重ねる構成

### 3.3 iOS での推奨対応

推奨構成は以下。

- UI: `SwiftUI`
- 画面状態: `@MainActor` な Store / ViewModel
- 観測: iOS 17+ なら `Observation`、iOS 16 対応が必要なら `ObservableObject`
- 永続化: `Core Data` 推奨
- 非同期: `async/await`
- ファイル入出力: `fileImporter`, `fileExporter`, `UIDocumentPickerViewController`
- 外部 URL: `openURL`
- チュートリアルのターゲット計測: `GeometryReader` + `PreferenceKey`

補足:

- Room の移行性と SQLite ベース永続化に近い感覚を保つため、`SwiftData` より `Core Data` の方が安全
- ただし iOS 専用の簡潔さを優先するなら `SwiftData` でも実装可能
- ただし DB マイグレーションを明示管理したい場合は `Core Data` が望ましい

---

## 4. 機能一覧

### 4.1 必須機能

- 複数ボード管理
- ボードの追加
- ボードの削除
- ボード名変更
- ボード並べ替え
- 現在ボードの切り替え
- アイテム追加
- アイテム名変更
- アイテム削除
- アイテム状態切り替え
- 在庫側 / 欠品側フィルタ
- 並び替え
- 検索
- 買い物リスト表示
- JSON エクスポート
- CSV エクスポート
- JSON / CSV インポート
- チュートリアル
- About / 利用規約 / OSS / プライバシーポリシー表示
- 全データ削除

### 4.2 外部リンク機能

ドロワーから次の外部ページを開く。

- ボード作成補助ツール  
  `https://morosy.github.io/sm_template_maker.html`
- 問い合わせページ  
  `https://morosy.github.io/contact.html`

iOS では `openURL` で Safari に遷移すればよい。

---

## 5. ドメインモデル

## 5.1 Board

ボードは在庫カテゴリのまとまりである。

推奨 iOS モデル:

```swift
struct Board: Identifiable, Equatable {
    var id: Int64
    var name: String
    var createdAt: Int64
    var exportId: String?
    var sortOrder: Int
}
```

### 仕様

- `id`: DB 主キー
- `name`: ボード名
- `createdAt`: UNIX epoch millis
- `exportId`: import/export 用識別子。通常作成時は `nil`
- `sortOrder`: ボード並び順

### 制約

- 最大文字数: `10`
- 空文字不可
- 重複名禁止はしていない

## 5.2 StockItem

```swift
struct StockItem: Identifiable, Equatable {
    var id: Int64
    var boardId: Int64
    var name: String
    var status: Int
    var createdAt: Int64
    var updatedAt: Int64
    var exportId: String?
}
```

### 制約

- 最大文字数: `24`
- 空文字不可
- 追加時のみ「同一ボード内で完全一致の重複名」を禁止
- 名前変更時は重複チェックをしていない
- import 時も新規ボードへ投入するため重複抑止はしていない

### 状態

- `0`: 在庫側
- `1`: 強調状態
- `2`: 欠品側

状態遷移は常に循環。

```text
0 -> 1 -> 2 -> 0
```

### 補足

- `HIGHLIGHTED` はロジック上「在庫側」とみなす
- つまり `isStockVisible(status)` は `status != OUT_OF_STOCK`

## 5.3 Settings

```swift
struct Settings {
    var id: Int64 // 常に 0
    var currentBoardId: Int64?
    var showStock: Bool
    var showOut: Bool
    var sortMode: String
    var query: String
    var tutorialSeen: Bool
}
```

### 役割

- 現在選択中ボード
- フィルタ状態
- ソート状態
- 検索文字列
- チュートリアル既読状態

### 重要ルール

- `showStock` と `showOut` は両方 `false` にしてはいけない
- Android 版は toggle 時に必ずどちらか片方は `true` になるよう補正している

---

## 6. 永続化仕様

### 6.1 テーブル構成

Android 版 Room DB は以下。

- `boards`
- `stock_items`
- `settings`

`stock_items.board_id -> boards.id` はカスケード削除。

### 6.2 DB バージョン履歴

Android 版 DB version は `7`。履歴上、以下が追加された。

- `boards.sort_order`
- `boards.created_at`
- `boards.export_id`
- `stock_items.updated_at`
- `stock_items.export_id`
- `stock_items.status`
- `settings.tutorial_seen`

iOS 新規実装では既存 Android DB を直接読む必要は通常ないため、初回版は最新スキーマのみ持てばよい。  
ただし将来 iOS 側もスキーマ変更が起こる前提で、マイグレーション容易性を持つ実装が望ましい。

### 6.3 バックアップ

Android 版はアプリデータのクラウドバックアップを特に無効化していない。  
iOS 版も通常のアプリデータ領域に DB を置けば iCloud Backup 対象になり得る。  
仕様として問題ない。

---

## 7. 初期化・起動時仕様

### 7.1 初回起動シード

Android 版は、以下条件のとき初期データを投入する。

- `boards` が 0 件
- かつ `settings` が存在しない

投入内容:

- 初期ボード 1 件
- 初期アイテム 1 件
- `currentBoardId` をそのボードに設定
- `tutorialSeen = false`

### 7.2 初回チュートリアル起動

`ensureSeeded()` が `true` を返した場合、UI 側で自動的にチュートリアル開始フラグが立つ。

重要:

- Android 版では「チュートリアルを完走した時」ではなく「チュートリアルを開始した時」に `tutorialSeen = true` にしている
- つまり自動チュートリアルを途中で閉じても、次回自動再生はされない

iOS 版もこの仕様を基本踏襲する。

### 7.3 現在ボード復元ルール

起動時またはデータ変化時、`currentBoardId` は次ルールで安全化される。

1. ボードが 0 件なら `0`
2. `settings.currentBoardId` が存在し、かつその ID のボードが存在すればそれを採用
3. それ以外は先頭ボードを採用

したがって、現在ボードが削除されても UI は先頭ボードへ自然にフォールバックする。

---

## 8. ホーム画面仕様

## 8.1 レイアウト全体

ホーム画面は大きく次で構成される。

1. 上部トップバー
2. フィルタ行
3. 検索欄
4. 2 カラムのアイテムグリッド
5. 下部アクション群

### 8.2 トップバー

表示内容:

- 中央: 現在ボード名
- 左: メニューアイコン
- 右: 検索アイコン

挙動:

- 中央タイトルタップでボード名変更オーバーレイ
- 左アイコンでボードドロワー開く
- 右アイコンで検索欄の表示/非表示切り替え

### 8.3 フィルタ行

2 セグメント。

- 在庫側表示
- 欠品側表示

ルール:

- 両方 ON 可能
- 片方だけ ON 可能
- 両方 OFF は禁止

### 8.4 ソートボタン

Split Button 形式。

- 左ボタン: 現在のソート名を表示し、全候補メニューを開く
- 右ボタン: 対になるソートへ即切り替え

ペアは以下。

- `OLDEST` <-> `NEWEST`
- `NAME` <-> `NAME_DESC`
- `STOCK_FIRST` <-> `OUT_FIRST`

### 8.5 検索欄

表示中のみテキストフィールドを出す。

検索仕様:

- 部分一致
- 大文字小文字無視
- 対象は `item.name`

注意:

- 検索文字列自体は `settings.query` に永続化される
- Android 版では `searchOpen` は永続化されない
- そのため、アプリ再起動後に検索欄は閉じていても `query` のフィルタだけが有効な状態になり得る

iOS 版は parity 重視ならこの挙動を踏襲する。  
ただし UX 改善として「query が空でなければ検索 UI を開いた状態で復元」してもよい。  
もし完全互換を優先するなら Android の仕様をそのまま採用する。

### 8.6 アイテムグリッド

- 2 カラム固定
- 各カードはマグネット風
- 1 カード高さはコンパクト
- 名称は中央寄せ、最大 2 行

表示対象は、次条件をすべて満たすアイテム。

- 現在ボードに属する
- フィルタ条件を満たす
- 検索条件を満たす

空状態:

- ボードが 0 件: ボード追加を促すメッセージ
- 現在ボードのアイテムが 0 件: アイテム追加を促すメッセージ

### 8.7 下部アクション

通常時:

- 左下 FAB: アイテム編集モードへ
- 中央横長 FAB: 買い物リスト表示
- 右下 FAB: アイテム追加

アイテム編集モード時:

- 左下/右下 FAB は消える
- 中央に「編集完了」ボタンを表示
- 画面上部に編集モード説明テキスト

### 8.8 セーフエリア

Android 版は edge-to-edge + navigation bar inset を考慮して下部余白を計算している。  
iOS 版では `safeAreaInset(edge: .bottom)` または `safeAreaPadding(.bottom)` で確実に対応すること。

---

## 9. アイテムカード仕様

## 9.1 見た目

状態ごとにカード色が変わる。

### Light mode の意図

- `IN_STOCK`: 白ベース
- `HIGHLIGHTED`: 黄ベース
- `OUT_OF_STOCK`: 赤ベース

### Dark mode の意図

- `IN_STOCK`: 暗い面色
- `HIGHLIGHTED`: 暗い黄
- `OUT_OF_STOCK`: 暗い赤

### Android の主な色

- Primary: `#6750A4`
- Light background: `#F5F5F5`
- Dark background: `#141218`
- Warning light: `#FFF9C4`
- Error light: `#F9DEDC`

iOS 側も色の意味は維持すること。完全に同一 hex でなくてもよいが、状態の認識は揃える。

## 9.2 タップ挙動

通常モード時:

- タップで状態を 1 つ進める
- 変更後の状態を DB に保存

編集モード時:

- カードタップで削除ではなく「名前編集モーダル」を開く
- カード右端の小さな `x` ボタンが削除アクション

## 9.3 アニメーション

Android 版には以下の演出がある。

- 状態切り替え時の横フリップ
- アイテム編集モード時の左右 wobble
- 削除時の fade + shrink

iOS 版で完全一致までは不要だが、少なくとも以下の意味を残す。

- 状態変更が視覚的に分かる
- 編集モード中だと分かる
- 削除が即断ではなく視覚的に消える

---

## 10. ボードドロワー仕様

## 10.1 基本

左からスライドインするサイドパネル。

内容:

- ヘッダ
- 右上にメニューボタン
- ボード一覧
- 下部の編集/追加/完了ボタン群

## 10.2 通常モード

一覧にはボードを表示する。

- 現在ボードは選択色
- タップでそのボードへ切り替え
- 下部ボタンでボード編集モードへ入る

## 10.3 ボード編集モード

一覧の各行に以下を表示。

- 左: ドラッグハンドル風表示
- 中央: ボード名
- 右: 削除ボタン

挙動:

- 長押しドラッグで並び替え
- 並び替え終了時に `sortOrder` を保存
- 下部に「ボード追加」ボタン
- 下部に「編集完了」ボタン

## 10.4 並び順仕様

Android 版は `sort_order ASC, id ASC` で表示する。

注意:

- 新規ボードの `sortOrder` は `countBoards()` を使っているため、削除後に sortOrder の飛びや重複が理論上起こり得る
- UI は `id ASC` を副キーに持つため破綻しにくい

iOS 版ではより健全に、並び替えや削除後に `sortOrder` を連番で再正規化してよい。  
ユーザー体験が同じなら問題ない。

## 10.5 ドロワーメニュー

メニュー項目は以下。

- JSON エクスポート
- CSV エクスポート
- インポート
- 外部ツールからボード作成
- 使い方
- 問い合わせ
- About
- 利用規約
- OSS ライセンス
- プライバシーポリシー
- データ削除

---

## 11. ボード関連モーダル仕様

## 11.1 ボード追加モーダル

- テキスト入力
- 文字数上限 10
- 空文字不可
- 保存後は新規ボードを current board にする

## 11.2 ボード名変更

- 現在ボード名を初期表示
- 文字数上限 10
- 空文字なら保存しない
- 重複チェックなし

## 11.3 ボード削除確認

- 対象ボード名を表示
- confirm でボード削除
- アイテムは cascade delete

---

## 12. アイテム関連モーダル仕様

## 12.1 アイテム追加

- 文字数上限 24
- 空文字不可
- 同一ボード内で完全一致の重複名は追加不可
- 成功時のみモーダルを閉じる

## 12.2 アイテム名変更

- 初期値に既存名を表示
- 文字数上限 24
- 空文字なら保存しない
- 重複チェックなし

---

## 13. フィルタ・検索・ソート仕様

## 13.1 フィルタ

各アイテムは次で判定される。

- `IN_STOCK` と `HIGHLIGHTED` は「在庫側」
- `OUT_OF_STOCK` は「欠品側」

表示条件:

- 在庫側アイテムかつ `showStock == true`
- または欠品側アイテムかつ `showOut == true`

## 13.2 ソート

定義は以下。

- `OLDEST`: `createdAt` 昇順
- `NEWEST`: `createdAt` 降順
- `NAME`: `name` 昇順
- `NAME_DESC`: `name` 降順
- `STOCK_FIRST`: 白 -> 黄 -> 赤、その後 `name`
- `OUT_FIRST`: 赤 -> 黄 -> 白、その後 `name`

## 13.3 買い物リスト内ソート

買い物リストは通常画面と少し違う。

まず大原則:

- 買い物リストに載るのは `HIGHLIGHTED` と `OUT_OF_STOCK` のみ
- `IN_STOCK` は載らない

優先順位:

1. `HIGHLIGHTED`
2. `OUT_OF_STOCK`
3. その中で選択中ソートに従う

つまり `STOCK_FIRST` / `OUT_FIRST` を選んでいても、買い物リスト側では黄優先・赤次点が常に優先される。

---

## 14. 買い物リスト仕様

## 14.1 オーバーレイの 2 ステップ構成

`ShoppingListOverlay` は 2 段階。

1. `BoardSelection`
2. `Result`

## 14.2 ボード選択ステップ

- 全ボード一覧を表示
- オーバーレイを開いた瞬間、全ボードが選択済み
- タップで選択/解除
- 1 件以上選択で結果表示ボタン活性

## 14.3 結果ステップ

- 選択ボードごとにセクション表示
- 各セクション内は 2 カラム表示
- 表示するのは `HIGHLIGHTED` / `OUT_OF_STOCK` のみ

## 14.4 結果画面でのタップ

結果画面でアイテムをタップすると、その場で状態が循環する。

```text
HIGHLIGHTED -> OUT_OF_STOCK -> IN_STOCK
OUT_OF_STOCK -> IN_STOCK -> HIGHLIGHTED
```

ただし DB には即保存しない。  
オーバーレイ内のドラフト状態として保持し、閉じる時に差分のみ保存する。

## 14.5 保存タイミング

- 「閉じる」時に変更差分があればまとめて保存
- 未保存差分がある状態で閉じようとすると破棄確認ダイアログ

### 保存内容

- 変更があったアイテムのみ更新
- `status` を正規化
- `updatedAt` を保存時刻に更新

---

## 15. チュートリアル仕様

## 15.1 概要

ホーム画面上の特定 UI をスポットライトで強調しながら、段階的に操作説明する。

実装上は各 UI の矩形を登録し、現在ステップ対象の rect を円形にくり抜いている。

## 15.2 対象ターゲット

- メニュー
- ボード編集ボタン
- ボード追加ボタン
- アイテム追加 FAB
- アイテム編集 FAB
- ボード一覧
- 現在ボード行
- 現在アイテム
- ボードタイトル
- フィルタ行
- ソートボタン
- 買い物リスト FAB

## 15.3 ステップ一覧

概念的には以下。

1. ドロワーを開く
2. ボード編集を開く
3. アイテムの意味を説明
4. 必要ならボード追加
5. アイテム追加
6. アイテム編集
7. ボード一覧の説明
8. ボード切り替えの説明
9. ボード名変更の説明
10. フィルタ説明
11. ソート説明
12. 買い物リスト説明
13. リマインド

## 15.4 進行ルール

- ステップによっては対象 UI が画面上に出るまで進めない
- `ADD_BOARD` は `ui.boards.isEmpty()` の時のみフローに入る
- ただし通常の初回起動ではシード済みのため、実際には `ADD_BOARD` をスキップすることが多い
- スキップ可能
- 戻る可能

## 15.5 iOS 実装方針

SwiftUI では以下を推奨。

- 対象 View の frame を `PreferenceKey` で上位へ集約
- 全画面 `ZStack` で半透明レイヤーを載せる
- `Canvas` か `blendMode(.destinationOut)` を使ってスポットライト表現
- 対象タップで次へ進める

完全に同じ見た目に拘る必要はないが、以下は保持する。

- 対象 UI の強調
- 現在ステップ / 全ステップ数
- 戻る / 次へ / スキップ

---

## 16. インポート / エクスポート仕様

## 16.1 対応形式

- JSON
- CSV

## 16.2 形式判定

Android 版は次順序で判定している。

1. MIME type / 拡張子から推定
2. 未指定ならコンテンツ先頭で判定
3. 先頭が `{` なら JSON、それ以外は CSV

iOS 版でも同等にする。

## 16.3 JSON エクスポート仕様

概形:

```json
{
  "schemaVersion": 1,
  "format": "stockmanager-board-export",
  "exportedAt": "2026-03-03T00:00:00+09:00",
  "board": {
    "exportId": "b-uuid",
    "name": "Board Name",
    "createdAt": 1700000000000,
    "items": [
      {
        "exportId": "i-uuid",
        "name": "Item A",
        "status": 0,
        "inStock": true,
        "createdAt": 1700000001000,
        "updatedAt": 1700000001000
      }
    ]
  }
}
```

### 重要点

- `schemaVersion` は必須、現在 `1`
- `format` は `"stockmanager-board-export"`
- `exportedAt` は ISO8601 with offset
- `board.name` 必須
- `items` は省略可または空配列可
- `status` と `inStock` を両方出す
- `inStock` は後方互換用

## 16.4 JSON インポート仕様

受理条件:

- `schemaVersion == 1`
- `board` オブジェクト存在
- `board.name` 非空

各 item:

- `name` が空なら無視
- `status` があれば優先
- `status` がなければ `inStock` から旧形式互換変換
- `createdAt`, `updatedAt`, `exportId` は任意

### `status` の受理値

数値だけでなく文字列も許容している。

- `0`, `white`, `stock`, `in_stock`, `instock` -> `IN_STOCK`
- `1`, `yellow`, `highlight`, `highlighted`, `warning`, `pending` -> `HIGHLIGHTED`
- `2`, `red`, `out`, `out_of_stock`, `outofstock` -> `OUT_OF_STOCK`

それ以外は `nil` 扱いとなり、最終的に `inStock` フォールバックまたは既定値へ進む。

## 16.5 JSON テンプレート互換

Android 版の import 実装は `format` を厳密には見ていない。  
そのため、以下のような最小テンプレートも取り込める。

```json
{
  "schemaVersion": 1,
  "format": "stockmanager-board-template",
  "board": {
    "name": "Example Template Board",
    "items": [
      { "name": "Item A" },
      { "name": "Item B" }
    ]
  }
}
```

この場合:

- `status` 未指定 -> `IN_STOCK`
- `createdAt`, `updatedAt` 未指定 -> import 時刻
- `exportId` 未指定 -> import 時に UUID 生成

iOS 版もこの緩い互換性を維持すること。

## 16.6 CSV エクスポート仕様

概形:

```csv
meta_key,meta_value
schemaVersion,1
format,stockmanager-board-export-csv
exportedAt,2026-03-03T00:00:00+09:00
boardExportId,b-uuid
boardName,Board Name
boardCreatedAt,1700000000000

type,exportId,name,status,inStock,createdAt,updatedAt
item,i-uuid,Item A,1,true,1700000001000,1700000001000
```

## 16.7 CSV インポート仕様

受理条件:

- `schemaVersion == 1`
- `boardName` 非空

旧形式互換:

- `status` 列がなくてもよい
- `inStock` だけの legacy CSV を読める

CSV パーサは簡易実装だが、以下に対応。

- クオート
- `""` エスケープ
- カンマ含みセル

## 16.8 import 時の新規作成仕様

インポートは「既存ボードへマージ」ではなく、常に「新規ボードを 1 つ作る」。

仕様:

- 新規ボードを追加
- そのボードへ最大 500 件の item を投入
- 完了後、そのボードを current board にする

### 重要

- import 件数上限は 500
- 500 件超は切り捨て
- 既存ボードとの重複チェックなし

## 16.9 import/export ID の扱い

Android 版には少し癖がある。

- 通常追加された board/item は `exportId == nil`
- export 時、`exportId` がなければ一時的に UUID を生成してファイルへ出す
- ただしその UUID を DB に保存し直してはいない

つまり、手作成データは export のたびに `exportId` が変わり得る。  
import 済みデータだけは `exportId` が DB に残るため比較的安定する。

iOS 版の選択肢:

1. Android 完全準拠  
   export 時のみ仮 ID を生成し、DB へは保存しない
2. 改善案  
   board/item 作成時点で `exportId` を払い出して永続化する

「現行 Android と同じ機能」を優先するなら 1 でよい。  
将来の同期や差分比較を見据えるなら 2 を推奨する。  
ただし 2 を採ると Android 版と厳密には内部挙動が異なるので、仕様確定が必要である。

## 16.10 エクスポートファイル名

形式:

```text
{safeBoardName}_{yyyyMMdd-HHmmss-SSS}.json
{safeBoardName}_{yyyyMMdd-HHmmss-SSS}.csv
```

ファイル名に使えない文字は `_` に置換。

---

## 17. 全データ削除仕様

## 17.1 Android 版の仕様

- 2 段階確認
- 最終段階で `delete` と完全一致入力が必要
- 実行すると DB 全消去
- 成功後 `finishAffinity()` でアプリ終了

## 17.2 iOS 版の推奨置き換え

iOS ではアプリをプログラム終了させるべきではない。  
したがって次のように置き換える。

- 永続ストア全消去
- メモリ上状態も初期化
- 初回起動相当の初期ボード/初期アイテムを再シード
- current board を初期ボードへ
- tutorial を再表示

これが最も自然な iOS 版 parity である。  
もし Android と同じ「次回起動時に再シード」に寄せたいなら、削除後にプレースホルダ画面を出して root state を再生成してもよい。

---

## 18. About / 法務 / 補助画面

## 18.1 About

表示内容:

- アプリ名 `StockManager`
- バージョン
- Copyright 表示

Android 版 current version:

- `1.3.0`

## 18.2 法務文書

表示する文書:

- 利用規約
- OSS ライセンス
- プライバシーポリシー

Android 版では raw text をそのままスクロール表示している。  
iOS 版でもまずは同じでよい。

ソース:

- `app/src/main/res/raw/terms.txt`
- `app/src/main/res/raw/oss_licenses.txt`
- `app/src/main/res/raw/privacy_policy.txt`

## 18.3 使い方

Android 版には `HOW_TO_USE` という enum はあるが、実際の「使い方」は独立画面ではなくチュートリアル起動で代用されている。  
iOS 版も同じでよい。

---

## 19. Android 特有実装と iOS 置換方針

| Android | 役割 | iOS 推奨 |
|---|---|---|
| `ComponentActivity` + `setContent` | app root | `@main App` + root `WindowGroup` |
| Jetpack Compose | 宣言的 UI | SwiftUI |
| `AndroidViewModel` | 画面状態とユースケース | `@MainActor` Store / ViewModel |
| `Flow` + `combine` | DB と設定の反映 | Observation / Combine / AsyncSequence |
| Room | SQLite 永続化 | Core Data 推奨 |
| `Dialog`, custom overlay | モーダル/UI 重ね表示 | `.sheet`, `.alert`, custom `ZStack` overlay |
| `ActivityResultContracts.OpenDocument/CreateDocument` | ファイル import/export | `fileImporter`, `fileExporter`, `UIDocumentPicker` |
| `Toast` | 短い通知 | `Alert`, banner, HUD, toast ライク自前実装 |
| `Intent.ACTION_VIEW` | 外部 URL 起動 | `openURL` |
| `SplashScreen` API | 起動画面 | Launch Screen |
| `enableEdgeToEdge` | システムバー共存 | safe area 制御 |
| `onGloballyPositioned` | チュートリアルターゲット矩形取得 | `GeometryReader` + `PreferenceKey` |
| drag gesture reorder | ボード並べ替え | `.onMove` または custom drag/drop |

---

## 20. iOS 側の推奨アーキテクチャ

## 20.1 推奨レイヤ

- `App`
- `RootStore` または `StockManagerStore`
- `Persistence`
- `ImportExportService`
- `TutorialOverlayCoordinator`
- `Views`

## 20.2 推奨責務分離

### Store

保持する状態:

- boards
- currentBoardId
- filter flags
- sort mode
- query
- tutorial flags
- 各種 overlay 開閉状態
- shopping list draft state

### Persistence

責務:

- boards/items/settings の CRUD
- 初回シード
- 並び順保存
- 一括 status 更新
- 全データ削除

### ImportExportService

責務:

- JSON / CSV encode
- JSON / CSV decode
- schemaVersion 検証
- legacy format 吸収

### Views

責務:

- 表示と input
- frame 計測
- animation

---

## 21. iOS UI 実装ガイド

## 21.1 ナビゲーション

- ルートは 1 画面でよい
- 画面 push は基本不要
- サイドドロワーは custom overlay で実装

## 21.2 オーバーレイ実装

推奨:

- 軽い確認系: `.alert`, `.confirmationDialog`
- フォーム入力系: custom modal sheet か custom centered overlay
- チュートリアル: custom full-screen overlay

Android 版は多くが中央ダイアログ型なので、iOS でも sheet より custom popup の方が体験が近い。

## 21.3 リスト / グリッド

- iPhone portrait は 2 カラムを守る
- iPad は 2 カラム固定でもよいし、adaptive にしてもよい
- ただしカードの意味、色、操作は変えない

## 21.4 アニメーション優先度

優先して残すべきもの:

- アイテム状態変化の視認性
- 編集モードの視認性
- ドロワー開閉
- ボード並べ替えの持ち上がり感
- チュートリアルのスポットライト

## 21.5 文字列管理

Android 版は多くの文言を Composable 内に直接書いている。  
iOS 版では最初から `Localizable.strings` へ寄せることを推奨する。

理由:

- AI 実装時に文言散逸を防げる
- 将来の多言語化に備えられる
- iOS 側の保守が楽になる

---

## 22. データ整合性ルール

以下は iOS 版でも守ること。

- ボード削除時、配下アイテムを同時削除
- フィルタは両方 OFF 不可
- current board が不正なら先頭へフォールバック
- import は常に新規ボード作成
- import item 上限は 500
- item status は常に 0/1/2 に正規化
- shopping list 保存時は差分だけ更新
- item 追加時の重複チェックは「同一ボード内」「完全一致」

---

## 23. parity のための受け入れ条件

以下が満たされれば iOS 版は主要機能 parity 達成とみなせる。

- 初回起動で初期ボード 1 件と初期アイテム 1 件が見える
- アイテムタップで 白 -> 黄 -> 赤 -> 白 と循環する
- ボードを複数作成し、切り替えられる
- ボードを並び替えられる
- ボードを削除すると配下アイテムも消える
- アイテム追加時、同一ボード内の完全一致重複は拒否される
- 検索、フィルタ、ソートが組み合わさって表示に反映される
- 買い物リストに黄/赤のみ出る
- 買い物リストで変えた状態が閉じる時に保存される
- JSON/CSV を export できる
- JSON/CSV を import して新規ボードが増える
- minimal JSON template も import できる
- チュートリアルが初回シード時に自動開始される
- 利用規約 / OSS / プライバシーポリシーが読める
- 全データ削除後に初回状態へ戻せる

---

## 24. 実装順序の推奨

1. Core Data モデル定義
2. `Board`, `StockItem`, `Settings` の repository 実装
3. 初回シード、current board 解決、filter/sort/query の store 実装
4. ホーム画面の 2 カラムグリッド
5. アイテム追加/編集/削除
6. ボードドロワー、ボード追加/削除/並び替え
7. 買い物リスト
8. JSON/CSV import/export
9. チュートリアル
10. About / 法務 / 外部リンク
11. 全データ削除
12. アニメーション調整

---

## 25. iOS 実装時の注意点

### 25.1 Android 版の内部仕様をそのまま持ち込まなくてよいもの

- `finishAffinity()` による終了
- sortOrder の飛び/重複の許容
- 検索欄が閉じていても query が残る UX
- exportId を export 時のみ仮生成する曖昧さ

これらは「機能 parity に影響しない範囲」で iOS 向けに改善してよい。  
ただし改善するなら、Android 完全準拠との差分として明示すること。

### 25.2 Android 版と合わせるべきもの

- 3 状態モデル
- ボード・アイテムの文字数制限
- add 時の重複禁止ルール
- shopping list の抽出条件
- import/export schemaVersion
- tutorialSeen を開始時に立てること

---

## 26. 推奨する iOS 側の型定義

```swift
enum ItemStatus: Int, Codable, CaseIterable {
    case inStock = 0
    case highlighted = 1
    case outOfStock = 2

    func next() -> ItemStatus {
        switch self {
        case .inStock: return .highlighted
        case .highlighted: return .outOfStock
        case .outOfStock: return .inStock
        }
    }

    var isStockSide: Bool {
        self != .outOfStock
    }
}

enum SortMode: String, Codable, CaseIterable {
    case oldest = "OLDEST"
    case newest = "NEWEST"
    case name = "NAME"
    case nameDesc = "NAME_DESC"
    case stockFirst = "STOCK_FIRST"
    case outFirst = "OUT_FIRST"
}
```

---

## 27. 最終推奨

iOS 版は、見た目だけを Android に寄せるよりも、以下を優先するとよい。

- 3 状態マグネット在庫管理という中核体験
- ボード切替と複数管理
- 買い物リスト生成
- JSON/CSV 互換
- 初回チュートリアル

推奨技術選定は以下。

- UI: SwiftUI
- 状態管理: Observation ベース Store
- 永続化: Core Data
- import/export: Codable + 独自 CSV codec
- overlay: custom SwiftUI overlay

この方針で実装すれば、Android 版の意味論を崩さずに iOS らしいアプリへ移植できる。
