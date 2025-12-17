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
        let apiId: String?
        let name: String
        let description: String
        let price: Int
        let sizes: [String]
        let spicinessOptions: [String]
        let allergens: [String]
        let tags: [String]
        let drinkOptions: [DrinkOption]

        init(id: UUID = UUID(),
             apiId: String? = nil,
             name: String,
             description: String,
             price: Int,
             sizes: [String] = ["中份"],
             spicinessOptions: [String] = ["不辣", "小辣", "中辣"],
             allergens: [String] = [],
             tags: [String] = [],
             drinkOptions: [DrinkOption] = DrinkOption.defaultOptions) {
            self.id = id
            self.apiId = apiId
            self.name = name
            self.description = description
            self.price = price
            self.sizes = sizes
            self.spicinessOptions = spicinessOptions
            self.allergens = allergens
            self.tags = tags
            self.drinkOptions = drinkOptions
        }
    }

    enum SampleMenu {
        static let items: [MenuItem] = [
            MenuItem(
                name: "炙烤鮭魚",
                description: "檸檬奶油醬、爐烤時蔬",
                price: 188,
                sizes: ["中份", "大份"],
                spicinessOptions: ["不辣", "小辣"],
                allergens: ["魚類"],
                tags: ["主餐", "健康"],
                drinkOptions: DrinkOption.defaultOptions
            ),
            MenuItem(
                name: "奶油蛤蜊濃湯",
                description: "紐英倫風味，佐香草脆麵包",
                price: 95,
                sizes: ["單碗"],
                spicinessOptions: ["不辣"],
                allergens: ["甲殼類", "奶製品"],
                tags: ["湯品"],
                drinkOptions: DrinkOption.defaultOptions
            ),
            MenuItem(
                name: "芝麻海帶沙拉",
                description: "脆爽海帶搭配和風芝麻醬",
                price: 75,
                sizes: ["單份"],
                spicinessOptions: ["不辣"],
                allergens: ["芝麻"],
                tags: ["沙拉", "清爽"],
                drinkOptions: DrinkOption.defaultOptions
            )
        ]
    }

    struct CartItem: Identifiable, Hashable, Codable {
        let id: UUID
        let item: MenuItem
        let restaurantId: String?
        let restaurantName: String
        var size: String
        var spiciness: String
        var drinkOption: DrinkOption
        var quantity: Int

        init(id: UUID = UUID(), item: MenuItem, restaurantId: String?, restaurantName: String, size: String, spiciness: String, drinkOption: DrinkOption, quantity: Int) {
            self.id = id
            self.item = item
            self.restaurantId = restaurantId
            self.restaurantName = restaurantName
            self.size = size
            self.spiciness = spiciness
            self.drinkOption = drinkOption
            self.quantity = quantity
        }

        var unitPrice: Int { item.price + drinkOption.priceDelta }
        var lineTotal: Int { unitPrice * quantity }
    }

    final class Cart: ObservableObject {
        @Published var items: [CartItem] = []
        @Published var currentRestaurantId: String? = nil
        @Published var currentRestaurantName: String? = nil

        var itemCount: Int { items.reduce(0) { $0 + $1.quantity } }
        var subtotal: Int { items.reduce(0) { $0 + $1.lineTotal } }

        func add(item: MenuItem, restaurantId: String?, restaurantName: String, size: String, spiciness: String, drinkOption: DrinkOption, quantity: Int) {
            if let idx = items.firstIndex(where: { $0.item.id == item.id && $0.restaurantName == restaurantName && $0.size == size && $0.spiciness == spiciness && $0.drinkOption.id == drinkOption.id }) {
                items[idx].quantity += quantity
            } else {
                items.append(CartItem(item: item, restaurantId: restaurantId, restaurantName: restaurantName, size: size, spiciness: spiciness, drinkOption: drinkOption, quantity: quantity))
            }
            if let restaurantId {
                currentRestaurantId = restaurantId
            }
            currentRestaurantName = restaurantName
        }

        func remove(id: UUID) { items.removeAll { $0.id == id } }
        func clear() {
            items.removeAll()
            currentRestaurantId = nil
            currentRestaurantName = nil
        }
    }
}

// MARK: - Convenience typealiases for Views
typealias MenuItem = AppModels.MenuItem
typealias CartItem = AppModels.CartItem

typealias Cart = AppModels.Cart

struct DrinkOption: Identifiable, Hashable, Codable {
    let id: String
    let label: String
    let priceDelta: Int
    let addsDrink: Bool

    init(id: String = UUID().uuidString, label: String, priceDelta: Int = 0, addsDrink: Bool = false) {
        self.id = id
        self.label = label
        self.priceDelta = priceDelta
        self.addsDrink = addsDrink
    }

    static let defaultOptions: [DrinkOption] = [
        .init(id: "no_drink", label: "不加飲料", priceDelta: 0, addsDrink: false),
        .init(id: "add_drink", label: "加飲料", priceDelta: 0, addsDrink: true)
    ]
}
