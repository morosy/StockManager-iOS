//
//  StockManagerModels.swift
//  StockManager
//
//  Created by Codex on 2026/04/02.
//

import Foundation

enum ItemStatus: Int, Codable, CaseIterable, Identifiable {
    case inStock = 0
    case highlighted = 1
    case outOfStock = 2

    var id: Int {
        rawValue
    }

    func next() -> ItemStatus {
        switch self {
        case .inStock:
            return .highlighted
        case .highlighted:
            return .outOfStock
        case .outOfStock:
            return .inStock
        }
    }

    var isStockSide: Bool {
        self != .outOfStock
    }

    static func normalized(_ rawValue: Int) -> ItemStatus {
        ItemStatus(rawValue: rawValue) ?? .inStock
    }
}

enum SortMode: String, Codable, CaseIterable, Identifiable {
    case oldest = "OLDEST"
    case newest = "NEWEST"
    case name = "NAME"
    case nameDesc = "NAME_DESC"
    case stockFirst = "STOCK_FIRST"
    case outFirst = "OUT_FIRST"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .oldest:
            return "古い順"
        case .newest:
            return "新しい順"
        case .name:
            return "名前順"
        case .nameDesc:
            return "名前逆順"
        case .stockFirst:
            return "在庫優先"
        case .outFirst:
            return "欠品優先"
        }
    }

    var pairedMode: SortMode {
        switch self {
        case .oldest:
            return .newest
        case .newest:
            return .oldest
        case .name:
            return .nameDesc
        case .nameDesc:
            return .name
        case .stockFirst:
            return .outFirst
        case .outFirst:
            return .stockFirst
        }
    }
}

struct Board: Identifiable, Codable, Equatable, Hashable {
    var id: Int64
    var name: String
    var createdAt: Int64
    var exportId: String?
    var sortOrder: Int
}

struct StockItem: Identifiable, Codable, Equatable, Hashable {
    var id: Int64
    var boardId: Int64
    var name: String
    var status: Int
    var createdAt: Int64
    var updatedAt: Int64
    var exportId: String?

    var itemStatus: ItemStatus {
        get {
            ItemStatus.normalized(status)
        }
        set {
            status = newValue.rawValue
        }
    }
}

struct Settings: Codable, Equatable {
    var id: Int64 = 0
    var currentBoardId: Int64?
    var showStock: Bool = true
    var showOut: Bool = true
    var sortMode: String = SortMode.oldest.rawValue
    var query: String = ""
    var tutorialSeen: Bool = false

    var resolvedSortMode: SortMode {
        get {
            SortMode(rawValue: sortMode) ?? .oldest
        }
        set {
            sortMode = newValue.rawValue
        }
    }
}

struct AppDataSnapshot: Codable, Equatable {
    var boards: [Board]
    var items: [StockItem]
    var settings: Settings
}

struct ImportedBoardPayload: Equatable {
    var boardName: String
    var boardExportId: String?
    var boardCreatedAt: Int64
    var items: [ImportedItemPayload]
}

struct ImportedItemPayload: Equatable {
    var name: String
    var status: ItemStatus
    var createdAt: Int64
    var updatedAt: Int64
    var exportId: String?
}

struct TutorialStep: Identifiable, Equatable {
    var id: String
    var target: TutorialTargetID?
    var title: String
    var message: String
    var drawerOpen: Bool
    var boardEditMode: Bool
    var itemEditMode: Bool
}

enum TutorialTargetID: String, Hashable {
    case menuButton
    case boardEditButton
    case boardAddButton
    case itemAddButton
    case itemEditButton
    case boardList
    case currentBoardRow
    case currentItem
    case boardTitle
    case filterRow
    case sortButton
    case shoppingButton
}

enum ShoppingOverlayStage {
    case boardSelection
    case result
}

struct ShoppingOverlayState {
    var selectedBoardIDs: Set<Int64>
    var draftStatuses: [Int64: ItemStatus]
    var stage: ShoppingOverlayStage
}

enum StockManagerStoreError: LocalizedError, Equatable {
    case emptyBoardName
    case emptyItemName
    case itemAlreadyExists
    case missingCurrentBoard
    case invalidImportFormat
    case invalidImportData
    case unsupportedSchemaVersion

    var errorDescription: String? {
        switch self {
        case .emptyBoardName:
            return "ボード名を入力してください。"
        case .emptyItemName:
            return "アイテム名を入力してください。"
        case .itemAlreadyExists:
            return "同じ名前のアイテムが既に存在します。"
        case .missingCurrentBoard:
            return "選択中のボードが見つかりません。"
        case .invalidImportFormat:
            return "対応していない形式です。"
        case .invalidImportData:
            return "インポートするデータを読み取れませんでした。"
        case .unsupportedSchemaVersion:
            return "対応していない schemaVersion です。"
        }
    }
}

enum TransferFormat {
    case json
    case csv

    var fileExtension: String {
        switch self {
        case .json:
            return "json"
        case .csv:
            return "csv"
        }
    }
}

extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func limited(to maxLength: Int) -> String {
        String(prefix(maxLength))
    }
}

func currentEpochMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000.0)
}

func nextIdentifier(existingIDs: [Int64]) -> Int64 {
    (existingIDs.max() ?? 0) + 1
}

func makeSeedSnapshot(now: Int64 = currentEpochMillis()) -> AppDataSnapshot {
    let board = Board(
        id: 1,
        name: "ボード1",
        createdAt: now,
        exportId: nil,
        sortOrder: 0
    )
    let item = StockItem(
        id: 1,
        boardId: board.id,
        name: "サンプル",
        status: ItemStatus.inStock.rawValue,
        createdAt: now,
        updatedAt: now,
        exportId: nil
    )
    return AppDataSnapshot(
        boards: [board],
        items: [item],
        settings: Settings(currentBoardId: board.id, showStock: true, showOut: true, sortMode: SortMode.oldest.rawValue, query: "", tutorialSeen: false)
    )
}
