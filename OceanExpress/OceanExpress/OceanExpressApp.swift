//
//  OceanExpressApp.swift
//  OceanExpress
//
//  Created by 呂翰昇 on 2025/10/13.
//

import SwiftUI
import SwiftData

@main
struct OceanExpressApp: App {
    @StateObject private var cart = Cart()
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Item.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            LoginView()
                .environmentObject(cart)
        }
        .modelContainer(sharedModelContainer)
    }
}
