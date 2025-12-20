import SwiftUI
import Charts
import UIKit
import Combine
import UserNotifications

// MARK: - Models

enum RestaurantAdminTab: Hashable {
    case orders, menu, reports, settings
}

enum RestaurantOrderStatusAdmin: String, CaseIterable, Identifiable {
    case available
    case assigned
    case en_route_to_pickup
    case picked_up
    case delivering
    case delivered
    case cancelled

    var id: String { rawValue }

    init(apiValue: String) {
        switch apiValue {
        case "enRouteToPickup": self = .en_route_to_pickup
        case "pickedUp": self = .picked_up
        default:
            self = RestaurantOrderStatusAdmin(rawValue: apiValue) ?? .available
        }
    }

    var apiValue: String { rawValue }

    var title: String {
        switch self {
        case .available: return "未接單"
        case .assigned: return "備餐中"
        case .en_route_to_pickup: return "待取餐"
        case .picked_up: return "已取餐"
        case .delivering: return "配送中"
        case .delivered: return "已完成"
        case .cancelled: return "已取消"
        }
    }

    var badgeColor: Color {
        switch self {
        case .available: return .gray
        case .assigned: return .orange
        case .en_route_to_pickup: return .blue
        case .picked_up: return .teal
        case .delivering: return .purple
        case .delivered: return .green
        case .cancelled: return .red
        }
    }

    /// 餐廳端可操作的狀態流：接單/拒單、備餐中→待取餐、可取消
    var nextStepsForRestaurant: [RestaurantOrderStatusAdmin] {
        switch self {
        case .available: return [.assigned, .cancelled]
        case .assigned: return [.en_route_to_pickup, .cancelled]
        default: return []
        }
    }

    var isHistory: Bool {
        self == .delivered || self == .cancelled
    }
}

struct RestaurantOrderItemAdmin: Identifiable, Hashable {
    var id: String
    var name: String
    var size: String?
    var spiciness: String?
    var quantity: Int
    var price: Int?
}

struct RestaurantOrderAdmin: Identifiable, Hashable {
    var id: String
    var code: String?
    var restaurantId: String?
    var status: RestaurantOrderStatusAdmin
    var placedAt: Date?
    var etaMinutes: Int?
    var totalAmount: Int?
    var deliveryFee: Int?
    var customerName: String?
    var customerPhone: String?
    var items: [RestaurantOrderItemAdmin]
    var notes: String?
    var deliveryLocation: OrderAPI.DeliveryLocationPayload?
    var statusHistory: [OrderAPI.StatusHistory]
    var riderName: String?
    var riderPhone: String?

    static func == (lhs: RestaurantOrderAdmin, rhs: RestaurantOrderAdmin) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct RestaurantMenuItemAdmin: Identifiable, Hashable {
    var id: String
    var name: String
    var description: String
    var price: Int
    var sizes: [String]
    var spicinessOptions: [String]
    var allergens: [String]
    var tags: [String]
    var imageUrl: String?
    var isAvailable: Bool
    var sortOrder: Int?
    var isNew: Bool = false
}

struct RestaurantTopItem: Identifiable, Hashable {
    var id: String
    var name: String
    var quantity: Int
    var revenue: Int
}

struct RestaurantReport: Hashable {
    var range: String
    var totalRevenue: Int
    var orderCount: Int
    var topItems: [RestaurantTopItem]
}

enum ReportRange: String, CaseIterable, Identifiable {
    case today = "today"
    case week = "7d"
    case month = "30d"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "今日"
        case .week: return "本週"
        case .month: return "本月"
        }
    }
}

// MARK: - Services

protocol RestaurantServiceProtocol {
    func fetchOrders(status: String) async throws -> [RestaurantOrderAdmin]
    func updateOrderStatus(id: String, status: RestaurantOrderStatusAdmin) async throws -> RestaurantOrderAdmin
    func fetchMenu() async throws -> [RestaurantMenuItemAdmin]
    func createMenuItem(_ item: RestaurantMenuItemAdmin) async throws -> RestaurantMenuItemAdmin
    func updateMenuItem(_ item: RestaurantMenuItemAdmin) async throws -> RestaurantMenuItemAdmin
    func deleteMenuItem(id: String) async throws
    func fetchReport(range: ReportRange) async throws -> RestaurantReport
    func fetchReviews(restaurantId: String) async throws -> [RestaurantAPI.Review]
}

final class NetworkRestaurantService: RestaurantServiceProtocol {
    private let tokenProvider: () -> String?
    private let restaurantId: String?

    init(tokenProvider: @escaping () -> String?, restaurantId: String? = nil) {
        self.tokenProvider = tokenProvider
        self.restaurantId = restaurantId
    }

