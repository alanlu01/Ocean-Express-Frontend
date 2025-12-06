import Foundation

enum APIConfig {
    static var baseURL: URL {
        if let env = ProcessInfo.processInfo.environment["API_BASE_URL"], let url = URL(string: env) {
            return url
        }
        return URL(string: "http://localhost:3000")!
    }
}

struct APIError: Error, LocalizedError {
    let message: String
    let code: String?
    init(message: String, code: String? = nil) {
        self.message = message
        self.code = code
    }
    var errorDescription: String? { message }
}

private struct APIErrorResponse: Decodable {
    let message: String?
    let code: String?
}

private enum DateDecoder {
    static let isoFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timeInterval = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timeInterval)
            }
            let string = try container.decode(String.self)
            if let date = isoFormatter.date(from: string) {
                return date
            }
            if let date = ISO8601DateFormatter().date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(string)")
        }
        return decoder
    }
}

enum APIClient {
    static func decoder() -> JSONDecoder {
        DateDecoder.makeJSONDecoder()
    }

    static func request(_ path: String, method: String = "GET", token: String? = nil, body: Encodable? = nil) async throws -> Data {
        let url = APIConfig.baseURL.appendingPathComponent(path)
        return try await request(url: url, method: method, token: token, body: body)
    }

    static func request(url: URL, method: String = "GET", token: String? = nil, body: Encodable? = nil) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError(message: "No response")
        }
        if (200..<300).contains(http.statusCode) { return data }
        if let decoded = try? decoder().decode(APIErrorResponse.self, from: data) {
            throw APIError(message: decoded.message ?? "HTTP \(http.statusCode)", code: decoded.code)
        }
        let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
        throw APIError(message: msg, code: nil)
    }
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void
    init(_ encodable: Encodable) {
        encodeClosure = encodable.encode
    }
    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}

// MARK: - Auth

enum AuthAPI {
    struct LoginRequest: Encodable { let email: String; let password: String }
    struct RegisterRequest: Encodable { let name: String; let email: String; let password: String; let phone: String }
    struct LoginResponse: Decodable {
        let token: String
        let user: APIUser
    }
    struct LoginWrapper: Decodable {
        let data: LoginResponse
    }

    struct APIUser: Decodable {
        let id: String
        let email: String
        let role: String
    }

    static func login(email: String, password: String) async throws -> LoginResponse {
        let data = try await APIClient.request("auth/login", method: "POST", body: LoginRequest(email: email, password: password))
        let wrapper = try APIClient.decoder().decode(LoginWrapper.self, from: data)
        return wrapper.data
    }

    static func register(name: String, email: String, password: String, phone: String) async throws {
        _ = try await APIClient.request("auth/register", method: "POST", body: RegisterRequest(name: name, email: email, password: password, phone: phone))
    }
}

// MARK: - Restaurant / Menu

enum RestaurantAPI {
    struct RestaurantSummary: Decodable {
        let id: String
        let name: String
        let imageUrl: String?
        let rating: Double?
    }

    struct Review: Decodable, Identifiable {
        let id: String
        let userName: String?
        let rating: Int
        let comment: String?
        let createdAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, userName, rating, comment, createdAt, _id, user
        }

