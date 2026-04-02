//
//  StockManagerApp.swift
//  StockManager
//
//  Created by MOROZUMI Shunsuke on 2026/04/01.
//

import SwiftUI

@main
struct StockManagerApp: App {
    @StateObject private var store = StockManagerStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