    func fetchOrders(status: String) async throws -> [RestaurantOrderAdmin] {
        let dtos = try await RestaurantAdminAPI.fetchOrders(status: status, restaurantId: restaurantId, token: tokenProvider())
        return dtos.map { $0.toModel() }
    }

    func updateOrderStatus(id: String, status: RestaurantOrderStatusAdmin) async throws -> RestaurantOrderAdmin {
        let dto = try await RestaurantAdminAPI.updateOrderStatus(id: id, status: status.apiValue, token: tokenProvider())
        return dto.toModel()
    }

    func fetchMenu() async throws -> [RestaurantMenuItemAdmin] {
        let dtos = try await RestaurantAdminAPI.fetchMenu(token: tokenProvider())
        return dtos.map { $0.toModel() }
    }

    func createMenuItem(_ item: RestaurantMenuItemAdmin) async throws -> RestaurantMenuItemAdmin {
        let payload = item.toPayload()
        let dto = try await RestaurantAdminAPI.createMenuItem(payload, token: tokenProvider())
        return dto.toModel()
    }

    func updateMenuItem(_ item: RestaurantMenuItemAdmin) async throws -> RestaurantMenuItemAdmin {
        let payload = item.toPayload()
        let dto = try await RestaurantAdminAPI.updateMenuItem(id: item.id, payload: payload, token: tokenProvider())
        return dto.toModel()
    }

    func deleteMenuItem(id: String) async throws {
        try await RestaurantAdminAPI.deleteMenuItem(id: id, token: tokenProvider())
    }

    func fetchReport(range: ReportRange) async throws -> RestaurantReport {
        let dto = try await RestaurantAdminAPI.fetchReport(range: range.rawValue, restaurantId: restaurantId, token: tokenProvider())
        return dto.toModel()
    }

    func fetchReviews(restaurantId: String) async throws -> [RestaurantAPI.Review] {
        try await RestaurantAPI.fetchReviews(restaurantId: restaurantId)
    }
}

final class DemoRestaurantService: RestaurantServiceProtocol {
    private var activeOrders: [RestaurantOrderAdmin] = [
        RestaurantOrderAdmin(
            id: "ord-201",
            code: "R-201",
            restaurantId: "rest-001",
            status: .assigned,
            placedAt: Date().addingTimeInterval(-1800),
            etaMinutes: 18,
            totalAmount: 520,
            deliveryFee: 20,
            customerName: "林小姐",
            customerPhone: "0912-000-001",
            items: [
                .init(id: "menu-001", name: "港灣漢堡", size: "中份", spiciness: "小辣", quantity: 2, price: 180),
                .init(id: "menu-002", name: "薯條", size: "單份", spiciness: nil, quantity: 1, price: 80)
            ],
            notes: "記得多附醬",
            deliveryLocation: .init(name: "行政大樓", lat: 25.1503, lng: 121.7655),
            statusHistory: [],
            riderName: "王外送",
            riderPhone: "0900-111-222"
        ),
        RestaurantOrderAdmin(
            id: "ord-202",
            code: "R-202",
            restaurantId: "rest-001",
            status: .en_route_to_pickup,
            placedAt: Date().addingTimeInterval(-900),
            etaMinutes: 10,
            totalAmount: 320,
            deliveryFee: 20,
            customerName: "張同學",
            customerPhone: "0912-000-002",
            items: [
                .init(id: "menu-003", name: "綠光沙拉碗", size: "單份", spiciness: "不辣", quantity: 1, price: 150),
                .init(id: "menu-004", name: "奶茶", size: "大杯", spiciness: nil, quantity: 1, price: 70)
            ],
            notes: "請放門口",
            deliveryLocation: .init(name: "圖書館", lat: 25.1501, lng: 121.7753),
            statusHistory: [],
            riderName: nil,
            riderPhone: nil
        )
    ]

    private var historyOrders: [RestaurantOrderAdmin] = [
        RestaurantOrderAdmin(
            id: "ord-199",
            code: "R-199",
            restaurantId: "rest-001",
            status: .delivered,
            placedAt: Date().addingTimeInterval(-7200),
            etaMinutes: 0,
            totalAmount: 680,
            deliveryFee: 20,
            customerName: "黃先生",
            customerPhone: "0912-000-099",
            items: [
                .init(id: "menu-005", name: "炙烤鮭魚", size: "大份", spiciness: "不辣", quantity: 2, price: 188)
            ],
            notes: "提前十分鐘通知",
            deliveryLocation: .init(name: "第二餐廳", lat: 25.1485, lng: 121.7791),
            statusHistory: [],
            riderName: "陳外送",
            riderPhone: "0900-999-888"
        )
    ]

