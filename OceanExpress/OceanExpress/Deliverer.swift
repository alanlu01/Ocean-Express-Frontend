// SwiftUI Deliverer App Prototype
// GOGOGO-333 — 外送員端原型 (iOS 16+)
// 功能：查附近訂單、接單、取餐、更新進度、確認交付、查看評價
// 特色：強調定位與即時資訊同步，支援多筆配送任務
// 注意：此檔為教學性原型，服務端以 Mock 實作，可直接編譯執行以預覽
// 隱私權設定：請在 Info.plist 加入 NSLocationWhenInUseUsageDescription 文字說明

import SwiftUI
import Combine
import MapKit
import CoreLocation
import CoreLocationUI
import Charts
import UIKit
import UserNotifications

// MARK: - Domain Models

enum OrderStatus: String, Codable, CaseIterable, Identifiable {
    case available // 待接
    case assigned  // 已接單，前往取餐
    case enRouteToPickup // 導航至商家
    case pickedUp // 已取餐
    case delivering // 配送中（前往顧客）
    case delivered // 已送達
    case cancelled // 已取消

    var id: String { rawValue }

    var title: String {
        switch self {
        case .available: return "可接單"
        case .assigned: return "已接單"
        case .enRouteToPickup: return "前往取餐"
        case .pickedUp: return "已取餐"
        case .delivering: return "配送中"
        case .delivered: return "已送達"
        case .cancelled: return "已取消"
        }
    }

    var stepIndex: Int {
        switch self {
        case .available: return 0
        case .assigned: return 1
        case .enRouteToPickup: return 2
        case .pickedUp: return 3
        case .delivering: return 4
        case .delivered: return 5
        case .cancelled: return -1
        }
    }
}

enum MerchantPrepStatus: String, Codable, CaseIterable, Identifiable {
    case preparing      // 商家準備中
    case ready          // 可取餐
    case delayed        // 延遲
    case cancelled      // 已取消 / 無法供應

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preparing: return "商家準備中"
        case .ready:     return "可取餐"
        case .delayed:   return "出餐延遲"
        case .cancelled: return "無法供應"
        }
    }
}

extension MerchantPrepStatus {
    var color: Color {
        switch self {
        case .preparing: return .orange
        case .ready:     return .green
        case .delayed:   return .red
        case .cancelled: return .gray
        }
    }

    var systemImage: String {
        switch self {
        case .preparing: return "hourglass"
        case .ready:     return "checkmark.seal.fill"
        case .delayed:   return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.octagon.fill"
        }
    }
}

struct Place: Hashable {
    var name: String
    var coordinate: CLLocationCoordinate2D
    static func == (lhs: Place, rhs: Place) -> Bool {
        lhs.name == rhs.name &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }
}

struct Customer: Hashable {
    var displayName: String
    var phone: String
}

struct Order: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var code: String // 顯示編號用
    var fee: Double // 外送費
    var distanceKm: Double // 粗估距離（列表展示）
    var etaMinutes: Int // 粗估時間（列表展示）
    var createdAt: Date = Date()

    var merchant: Place
    var customer: Customer
    var dropoff: Place

    var notes: String
    var canPickup: Bool
    var status: OrderStatus

    var routePolyline: MKPolyline? = nil

    /// 進行中任務：已接單後才算 active（排除 available / delivered / cancelled）
    var isActive: Bool {
        status != .available && status != .delivered && status != .cancelled
    }

    static func == (lhs: Order, rhs: Order) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}


extension Order {
    /// 目前先以 canPickup 對應商家狀態：false = 準備中、true = 可取餐。
    /// 未來若後端提供更細緻的商家狀態，可在這裡改成讀取 API 的欄位。
    var merchantPrepStatus: MerchantPrepStatus {
        return canPickup ? .ready : .preparing
    }
}
@MainActor
final class MockOrderService: OrderServiceProtocol {
    private var orders: [Order]

    init() {
        self.orders = MockOrderService.sampleOrders()
    }