        enum OIDKeys: String, CodingKey { case oid = "$oid" }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let id = try? c.decode(String.self, forKey: .id) {
                self.id = id
            } else if let oidContainer = try? c.nestedContainer(keyedBy: OIDKeys.self, forKey: ._id) {
                self.id = try oidContainer.decode(String.self, forKey: .oid)
            } else if let rawId = try? c.decode(String.self, forKey: ._id) {
                self.id = rawId
            } else {
                self.id = UUID().uuidString
            }
            userName = (try? c.decode(String.self, forKey: .userName)) ?? (try? c.decode(String.self, forKey: .user))
            rating = (try? c.decode(Int.self, forKey: .rating)) ?? 0
            comment = try? c.decode(String.self, forKey: .comment)
            createdAt = try? c.decode(Date.self, forKey: .createdAt)
        }

        init(id: String = UUID().uuidString, userName: String? = nil, rating: Int, comment: String? = nil, createdAt: Date? = nil) {
            self.id = id
            self.userName = userName
            self.rating = rating
            self.comment = comment
            self.createdAt = createdAt
        }
    }

    struct MenuItemDTO: Decodable {
        let id: String
        let name: String
        let description: String
        let price: Int
        let sizes: [String]?
        let spicinessOptions: [String]?
        let allergens: [String]?
        let tags: [String]?

        enum CodingKeys: String, CodingKey {
            case id, name, description, price, sizes, spicinessOptions, _id, allergens, tags
        }

        enum OIDKeys: String, CodingKey {
            case oid = "$oid"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let id = try? container.decode(String.self, forKey: .id) {
                self.id = id
            } else if let oidContainer = try? container.nestedContainer(keyedBy: OIDKeys.self, forKey: ._id) {
                self.id = try oidContainer.decode(String.self, forKey: .oid)
            } else if let rawId = try? container.decode(String.self, forKey: ._id) {
                self.id = rawId
            } else {
                self.id = UUID().uuidString
            }
            name = try container.decode(String.self, forKey: .name)
            description = try container.decode(String.self, forKey: .description)
            if let intPrice = try? container.decode(Int.self, forKey: .price) {
                price = intPrice
            } else {
                let doublePrice = try container.decode(Double.self, forKey: .price)
                price = Int(doublePrice.rounded())
            }
            sizes = try? container.decode([String].self, forKey: .sizes)
            spicinessOptions = try? container.decode([String].self, forKey: .spicinessOptions)
            allergens = try? container.decode([String].self, forKey: .allergens)
            tags = try? container.decode([String].self, forKey: .tags)
        }

    }

    static func fetchRestaurants() async throws -> [RestaurantSummary] {
        let data = try await APIClient.request("restaurants")
        let wrapper = try APIClient.decoder().decode(RestaurantListResponse.self, from: data)
        return wrapper.data
    }

    static func fetchMenu(restaurantId: String) async throws -> [MenuItemDTO] {
        let data = try await APIClient.request("restaurants/\(restaurantId)/menu")
        if let wrapper = try? APIClient.decoder().decode(MenuListResponse.self, from: data) {
            return wrapper.items
        }
        return try APIClient.decoder().decode([MenuItemDTO].self, from: data)
    }

    static func fetchReviews(restaurantId: String) async throws -> [Review] {
        let data = try await APIClient.request("restaurants/\(restaurantId)/reviews")
        if let wrapper = try? APIClient.decoder().decode(ReviewListResponse.self, from: data) {
            return wrapper.data
        }
        return try APIClient.decoder().decode([Review].self, from: data)
    }

    private struct RestaurantListResponse: Decodable { let data: [RestaurantSummary] }
    private struct MenuListResponse: Decodable { let items: [MenuItemDTO] }
    private struct ReviewListResponse: Decodable { let data: [Review] }
}

// MARK: - Orders

enum OrderAPI {
    struct CreateOrderItem: Encodable {
        let menuItemId: String
        let size: String
        let spiciness: String
        let addDrink: Bool
        let quantity: Int
    }

    struct CreateOrderPayload: Encodable {
        let restaurantId: String
        let items: [CreateOrderItem]
        let deliveryLocation: DeliveryLocationPayload
        let notes: String?
        let requestedTime: String?
        let deliveryFee: Int?
        let totalAmount: Int?
    }

    struct DeliveryLocationPayload: Codable {
        let name: String
        let lat: Double?
        let lng: Double?
    }

    static func createOrder(payload: CreateOrderPayload, token: String?) async throws {
        _ = try await APIClient.request("orders", method: "POST", token: token, body: payload)
    }

    struct OrderSummary: Decodable {
        let id: String
        let restaurantName: String
        let status: String
        let etaMinutes: Int?
        let placedAt: Date?
        let totalAmount: Int?
    }

    struct OrderDetail: Decodable {
        let id: String
        let restaurantName: String?
        let status: String
        let etaMinutes: Int?
        let placedAt: Date?
        let items: [OrderItem]?
        let deliveryLocation: DeliveryLocationPayload?
        let notes: String?
        let requestedTime: Date?
        let deliveryFee: Int?
        let totalAmount: Int?
        let riderName: String?
        let riderPhone: String?
        let statusHistory: [StatusHistory]?
        var rating: OrderRating?
    }

    struct OrderItem: Decodable {
        let name: String
        let size: String?
        let spiciness: String?
        let addDrink: Bool?
        let quantity: Int?
        let price: Int?
    }

    struct StatusHistory: Decodable {
        let status: String
        let timestamp: Date?
    }

    struct OrderRating: Codable {
        let score: Int
        let comment: String?
    }

