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
    }

    static func fetchRestaurants() async throws -> [RestaurantSummary] {
        let data = try await APIClient.request("restaurants")
        let wrapper = try JSONDecoder().decode(RestaurantListResponse.self, from: data)
        return wrapper.data
    }

    static func fetchMenu(restaurantId: String) async throws -> [MenuItemDTO] {
        let data = try await APIClient.request("restaurants/\(restaurantId)/menu")
        let wrapper = try JSONDecoder().decode(MenuListResponse.self, from: data)
        return wrapper.items
    }

    private struct RestaurantListResponse: Decodable { let data: [RestaurantSummary] }
    private struct MenuListResponse: Decodable { let items: [MenuItemDTO] }
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
    }

    struct DeliveryLocationPayload: Encodable { let name: String }

    static func createOrder(payload: CreateOrderPayload, token: String?) async throws {
        _ = try await APIClient.request("orders", method: "POST", token: token, body: payload)
    }
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
