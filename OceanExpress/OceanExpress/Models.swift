import Foundation
import Combine

enum AppModels {
    struct Restaurant: Identifiable, Hashable, Codable {
        let id: UUID
        let name: String
        let imageURL: URL?

        init(name: String, imageURL: URL?) {
            self.id = UUID()
            self.name = name
            self.imageURL = imageURL
        }
    }

    struct MenuItem: Identifiable, Hashable, Codable {
        let id: UUID
        let name: String
        let description: String
        let price: Double
        let sizes: [String]
        let spicinessOptions: [String]

        init(name: String,
             description: String,
             price: Double,
             sizes: [String] = ["Regular"],
             spicinessOptions: [String] = ["Mild", "Medium", "Hot"]) {
            self.id = UUID()
            self.name = name
            self.description = description
            self.price = price
            self.sizes = sizes
            self.spicinessOptions = spicinessOptions
        }
    }

    enum SampleMenu {
        static let items: [MenuItem] = [
            MenuItem(name: "Grilled Salmon", description: "Fresh Atlantic salmon with lemon butter sauce.", price: 18.99),
            MenuItem(name: "Clam Chowder", description: "Creamy New England style with tender clams.", price: 7.49),
            MenuItem(name: "Seaweed Salad", description: "Crisp seaweed with sesame dressing.", price: 5.99)
        ]
    }

    struct CartItem: Identifiable, Hashable, Codable {
        let id: UUID
        let item: MenuItem
        var size: String
        var spiciness: String
        var addDrink: Bool
        var quantity: Int

        init(id: UUID = UUID(), item: MenuItem, size: String, spiciness: String, addDrink: Bool, quantity: Int) {
            self.id = id
            self.item = item
            self.size = size
            self.spiciness = spiciness
            self.addDrink = addDrink
            self.quantity = quantity
        }

        var unitPrice: Double { item.price + (addDrink ? 1.50 : 0) }
        var lineTotal: Double { unitPrice * Double(quantity) }
    }

    final class Cart: ObservableObject {
        @Published var items: [CartItem] = []

        var itemCount: Int { items.reduce(0) { $0 + $1.quantity } }
        var subtotal: Double { items.reduce(0) { $0 + $1.lineTotal } }

        func add(item: MenuItem, size: String, spiciness: String, addDrink: Bool, quantity: Int) {
            if let idx = items.firstIndex(where: { $0.item.id == item.id && $0.size == size && $0.spiciness == spiciness && $0.addDrink == addDrink }) {
                items[idx].quantity += quantity
            } else {
                items.append(CartItem(item: item, size: size, spiciness: spiciness, addDrink: addDrink, quantity: quantity))
            }
        }

        func remove(id: UUID) { items.removeAll { $0.id == id } }
        func clear() { items.removeAll() }
    }
}

// MARK: - Convenience typealiases for Views
typealias MenuItem = AppModels.MenuItem
typealias CartItem = AppModels.CartItem

typealias Cart = AppModels.Cart
