import SwiftUI

@main
struct OceanExpressApp: App {
    @StateObject private var cart = Cart()

    var body: some Scene {
        WindowGroup {
            LoginView()
                .environmentObject(cart)
        }
    }
}