    private static func sampleOrders() -> [Order] {
        let merchant1 = Place(
            name: "小林便當 - 公館店",
            coordinate: CLLocationCoordinate2D(latitude: 25.0143, longitude: 121.5323)
        )
        let drop1 = Place(
            name: "台大電機系館",
            coordinate: CLLocationCoordinate2D(latitude: 25.0172, longitude: 121.5395)
        )
        let cust1 = Customer(displayName: "王先生", phone: "0912-345-678")

        let merchant2 = Place(
            name: "珍煮丹 - 羅斯福店",
            coordinate: CLLocationCoordinate2D(latitude: 25.0211, longitude: 121.5280)
        )
        let drop2 = Place(
            name: "公館捷運站出口2",
            coordinate: CLLocationCoordinate2D(latitude: 25.0149, longitude: 121.5331)
        )
        let cust2 = Customer(displayName: "林小姐", phone: "0988-555-666")

        let now = Date()

        var orders: [Order] = []

        // 產生約 20 筆假資料：大多數為已送達少數為可接單，時間往回推
        for i in 0..<20 {
            let isFirstMerchant = i % 2 == 0
            let merchant = isFirstMerchant ? merchant1 : merchant2
            let drop = isFirstMerchant ? drop1 : drop2
            let customer = isFirstMerchant ? cust1 : cust2

            // 最近的幾筆維持為可接單，其餘視為已完成訂單
            let status: OrderStatus = (i < 3) ? .available : .delivered

            // 每筆間隔 45 分鐘，往過去推，讓歷史、收益有跨日資料
            let createdAt = now.addingTimeInterval(TimeInterval(-45 * 60 * (i + 1)))

            let codePrefix = isFirstMerchant ? "A" : "B"
            let code = String(format: "%@%02d-%03d", codePrefix, i, 100 + i)

            let fee: Double = 60 + Double((i % 5) * 10) // 60, 70, 80, 90, 100 循環
            let distance: Double = 0.6 + Double(i % 4) * 0.4
            let eta: Int = 8 + (i % 5) * 2

            let notes = isFirstMerchant ? "多加辣，飲料去冰" : "請先聯繫再上樓"
            let canPickup = (status == .available) ? (i % 2 == 0) : true

            let order = Order(
                code: code,
                fee: fee,
                distanceKm: distance,
                etaMinutes: eta,
                createdAt: createdAt,
                merchant: merchant,
                customer: customer,
                dropoff: drop,
                notes: notes,
                canPickup: canPickup,
                status: status
            )
            orders.append(order)
        }

        return orders
    }

    func streamAvailableOrders() -> AsyncStream<[Order]> {
        AsyncStream { continuation in
            let available = orders.filter { $0.status == .available }
            continuation.yield(available)
        }
    }

    func fetchActiveTasks() async throws -> [Order] {
        // 回傳全部訂單，由 AppState 根據 isActive 拆成進行中與歷史
        return orders
    }

    func accept(order: Order) async throws -> Order {
        guard let idx = orders.firstIndex(where: { $0.id == order.id }) else {
            return order
        }
        orders[idx].status = .assigned
        return orders[idx]
    }

    func updateStatus(order: Order, to status: OrderStatus) async throws -> Order {
        if let idx = orders.firstIndex(where: { $0.id == order.id }) {
            orders[idx].status = status
            return orders[idx]
        }
        var updated = order
        updated.status = status
        return updated
    }

    func reportIncident(order: Order, note: String) async throws {
        print("Mock incident for order \(order.id): \(note)")
    }
}


struct DailyEarning: Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var amount: Double
}

// MARK: - Location Manager

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var userLocation: CLLocation?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    func request() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if self.authorizationStatus == .authorizedWhenInUse || self.authorizationStatus == .authorizedAlways {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.userLocation = locations.last
        }
    }
}

// MARK: - Services (API + Mock)

protocol OrderServiceProtocol {
    func streamAvailableOrders() -> AsyncStream<[Order]>
    func fetchActiveTasks() async throws -> [Order]
    func accept(order: Order) async throws -> Order
    func updateStatus(order: Order, to status: OrderStatus) async throws -> Order
    func reportIncident(order: Order, note: String) async throws
}

@MainActor
final class NetworkOrderService: OrderServiceProtocol {
    private let tokenProvider: () -> String?
    private let pollInterval: Duration = .seconds(6)

    init(tokenProvider: @escaping () -> String?) {
        self.tokenProvider = tokenProvider
    }

