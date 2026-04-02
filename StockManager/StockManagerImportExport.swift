//
//  StockManagerImportExport.swift
//  StockManager
//
//  Created by Codex on 2026/04/02.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BoardTransferDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.json, .commaSeparatedText, .plainText]

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

final class StockManagerImportExportService {
    private let csvHeader = ["type", "exportId", "name", "status", "inStock", "createdAt", "updatedAt"]
    private let exportDateFormatter: ISO8601DateFormatter

    init() {
        self.exportDateFormatter = ISO8601DateFormatter()
        self.exportDateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.exportDateFormatter.timeZone = .current
    }

    func exportData(board: Board, items: [StockItem], format: TransferFormat) throws -> Data {
        switch format {
        case .json:
            return try exportJSON(board: board, items: items)
        case .csv:
            return try exportCSV(board: board, items: items)
        }
    }

    func suggestedFilename(boardName: String, format: TransferFormat) -> String {
        let timestampFormatter = DateFormatter()
        timestampFormatter.locale = Locale(identifier: "en_US_POSIX")
        timestampFormatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let safeName = boardName
            .replacingOccurrences(of: #"[^A-Za-z0-9\-_]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let resolvedName = safeName.isEmpty ? "board" : safeName
        return "\(resolvedName)_\(timestampFormatter.string(from: Date())).\(format.fileExtension)"
    }

    func importBoard(data: Data, contentType: UTType?, fileExtension: String?) throws -> ImportedBoardPayload {
        let format = try detectFormat(data: data, contentType: contentType, fileExtension: fileExtension)
        switch format {
        case .json:
            return try importJSON(data: data)
        case .csv:
            return try importCSV(data: data)
        }
    }

    private func detectFormat(data: Data, contentType: UTType?, fileExtension: String?) throws -> TransferFormat {
        if let contentType {
            if contentType.conforms(to: .json) {
                return .json
            }
            if contentType.conforms(to: .commaSeparatedText) {
                return .csv
            }
        }

        if let fileExtension {
            switch fileExtension.lowercased() {
            case "json":
                return .json
            case "csv":
                return .csv
            default:
                break
            }
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw StockManagerStoreError.invalidImportData
        }
        let firstCharacter = text.trimmingCharacters(in: .whitespacesAndNewlines).first
        if firstCharacter == "{" {
            return .json
        }
        if firstCharacter != nil {
            return .csv
        }
        throw StockManagerStoreError.invalidImportFormat
    }

    private func exportJSON(board: Board, items: [StockItem]) throws -> Data {
        let exportedAt = exportDateFormatter.string(from: Date())
        let boardObject: [String: Any] = [
            "exportId": board.exportId ?? UUID().uuidString,
            "name": board.name,
            "createdAt": board.createdAt,
            "items": items.map { item in
                [
                    "exportId": item.exportId ?? UUID().uuidString,
                    "name": item.name,
                    "status": ItemStatus.normalized(item.status).rawValue,
                    "inStock": ItemStatus.normalized(item.status) != .outOfStock,
                    "createdAt": item.createdAt,
                    "updatedAt": item.updatedAt
                ]
            }
        ]
        let root: [String: Any] = [
            "schemaVersion": 1,
            "format": "stockmanager-board-export",
            "exportedAt": exportedAt,
            "board": boardObject
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private func exportCSV(board: Board, items: [StockItem]) throws -> Data {
        let exportedAt = exportDateFormatter.string(from: Date())
        var rows: [[String]] = [
            ["meta_key", "meta_value"],
            ["schemaVersion", "1"],
            ["format", "stockmanager-board-export-csv"],
            ["exportedAt", exportedAt],
            ["boardExportId", board.exportId ?? UUID().uuidString],
            ["boardName", board.name],
            ["boardCreatedAt", "\(board.createdAt)"],
            [],
            csvHeader
        ]

        for item in items {
            let status = ItemStatus.normalized(item.status)
            rows.append([
                "item",
                item.exportId ?? UUID().uuidString,
                item.name,
                "\(status.rawValue)",
                String(status != .outOfStock),
                "\(item.createdAt)",
                "\(item.updatedAt)"
            ])
        }

        let csvString = rows.map { row in
            row.map(escapeCSVCell(_:)).joined(separator: ",")
        }.joined(separator: "\n")
        guard let data = csvString.data(using: .utf8) else {
            throw StockManagerStoreError.invalidImportData
        }
        return data
    }

    private func importJSON(data: Data) throws -> ImportedBoardPayload {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StockManagerStoreError.invalidImportData
        }
        guard (root["schemaVersion"] as? NSNumber)?.intValue == 1 else {
            throw StockManagerStoreError.unsupportedSchemaVersion
        }
        guard let boardObject = root["board"] as? [String: Any] else {
            throw StockManagerStoreError.invalidImportData
        }
        let boardName = (boardObject["name"] as? String)?.trimmed() ?? ""
        guard boardName.isEmpty == false else {
            throw StockManagerStoreError.invalidImportData
        }

        let importTime = currentEpochMillis()
        let boardCreatedAt = parseInt64(boardObject["createdAt"]) ?? importTime
        let boardExportId = boardObject["exportId"] as? String
        let rawItems = boardObject["items"] as? [Any] ?? []
        let items = rawItems.prefix(500).compactMap { rawItem -> ImportedItemPayload? in
            guard let itemObject = rawItem as? [String: Any] else {
                return nil
            }
            let itemName = (itemObject["name"] as? String)?.trimmed() ?? ""
            guard itemName.isEmpty == false else {
                return nil
            }

            let status = parseStatus(itemObject["status"])
                ?? parseLegacyInStockStatus(itemObject["inStock"])
                ?? .inStock

            return ImportedItemPayload(
                name: itemName,
                status: status,
                createdAt: parseInt64(itemObject["createdAt"]) ?? importTime,
                updatedAt: parseInt64(itemObject["updatedAt"]) ?? importTime,
                exportId: itemObject["exportId"] as? String
            )
        }

        return ImportedBoardPayload(
            boardName: boardName,
            boardExportId: boardExportId,
            boardCreatedAt: boardCreatedAt,
            items: Array(items)
        )
    }

    private func importCSV(data: Data) throws -> ImportedBoardPayload {
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw StockManagerStoreError.invalidImportData
        }
        let rows = parseCSVRows(csvString)
        guard rows.count >= 2 else {
            throw StockManagerStoreError.invalidImportData
        }

        var metadata: [String: String] = [:]
        var itemRows: [[String: String]] = []
        var currentIndex = 1

        while currentIndex < rows.count {
            let row = rows[currentIndex]
            if row.first == "type" {
                break
            }
            if row.count >= 2, row[0].isEmpty == false {
                metadata[row[0]] = row[1]
            }
            currentIndex += 1
        }

        guard metadata["schemaVersion"] == "1" else {
            throw StockManagerStoreError.unsupportedSchemaVersion
        }
        let boardName = (metadata["boardName"] ?? "").trimmed()
        guard boardName.isEmpty == false else {
            throw StockManagerStoreError.invalidImportData
        }

        guard currentIndex < rows.count else {
            return ImportedBoardPayload(
                boardName: boardName,
                boardExportId: metadata["boardExportId"],
                boardCreatedAt: Int64(metadata["boardCreatedAt"] ?? "") ?? currentEpochMillis(),
                items: []
            )
        }

        let header = rows[currentIndex]
        currentIndex += 1
        while currentIndex < rows.count {
            let row = rows[currentIndex]
            if row.isEmpty || row.allSatisfy(\.isEmpty) {
                currentIndex += 1
                continue
            }
            var dictionary: [String: String] = [:]
            for (index, key) in header.enumerated() where index < row.count {
                dictionary[key] = row[index]
            }
            itemRows.append(dictionary)
            currentIndex += 1
        }

        let importTime = currentEpochMillis()
        let items = itemRows.prefix(500).compactMap { row -> ImportedItemPayload? in
            let name = (row["name"] ?? "").trimmed()
            guard name.isEmpty == false else {
                return nil
            }
            let status = parseStatus(row["status"])
                ?? parseLegacyInStockStatus(row["inStock"])
                ?? .inStock
            return ImportedItemPayload(
                name: name,
                status: status,
                createdAt: Int64(row["createdAt"] ?? "") ?? importTime,
                updatedAt: Int64(row["updatedAt"] ?? "") ?? importTime,
                exportId: row["exportId"]
            )
        }

        return ImportedBoardPayload(
            boardName: boardName,
            boardExportId: metadata["boardExportId"],
            boardCreatedAt: Int64(metadata["boardCreatedAt"] ?? "") ?? importTime,
            items: Array(items)
        )
    }

    private func parseStatus(_ rawValue: Any?) -> ItemStatus? {
        if let number = rawValue as? NSNumber {
            return ItemStatus(rawValue: number.intValue)
        }
        if let intValue = rawValue as? Int {
            return ItemStatus(rawValue: intValue)
        }
        if let stringValue = rawValue as? String {
            let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch normalized {
            case "0", "white", "stock", "in_stock", "instock":
                return .inStock
            case "1", "yellow", "highlight", "highlighted", "warning", "pending":
                return .highlighted
            case "2", "red", "out", "out_of_stock", "outofstock":
                return .outOfStock
            default:
                return nil
            }
        }
        return nil
    }

    private func parseLegacyInStockStatus(_ rawValue: Any?) -> ItemStatus? {
        if let boolValue = rawValue as? Bool {
            return boolValue ? .inStock : .outOfStock
        }
        if let number = rawValue as? NSNumber {
            return number.boolValue ? .inStock : .outOfStock
        }
        if let stringValue = rawValue as? String {
            switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return .inStock
            case "false", "0", "no":
                return .outOfStock
            default:
                return nil
            }
        }
        return nil
    }

