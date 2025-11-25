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
    var errorDescription: String? { message }
}

enum APIClient {
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
        let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
        throw APIError(message: msg)
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
    struct RegisterRequest: Encodable { let name: String; let email: String; let password: String }
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
        let wrapper = try JSONDecoder().decode(LoginWrapper.self, from: data)
        return wrapper.data
    }

    static func register(name: String, email: String, password: String) async throws {
        _ = try await APIClient.request("auth/register", method: "POST", body: RegisterRequest(name: name, email: email, password: password))
    }
}

// MARK: - Restaurant / Menu

enum RestaurantAPI {
    struct RestaurantSummary: Decodable {
        let id: String
        let name: String
        let imageUrl: String?
    }

    struct MenuItemDTO: Decodable {
        let id: String
        let name: String
        let description: String
        let price: Double
        let sizes: [String]?
        let spicinessOptions: [String]?

        enum CodingKeys: String, CodingKey {
            case id, name, description, price, sizes, spicinessOptions, _id
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
            price = try container.decode(Double.self, forKey: .price)
            sizes = try? container.decode([String].self, forKey: .sizes)
            spicinessOptions = try? container.decode([String].self, forKey: .spicinessOptions)
        }
    }

    static func fetchRestaurants() async throws -> [RestaurantSummary] {
        let data = try await APIClient.request("restaurants")
        let wrapper = try JSONDecoder().decode(RestaurantListResponse.self, from: data)
        return wrapper.data
    }

    static func fetchMenu(restaurantId: String) async throws -> [MenuItemDTO] {
        let data = try await APIClient.request("restaurants/\(restaurantId)/menu")
        if let wrapper = try? JSONDecoder().decode(MenuListResponse.self, from: data) {
            return wrapper.items
        }
        return try JSONDecoder().decode([MenuItemDTO].self, from: data)
    }

    private struct RestaurantListResponse: Decodable { let data: [RestaurantSummary] }
    private struct MenuListResponse: Decodable { let items: [MenuItemDTO] }
}

// MARK: - Orders

enum OrderAPI {
    struct CreateOrderItem: Encodable {
        let name: String
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
    }

    struct DeliveryLocationPayload: Codable { let name: String }

    static func createOrder(payload: CreateOrderPayload, token: String?) async throws {
        _ = try await APIClient.request("orders", method: "POST", token: token, body: payload)
    }

    struct OrderSummary: Decodable {
        let id: String
        let restaurantName: String
        let status: String
        let etaMinutes: Int?
        let placedAt: String
    }

    struct OrderDetail: Decodable {
        let id: String
        let restaurantName: String?
        let status: String
        let etaMinutes: Int?
        let placedAt: String
        let items: [OrderItem]?
        let deliveryLocation: DeliveryLocationPayload?
        let notes: String?
        let requestedTime: String?
    }

    struct OrderItem: Decodable {
        let name: String
        let size: String?
        let spiciness: String?
        let addDrink: Bool?
        let quantity: Int?
    }

    static func fetchOrders(status: String? = nil, token: String?) async throws -> [OrderSummary] {
        var components = URLComponents(url: APIConfig.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/orders"
        if let status {
            components?.queryItems = [URLQueryItem(name: "status", value: status)]
        }
        guard let url = components?.url else { throw APIError(message: "Invalid orders URL") }

        let data = try await APIClient.request(url: url, token: token)
        let wrapper = try JSONDecoder().decode(OrderListWrapper.self, from: data)
        return wrapper.data
    }

    static func fetchOrderDetail(id: String, token: String?) async throws -> OrderDetail {
        var components = URLComponents(url: APIConfig.baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/orders/\(id)"
        guard let url = components?.url else { throw APIError(message: "Invalid order detail URL") }

        let data = try await APIClient.request(url: url, token: token)
        let wrapper = try JSONDecoder().decode(OrderDetailWrapper.self, from: data)
        return wrapper.data
    }

    private struct OrderListWrapper: Decodable { let data: [OrderSummary] }
    private struct OrderDetailWrapper: Decodable { let data: OrderDetail }
}

extension RestaurantAPI.MenuItemDTO {
    func toMenuItem() -> MenuItem {
        MenuItem(
            name: name,
            description: description,
            price: price,
            sizes: sizes ?? ["Regular"],
            spicinessOptions: spicinessOptions ?? ["Mild", "Medium", "Hot"]
        )
    }
}
