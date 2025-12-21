import Foundation

enum APIConfig {
    static var baseURL: URL {
        if let env = ProcessInfo.processInfo.environment["API_BASE_URL"], let url = URL(string: env) {
            return url
        }
        return URL(string: "https://ocean-express-backend.onrender.com")!
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
            // Fallback for "yyyy-MM-dd HH:mm:ss.SSS +HH:mm:ss" (e.g., "2025-12-19 12:22:49.349 +00:00:00")
            let fallback = DateFormatter()
            fallback.locale = Locale(identifier: "en_US_POSIX")
            fallback.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZ"
            let cleaned = string.replacingOccurrences(of: "+00:00:00", with: "+0000")
            if let date = fallback.date(from: cleaned) {
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
        if http.statusCode == 401 || http.statusCode == 403 {
            throw APIError(message: "需要登入或無權限 (HTTP \(http.statusCode))", code: "auth.forbidden")
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
        let restaurantId: String?
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

        enum CodingKeys: String, CodingKey { case id, name, imageUrl, rating }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
            name = (try? c.decode(String.self, forKey: .name)) ?? ""
            imageUrl = try? c.decode(String.self, forKey: .imageUrl)
            if let dbl = try? c.decode(Double.self, forKey: .rating) {
                rating = dbl
            } else if let intVal = try? c.decode(Int.self, forKey: .rating) {
                rating = Double(intVal)
            } else if let str = try? c.decode(String.self, forKey: .rating), let dbl = Double(str) {
                rating = dbl
            } else {
                rating = nil
            }
        }
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
        let isAvailable: Bool
        let sizes: [String]?
        let spicinessOptions: [String]?
        let allergens: [String]?
        let tags: [String]?

        enum CodingKeys: String, CodingKey {
            case id, name, description, price, sizes, spicinessOptions, _id, allergens, tags, isAvailable
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
            } else if let doublePrice = try? container.decode(Double.self, forKey: .price) {
                price = Int(doublePrice.rounded())
            } else if let str = try? container.decode(String.self, forKey: .price), let intPrice = Int(str) {
                price = intPrice
            } else {
                price = 0
            }
            isAvailable = (try? container.decode(Bool.self, forKey: .isAvailable)) ?? true
            sizes = (try? container.decode([String].self, forKey: .sizes)) ?? []
            spicinessOptions = (try? container.decode([String].self, forKey: .spicinessOptions)) ?? []
            allergens = (try? container.decode([String].self, forKey: .allergens)) ?? []
            tags = (try? container.decode([String].self, forKey: .tags)) ?? []
        }

    }

    static func fetchRestaurants() async throws -> [RestaurantSummary] {
        let data = try await APIClient.request("restaurants")
        if let raw = String(data: data, encoding: .utf8) {
            print("🏪 fetchRestaurants raw:\n\(raw)")
        }
        if let wrapper = try? APIClient.decoder().decode(RestaurantListResponse.self, from: data) {
            return wrapper.data
        }
        if let direct = try? APIClient.decoder().decode([RestaurantSummary].self, from: data) {
            return direct
        }
        if
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataField = json["data"]
        {
            if let arr = dataField as? [[String: Any]], let arrData = try? JSONSerialization.data(withJSONObject: arr) {
                if let decoded = try? APIClient.decoder().decode([RestaurantSummary].self, from: arrData) {
                    return decoded
                }
            }
            if let items = (dataField as? [String: Any])?["items"] as? [[String: Any]], let arrData = try? JSONSerialization.data(withJSONObject: items) {
                if let decoded = try? APIClient.decoder().decode([RestaurantSummary].self, from: arrData) {
                    return decoded
                }
            }
        }
        return []
    }