    func streamAvailableOrders() -> AsyncStream<[Order]> {
        let tokenProvider = self.tokenProvider
        return AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    do {
                        guard let token = tokenProvider(), !token.isEmpty else {
                            continuation.yield([])
                            try? await Task.sleep(for: pollInterval)
                            continue
                        }
                        let list = try await DelivererAPI.fetchAvailable(token: token)
                        continuation.yield(list.map { $0.toOrder() })
                    } catch {
                        print("Available orders fetch error:", error)
                    }
                    try? await Task.sleep(for: pollInterval)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func fetchActiveTasks() async throws -> [Order] {
        guard let token = tokenProvider(), !token.isEmpty else { return [] }
        let list = try await DelivererAPI.fetchActive(token: token)
        return list.map { $0.toOrder() }
    }

    func accept(order: Order) async throws -> Order {
        let token = tokenProvider()
        if let task = try await DelivererAPI.accept(id: order.id, token: token) {
            return task.toOrder(overrides: order)
        }
        var updated = order
        updated.status = .assigned
        return updated
    }

    func updateStatus(order: Order, to status: OrderStatus) async throws -> Order {
        let token = tokenProvider()
        if let task = try await DelivererAPI.updateStatus(id: order.id, status: status.rawValue, token: token) {
            return task.toOrder(overrides: order)
        }
        var updated = order
        updated.status = status
        return updated
    }

    func reportIncident(order: Order, note: String) async throws {
        // TODO: 改成真正呼叫後端 `POST /delivery/{id}/incident`
        // 目前先簡單印出，避免中斷流程
        print("Report incident for order \(order.id): \(note)")
    }
}


private let defaultCoordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)

extension DelivererAPI.Stop {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat ?? 0, longitude: lng ?? 0)
    }

    func toPlace() -> Place {
        Place(name: name, coordinate: coordinate)
    }

    func toCustomer() -> Customer {
        Customer(displayName: name, phone: phone ?? "")
    }
}

extension DelivererAPI.Task {
    func toOrder(overrides existing: Order? = nil) -> Order {
        var base = existing ?? Order(
            code: code ?? (id ?? "N/A"),
            fee: fee.map(Double.init) ?? 0,
            distanceKm: distanceKm ?? 0,
            etaMinutes: etaMinutes ?? 0,
            merchant: merchant?.toPlace() ?? Place(name: "未知店家", coordinate: defaultCoordinate),
            customer: customer?.toCustomer() ?? Customer(displayName: "顧客", phone: ""),
            dropoff: (dropoff ?? customer)?.toPlace() ?? Place(name: "送達地點", coordinate: defaultCoordinate),
            notes: notes ?? "",
            canPickup: canPickup ?? true,
            status: OrderStatus(rawValue: status ?? "") ?? .available
        )
        base.id = id ?? existing?.id ?? UUID().uuidString
        base.code = code ?? base.code
        base.fee = fee.map(Double.init) ?? base.fee
        base.distanceKm = distanceKm ?? base.distanceKm
        base.etaMinutes = etaMinutes ?? base.etaMinutes
        base.notes = notes ?? base.notes
        base.canPickup = canPickup ?? base.canPickup
        if let createdAt { base.createdAt = createdAt }
        if let newStatus = OrderStatus(rawValue: status ?? "") {
            base.status = newStatus
        }
        if let merchantPlace = merchant?.toPlace() {
            base.merchant = merchantPlace
        }
        if let customerStop = customer {
            base.customer = customerStop.toCustomer()
            if dropoff == nil {
                base.dropoff = customerStop.toPlace()
            }
        }
        if let dropStop = dropoff {
            base.dropoff = dropStop.toPlace()
        }
        return base
    }
}

// MARK: - App State (ViewModel)

@MainActor
final class AppState: ObservableObject {
    @Published var availableOrders: [Order] = []
    @Published var activeTasks: [Order] = [] // 支援多筆任務
    @Published var history: [Order] = []
    @Published var dailyEarnings: [DailyEarning] = []
    @Published var selectedOrder: Order? = nil
    @Published var enableNewOrderNotifications: Bool = true

    private let service: OrderServiceProtocol
    private var streamTask: Task<Void, Never>? = nil
    private var lastAvailableOrderIDs: Set<String> = []

    init(service: any OrderServiceProtocol) {
        self.service = service
        self.dailyEarnings = []
        startStreaming()
        Task { await refreshTasks() }
    }

    deinit { streamTask?.cancel() }