    private var menu: [RestaurantMenuItemAdmin] = [
        .init(id: "menu-001", name: "港灣漢堡", description: "炙烤牛肉、生菜番茄", price: 180, sizes: ["中份", "大份"], spicinessOptions: ["不辣", "小辣"], allergens: ["牛肉", "麩質"], tags: ["主餐", "人氣"], imageUrl: nil, isAvailable: true, sortOrder: 1),
        .init(id: "menu-002", name: "檸檬蜜茶", description: "手工現泡", price: 70, sizes: ["中杯", "大杯"], spicinessOptions: ["不辣"], allergens: [], tags: ["飲品"], imageUrl: nil, isAvailable: true, sortOrder: 2),
        .init(id: "menu-003", name: "海港薯條", description: "酥脆現炸", price: 80, sizes: ["單份"], spicinessOptions: ["不辣"], allergens: [], tags: ["點心"], imageUrl: nil, isAvailable: true, sortOrder: 3)
    ]

    func fetchOrders(status: String) async throws -> [RestaurantOrderAdmin] {
        status == "history" ? historyOrders : activeOrders
    }

    func updateOrderStatus(id: String, status: RestaurantOrderStatusAdmin) async throws -> RestaurantOrderAdmin {
        if let idx = activeOrders.firstIndex(where: { $0.id == id }) {
            activeOrders[idx].status = status
            if status.isHistory {
                let moved = activeOrders.remove(at: idx)
                var updated = moved
                updated.status = status
                historyOrders.append(updated)
            }
            return activeOrders.first(where: { $0.id == id }) ?? historyOrders.last!
        }
        if let idx = historyOrders.firstIndex(where: { $0.id == id }) {
            historyOrders[idx].status = status
            return historyOrders[idx]
        }
        throw APIError(message: "找不到訂單")
    }

    func fetchMenu() async throws -> [RestaurantMenuItemAdmin] {
        menu
    }

    func createMenuItem(_ item: RestaurantMenuItemAdmin) async throws -> RestaurantMenuItemAdmin {
        var newItem = item
        newItem.id = "menu-\(Int.random(in: 300...999))"
        newItem.isNew = false
        menu.append(newItem)
        return newItem
    }

    func updateMenuItem(_ item: RestaurantMenuItemAdmin) async throws -> RestaurantMenuItemAdmin {
        if let idx = menu.firstIndex(where: { $0.id == item.id }) {
            var updated = item
            updated.isNew = false
            menu[idx] = updated
            return updated
        }
        return try await createMenuItem(item)
    }

    func deleteMenuItem(id: String) async throws {
        menu.removeAll { $0.id == id }
    }

    func fetchReport(range: ReportRange) async throws -> RestaurantReport {
        let total = (activeOrders + historyOrders).reduce(0) { $0 + ($1.totalAmount ?? 0) }
        let top: [RestaurantTopItem] = menu.prefix(3).enumerated().map { idx, item in
            RestaurantTopItem(id: item.id, name: item.name, quantity: 10 - idx * 2, revenue: (10 - idx * 2) * item.price)
        }
        return RestaurantReport(range: range.rawValue, totalRevenue: total, orderCount: activeOrders.count + historyOrders.count, topItems: top)
    }

    func fetchReviews(restaurantId: String) async throws -> [RestaurantAPI.Review] {
        [
            RestaurantAPI.Review(userName: "Alice", rating: 5, comment: "餐點好吃，出餐很快！", createdAt: Date().addingTimeInterval(-3600)),
            RestaurantAPI.Review(userName: "Bob", rating: 4, comment: "份量足，外送包裝完整。", createdAt: Date().addingTimeInterval(-7200))
        ]
    }
}

// MARK: - Store

@MainActor
final class RestaurantAdminStore: ObservableObject {
    @Published var activeOrders: [RestaurantOrderAdmin] = []
    @Published var historyOrders: [RestaurantOrderAdmin] = []
    @Published var menuItems: [RestaurantMenuItemAdmin] = []
    @Published var report: RestaurantReport?
    @Published var reviews: [RestaurantAPI.Review] = []
    @Published var statusMessage: String?
    @Published var reportRange: ReportRange = .today

    private let service: RestaurantServiceProtocol
    private var restaurantId: String?
    private let defaultRestaurantId: String?
    private var lastOrderCount: Int = 0
    private var demoTimer: Timer?
    private var demoCounter: Int = 300

    init(service: RestaurantServiceProtocol, restaurantId: String? = nil) {
        self.service = service
        self.restaurantId = restaurantId
        self.defaultRestaurantId = restaurantId
        if DemoConfig.isDemoAccount {
            startDemoOrders()
        }
    }

    deinit {
        stopDemoOrders()
    }