    static func fetchMenu(restaurantId: String) async throws -> [MenuItemDTO] {
        let data = try await APIClient.request("restaurants/\(restaurantId)/menu")
        if let raw = String(data: data, encoding: .utf8) {
            print("🍽️ fetchMenu raw response for restaurant \(restaurantId):\n\(raw)")
        }
        if let wrapper = try? APIClient.decoder().decode(MenuListResponse.self, from: data) {
            return wrapper.data.items
        }
        if let flatData = try? APIClient.decoder().decode(MenuListResponseFlat.self, from: data) {
            return flatData.data
        }
        if let legacy = try? APIClient.decoder().decode(LegacyMenuListResponse.self, from: data) {
            return legacy.items
        }
        if let parsed = decodeMenuFallback(data) {
            return parsed
        }
        return try APIClient.decoder().decode([MenuItemDTO].self, from: data)
    }

    static func fetchReviews(restaurantId: String) async throws -> [Review] {
        let data = try await APIClient.request("restaurants/\(restaurantId)/reviews")
        if let raw = String(data: data, encoding: .utf8) {
            print("📝 fetchReviews raw for \(restaurantId):\n\(raw)")
        }
        if let wrapper = try? APIClient.decoder().decode(ReviewListResponse.self, from: data) {
            return wrapper.data
        }
        if let direct = try? APIClient.decoder().decode([Review].self, from: data) {
            return direct
        }
        if
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataField = json["data"]
        {
            if let arr = dataField as? [[String: Any]], let arrData = try? JSONSerialization.data(withJSONObject: arr) {
                if let decoded = try? APIClient.decoder().decode([Review].self, from: arrData) {
                    return decoded
                }
            }
            if let items = (dataField as? [String: Any])?["items"] as? [[String: Any]], let arrData = try? JSONSerialization.data(withJSONObject: items) {
                if let decoded = try? APIClient.decoder().decode([Review].self, from: arrData) {
                    return decoded
                }
            }
        }
        return []
    }

    private struct RestaurantListResponse: Decodable { let data: [RestaurantSummary] }
    private struct MenuListResponse: Decodable {
        let data: Items
        struct Items: Decodable { let items: [MenuItemDTO] }
    }
    private struct MenuListResponseFlat: Decodable { let data: [MenuItemDTO] }
    private struct LegacyMenuListResponse: Decodable { let items: [MenuItemDTO] }
    private struct ReviewListResponse: Decodable { let data: [Review] }

    /// 最後一道防線：容錯解析非預期格式（例如 data.items 是單一物件或陣列、或 data 本身是陣列/物件）。
    private static func decodeMenuFallback(_ data: Data) -> [MenuItemDTO]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let decoder = APIClient.decoder()

        func decodeArray(from any: Any) -> [MenuItemDTO]? {
            if let arr = any as? [Any], let arrData = try? JSONSerialization.data(withJSONObject: arr) {
                return try? decoder.decode([MenuItemDTO].self, from: arrData)
            }
            if let dict = any as? [String: Any], let dictData = try? JSONSerialization.data(withJSONObject: [dict]) {
                return try? decoder.decode([MenuItemDTO].self, from: dictData)
            }
            return nil
        }