    func startStreaming() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            for await list in service.streamAvailableOrders() {
                let available = list.filter { $0.status == .available }
                let currentIDs = Set(available.map { $0.id })
                let newlyAdded = available.filter { !self.lastAvailableOrderIDs.contains($0.id) }
                self.lastAvailableOrderIDs = currentIDs
                await MainActor.run {
                    self.availableOrders = available
                    newlyAdded.forEach { order in
                        if self.enableNewOrderNotifications {
                            NotificationManager.shared.notifyNewOrder(order)
                        }
                    }
                }
            }
        }
    }

    func accept(_ order: Order) async {
        do {
            let accepted = try await service.accept(order: order)
            // 從 available 移除，加入 active
            availableOrders.removeAll { $0.id == order.id }
            activeTasks.append(accepted)
            selectedOrder = accepted
            await refreshTasks()
        } catch {
            print("Accept error: \(error)")
        }
    }

    func updateStatus(for order: Order, to status: OrderStatus) async {
        do {
            let updated = try await service.updateStatus(order: order, to: status)
            // 先在目前 activeTasks 中樂觀更新，讓列表上的狀態文字立即變更
            if let idx = activeTasks.firstIndex(where: { $0.id == order.id }) {
                activeTasks[idx] = updated
            }
            // 再由 refreshTasks() 根據最新 orders 決定 activeTasks / history / dailyEarnings
            await refreshTasks()
            NotificationManager.shared.notifyStatusChanged(updated)
        } catch {
            print("Status update error: \(error)")
        }
    }

    func reportIncident(for order: Order, note: String) async {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await service.reportIncident(order: order, note: trimmed)
            // 回報後重新同步，確保進行中／歷史頁面資料一致
            await refreshTasks()
        } catch {
            print("Report incident error:", error)
        }
    }

    func refreshTasks() async {
        do {
            let tasks = try await service.fetchActiveTasks()
            let actives = tasks.filter { $0.isActive }
            let histories = tasks.filter { !$0.isActive }
            activeTasks = actives
            history = histories.sorted { $0.createdAt < $1.createdAt }
            dailyEarnings = AppState.computeEarnings(from: histories)
        } catch {
            print("Fetch tasks error:", error)
        }
    }

    private static func computeEarnings(from orders: [Order]) -> [DailyEarning] {
        var accumulator: [Date: Int] = [:]
        let cal = Calendar.current

        // 收益邏輯：每單固定 20 元，當日收益 = 20 * 當日完成單數
        orders.forEach { order in
            let day = cal.startOfDay(for: order.createdAt)
            accumulator[day, default: 0] += 1
        }

        return accumulator
            .map { (day, count) in
                DailyEarning(date: day, amount: Double(count * 20))
            }
            .sorted { $0.date < $1.date }
    }
}

// MARK: - Views

@MainActor struct DelivererModule: View {
    @StateObject private var appState: AppState
    @StateObject private var loc: LocationManager
    var onLogout: () -> Void
    var onSwitchRole: () -> Void

    init(onLogout: @escaping () -> Void = {}, onSwitchRole: @escaping () -> Void = {}) {
        let service: OrderServiceProtocol = MockOrderService()
        _appState = StateObject(wrappedValue: AppState(service: service))
        _loc = StateObject(wrappedValue: LocationManager())
        self.onLogout = onLogout
        self.onSwitchRole = onSwitchRole
    }

    var body: some View {
        RootView(onLogout: onLogout, onSwitchRole: onSwitchRole)
            .environmentObject(appState)
            .environmentObject(loc)
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocationManager
    var onLogout: () -> Void
    var onSwitchRole: () -> Void
    var body: some View {
        TabView {
            TaskListView()
                .tabItem { Label("任務清單", systemImage: "list.bullet.rectangle") }

            ActiveTasksView()
                .tabItem { Label("進行中", systemImage: "bolt.car") }

            HistoryView()
                .tabItem { Label("歷史紀錄", systemImage: "clock.arrow.circlepath") }

            DelivererSettingsView(onLogout: onLogout, onSwitchRole: onSwitchRole)
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
        .onAppear {
            loc.request()
            NotificationManager.shared.requestAuthorization()
        }
        .task {
            await app.refreshTasks()
        }
    }
}

// MARK: 任務清單頁（可接訂單）

struct TaskListView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("可接訂單") {
                    ForEach(app.availableOrders) { order in
                        OrderCard(order: order, actionTitle: "接單") {
                            Task { await app.accept(order) }
                        }
                    }
                }
            }
            .navigationTitle("附近待接訂單")
        }
    }
}