    func loadOrders() async {
        do {
            let active = try await service.fetchOrders(status: "active")
            let history = try await service.fetchOrders(status: "history")
            self.activeOrders = active
            self.historyOrders = history
            // 優先使用建構時注入的 restaurantId，否則從訂單回傳帶回。
            if restaurantId == nil {
                restaurantId = active.compactMap { $0.restaurantId }.first ?? history.compactMap { $0.restaurantId }.first
            }
            if restaurantId == nil, let firstId = (active + history).compactMap({ $0.restaurantId }).first {
                restaurantId = firstId
            }
            if restaurantId == nil {
                restaurantId = defaultRestaurantId ?? ProcessInfo.processInfo.environment["RESTAURANT_ID"] ?? UserDefaults.standard.string(forKey: "restaurant_id")
            }
            print("📝 loadOrders captured restaurantId=\(restaurantId ?? "nil")")
            notifyIfNewOrder(currentActiveCount: active.count)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateStatus(order: RestaurantOrderAdmin, to status: RestaurantOrderStatusAdmin) async {
        do {
            let updated = try await service.updateOrderStatus(id: order.id, status: status)
            replaceOrder(updated)
            statusMessage = "狀態已更新並推播通知"
            await loadOrders()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func loadMenu() async {
        do {
            menuItems = try await service.fetchMenu().sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveMenuItem(_ item: RestaurantMenuItemAdmin) async {
        do {
            if item.isNew {
                _ = try await service.createMenuItem(item)
            } else {
                _ = try await service.updateMenuItem(item)
            }
            // 以後端回傳為準，同步一次列表，避免本地狀態與伺服器不一致
            await loadMenu()
            statusMessage = "菜單已儲存"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteMenuItem(id: String) async {
        do {
            try await service.deleteMenuItem(id: id)
            await loadMenu()
            statusMessage = "餐點已刪除"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func loadReport() async {
        do {
            report = try await service.fetchReport(range: reportRange)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func loadReviews() async {
        guard let restaurantId = resolvedRestaurantId, !restaurantId.isEmpty else {
            statusMessage = "無法取得餐廳 ID，請先重新整理訂單"
            print("📝 loadReviews skip: missing restaurantId. active=\(activeOrders.count) history=\(historyOrders.count)")
            return
        }
        print("📝 loadReviews for restaurantId=\(restaurantId)")
        do {
            reviews = try await service.fetchReviews(restaurantId: restaurantId)
            if reviews.isEmpty {
                statusMessage = "目前沒有買家評論"
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func order(with id: String) -> RestaurantOrderAdmin? {
        activeOrders.first(where: { $0.id == id }) ?? historyOrders.first(where: { $0.id == id })
    }

    private func replaceOrder(_ order: RestaurantOrderAdmin) {
        if let idx = activeOrders.firstIndex(where: { $0.id == order.id }) {
            activeOrders[idx] = order
            if order.status.isHistory {
                let moved = activeOrders.remove(at: idx)
                historyOrders.append(moved)
            }
        } else if let idx = historyOrders.firstIndex(where: { $0.id == order.id }) {
            historyOrders[idx] = order
        }
    }

    private func notifyIfNewOrder(currentActiveCount: Int) {
        guard currentActiveCount > lastOrderCount else {
            lastOrderCount = currentActiveCount
            return
        }
        guard NotificationManager.shared.isPushEnabled else {
            lastOrderCount = currentActiveCount
            return
        }
        lastOrderCount = currentActiveCount
        // 本地通知提示有新訂單（推播占位）
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "新訂單"
            content.body = "有新的訂單待接單，請立即查看。"
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        }
    }

    private func startDemoOrders() {
        demoTimer?.invalidate()
        // 若不在 Demo 模式或已切換到真人服務，避免啟動 demo 訂單
        guard DemoConfig.isDemoAccount else { return }
        demoTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let id = "demo-\(self.demoCounter)"
                self.demoCounter += 1
                let newOrder = RestaurantOrderAdmin(
                    id: id,
                    code: "D-\(self.demoCounter)",
                    restaurantId: self.restaurantId ?? "rest-001",
                    status: .available,
                    placedAt: Date(),
                    etaMinutes: Int.random(in: 10...25),
                    totalAmount: Int.random(in: 180...520),
                    deliveryFee: 20,
                    customerName: ["林小姐", "張同學", "王先生", "陳小姐"].randomElement(),
                    customerPhone: "0912-000-\(String(format: "%03d", Int.random(in: 100...999)))",
                    items: [
                        RestaurantOrderItemAdmin(id: "menu-demo", name: "新品快閃 \(self.demoCounter)", size: ["中份", "大份"].randomElement(), spiciness: ["不辣", "小辣"].randomElement(), quantity: 1, price: Int.random(in: 120...260))
                    ],
                    notes: ["記得多醬", "請放門口", "提前聯絡"].randomElement(),
                    deliveryLocation: .init(name: ["行政大樓", "圖書館", "第二餐廳"].randomElement() ?? "校園", lat: nil, lng: nil),
                    statusHistory: [],
                    riderName: nil,
                    riderPhone: nil
                )
                self.activeOrders.insert(newOrder, at: 0)
                self.notifyIfNewOrder(currentActiveCount: self.activeOrders.count)
            }
        }
    }

    nonisolated func stopDemoOrders() {
        Task { @MainActor [weak self] in
            self?.demoTimer?.invalidate()
            self?.demoTimer = nil
        }
    }

    var restaurantIdentifier: String {
        resolvedRestaurantId ?? ""
    }

    var resolvedRestaurantId: String? {
        restaurantId ?? activeOrders.first?.restaurantId ?? historyOrders.first?.restaurantId
    }
}

// MARK: - Views

struct RestaurantModule: View {
    @StateObject private var store: RestaurantAdminStore
    @State private var selectedTab: RestaurantAdminTab = .orders
    var onLogout: () -> Void
    var onSwitchRole: () -> Void

    init(onLogout: @escaping () -> Void = {}, onSwitchRole: @escaping () -> Void = {}) {
        let tokenProvider = { UserDefaults.standard.string(forKey: "auth_token") }
        let envRestaurantId = ProcessInfo.processInfo.environment["RESTAURANT_ID"] ?? UserDefaults.standard.string(forKey: "restaurant_id")
        let service: RestaurantServiceProtocol = DemoConfig.isDemoAccount ? DemoRestaurantService() : NetworkRestaurantService(tokenProvider: tokenProvider, restaurantId: envRestaurantId)
        _store = StateObject(wrappedValue: RestaurantAdminStore(service: service, restaurantId: envRestaurantId))
        self.onLogout = onLogout
        self.onSwitchRole = onSwitchRole
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            RestaurantOrdersView()
                .tabItem { Label("訂單", systemImage: "list.bullet.rectangle") }
                .tag(RestaurantAdminTab.orders)

            RestaurantMenuManagerView()
                .tabItem { Label("菜單", systemImage: "fork.knife") }
                .tag(RestaurantAdminTab.menu)

            RestaurantReportsView()
                .tabItem { Label("報表", systemImage: "chart.bar") }
                .tag(RestaurantAdminTab.reports)

            RestaurantSettingsView(onLogout: onLogout)
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(RestaurantAdminTab.settings)
        }
        .environmentObject(store)
        .onAppear {
            // 離開 demo 模式時確保不會殘留假訂單計時器
            if !DemoConfig.isDemoAccount {
                Task { @MainActor in store.stopDemoOrders() }
            }
        }
        .onDisappear {
            Task { @MainActor in store.stopDemoOrders() }
        }
    }
}

// MARK: 訂單列表

struct RestaurantOrdersView: View {
    @EnvironmentObject var store: RestaurantAdminStore
    @State private var selectedStatus: String = "active"
    @State private var selectedOrderId: String?
    @State private var showToast = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("狀態", selection: $selectedStatus) {
                    Text("進行中").tag("active")
                    Text("歷史紀錄").tag("history")
                }
                .pickerStyle(.segmented)
                .padding()

                List {
                    ForEach(currentOrders) { order in
                        RestaurantOrderRow(
                            order: order,
                            onAccept: { Task { await store.updateStatus(order: order, to: .assigned) } },
                            onReject: { Task { await store.updateStatus(order: order, to: .cancelled) } }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedOrderId = order.id }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("訂單管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if DemoConfig.isEnabled {
                        Text("Demo").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .task { await store.loadOrders() }
            .refreshable { await store.loadOrders() }
            .sheet(item: sheetBinding()) { id in
                if let order = store.order(with: id.id) {
                    RestaurantOrderDetailView(order: order) { status in
                        await store.updateStatus(order: order, to: status)
                        if let updated = store.order(with: order.id) {
                            selectedOrderId = updated.id
                        }
                    }
                } else {
                    ContentUnavailableView("找不到訂單", systemImage: "exclamationmark.triangle")
                }
            }
            .onChange(of: store.statusMessage) { _, newValue in
                showToast = newValue != nil
            }
            .overlay(alignment: .bottom) {
                if showToast, let message = store.statusMessage {
                    Text(message)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { showToast = false }
                            }
                        }
                }
            }
        }
    }

    private var currentOrders: [RestaurantOrderAdmin] {
        selectedStatus == "active" ? store.activeOrders : store.historyOrders
    }

    private func sheetBinding() -> Binding<IdentifiableString?> {
        Binding<IdentifiableString?>(
            get: {
                guard let id = selectedOrderId else { return nil }
                return IdentifiableString(id: id)
            },
            set: { selectedOrderId = $0?.id }
        )
    }
}

private struct IdentifiableString: Identifiable { let id: String }

struct RestaurantOrderRow: View {
    let order: RestaurantOrderAdmin
    var onAccept: (() -> Void)?
    var onReject: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(order.code ?? order.id)
                    .font(.headline)
                Spacer()
                Text(order.status.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(order.status.badgeColor, in: Capsule())
            }
            if let total = order.totalAmount {
                Text("金額：$\(total)")
                    .font(.subheadline.weight(.semibold))
            }
            if let customer = order.customerName {
                Text("客戶：\(customer)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let loc = order.deliveryLocation?.name {
                Text("地點：\(loc)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if order.status == .available {
                HStack {
                    if let onReject {
                        Button {
                            onReject()
                        } label: {
                            Label("拒單", systemImage: "xmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red.opacity(0.9))
                        .foregroundStyle(.white)
                    }
                    if let onAccept {
                        Button {
                            onAccept()
                        } label: {
                            Label("接單", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .foregroundStyle(.white)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RestaurantOrderDetailView: View {
    let order: RestaurantOrderAdmin
    var onUpdateStatus: (RestaurantOrderStatusAdmin) async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("訂單摘要") {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(order.code ?? order.id).font(.headline)
                            Text(order.status.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(order.status.badgeColor)
                        }
                        Spacer()
                        if let total = order.totalAmount {
                            Text("$\(total)")
                                .font(.title3.weight(.bold))
                        }
                    }
                    if let fee = order.deliveryFee {
                        Text("外送費：$\(fee)")
                            .font(.subheadline)
                    }
                    if let eta = order.etaMinutes {
                        Text("預估 \(eta) 分鐘")
                            .foregroundStyle(.secondary)
                    }
                    if order.status == .available {
                        HStack {
                            Button {
                                Task { await onUpdateStatus(.cancelled) }
                            } label: {
                                Label("拒單", systemImage: "xmark.circle.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red.opacity(0.9))
                            .foregroundColor(.white)

                            Button {
                                Task { await onUpdateStatus(.assigned) }
                            } label: {
                                Label("接單", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .foregroundColor(.white)
                        }
                        .padding(.top, 6)
                    }
                }

                if !order.items.isEmpty {
                    Section("餐點") {
                        ForEach(order.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.headline)
                                HStack(spacing: 8) {
                                    if let size = item.size { Text(size) }
                                    if let sp = item.spiciness { Text(sp) }
                                    Text("x\(item.quantity)")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if let price = item.price {
                                    Text("$\(price)")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("配送") {
                    if let loc = order.deliveryLocation?.name {
                        Text("地點：\(loc)")
                    }
                    if let notes = order.notes, !notes.isEmpty {
                        Text("備註：\(notes)")
                    }
                }

                Section("聯絡資訊") {
                    if let name = order.customerName {
                        Text("買家：\(name)")
                    }
                    if let phone = order.customerPhone {
                        Button {
                            if let url = URL(string: "tel://\(phone.replacingOccurrences(of: "-", with: ""))") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("撥打買家電話 \(phone)", systemImage: "phone.fill")
                        }
                    }
                    if let rider = order.riderName {
                        Text("外送員：\(rider)")
                    }
                    if let phone = order.riderPhone {
                        Button {
                            if let url = URL(string: "tel://\(phone.replacingOccurrences(of: "-", with: ""))") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("撥打外送員 \(phone)", systemImage: "phone.fill.arrow.up.right")
                        }
                    }
                }

                if !order.statusHistory.isEmpty {
                    Section("時間軸") {
                        ForEach(order.statusHistory, id: \.status) { history in
                            HStack {
                                Text(history.status)
                                Spacer()
                                if let ts = history.timestamp {
                                    Text(ts, style: .time)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

            }
            .navigationTitle("訂單詳情")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !order.status.nextStepsForRestaurant.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(order.status.nextStepsForRestaurant, id: \.self) { next in
                            Button {
                                Task { await onUpdateStatus(next) }
                            } label: {
                                Label(next.title, systemImage: next == .cancelled ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .font(.headline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(next == .cancelled ? .red : .accentColor)
                            .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(.thinMaterial)
                }
            }
        }
    }
}

// MARK: 菜單管理

struct RestaurantMenuManagerView: View {
    @EnvironmentObject var store: RestaurantAdminStore
    @State private var editingItem: RestaurantMenuItemAdmin?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        createNewItem()
                    } label: {
                        Label("新增餐點", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Section {
                    ForEach(store.menuItems) { item in
                        Button {
                            editingItem = item
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.name)
                                        .font(.headline)
                                    Text(item.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("價格：$\(item.price)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }
                                VStack(alignment: .trailing, spacing: 6) {
                                    Text(item.isAvailable ? "上架中" : "已下架")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(item.isAvailable ? .green : .secondary)
                                    if let sort = item.sortOrder {
                                        Text("#\(sort)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .navigationTitle("菜單管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        createNewItem()
                    } label: {
                        Label("新增", systemImage: "plus")
                    }
                }
            }
            .task { await store.loadMenu() }
            .refreshable { await store.loadMenu() }
            .sheet(item: $editingItem) { item in
                RestaurantMenuEditor(
                    item: item,
                    onSave: { updated in
                        await store.saveMenuItem(updated)
                        await MainActor.run { editingItem = nil }
                    },
                    onDelete: { id in
                        await store.deleteMenuItem(id: id)
                        await MainActor.run { editingItem = nil }
                    }
                )
            }
        }
    }

    private func createNewItem() {
        editingItem = RestaurantMenuItemAdmin(
            id: UUID().uuidString,
            name: "",
            description: "",
            price: 100,
            sizes: ["單份"],
            spicinessOptions: ["不辣"],
            allergens: [],
            tags: [],
            imageUrl: nil,
            isAvailable: true,
            sortOrder: (store.menuItems.map { $0.sortOrder ?? 0 }.max() ?? 0) + 1,
            isNew: true
        )
    }
}

struct RestaurantMenuEditor: View {
    @State var item: RestaurantMenuItemAdmin
    var onSave: (RestaurantMenuItemAdmin) async -> Void
    var onDelete: ((String) async -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("名稱", text: $item.name)
                    TextField("描述", text: $item.description, axis: .vertical)
                    TextField("價格", value: $item.price, format: .number)
                        .keyboardType(.numberPad)
                    Toggle("上架", isOn: $item.isAvailable)
                    Stepper("排序 \(item.sortOrder ?? 0)", value: Binding(get: { item.sortOrder ?? 0 }, set: { item.sortOrder = $0 }), in: 0...999)
                }
                Section("選項") {
                    TagsEditor(title: "尺寸", items: $item.sizes, placeholder: "尺寸")
                    TagsEditor(title: "辣度", items: $item.spicinessOptions, placeholder: "辣度")
                    TagsEditor(title: "過敏原", items: $item.allergens, placeholder: "過敏原")
                    TagsEditor(title: "標籤", items: $item.tags, placeholder: "標籤")
                }
                if !item.isNew, onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("刪除餐點", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(item.isNew ? "新增餐點" : "編輯餐點")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        Task {
                            await onSave(item)
                            dismiss()
                        }
                    }
                    .disabled(item.name.isEmpty)
                }
            }
            .confirmationDialog(
                "確定要刪除這個餐點嗎？此操作無法復原。",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                if let onDelete {
                    Button("刪除", role: .destructive) {
                        Task {
                            await onDelete(item.id)
                            dismiss()
                        }
                    }
                }
                Button("取消", role: .cancel) { showDeleteConfirm = false }
            }
        }
    }
}

struct TagsEditor: View {
    let title: String
    @Binding var items: [String]
    let placeholder: String
    @State private var newValue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    addTag()
                } label: {
                    Text("新增")
                        .font(.footnote.weight(.semibold))
                }
            }

            if !items.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(items, id: \.self) { tag in
                        HStack(spacing: 6) {
                            Text(tag)
                                .lineLimit(1)
                            Button {
                                items.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                TextField(placeholder, text: $newValue)
                    .textFieldStyle(.roundedBorder)
                Button("加入") { addTag() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
    }

    private func addTag() {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(trimmed)
        newValue = ""
    }
}

// MARK: 報表

struct RestaurantReportsView: View {
    @EnvironmentObject var store: RestaurantAdminStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("區間", selection: $store.reportRange) {
                        ForEach(ReportRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 8)
                    .onChange(of: store.reportRange) { _, _ in
                        Task { await store.loadReport() }
                    }

                    if let report = store.report {
                        summaryCards(report)
                        if report.topItems.isEmpty {
                            ContentUnavailableView("暫無熱門品項", systemImage: "chart.bar")
                        } else {
                            Chart(report.topItems) { item in
                                BarMark(
                                    x: .value("品項", item.name),
                                    y: .value("營收", item.revenue)
                                )
                                .foregroundStyle(Color.accentColor)
                                .annotation(position: .top) {
                                    Text("$\(item.revenue)")
                                        .font(.caption)
                                }
                            }
                            .frame(height: 260)
                        }
                    } else {
                        ProgressView("載入報表中")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding()
            }
            .navigationTitle("報表")
            .task { await store.loadReport() }
            .refreshable { await store.loadReport() }
        }
    }

    private func summaryCards(_ report: RestaurantReport) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("總營收")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("$\(report.totalRevenue)")
                        .font(.title2.weight(.bold))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("訂單數")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(report.orderCount) 筆")
                        .font(.title2.weight(.bold))
                }
                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: 設定

struct RestaurantSettingsView: View {
    @EnvironmentObject var store: RestaurantAdminStore
    @State private var showReviews = false
    var onLogout: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("帳號") {
                    Button(role: .destructive) {
                        onLogout()
                    } label: {
                        Label("登出", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("餐廳評價") {
                    Button {
                        Task {
                            if store.reviews.isEmpty {
                                await store.loadOrders()
                            }
                            await store.loadReviews()
                            showReviews = true
                        }
                    } label: {
                        Label("查看買家評論", systemImage: "star.bubble")
                    }
                }

                if DemoConfig.isEnabled {
                    Section {
                        Label("Demo 模式中，顯示假資料", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
            .sheet(isPresented: $showReviews) {
                RestaurantReviewsView(
                    restaurantId: store.restaurantIdentifier,
                    restaurantName: "餐廳",
                    rating: nil,
                    initialReviews: store.reviews
                )
            }
        }
    }
}

// MARK: - Helpers

private extension RestaurantAdminAPI.OrderDTO {
    func toModel() -> RestaurantOrderAdmin {
        RestaurantOrderAdmin(
            id: id,
            code: code,
            restaurantId: restaurantId,
            status: RestaurantOrderStatusAdmin(apiValue: status),
            placedAt: placedAt,
            etaMinutes: etaMinutes,
            totalAmount: totalAmount,
            deliveryFee: deliveryFee,
            customerName: customer?.name,
            customerPhone: customer?.phone,
            items: (items ?? []).map { dto in
                RestaurantOrderItemAdmin(id: dto.id ?? UUID().uuidString, name: dto.name, size: dto.size, spiciness: dto.spiciness, quantity: dto.quantity ?? 1, price: dto.price)
            },
            notes: notes,
            deliveryLocation: deliveryLocation,
            statusHistory: statusHistory ?? [],
            riderName: riderName,
            riderPhone: riderPhone
        )
    }
}

private extension RestaurantAdminAPI.MenuItemDTO {
    func toModel() -> RestaurantMenuItemAdmin {
        RestaurantMenuItemAdmin(
            id: id,
            name: name,
            description: description,
            price: price,
            sizes: sizes,
            spicinessOptions: spicinessOptions,
            allergens: allergens,
            tags: tags,
            imageUrl: imageUrl,
            isAvailable: isAvailable,
            sortOrder: sortOrder,
            isNew: false
        )
    }
}

private extension RestaurantAdminAPI.MenuItemPayload {
    init(from item: RestaurantMenuItemAdmin) {
        self.init(
            name: item.name,
            description: item.description,
            price: item.price,
            sizes: item.sizes,
            spicinessOptions: item.spicinessOptions,
            allergens: item.allergens,
            tags: item.tags,
            imageUrl: item.imageUrl,
            isAvailable: item.isAvailable,
            sortOrder: item.sortOrder
        )
    }
}

private extension RestaurantMenuItemAdmin {
    func toPayload() -> RestaurantAdminAPI.MenuItemPayload {
        RestaurantAdminAPI.MenuItemPayload(from: self)
    }
}

private extension RestaurantAdminAPI.Report {
    func toModel() -> RestaurantReport {
        RestaurantReport(
            range: range,
            totalRevenue: totalRevenue,
            orderCount: orderCount,
            topItems: topItems.map { RestaurantTopItem(id: $0.id, name: $0.name, quantity: $0.quantity, revenue: $0.revenue) }
        )
    }
}

struct FlowLayout<Data: RandomAccessCollection, ID: Hashable, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let id: KeyPath<Data.Element, ID>
    let content: (Data.Element) -> Content

    init(items: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items
        self.id = id
        self.content = content
    }

    var body: some View {
        return GeometryReader { geo in
            var width: CGFloat = 0
            var height: CGFloat = 0
            ZStack(alignment: .topLeading) {
                ForEach(items, id: id) { item in
                    content(item)
                        .padding(4)
                        .alignmentGuide(.leading) { d in
                            if width + d.width > geo.size.width {
                                width = 0
                                height += d.height
                            }
                            let result = width
                            width += d.width
                            return result
                        }
                        .alignmentGuide(.top) { _ in
                            height
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