    private func parseInt64(_ rawValue: Any?) -> Int64? {
        if let intValue = rawValue as? Int64 {
            return intValue
        }
        if let intValue = rawValue as? Int {
            return Int64(intValue)
        }
        if let number = rawValue as? NSNumber {
            return number.int64Value
        }
        if let stringValue = rawValue as? String {
            return Int64(stringValue)
        }
        return nil
    }

    private func escapeCSVCell(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func parseCSVRows(_ string: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentCell = ""
        var isInsideQuotes = false
        let characters = Array(string)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if isInsideQuotes {
                if character == "\"" {
                    let nextIndex = index + 1
                    if nextIndex < characters.count, characters[nextIndex] == "\"" {
                        currentCell.append("\"")
                        index += 1
                    } else {
                        isInsideQuotes = false
                    }
                } else {
                    currentCell.append(character)
                }
            } else {
                switch character {
                case "\"":
                    isInsideQuotes = true
                case ",":
                    currentRow.append(currentCell)
                    currentCell = ""
                case "\n":
                    currentRow.append(currentCell)
                    rows.append(currentRow)
                    currentRow = []
                    currentCell = ""
                case "\r":
                    break
                default:
                    currentCell.append(character)
                }
            }
            index += 1
        }

        if currentCell.isEmpty == false || currentRow.isEmpty == false {
            currentRow.append(currentCell)
            rows.append(currentRow)
        }
        return rows
    }
}
