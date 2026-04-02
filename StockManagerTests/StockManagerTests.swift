//
//  StockManagerTests.swift
//  StockManagerTests
//
//  Created by MOROZUMI Shunsuke on 2026/04/01.
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import StockManager

struct StockManagerTests {

    @Test
    @MainActor
    func seedAndDuplicateItemRule() throws {
        let store = makeStore()

        #expect(store.sortedBoards.count == 1)
        #expect(store.currentBoard?.name == "ボード1")
        #expect(store.currentBoardItems.count == 1)

        try store.addItem(named: "牛乳")

        do {
            try store.addItem(named: "牛乳")
            Issue.record("重複アイテム追加が成功してしまいました。")
        } catch {
            #expect(error as? StockManagerStoreError == .itemAlreadyExists)
        }
    }

    @Test
    @MainActor
    func filterNeverAllowsBothSidesOff() {
        let store = makeStore()

        store.setShowStock(false)
        #expect(store.settings.showStock == false)
        #expect(store.settings.showOut == true)

        store.setShowOut(false)
        #expect(store.settings.showStock == true)
        #expect(store.settings.showOut == false)
    }

    @Test
    func jsonTemplateImportFallsBackToDefaultStatus() throws {
        let service = StockManagerImportExportService()
        let data = Data(
            """
            {
              "schemaVersion": 1,
              "format": "stockmanager-board-template",
              "board": {
                "name": "テンプレート",
                "items": [
                  { "name": "Item A" },
                  { "name": "Item B", "status": "red" }
                ]
              }
            }
            """.utf8
        )

        let payload = try service.importBoard(data: data, contentType: .json, fileExtension: "json")

        #expect(payload.boardName == "テンプレート")
        #expect(payload.items.count == 2)
        #expect(payload.items[0].status == .inStock)
        #expect(payload.items[1].status == .outOfStock)
    }

    @Test
    @MainActor
    func shoppingListKeepsHighlightedBeforeOutOfStock() throws {
        let store = makeStore()

        try store.addItem(named: "パン")

        if let sample = store.currentBoardItems.first(where: { $0.name == "サンプル" }) {
            store.toggleStatus(for: sample.id)
        }
        if let bread = store.currentBoardItems.first(where: { $0.name == "パン" }) {
            store.toggleStatus(for: bread.id)
            store.toggleStatus(for: bread.id)
        }

        store.setSortMode(.outFirst)
        store.openShoppingOverlay()
        store.proceedShoppingSelection()

        let sectionItems = store.shoppingSections().first?.items ?? []

        #expect(sectionItems.count == 2)
        #expect(sectionItems.first?.itemStatus == .highlighted)
        #expect(sectionItems.last?.itemStatus == .outOfStock)
    }

    @MainActor
    private func makeStore() -> StockManagerStore {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        return StockManagerStore(
            persistence: StockManagerPersistence(fileURL: tempURL),
            importExportService: StockManagerImportExportService()
        )
    }
}
