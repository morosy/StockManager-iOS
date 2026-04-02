//
//  StockManagerStore.swift
//  StockManager
//
//  Created by Codex on 2026/04/02.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class StockManagerStore: ObservableObject {
    @Published private(set) var boards: [Board] = []
    @Published private(set) var items: [StockItem] = []
    @Published private(set) var settings = Settings()
    @Published var drawerOpen = false
    @Published var boardEditMode = false
    @Published var itemEditMode = false
    @Published var searchOpen = false
    @Published var tutorialSteps: [TutorialStep] = []
    @Published var tutorialStepIndex = 0
    @Published var shoppingState: ShoppingOverlayState?
    @Published var bannerMessage: String?

    private let persistence: StockManagerPersistence
    let importExportService: StockManagerImportExportService

    init(preview: Bool = false) {
        self.persistence = StockManagerPersistence()
        self.importExportService = StockManagerImportExportService()
        if preview {
            applySnapshot(makeSeedSnapshot(), openSearchForQuery: true)
        } else {
            loadInitialState()
        }
    }

    init(
        persistence: StockManagerPersistence,
        importExportService: StockManagerImportExportService,
        preview: Bool = false
    ) {
        self.persistence = persistence
        self.importExportService = importExportService
        if preview {
            applySnapshot(makeSeedSnapshot(), openSearchForQuery: true)
        } else {
            loadInitialState()
        }
    }

    var sortedBoards: [Board] {
        boards.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.id < $1.id
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    var currentBoard: Board? {
        let boardID = resolvedCurrentBoardID()
        return sortedBoards.first(where: { $0.id == boardID })
    }

    var currentBoardItems: [StockItem] {
        visibleItems(for: currentBoard?.id)
    }

    var currentSortMode: SortMode {
        settings.resolvedSortMode
    }

    var tutorialIsPresented: Bool {
        tutorialSteps.isEmpty == false && tutorialStepIndex < tutorialSteps.count
    }

    var currentTutorialStep: TutorialStep? {
        guard tutorialIsPresented else {
            return nil
        }
        return tutorialSteps[tutorialStepIndex]
    }

    func visibleItems(for boardID: Int64?) -> [StockItem] {
        guard let boardID else {
            return []
        }
        return sortItems(
            items.filter { item in
                item.boardId == boardID &&
                shouldShow(item: item) &&
                matchesQuery(item: item)
            },
            mode: currentSortMode
        )
    }

    func itemForCurrentBoard(at index: Int) -> StockItem? {
        let currentItems = currentBoardItems
        guard currentItems.indices.contains(index) else {
            return nil
        }
        return currentItems[index]
    }

    func setCurrentBoard(_ boardID: Int64) {
        settings.currentBoardId = boardID
        persistAndRefresh()
        drawerOpen = false
        boardEditMode = false
    }

    func toggleStatus(for itemID: Int64) {
        mutateItem(id: itemID) { item in
            item.itemStatus = item.itemStatus.next()
            item.updatedAt = currentEpochMillis()
        }
    }

    func addBoard(named rawName: String) throws {
        let name = rawName.trimmed().limited(to: 10)
        guard name.isEmpty == false else {
            throw StockManagerStoreError.emptyBoardName
        }
        let newBoard = Board(
            id: nextIdentifier(existingIDs: boards.map(\.id)),
            name: name,
            createdAt: currentEpochMillis(),
            exportId: nil,
            sortOrder: sortedBoards.count
        )
        boards.append(newBoard)
        settings.currentBoardId = newBoard.id
        boardEditMode = false
        drawerOpen = false
        persistAndRefresh()
    }

    func renameCurrentBoard(to rawName: String) throws {
        guard let board = currentBoard else {
            throw StockManagerStoreError.missingCurrentBoard
        }
        try renameBoard(id: board.id, to: rawName)
    }

    func renameBoard(id: Int64, to rawName: String) throws {
        let name = rawName.trimmed().limited(to: 10)
        guard name.isEmpty == false else {
            throw StockManagerStoreError.emptyBoardName
        }
        guard let index = boards.firstIndex(where: { $0.id == id }) else {
            throw StockManagerStoreError.missingCurrentBoard
        }
        boards[index].name = name
        persistAndRefresh()
    }

    func deleteBoard(id: Int64) {
        boards.removeAll(where: { $0.id == id })
        items.removeAll(where: { $0.boardId == id })
        persistAndRefresh()
    }

    func moveBoards(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = sortedBoards
        reordered.move(fromOffsets: source, toOffset: destination)
        boards = reordered.enumerated().map { index, board in
            var updatedBoard = board
            updatedBoard.sortOrder = index
            return updatedBoard
        }
        persistAndRefresh()
    }

    func addItem(named rawName: String) throws {
        guard let board = currentBoard else {
            throw StockManagerStoreError.missingCurrentBoard
        }
        let name = rawName.trimmed().limited(to: 24)
        guard name.isEmpty == false else {
            throw StockManagerStoreError.emptyItemName
        }
        let exists = items.contains(where: { $0.boardId == board.id && $0.name == name })
        guard exists == false else {
            throw StockManagerStoreError.itemAlreadyExists
        }
        let now = currentEpochMillis()
        let newItem = StockItem(
            id: nextIdentifier(existingIDs: items.map(\.id)),
            boardId: board.id,
            name: name,
            status: ItemStatus.inStock.rawValue,
            createdAt: now,
            updatedAt: now,
            exportId: nil
        )
        items.append(newItem)
        persistAndRefresh()
    }

    func renameItem(id: Int64, to rawName: String) throws {
        let name = rawName.trimmed().limited(to: 24)
        guard name.isEmpty == false else {
            throw StockManagerStoreError.emptyItemName
        }
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw StockManagerStoreError.invalidImportData
        }
        items[index].name = name
        items[index].updatedAt = currentEpochMillis()
        persistAndRefresh()
    }

    func deleteItem(id: Int64) {
        items.removeAll(where: { $0.id == id })
        persistAndRefresh()
    }

    func setShowStock(_ value: Bool) {
        settings.showStock = value
        if settings.showStock == false && settings.showOut == false {
            settings.showOut = true
        }
        persistAndRefresh()
    }

    func setShowOut(_ value: Bool) {
        settings.showOut = value
        if settings.showStock == false && settings.showOut == false {
            settings.showStock = true
        }
        persistAndRefresh()
    }

    func setSortMode(_ mode: SortMode) {
        settings.resolvedSortMode = mode
        persistAndRefresh()
    }

    func toggleSortModePair() {
        settings.resolvedSortMode = currentSortMode.pairedMode
        persistAndRefresh()
    }

    func setQuery(_ query: String) {
        settings.query = query
        persistAndRefresh()
    }

    func openShoppingOverlay() {
        shoppingState = ShoppingOverlayState(
            selectedBoardIDs: Set(sortedBoards.map(\.id)),
            draftStatuses: [:],
            stage: .boardSelection
        )
    }

    func closeShoppingOverlayDiscardingChanges() {
        shoppingState = nil
    }

    func proceedShoppingSelection() {
        guard var shoppingState else {
            return
        }
        shoppingState.stage = .result
        self.shoppingState = shoppingState
    }

    func goBackToShoppingSelection() {
        guard var shoppingState else {
            return
        }
        shoppingState.stage = .boardSelection
        self.shoppingState = shoppingState
    }

    func toggleShoppingBoard(_ boardID: Int64) {
        guard var shoppingState else {
            return
        }
        if shoppingState.selectedBoardIDs.contains(boardID) {
            shoppingState.selectedBoardIDs.remove(boardID)
        } else {
            shoppingState.selectedBoardIDs.insert(boardID)
        }
        self.shoppingState = shoppingState
    }

    func cycleShoppingStatus(for itemID: Int64) {
        guard var shoppingState, let item = items.first(where: { $0.id == itemID }) else {
            return
        }
        let currentStatus = shoppingState.draftStatuses[itemID] ?? item.itemStatus
        shoppingState.draftStatuses[itemID] = currentStatus.next()
        self.shoppingState = shoppingState
    }

    func shoppingHasUnsavedChanges() -> Bool {
        guard let shoppingState else {
            return false
        }
        return shoppingState.draftStatuses.contains { itemID, status in
            items.first(where: { $0.id == itemID })?.itemStatus != status
        }
    }

    func saveShoppingChanges() {
        guard let shoppingState else {
            return
        }
        let now = currentEpochMillis()
        for (itemID, draftStatus) in shoppingState.draftStatuses {
            if let index = items.firstIndex(where: { $0.id == itemID }), items[index].itemStatus != draftStatus {
                items[index].itemStatus = draftStatus
                items[index].updatedAt = now
            }
        }
        self.shoppingState = nil
        persistAndRefresh()
    }

    func shoppingSections() -> [(board: Board, items: [StockItem])] {
        guard let shoppingState else {
            return []
        }
        return sortedBoards.compactMap { board in
            guard shoppingState.selectedBoardIDs.contains(board.id) else {
                return nil
            }
            let boardItems = items.compactMap { item -> StockItem? in
                guard item.boardId == board.id else {
                    return nil
                }
                let status = shoppingState.draftStatuses[item.id] ?? item.itemStatus
                guard status != .inStock else {
                    return nil
                }
                var updatedItem = item
                updatedItem.itemStatus = status
                return updatedItem
            }
            let sortedItems = sortShoppingItems(boardItems, mode: currentSortMode)
            guard sortedItems.isEmpty == false else {
                return nil
            }
            return (board, sortedItems)
        }
    }

    func importBoard(payload: ImportedBoardPayload) {
        let boardID = nextIdentifier(existingIDs: boards.map(\.id))
        let newBoard = Board(
            id: boardID,
            name: payload.boardName.limited(to: 10),
            createdAt: payload.boardCreatedAt,
            exportId: payload.boardExportId,
            sortOrder: sortedBoards.count
        )
        boards.append(newBoard)
        var nextItemID = nextIdentifier(existingIDs: items.map(\.id))
        for payloadItem in payload.items.prefix(500) {
            items.append(
                StockItem(
                    id: nextItemID,
                    boardId: boardID,
                    name: payloadItem.name.limited(to: 24),
                    status: payloadItem.status.rawValue,
                    createdAt: payloadItem.createdAt,
                    updatedAt: payloadItem.updatedAt,
                    exportId: payloadItem.exportId ?? UUID().uuidString
                )
            )
            nextItemID += 1
        }
        settings.currentBoardId = boardID
        drawerOpen = false
        boardEditMode = false
        persistAndRefresh()
        showBanner("インポートが完了しました。")
    }

    func resetAllData() {
        do {
            let seed = try persistence.reset()
            applySnapshot(seed, openSearchForQuery: false)
            startTutorial()
            showBanner("データを初期化しました。")
        } catch {
            showBanner("データの初期化に失敗しました。")
        }
    }

    func startTutorial() {
        tutorialSteps = makeTutorialSteps(includeAddBoardStep: sortedBoards.isEmpty)
        tutorialStepIndex = 0
        if settings.tutorialSeen == false {
            settings.tutorialSeen = true
            persistAndRefresh()
        }
        applyTutorialPresentation()
    }

    func stopTutorial() {
        tutorialSteps = []
        tutorialStepIndex = 0
    }

    func nextTutorialStep() {
        guard tutorialIsPresented else {
            return
        }
        if tutorialStepIndex + 1 >= tutorialSteps.count {
            stopTutorial()
            return
        }
        tutorialStepIndex += 1
        applyTutorialPresentation()
    }

    func previousTutorialStep() {
        guard tutorialIsPresented else {
            return
        }
        tutorialStepIndex = max(tutorialStepIndex - 1, 0)
        applyTutorialPresentation()
    }

    func previewExport(format: TransferFormat) throws -> (document: BoardTransferDocument, filename: String) {
        guard let board = currentBoard else {
            throw StockManagerStoreError.missingCurrentBoard
        }
        let boardItems = sortItems(items.filter { $0.boardId == board.id }, mode: currentSortMode)
        let data = try importExportService.exportData(board: board, items: boardItems, format: format)
        let filename = importExportService.suggestedFilename(boardName: board.name, format: format)
        return (BoardTransferDocument(data: data), filename)
    }

    private func loadInitialState() {
        do {
            let result = try persistence.loadOrSeed()
            applySnapshot(result.snapshot, openSearchForQuery: true)
            if result.didSeed {
                startTutorial()
            }
        } catch {
            let seed = makeSeedSnapshot()
            applySnapshot(seed, openSearchForQuery: true)
            startTutorial()
            showBanner("初期データで起動しました。")
        }
    }

    private func applySnapshot(_ snapshot: AppDataSnapshot, openSearchForQuery: Bool) {
        boards = snapshot.boards
        items = snapshot.items
        settings = snapshot.settings
        searchOpen = openSearchForQuery ? snapshot.settings.query.isEmpty == false : false
        drawerOpen = false
        boardEditMode = false
        itemEditMode = false
        shoppingState = nil
    }

    private func persistAndRefresh() {
        normalizeState()
        do {
            try persistence.save(snapshot())
        } catch {
            showBanner("保存に失敗しました。")
        }
    }

    private func snapshot() -> AppDataSnapshot {
        AppDataSnapshot(boards: boards, items: items, settings: settings)
    }

    private func normalizeState() {
        boards = sortedBoards.enumerated().map { index, board in
            var updatedBoard = board
            updatedBoard.sortOrder = index
            return updatedBoard
        }
        let validBoardIDs = Set(boards.map(\.id))
        items = items
            .filter { validBoardIDs.contains($0.boardId) }
            .map { item in
                var updatedItem = item
                updatedItem.status = ItemStatus.normalized(item.status).rawValue
                return updatedItem
            }
        if settings.showStock == false && settings.showOut == false {
            settings.showStock = true
        }
        settings.currentBoardId = resolvedCurrentBoardID()
    }

    private func resolvedCurrentBoardID() -> Int64? {
        let validIDs = Set(boards.map(\.id))
        if let currentBoardId = settings.currentBoardId, validIDs.contains(currentBoardId) {
            return currentBoardId
        }
        return sortedBoards.first?.id
    }

    private func matchesQuery(item: StockItem) -> Bool {
        let query = settings.query.trimmed()
        guard query.isEmpty == false else {
            return true
        }
        return item.name.localizedCaseInsensitiveContains(query)
    }

    private func shouldShow(item: StockItem) -> Bool {
        let status = item.itemStatus
        if status.isStockSide {
            return settings.showStock
        }
        return settings.showOut
    }

    private func mutateItem(id: Int64, update: (inout StockItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        update(&items[index])
        persistAndRefresh()
    }

    private func sortItems(_ source: [StockItem], mode: SortMode) -> [StockItem] {
        source.sorted { lhs, rhs in
            compare(lhs: lhs, rhs: rhs, mode: mode)
        }
    }

    private func sortShoppingItems(_ source: [StockItem], mode: SortMode) -> [StockItem] {
        source.sorted { lhs, rhs in
            let lhsPriority = lhs.itemStatus == .highlighted ? 0 : 1
            let rhsPriority = rhs.itemStatus == .highlighted ? 0 : 1
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return compare(lhs: lhs, rhs: rhs, mode: mode)
        }
    }

    private func compare(lhs: StockItem, rhs: StockItem, mode: SortMode) -> Bool {
        switch mode {
        case .oldest:
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        case .newest:
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        case .name:
            let result = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if result == .orderedSame {
                return lhs.id < rhs.id
            }
            return result == .orderedAscending
        case .nameDesc:
            let result = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if result == .orderedSame {
                return lhs.id < rhs.id
            }
            return result == .orderedDescending
        case .stockFirst:
            let lhsPriority = statusPriority(lhs.itemStatus, stockFirst: true)
            let rhsPriority = statusPriority(rhs.itemStatus, stockFirst: true)
            if lhsPriority == rhsPriority {
                return compare(lhs: lhs, rhs: rhs, mode: .name)
            }
            return lhsPriority < rhsPriority
        case .outFirst:
            let lhsPriority = statusPriority(lhs.itemStatus, stockFirst: false)
            let rhsPriority = statusPriority(rhs.itemStatus, stockFirst: false)
            if lhsPriority == rhsPriority {
                return compare(lhs: lhs, rhs: rhs, mode: .name)
            }
            return lhsPriority < rhsPriority
        }
    }

    private func statusPriority(_ status: ItemStatus, stockFirst: Bool) -> Int {
        switch (stockFirst, status) {
        case (true, .inStock):
            return 0
        case (true, .highlighted):
            return 1
        case (true, .outOfStock):
            return 2
        case (false, .outOfStock):
            return 0
        case (false, .highlighted):
            return 1
        case (false, .inStock):
            return 2
        }
    }

    private func showBanner(_ message: String) {
        bannerMessage = message
    }

    private func applyTutorialPresentation() {
        guard let step = currentTutorialStep else {
            return
        }
        drawerOpen = step.drawerOpen
        boardEditMode = step.boardEditMode
        itemEditMode = step.itemEditMode
        searchOpen = settings.query.isEmpty == false
    }

    private func makeTutorialSteps(includeAddBoardStep: Bool) -> [TutorialStep] {
        var steps: [TutorialStep] = [
            TutorialStep(
                id: "menu",
                target: .menuButton,
                title: "メニュー",
                message: "左上のメニューからボード一覧、入出力、使い方、各種情報へアクセスできます。",
                drawerOpen: false,
                boardEditMode: false,
                itemEditMode: false
            ),
            TutorialStep(
                id: "board-edit",
                target: .boardEditButton,
                title: "ボード編集",
                message: "ドロワー下部のボード編集から並び替え、追加、削除ができます。",
                drawerOpen: true,
                boardEditMode: false,
                itemEditMode: false
            )
        ]

        if includeAddBoardStep {
            steps.append(
                TutorialStep(
                    id: "board-add",
                    target: .boardAddButton,
                    title: "ボード追加",
                    message: "編集モード中はボードを追加できます。カテゴリごとに分けて管理しましょう。",
                    drawerOpen: true,
                    boardEditMode: true,
                    itemEditMode: false
                )
            )
        }

        steps.append(contentsOf: [
            TutorialStep(
                id: "item-add",
                target: .itemAddButton,
                title: "アイテム追加",
                message: "右下の追加ボタンから新しいアイテムを登録できます。",
                drawerOpen: false,
                boardEditMode: false,
                itemEditMode: false
            ),
            TutorialStep(
                id: "item-edit",
                target: .itemEditButton,
                title: "アイテム編集",
                message: "左下の編集ボタンを押すと、アイテム名変更と削除モードに入ります。",
                drawerOpen: false,
                boardEditMode: false,
                itemEditMode: false
            ),
            TutorialStep(
                id: "board-list",
                target: .boardList,
                title: "ボード一覧",
                message: "ドロワーの一覧から現在のボードを切り替えられます。",
                drawerOpen: true,
                boardEditMode: false,
                itemEditMode: false
            ),
            TutorialStep(
                id: "board-row",
                target: .currentBoardRow,
                title: "現在のボード",
                message: "選択中のボードは強調表示されます。タップで切り替えます。",
                drawerOpen: true,
                boardEditMode: false,
                itemEditMode: false
            ),
            TutorialStep(
                id: "board-title",
                target: .boardTitle,
                title: "ボード名変更",
                message: "上部のボード名をタップすると、現在のボード名を変更できます。",
                drawerOpen: false,
                boardEditMode: false,
                itemEditMode: false
            ),
            TutorialStep(
                id: "filters",
                target: .filterRow,
                title: "フィルタ",
                message: "在庫側と欠品側を切り替え、見たいカードだけを表示できます。",
                drawerOpen: false,
                boardEditMode: false,
                itemEditMode: false
            ),
            TutorialStep(
                id: "sort",
                target: .sortButton,
                title: "ソート",
                message: "ソートメニューと右側の即時切り替えで並び順を変更できます。",
                drawerOpen: false,
                boardEditMode: false,
                itemEditMode: false
            ),
            TutorialStep(
                id: "shopping",
                target: .shoppingButton,
                title: "買い物リスト",
                message: "黄色と赤のアイテムだけをまとめて確認し、その場で状態変更もできます。",
                drawerOpen: false,
                boardEditMode: false,
                itemEditMode: false
            ),
            TutorialStep(
                id: "item-state",
                target: .currentItem,
                title: "状態切り替え",
                message: "通常モードではカードをタップすると 白 -> 黄 -> 赤 -> 白 の順で状態が変わります。",
                drawerOpen: false,
                boardEditMode: false,
                itemEditMode: false
            )
        ])

        return steps
    }
}