    static func fetchOrders(status: String? = nil, token: String?) async throws -> [OrderSummary] {
        var components = URLComponents(url: APIConfig.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/orders"
        if let status {
            components?.queryItems = [URLQueryItem(name: "status", value: status)]
        }
        guard let url = components?.url else { throw APIError(message: "Invalid orders URL") }

        let data = try await APIClient.request(url: url, token: token)
        let wrapper = try APIClient.decoder().decode(OrderListWrapper.self, from: data)
        return wrapper.data
    }

    static func fetchOrderDetail(id: String, token: String?) async throws -> OrderDetail {
        var components = URLComponents(url: APIConfig.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/orders/\(id)"
        guard let url = components?.url else { throw APIError(message: "Invalid order detail URL") }

        let data = try await APIClient.request(url: url, token: token)
        let wrapper = try APIClient.decoder().decode(OrderDetailWrapper.self, from: data)
        return wrapper.data
    }

    static func submitRating(orderId: String, score: Int, comment: String?, token: String?) async throws {
        struct RatingBody: Encodable { let score: Int; let comment: String? }
        _ = try await APIClient.request("orders/\(orderId)/rating", method: "POST", token: token, body: RatingBody(score: score, comment: comment))
    }

    private struct OrderListWrapper: Decodable { let data: [OrderSummary] }
    private struct OrderDetailWrapper: Decodable { let data: OrderDetail }
}

// MARK: - Deliverer

enum DelivererAPI {
    struct Stop: Decodable {
        let name: String
        let lat: Double?
        let lng: Double?
        let phone: String?
    }

    struct Task: Decodable {
        let id: String?
        let code: String?
        let fee: Int?
        let distanceKm: Double?
        let etaMinutes: Int?
        let status: String?
        let notes: String?
        let canPickup: Bool?
        let createdAt: Date?
        let merchant: Stop?
        let customer: Stop?
        let dropoff: Stop?
    }

    private struct ListWrapper: Decodable { let data: [Task] }
    private struct ItemWrapper: Decodable { let data: Task }
    private struct StatusWrapper: Decodable {
        struct StatusData: Decodable { let status: String }
        let data: StatusData
    }

    private static let decoder: JSONDecoder = {
        APIClient.decoder()
    }()

    static func fetchAvailable(token: String?) async throws -> [Task] {
        let data = try await APIClient.request("delivery/available", token: token)
        if let wrapper = try? decoder.decode(ListWrapper.self, from: data) {
            return wrapper.data
        }
        return []
    }

    static func fetchActive(token: String?) async throws -> [Task] {
        let data = try await APIClient.request("delivery/active", token: token)
        if let wrapper = try? decoder.decode(ListWrapper.self, from: data) {
            return wrapper.data
        }
        return []
    }

    static func accept(id: String, token: String?) async throws -> Task? {
        let data = try await APIClient.request("delivery/\(id)/accept", method: "POST", token: token)
        if let wrapper = try? decoder.decode(ItemWrapper.self, from: data) {
            return wrapper.data
        }
        return nil
    }

    static func updateStatus(id: String, status: String, token: String?) async throws -> Task? {
        struct StatusBody: Encodable { let status: String }
        let data = try await APIClient.request("delivery/\(id)/status", method: "PATCH", token: token, body: StatusBody(status: status))
        if let wrapper = try? decoder.decode(ItemWrapper.self, from: data) {
            return wrapper.data
        }
        if let status = try? decoder.decode(StatusWrapper.self, from: data) {
            return Task(id: id, code: nil, fee: nil, distanceKm: nil, etaMinutes: nil, status: status.data.status, notes: nil, canPickup: nil, createdAt: nil, merchant: nil, customer: nil, dropoff: nil)
        }
        return nil
    }
}

// MARK: - Delivery Locations

enum DeliveryLocationAPI {
    struct LocationDTO: Decodable {
        let name: String
        let lat: Double?
        let lng: Double?
        let category: String?
    }

    struct CategoryDTO: Decodable {
        let category: String
        let items: [LocationDTO]
    }

    private struct CategoryList: Decodable { let data: [CategoryDTO] }
    private struct FlatList: Decodable { let data: [LocationDTO] }

    static func fetchCategories() async throws -> [CategoryDTO] {
        let data = try await APIClient.request("delivery/locations")
        if let categories = try? APIClient.decoder().decode(CategoryList.self, from: data) {
            return categories.data
        }
        let flat = try APIClient.decoder().decode(FlatList.self, from: data)
        let cat = CategoryDTO(category: "預設地點", items: flat.data)
        return [cat]
    }
}

extension RestaurantAPI.MenuItemDTO {
    func toMenuItem() -> MenuItem {
        MenuItem(
            apiId: id,
            name: name,
            description: description,
            price: price,
            sizes: sizes ?? ["中份"],
            spicinessOptions: spicinessOptions ?? ["不辣", "小辣", "中辣"],
            allergens: allergens ?? [],
            tags: tags ?? []
        )
    }
}
