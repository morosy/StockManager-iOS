//
//  StockManagerLegalContent.swift
//  StockManager
//
//  Created by Codex on 2026/04/02.
//

import Foundation

enum InfoSheetKind: String, Identifiable {
    case about
    case terms
    case oss
    case privacy

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .about:
            return "About"
        case .terms:
            return "利用規約"
        case .oss:
            return "OSS ライセンス"
        case .privacy:
            return "プライバシーポリシー"
        }
    }

    var text: String {
        switch self {
        case .about:
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3.0"
            return """
            StockManager

            Version \(version)
            Copyright (c) morosy

            家庭内在庫をボード単位で管理し、買い物リスト化できる iOS アプリです。
            """
        case .terms:
            return """
            利用規約

            1. 本アプリは家庭内在庫の管理補助を目的として提供されます。
            2. 利用者は自己の責任で本アプリを使用するものとします。
            3. 開発者は、本アプリの利用または利用不能により生じた損害について、法令上認められる範囲で責任を負いません。
            4. 本規約は予告なく変更されることがあります。
            """
        case .oss:
            return """
            OSS ライセンス

            この iOS 版は Apple 純正フレームワークを中心に構成されています。

            - SwiftUI
            - Foundation
            - UniformTypeIdentifiers

            追加のサードパーティ依存は使用していません。
            """
        case .privacy:
            return """
            プライバシーポリシー

            1. 本アプリは、在庫データ・設定情報を端末内に保存します。
            2. 開発者は、アプリ内データを自動送信しません。
            3. 利用者が明示的にインポート / エクスポートしたファイルは、利用者自身の管理下で扱われます。
            4. OS 標準のバックアップ機能により、アプリデータが iCloud Backup 等の対象となる場合があります。
            """
        }
    }
}