struct OrderCard: View {
    let order: Order
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(order.code)")
                    .font(.headline)
                Spacer()
                Label("$\(Int(order.fee))", systemImage: "dollarsign.circle")
                    .fontWeight(.semibold)
            }
            HStack(spacing: 16) {
                Label("\(String(format: "%.1f", order.distanceKm)) km", systemImage: "location")
                Label("\(order.etaMinutes) 分", systemImage: "clock")
                Label(order.merchantPrepStatus.title, systemImage: order.canPickup ? "checkmark.seal" : "hourglass")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "house")
                VStack(alignment: .leading) {
                    Text(order.merchant.name).font(.subheadline)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person")
                VStack(alignment: .leading) {
                    Text(order.customer.displayName).font(.subheadline)
                    Text(order.dropoff.name).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !order.notes.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "note.text")
                    Text("備註：\(order.notes)")
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }
                .padding(8)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if let actionTitle, let action {
                BigActionButton(title: actionTitle, systemImage: "hand.tap.fill", action: action, size: .regular)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: 進行中（多任務） & 訂單詳情頁 + 狀態更新頁

struct ActiveTasksView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocationManager

    var body: some View {
        NavigationStack {
            Group {
                if app.activeTasks.isEmpty {
                    ContentUnavailableView("尚無進行中任務", systemImage: "tray")
                } else {
                    List(app.activeTasks) { order in
                        VStack(alignment: .leading, spacing: 8) {
                            NavigationLink(value: order) {
                                OrderProgressRow(order: order)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("進行中任務")
            .navigationDestination(for: Order.self) { order in
                OrderDetailView(order: order)
                    .environmentObject(app)
                    .environmentObject(loc)
            }
        }
    }
}

struct OrderProgressRow: View {
    @EnvironmentObject var app: AppState
    let order: Order

    /// 讓列顯示的是最新的訂單狀態，而不是初始傳入的快照
    private var currentOrder: Order {
        app.activeTasks.first(where: { $0.id == order.id }) ?? order
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("#\(currentOrder.code)").font(.headline)
                Spacer()
                Text(currentOrder.status.title)
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
            ProgressView(value: progressValue)
            HStack(spacing: 16) {
                Label("$\(Int(currentOrder.fee))", systemImage: "dollarsign")
                Label("\(String(format: "%.1f", currentOrder.distanceKm)) km", systemImage: "location")
                Label("\(currentOrder.etaMinutes) 分", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var progressValue: Double {
        let idx = currentOrder.status.stepIndex
        return max(0, min(1, Double(idx) / 5.0))
    }
}

struct StatusQuickActions: View {
    @EnvironmentObject var app: AppState
    let order: Order
    var body: some View {
        HStack(spacing: 8) {
            Button("前往取餐") { Task { await app.updateStatus(for: order, to: .enRouteToPickup) } }
            Button("已取餐") { Task { await app.updateStatus(for: order, to: .pickedUp) } }
            Button("配送中") { Task { await app.updateStatus(for: order, to: .delivering) } }
            Button("已送達") { Task { await app.updateStatus(for: order, to: .delivered) } }
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }
}

struct OrderDetailView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocationManager
    @Environment(\.dismiss) private var dismiss
    let order: Order
    @State private var region: MKCoordinateRegion
    @State private var showUpdateSheet = false
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var routeDistanceMeters: CLLocationDistance = 0
    @State private var routeETASecs: TimeInterval = 0

    private var liveOrder: Order {
        app.activeTasks.first(where: { $0.id == order.id }) ?? order
    }

    private func computeRoute() {
        // 優先使用後端回傳的路線座標（Order.routePolyline）
        if let polyline = liveOrder.routePolyline {
            let coords = polyline.coordinates
            guard !coords.isEmpty else { return }
            routeCoords = coords
            routeDistanceMeters = polyline.length
            // 若後端已估算 ETA，直接用訂單上的 etaMinutes；否則保留為 0
            routeETASecs = liveOrder.etaMinutes > 0 ? TimeInterval(liveOrder.etaMinutes * 60) : 0

            // 依據整條路線調整顯示範圍
            let rect = polyline.boundingMapRect
            let regionRect = MKCoordinateRegion(rect)
            region = regionRect
            return
        }

        // 若尚未有後端路線，退回使用 Apple Maps 規劃路線
        let startCoord: CLLocationCoordinate2D
        let endCoord: CLLocationCoordinate2D
        if liveOrder.status == .enRouteToPickup, let u = loc.userLocation?.coordinate {
            startCoord = u
            endCoord = liveOrder.merchant.coordinate
        } else if liveOrder.status == .delivering || liveOrder.status == .pickedUp {
            startCoord = liveOrder.merchant.coordinate
            endCoord = liveOrder.dropoff.coordinate
        } else {
            startCoord = liveOrder.merchant.coordinate
            endCoord = liveOrder.dropoff.coordinate
        }
        let req = MKDirections.Request()
        req.source = MKMapItem(location: CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude), address: nil)
        req.destination = MKMapItem(location: CLLocation(latitude: endCoord.latitude, longitude: endCoord.longitude), address: nil)
        req.transportType = .automobile
        let dir = MKDirections(request: req)
        dir.calculate { resp, _ in
            guard let route = resp?.routes.first else { return }
            routeCoords = route.polyline.coordinates
            routeDistanceMeters = route.distance
            routeETASecs = route.expectedTravelTime
            // 調整顯示範圍
            let rect = route.polyline.boundingMapRect
            let regionRect = MKCoordinateRegion(rect)
            region = regionRect
        }
    }

    /// 一鍵撥打給顧客（使用 tel://）
    private func callCustomer() {
        let raw = liveOrder.customer.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        UIApplication.shared.open(url)
    }

    init(order: Order) {
        self.order = order
        _region = State(initialValue: MKCoordinateRegion(center: order.merchant.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
    }

    var body: some View {
        ScrollView {
            Map(position: .constant(.region(region))) {
                if let _ = loc.userLocation {
                    UserAnnotation()
                        .annotationTitles(.automatic)
                }
                // 標註商家與顧客
                Annotation("取餐：\(liveOrder.merchant.name)", coordinate: liveOrder.merchant.coordinate) {
                    Label("取餐", systemImage: "bag")
                        .padding(8).background(.thinMaterial).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Annotation("送達：\(liveOrder.customer.displayName)", coordinate: liveOrder.dropoff.coordinate) {
                    Label("送達", systemImage: "mappin.and.ellipse")
                        .padding(8).background(.thinMaterial).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if !routeCoords.isEmpty {
                    MapPolyline(coordinates: routeCoords)
                        .stroke(.blue, lineWidth: 4)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .padding(.top)

            VStack(alignment: .leading, spacing: 12) {
                InfoRow(title: "顧客", value: "\(liveOrder.customer.displayName)  (☎︎ \(liveOrder.customer.phone))")
                InfoRow(title: "送達地點", value: liveOrder.dropoff.name)
                InfoRow(title: "商家", value: liveOrder.merchant.name)
                InfoRow(title: "備註", value: liveOrder.notes.isEmpty ? "無" : liveOrder.notes)
                HStack(alignment: .top) {
                    Text("取餐狀態")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Label(liveOrder.merchantPrepStatus.title, systemImage: liveOrder.merchantPrepStatus.systemImage)
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(.white)
                        .background(liveOrder.merchantPrepStatus.color)
                        .clipShape(Capsule())
                    Spacer()
                }
                Divider()
                HStack(spacing: 16) {
                    Label("$\(Int(liveOrder.fee))", systemImage: "dollarsign")
                    Label("\(String(format: "%.1f", liveOrder.distanceKm)) km", systemImage: "location")
                    Label("\(liveOrder.etaMinutes) 分", systemImage: "clock")
                }.foregroundStyle(.secondary)
                if routeDistanceMeters > 0 {
                    HStack(spacing: 16) {
                        Label(String(format: "路線距離 %.1f 公里", routeDistanceMeters / 1000.0), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        Label(String(format: "預估 %.0f 分鐘", routeETASecs / 60.0), systemImage: "timer")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .navigationTitle("訂單詳情 #\(liveOrder.code)")
        .sheet(isPresented: $showUpdateSheet) {
            StatusUpdateSheet(order: liveOrder)
                .presentationDetents([.height(360), .medium])
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button {
                    callCustomer()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.fill")
                        Text("打給買家")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    showUpdateSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                        Text("更新訂單")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
        }
        .onAppear { computeRoute() }
        .onChange(of: app.activeTasks) { _, _ in
            // 若此訂單已不再是進行中（例如已送達），自動返回列表
            if !liveOrder.isActive {
                dismiss()
            } else {
                computeRoute()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in computeRoute() }
    }
}

struct InfoRow: View {
    var title: String
    var value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.subheadline)
            Spacer()
        }
    }
}

struct StatusUpdateSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let order: Order
    @State private var incidentNote: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("更新配送狀態").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    BigActionButton(title: "前往取餐", systemImage: "figure.walk") {
                        Task { await app.updateStatus(for: order, to: .enRouteToPickup); dismiss() }
                    }
                    BigActionButton(title: "已取餐", systemImage: "bag.fill") {
                        Task { await app.updateStatus(for: order, to: .pickedUp); dismiss() }
                    }
                }
                GridRow {
                    BigActionButton(title: "配送中", systemImage: "bolt.car.fill") {
                        Task { await app.updateStatus(for: order, to: .delivering); dismiss() }
                    }
                    BigActionButton(title: "已送達", systemImage: "checkmark.seal.fill") {
                        Task { await app.updateStatus(for: order, to: .delivered); dismiss() }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider()
            Text("突發狀況回報（可選）").font(.subheadline)
            TextField("例如：飲料灑出、顧客臨時改地址…", text: $incidentNote, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("回報狀況") {
                    let trimmed = incidentNote.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        dismiss()
                        return
                    }
                    Task {
                        await app.reportIncident(for: order, note: trimmed)
                        incidentNote = ""
                        dismiss()
                    }
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("取消") { dismiss() }
            }
        }
        .padding()
    }
}

struct BigActionButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void
    var size: ControlSize = .large
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(size)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: 導航地圖頁（即時定位 + 路線更新）

struct NavigationMapView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var loc: LocationManager

    @State private var camPos: MapCameraPosition = .automatic
    @State private var selected: Order? = nil

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $camPos, selection: $selected) {
                if loc.userLocation != nil {
                    UserAnnotation()
                        .annotationTitles(.automatic)
                }

                ForEach(app.activeTasks) { order in
                    Annotation("#\(order.code)", coordinate: order.merchant.coordinate) {
                        Label("取餐", systemImage: "bag")
                            .padding(6).background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }.tag(order as Order?)

                    Annotation("#\(order.code)", coordinate: order.dropoff.coordinate) {
                        Label("送達", systemImage: "mappin.and.ellipse")
                            .padding(6).background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .mapControls {
                MapCompass()
                MapPitchToggle()
                MapScaleView()
            }
            .ignoresSafeArea(edges: .top)
            .frame(maxHeight: 360)

            if app.activeTasks.isEmpty {
                ContentUnavailableView("尚無任務", systemImage: "map")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("進行中任務") {
                        ForEach(app.activeTasks) { order in
                            OrderCard(order: order, actionTitle: "更新狀態") {
                                // 快速更新入口
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("導航與定位")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                LocationButton(.currentLocation) {
                    loc.request()
                }
                .labelStyle(.iconOnly)
                .symbolVariant(.fill)
                .foregroundStyle(.white)
                .tint(.blue)
            }
        }
    }
}

// MARK: 歷史紀錄頁（含收益統計）

enum EarningsFilter: String, CaseIterable, Identifiable {
    case year
    case month
    case week
    case day

    var id: String { rawValue }

    var title: String {
        switch self {
        case .year:  return "今年"
        case .month: return "本月"
        case .week:  return "本週"
        case .day:   return "今日"
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var app: AppState
    @State private var selectedFilter: EarningsFilter = .month

    private var filteredEarnings: [DailyEarning] {
        let cal = Calendar.current
        let now = Date()
        return app.dailyEarnings.filter { item in
            let date = item.date
            switch selectedFilter {
            case .year:
                return cal.isDate(date, equalTo: now, toGranularity: .year)
            case .month:
                return cal.isDate(date, equalTo: now, toGranularity: .month)
            case .week:
                return cal.isDate(date, equalTo: now, toGranularity: .weekOfYear)
            case .day:
                return cal.isDate(date, equalTo: now, toGranularity: .day)
            }
        }
    }

    private var filteredHistory: [Order] {
        let cal = Calendar.current
        let now = Date()
        return app.history.filter { order in
            let date = order.createdAt
            switch selectedFilter {
            case .year:
                return cal.isDate(date, equalTo: now, toGranularity: .year)
            case .month:
                return cal.isDate(date, equalTo: now, toGranularity: .month)
            case .week:
                return cal.isDate(date, equalTo: now, toGranularity: .weekOfYear)
            case .day:
                return cal.isDate(date, equalTo: now, toGranularity: .day)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                HStack {
                    Text("收益統計").font(.headline)
                    Spacer()
                    Picker("區間", selection: $selectedFilter) {
                        ForEach(EarningsFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
                .padding(.horizontal)

                Chart(filteredEarnings) { item in
                    LineMark(
                        x: .value("日期", item.date),
                        y: .value("金額", item.amount)
                    )
                    PointMark(
                        x: .value("日期", item.date),
                        y: .value("金額", item.amount)
                    )
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 220)
                .padding(.horizontal)

                List {
                    Section("已完成訂單") {
                        ForEach(filteredHistory) { order in
                            NavigationLink(value: order) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("#\(order.code)").font(.headline)
                                        Spacer()
                                        Text("$\(Int(order.fee))")
                                    }
                                    Text(order.dropoff.name).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("歷史紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Order.self) { order in
                CompletedOrderDetailView(order: order)
            }
        }
    }
}

struct CompletedOrderDetailView: View {
    let order: Order

    private var formattedDate: String {
        DateFormatter.localizedString(from: order.createdAt, dateStyle: .medium, timeStyle: .short)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("#\(order.code)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Text(order.status.title)
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                .padding(.bottom, 4)

                InfoRow(title: "完成時間", value: formattedDate)
                // 歷史訂單僅顯示顧客姓名，不再顯示電話，避免誤以為可撥打
                InfoRow(title: "顧客", value: order.customer.displayName)
                InfoRow(title: "送達地點", value: order.dropoff.name)
                InfoRow(title: "商家", value: order.merchant.name)
                InfoRow(title: "備註", value: order.notes.isEmpty ? "無" : order.notes)

                Divider()
                    .padding(.vertical, 4)

                HStack(spacing: 16) {
                    Label("$\(Int(order.fee))", systemImage: "dollarsign")
                    Label("\(String(format: "%.1f", order.distanceKm)) km", systemImage: "location")
                    Label("\(order.etaMinutes) 分", systemImage: "clock")
                }
                .foregroundStyle(.secondary)
                .font(.subheadline)

                Spacer(minLength: 12)
            }
            .padding()
        }
        .navigationTitle("訂單回顧")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DelivererSettingsView: View {
    @EnvironmentObject var app: AppState
    var onLogout: () -> Void
    var onSwitchRole: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("帳號") {
                    Button {
                        onSwitchRole()
                    } label: {
                        Label("切換成買家", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button(role: .destructive) {
                        onLogout()
                    } label: {
                        Label("登出", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("偏好設定") {
                    Toggle(isOn: $app.enableNewOrderNotifications) {
                        Label("接單通知", systemImage: "bell.badge.fill")
                    }
                    .tint(.accentColor)
                }

                Section("關於") {
                    HStack {
                        Label("版本", systemImage: "info.circle")
                        Spacer()
                        Text("0.1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
        }
    }
}



@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification auth error: \(error)")
            } else {
                print("Notification permission granted: \(granted)")
            }
        }
    }

    func notifyNewOrder(_ order: Order) {
        let content = UNMutableNotificationContent()
        content.title = "新任務可接單"
        content.body = "#\(order.code) $\(Int(order.fee)) · 約 \(String(format: "%.1f", order.distanceKm)) km / \(order.etaMinutes) 分"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "new-order-\(order.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func notifyStatusChanged(_ order: Order) {
        let content = UNMutableNotificationContent()
        content.title = "任務狀態更新：\(order.status.title)"
        content.body = "#\(order.code) 目前狀態為 \(order.status.title)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "status-\(order.id)-\(order.status.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

// MARK: - Utilities

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: Int(pointCount))
        getCoordinates(&coords, range: NSRange(location: 0, length: Int(pointCount)))
        return coords
    }

    /// 依照 polyline 上的所有點，估算總長度（公尺）
    var length: CLLocationDistance {
        let pts = points()
        let n = Int(pointCount)
        guard n > 1 else { return 0 }
        var dist: CLLocationDistance = 0
        for i in 0..<(n - 1) {
            let p1 = pts[i]
            let p2 = pts[i + 1]
            dist += p1.distance(to: p2)
        }
        return dist
    }
}