        if let dict = json as? [String: Any] {
            if let dataField = dict["data"] {
                if let items = (dataField as? [String: Any])?["items"] ?? (dataField as? [String: Any]) {
                    if let decoded = decodeArray(from: items) { return decoded }
                }
                if let decoded = decodeArray(from: dataField) { return decoded }
            }
            if let items = dict["items"], let decoded = decodeArray(from: items) { return decoded }
            if let decoded = decodeArray(from: dict) { return decoded }
        } else if let arr = json as? [Any], let decoded = decodeArray(from: arr) {
            return decoded
        }
        return nil
    }
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
        let rating: OrderRating?
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

    struct StatusHistory: Decodable, Hashable {
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
        if let raw = String(data: data, encoding: .utf8) {
            print("📦 Order detail raw for \(id):\n\(raw)")
        }
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
        let name: String?
        let lat: Double?
        let lng: Double?
        let phone: String?
        let email: String?
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
    private struct HistoryWrapper: Decodable { let data: [Task] }
    private struct StatusWrapper: Decodable {
        struct StatusData: Decodable { let status: String }
        let data: StatusData
    }

    private static let decoder: JSONDecoder = {
        APIClient.decoder()
    }()

    private static func decodeTasks(_ data: Data) -> [Task]? {
        if let wrapper = try? decoder.decode(ListWrapper.self, from: data) {
            return wrapper.data
        }
        if let hist = try? decoder.decode(HistoryWrapper.self, from: data) {
            return hist.data
        }
        if let direct = try? decoder.decode([Task].self, from: data) {
            return direct
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let dataField = json["data"] {
                if let arr = dataField as? [[String: Any]], let arrData = try? JSONSerialization.data(withJSONObject: arr) {
                    return try? decoder.decode([Task].self, from: arrData)
                }
                if let dict = dataField as? [String: Any], let items = dict["items"] {
                    if let arr = items as? [[String: Any]], let arrData = try? JSONSerialization.data(withJSONObject: arr) {
                        return try? decoder.decode([Task].self, from: arrData)
                    }
                }
            }
            if let items = json["items"] as? [[String: Any]], let arrData = try? JSONSerialization.data(withJSONObject: items) {
                return try? decoder.decode([Task].self, from: arrData)
            }
        }
        return nil
    }

    static func fetchAvailable(token: String?) async throws -> [Task] {
        let data = try await APIClient.request("delivery/available", token: token)
        if let raw = String(data: data, encoding: .utf8) {
            print("🚚 fetchAvailable raw:\n\(raw)")
        }
        if let decoded = decodeTasks(data) { return decoded }
        return []
    }

    static func fetchActive(token: String?) async throws -> [Task] {
        let data = try await APIClient.request("delivery/active", token: token)
        if let raw = String(data: data, encoding: .utf8) {
            print("🚚 fetchActive raw:\n\(raw)")
        }
        if let decoded = decodeTasks(data) { return decoded }
        return []
    }

    static func fetchHistory(token: String?) async throws -> [Task] {
        let data = try await APIClient.request("delivery/history", token: token)
        if let raw = String(data: data, encoding: .utf8) {
            print("🚚 fetchHistory raw:\n\(raw)")
        }
        if let decoded = decodeTasks(data) { return decoded }
        return []
    }

    static func accept(id: String, token: String?) async throws -> Task? {
        struct EmptyBody: Encodable {}
        let data = try await APIClient.request("delivery/\(id)/accept", method: "POST", token: token, body: EmptyBody())
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
        if let raw = String(data: data, encoding: .utf8) {
            print("🚚 updateStatus raw:\n\(raw)")
        }
        return nil
    }

    static func reportIncident(id: String, note: String, token: String?) async throws {
        struct IncidentBody: Encodable { let note: String }
        _ = try await APIClient.request("delivery/\(id)/incident", method: "POST", token: token, body: IncidentBody(note: note))
    }

    static func updateLocation(id: String, lat: Double, lng: Double, token: String?) async throws {
        struct Body: Encodable { let lat: Double; let lng: Double }
        _ = try await APIClient.request("delivery/\(id)/location", method: "POST", token: token, body: Body(lat: lat, lng: lng))
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

// MARK: - Push

enum PushAPI {
    struct RegisterRequest: Encodable {
        let token: String
        let platform: String
        let userId: String?
        let role: String?
        let restaurantId: String?
    }

    static func registerDevice(token: String, userId: String?, role: String?, restaurantId: String?, authToken: String?) async throws {
        let body = RegisterRequest(token: token, platform: "ios", userId: userId, role: role, restaurantId: restaurantId)
        _ = try await APIClient.request("push/register", method: "POST", token: authToken, body: body)
    }
}

// MARK: - Restaurant Admin

enum RestaurantAdminAPI {
    struct CustomerSummary: Decodable {
        let name: String?
        let phone: String?
    }

    struct OrderItemDTO: Decodable, Identifiable {
        let id: String?
        let name: String
        let size: String?
        let spiciness: String?
        let quantity: Int?
        let price: Int?
    }

    struct OrderDTO: Decodable, Identifiable {
        let id: String
        let code: String?
        let restaurantId: String?
        let status: String
        let placedAt: Date?
        let etaMinutes: Int?
        let totalAmount: Int?
        let deliveryFee: Int?
        let customer: CustomerSummary?
        let items: [OrderItemDTO]?
        let notes: String?
        let deliveryLocation: OrderAPI.DeliveryLocationPayload?
        let statusHistory: [OrderAPI.StatusHistory]?
        let riderName: String?
        let riderPhone: String?

        enum CodingKeys: String, CodingKey { case id, _id, code, restaurantId, status, placedAt, etaMinutes, totalAmount, deliveryFee, customer, items, notes, deliveryLocation, statusHistory, riderName, riderPhone }
        enum OIDKeys: String, CodingKey { case oid = "$oid" }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let id = try? c.decode(String.self, forKey: .id) {
                self.id = id
            } else if let nested = try? c.nestedContainer(keyedBy: OIDKeys.self, forKey: ._id) {
                self.id = try nested.decode(String.self, forKey: .oid)
            } else if let raw = try? c.decode(String.self, forKey: ._id) {
                self.id = raw
            } else {
                self.id = UUID().uuidString
            }
            code = try? c.decode(String.self, forKey: .code)
            restaurantId = try? c.decode(String.self, forKey: .restaurantId)
            status = (try? c.decode(String.self, forKey: .status)) ?? "available"
            placedAt = try? c.decode(Date.self, forKey: .placedAt)
            etaMinutes = try? c.decode(Int.self, forKey: .etaMinutes)
            if let total = try? c.decode(Int.self, forKey: .totalAmount) {
                totalAmount = total
            } else if let dbl = try? c.decode(Double.self, forKey: .totalAmount) {
                totalAmount = Int(dbl.rounded())
            } else { totalAmount = nil }
            if let fee = try? c.decode(Int.self, forKey: .deliveryFee) {
                deliveryFee = fee
            } else if let feeD = try? c.decode(Double.self, forKey: .deliveryFee) {
                deliveryFee = Int(feeD.rounded())
            } else { deliveryFee = nil }
            customer = try? c.decode(CustomerSummary.self, forKey: .customer)
            items = try? c.decode([OrderItemDTO].self, forKey: .items)
            notes = try? c.decode(String.self, forKey: .notes)
            deliveryLocation = try? c.decode(OrderAPI.DeliveryLocationPayload.self, forKey: .deliveryLocation)
            statusHistory = try? c.decode([OrderAPI.StatusHistory].self, forKey: .statusHistory)
            riderName = try? c.decode(String.self, forKey: .riderName)
            riderPhone = try? c.decode(String.self, forKey: .riderPhone)
        }
    }

    struct MenuItemDTO: Decodable, Identifiable {
        let id: String
        let name: String
        let description: String
        let price: Int
        let sizes: [String]
        let spicinessOptions: [String]
        let allergens: [String]
        let tags: [String]
        let imageUrl: String?
        let isAvailable: Bool
        let sortOrder: Int?

        enum CodingKeys: String, CodingKey { case id, _id, name, description, price, sizes, spicinessOptions, allergens, tags, imageUrl, isAvailable, sortOrder }
        enum OIDKeys: String, CodingKey { case oid = "$oid" }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let id = try? c.decode(String.self, forKey: .id) {
                self.id = id
            } else if let nested = try? c.nestedContainer(keyedBy: OIDKeys.self, forKey: ._id) {
                self.id = try nested.decode(String.self, forKey: .oid)
            } else if let raw = try? c.decode(String.self, forKey: ._id) {
                self.id = raw
            } else {
                self.id = UUID().uuidString
            }
            name = (try? c.decode(String.self, forKey: .name)) ?? ""
            description = (try? c.decode(String.self, forKey: .description)) ?? ""
            if let p = try? c.decode(Int.self, forKey: .price) {
                price = p
            } else if let dbl = try? c.decode(Double.self, forKey: .price) {
                price = Int(dbl.rounded())
            } else if let str = try? c.decode(String.self, forKey: .price), let intP = Int(str) {
                price = intP
            } else {
                price = 0
            }
            sizes = (try? c.decode([String].self, forKey: .sizes)) ?? []
            spicinessOptions = (try? c.decode([String].self, forKey: .spicinessOptions)) ?? []
            allergens = (try? c.decode([String].self, forKey: .allergens)) ?? []
            tags = (try? c.decode([String].self, forKey: .tags)) ?? []
            imageUrl = try? c.decode(String.self, forKey: .imageUrl)
            isAvailable = (try? c.decode(Bool.self, forKey: .isAvailable)) ?? true
            sortOrder = try? c.decode(Int.self, forKey: .sortOrder)
        }
    }

    struct MenuItemPayload: Encodable {
        let name: String
        let description: String
        let price: Int
        let sizes: [String]
        let spicinessOptions: [String]
        let allergens: [String]
        let tags: [String]
        let imageUrl: String?
        let isAvailable: Bool
        let sortOrder: Int?
    }

    struct Report: Decodable {
        struct TopItem: Decodable, Identifiable {
            let id: String
            let name: String
            let quantity: Int
            let revenue: Int
        }
        let range: String
        let totalRevenue: Int
        let orderCount: Int
        let topItems: [TopItem]
    }

    private struct OrdersWrapper: Decodable { let data: [OrderDTO] }
    private struct OrderWrapper: Decodable { let data: OrderDTO }
    private struct MenuWrapper: Decodable { let data: [MenuItemDTO] }
    private struct MenuItemWrapper: Decodable { let data: MenuItemDTO }
    private struct ReportWrapper: Decodable { let data: Report }

    private static func decodeMenuItemResponse(_ data: Data, fallbackId: String?, payload: MenuItemPayload) -> MenuItemDTO {
        let decoder = APIClient.decoder()
        if let wrapper = try? decoder.decode(MenuItemWrapper.self, from: data) {
            return wrapper.data
        }
        if let list = try? decoder.decode(MenuWrapper.self, from: data) {
            if let id = fallbackId, let matched = list.data.first(where: { $0.id == id }) { return matched }
            if let first = list.data.first { return first }
        }
        if let single = try? decoder.decode(MenuItemDTO.self, from: data) {
            return single
        }
        if let array = try? decoder.decode([MenuItemDTO].self, from: data) {
            if let id = fallbackId, let matched = array.first(where: { $0.id == id }) { return matched }
            if let first = array.first { return first }
        }
        if
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataField = json["data"] as? [String: Any],
            let items = dataField["items"],
            let itemsData = try? JSONSerialization.data(withJSONObject: items),
            let decoded = try? decoder.decode([MenuItemDTO].self, from: itemsData)
        {
            if let id = fallbackId, let matched = decoded.first(where: { $0.id == id }) { return matched }
            if let first = decoded.first { return first }
        }
        return MenuItemDTO(id: fallbackId ?? UUID().uuidString, payload: payload)
    }

    static func fetchOrders(status: String?, restaurantId: String?, token: String?) async throws -> [OrderDTO] {
        var components = URLComponents(url: APIConfig.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/restaurant/orders"
        var query: [URLQueryItem] = []
        if let status { query.append(.init(name: "status", value: status)) }
        if let restaurantId { query.append(.init(name: "restaurantId", value: restaurantId)) }
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw APIError(message: "Invalid restaurant orders URL") }
        let data = try await APIClient.request(url: url, token: token)
        if let raw = String(data: data, encoding: .utf8) {
            print("🏪 Admin fetchOrders raw (status=\(status ?? "nil"), restaurantId=\(restaurantId ?? "nil")):\n\(raw)")
        }
        let wrapper = try APIClient.decoder().decode(OrdersWrapper.self, from: data)
        return wrapper.data
    }

    static func fetchOrderDetail(id: String, token: String?) async throws -> OrderDTO {
        let data = try await APIClient.request("restaurant/orders/\(id)", token: token)
        let wrapper = try APIClient.decoder().decode(OrderWrapper.self, from: data)
        return wrapper.data
    }

    static func updateOrderStatus(id: String, status: String, token: String?) async throws -> OrderDTO {
        struct Body: Encodable { let status: String }
        let data = try await APIClient.request("restaurant/orders/\(id)/status", method: "PATCH", token: token, body: Body(status: status))
        if let wrapper = try? APIClient.decoder().decode(OrderWrapper.self, from: data) {
            return wrapper.data
        }
        throw APIError(message: "更新訂單狀態失敗")
    }

    static func fetchMenu(token: String?) async throws -> [MenuItemDTO] {
        let data = try await APIClient.request("restaurant/menu", token: token)
        if let raw = String(data: data, encoding: .utf8) {
            print("🍽️ Admin fetchMenu raw response:\n\(raw)")
        }
        let wrapper = try APIClient.decoder().decode(MenuWrapper.self, from: data)
        return wrapper.data
    }

    static func createMenuItem(_ payload: MenuItemPayload, token: String?) async throws -> MenuItemDTO {
        let data = try await APIClient.request("restaurant/menu", method: "POST", token: token, body: payload)
        if let raw = String(data: data, encoding: .utf8) {
            print("🍽️ Admin createMenuItem response:\n\(raw)")
        }
        return decodeMenuItemResponse(data, fallbackId: nil, payload: payload)
    }

    static func updateMenuItem(id: String, payload: MenuItemPayload, token: String?) async throws -> MenuItemDTO {
        let data = try await APIClient.request("restaurant/menu/\(id)", method: "PATCH", token: token, body: payload)
        if let raw = String(data: data, encoding: .utf8) {
            print("🍽️ Admin updateMenuItem response:\n\(raw)")
        }
        return decodeMenuItemResponse(data, fallbackId: id, payload: payload)
    }

    static func deleteMenuItem(id: String, token: String?) async throws {
        _ = try await APIClient.request("restaurant/menu/\(id)", method: "DELETE", token: token)
    }

    static func fetchReport(range: String, restaurantId: String?, token: String?) async throws -> Report {
        var components = URLComponents(url: APIConfig.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/restaurant/reports"
        var query: [URLQueryItem] = [URLQueryItem(name: "range", value: range)]
        if let restaurantId { query.append(.init(name: "restaurantId", value: restaurantId)) }
        components?.queryItems = query
        guard let url = components?.url else { throw APIError(message: "Invalid report URL") }
        let data = try await APIClient.request(url: url, token: token)
        let wrapper = try APIClient.decoder().decode(ReportWrapper.self, from: data)
        return wrapper.data
    }
}

extension RestaurantAPI.MenuItemDTO {
    func toMenuItem() -> MenuItem {
        MenuItem(
            apiId: id,
            name: name,
            description: description,
            price: price,
            isAvailable: isAvailable,
            sizes: sizes ?? ["中份"],
            spicinessOptions: spicinessOptions ?? ["不辣", "小辣", "中辣"],
            allergens: allergens ?? [],
            tags: tags ?? []
        )
    }
}

extension RestaurantAdminAPI.MenuItemDTO {
    init(id: String, payload: RestaurantAdminAPI.MenuItemPayload) {
        self.id = id
        self.name = payload.name
        self.description = payload.description
        self.price = payload.price
        self.sizes = payload.sizes
        self.spicinessOptions = payload.spicinessOptions
        self.allergens = payload.allergens
        self.tags = payload.tags
        self.imageUrl = payload.imageUrl
        self.isAvailable = payload.isAvailable
        self.sortOrder = payload.sortOrder
    }
}
