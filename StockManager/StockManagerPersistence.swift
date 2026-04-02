//
//  StockManagerPersistence.swift
//  StockManager
//
//  Created by Codex on 2026/04/02.
//

import Foundation

final class StockManagerPersistence {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.fileURL = baseURL.appendingPathComponent("StockManager").appendingPathComponent("stockmanager_data.json")
        }
    }

    func loadOrSeed() throws -> (snapshot: AppDataSnapshot, didSeed: Bool) {
        if let snapshot = try load(), snapshot.boards.isEmpty == false || snapshot.settings.currentBoardId != nil {
            return (normalize(snapshot), false)
        }
        let seed = makeSeedSnapshot()
        try save(seed)
        return (seed, true)
    }

    func load() throws -> AppDataSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(AppDataSnapshot.self, from: data)
    }

    func save(_ snapshot: AppDataSnapshot) throws {
        let normalized = normalize(snapshot)
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(normalized)
        try data.write(to: fileURL, options: .atomic)
    }

    func reset() throws -> AppDataSnapshot {
        let seed = makeSeedSnapshot()
        try save(seed)
        return seed
    }

    private func normalize(_ snapshot: AppDataSnapshot) -> AppDataSnapshot {
        let boards = snapshot.boards
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.id < $1.id
                }
                return $0.sortOrder < $1.sortOrder
            }
            .enumerated()
            .map { index, board in
                var updatedBoard = board
                updatedBoard.sortOrder = index
                return updatedBoard
            }

        let boardIDs = Set(boards.map(\.id))
        let items = snapshot.items
            .filter { boardIDs.contains($0.boardId) }
            .map { item in
                var updatedItem = item
                updatedItem.status = ItemStatus.normalized(item.status).rawValue
                return updatedItem
            }

        var settings = snapshot.settings
        if settings.showStock == false && settings.showOut == false {
            settings.showStock = true
        }

        if let currentBoardId = settings.currentBoardId, boardIDs.contains(currentBoardId) {
            settings.currentBoardId = currentBoardId
        } else {
            settings.currentBoardId = boards.first?.id
        }

        return AppDataSnapshot(boards: boards, items: items, settings: settings)
    }
}
