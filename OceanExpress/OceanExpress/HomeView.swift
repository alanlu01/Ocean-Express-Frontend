import SwiftUI
import Combine
import UserNotifications

enum HomeTab: Hashable {
    case restaurants
    case cart
    case status
    case settings
}

struct HomeView: View {
    @EnvironmentObject private var cart: Cart
    @State private var selectedTab: HomeTab = .restaurants
    @StateObject private var orderStore = CustomerOrderStore()
    var onLogout: () -> Void = {}
    var onSwitchRole: () -> Void = {}

    var body: some View {
        TabView(selection: $selectedTab) {
            RestaurantListView()
                .tabItem { Label("餐廳列表", systemImage: "fork.knife") }
                .tag(HomeTab.restaurants)

            CartView(selectedTab: $selectedTab)
                .environmentObject(orderStore)
                .tabItem { Label("購物車", systemImage: "cart") }
                .tag(HomeTab.cart)

            OrderStatusView()
                .environmentObject(orderStore)
                .tabItem { Label("訂單狀態", systemImage: "clock.arrow.circlepath") }
                .tag(HomeTab.status)

            SettingsView(onLogout: onLogout, onSwitchRole: onSwitchRole)
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(HomeTab.settings)
        }
        .tint(.accentColor)
    }
}

struct RestaurantListView: View {
    @State private var restaurants: [RestaurantListItem] = Self.sample
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(restaurants) { r in
                        NavigationLink(destination: RestaurantMenuView(restaurantId: r.id, restaurantName: r.name)) {
                            RestaurantCard(item: r)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("餐廳列表")
            .task {
                await loadRestaurants()
            }
        }
    }

    private func loadRestaurants() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if DemoConfig.isEnabled { return } // demo 保留樣本
        do {
            let data = try await RestaurantAPI.fetchRestaurants()
            restaurants = data.map { RestaurantListItem(id: $0.id, name: $0.name, imageURL: URL(string: $0.imageUrl ?? "")) }
        } catch {
            // 失敗時保留樣本
        }
    }

    fileprivate static let sample: [RestaurantListItem] = [
        .init(id: "rest-001", name: "Marina Burger", imageURL: URL(string: "https://images.unsplash.com/photo-1550547660-d9450f859349?w=1200&q=80")),
        .init(id: "rest-002", name: "Harbor Coffee", imageURL: URL(string: "https://images.unsplash.com/photo-1504754524776-8f4f37790ca0?w=1200&q=80")),
        .init(id: "rest-003", name: "Green Bowl", imageURL: URL(string: "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=1200&q=80"))
    ]
}

fileprivate struct RestaurantListItem: Identifiable, Hashable {
    let id: String
    let name: String
    let imageURL: URL?
}

fileprivate struct RestaurantCard: View {
    let item: RestaurantListItem

    // 固定高度避免使用已棄用的 UIScreen.main
    private let cardHeight: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: item.imageURL) { phase in
                switch phase {
                case .success(let img):
                    img
                        .resizable()
                        .scaledToFill()
                        .frame(height: cardHeight)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                default:
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: cardHeight)
                        .overlay(
                            Image(systemName: "photo")
                                .imageScale(.large)
                                .foregroundColor(.secondary)
                        )
                }
            }

            Text(item.name)
                .font(.headline)
                .padding(.horizontal, 4)
        }
    }
}

fileprivate struct RestaurantMenuView: View {
    let restaurantId: String
    let restaurantName: String
    @State private var items: [MenuItem] = AppModels.SampleMenu.items
    @State private var isLoading = false

    var body: some View {
        List {
            Section(header: Text("Menu")) {
                ForEach(items) { item in
                    NavigationLink(destination: MenuItemDetailView(item: item, restaurantId: restaurantId, restaurantName: restaurantName)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.headline)
                            HStack(spacing: 8) {
                                Text(String(format: "$%.2f", item.price))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                if let firstSize = item.sizes.first {
                                    Text(firstSize)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(restaurantName)
        .task { await loadMenu() }
    }

    private func loadMenu() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if DemoConfig.isEnabled { return }
        do {
            print("🚀 RestaurantMenuView: fetching menu for \(restaurantId)")
            let data = try await RestaurantAPI.fetchMenu(restaurantId: restaurantId)
            print("✅ RestaurantMenuView: received \(data.count) items for \(restaurantId)")
            items = data.map { $0.toMenuItem() }
        } catch {
            print("⚠️ RestaurantMenuView.loadMenu error:", error)
            // 保留樣本
        }
    }
}

fileprivate struct CartView: View {
    @EnvironmentObject private var cart: Cart
    @EnvironmentObject private var orderStore: CustomerOrderStore
    @Binding var selectedTab: HomeTab

    var body: some View {
        NavigationStack {
            List {
                if cart.items.isEmpty {
                    Text("Your cart is empty")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(cart.items) { ci in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ci.item.name)
                                    .font(.body)
                                Text("\(ci.size) • \(ci.spiciness)\(ci.addDrink ? " • +Drink" : "")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("x\(ci.quantity)")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                            Text(String(format: "$%.2f", ci.lineTotal))
                                .font(.subheadline)
                                .monospacedDigit()
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let id = cart.items[index].id
                            cart.remove(id: id)
                        }
                    }

                    Section {
                        HStack {
                            Text("Subtotal")
                            Spacer()
                            Text(String(format: "$%.2f", cart.subtotal))
                                .bold()
                                .monospacedDigit()
                        }
                    }
                    Section {
                        NavigationLink {
                            DeliverySetupView(selectedTab: $selectedTab)
                                .environmentObject(cart)
                                .environmentObject(orderStore)
                        } label: {
                            Text("下一步")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .disabled(cart.items.isEmpty)
                    }
                }
            }
            .navigationTitle("Cart")
        }
    }
}

struct DeliverySetupView: View {
    @EnvironmentObject private var cart: Cart
    @EnvironmentObject private var orderStore: CustomerOrderStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTab: HomeTab
    @State private var selectedLocation: DeliveryLocation = DeliveryLocation.sample.first!
    @State private var deliveryTime: Date = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
    @State private var notes: String = ""
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    private let timeRange: ClosedRange<Date> = {
        let now = Date()
        let upper = Calendar.current.date(byAdding: .hour, value: 3, to: now) ?? now
        return now...upper
    }()

    var body: some View {
        Form {
            Section("送餐地點") {
                Picker("地點", selection: $selectedLocation) {
                    ForEach(DeliveryLocation.sample) { loc in
                        Text(loc.name).tag(loc)
                    }
                }
            }

            Section("送達時間") {
                DatePicker("希望送達", selection: $deliveryTime, in: timeRange, displayedComponents: .hourAndMinute)
            }

            Section("備註（可選）") {
                TextField("例如：請在警衛室前交付", text: $notes, axis: .vertical)
            }

            Section {
                Button {
                    submitOrder()
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("送出訂單")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(isSubmitting || cart.items.isEmpty)
            }
        }
        .navigationTitle("設定送達資訊")
        .navigationBarTitleDisplayMode(.inline)
        .alert("送出失敗", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func submitOrder() {
        guard !isSubmitting else { return }
        isSubmitting = true
        let isDemo = DemoConfig.isEnabled
        let eta = Int(max(10, deliveryTime.timeIntervalSinceNow / 60))

        Task {
            defer { isSubmitting = false }
            if isDemo {
                let orderTitle = cart.items.first?.restaurantName ?? "新訂單"
                orderStore.addDemoOrder(title: orderTitle, location: selectedLocation.name, etaMinutes: eta)
                cart.clear()
                selectedTab = .status
                dismiss()
                return
            }

            do {
                guard let restaurantId = cart.items.first?.restaurantId ?? cart.currentRestaurantId else {
                    throw APIError(message: "缺少餐廳資訊")
                }
                let token = UserDefaults.standard.string(forKey: "auth_token")
                let itemsPayload = try cart.items.map { cartItem -> OrderAPI.CreateOrderItem in
                    guard let menuItemId = cartItem.item.apiId else {
                        throw APIError(message: "缺少餐點 ID，請重新載入菜單")
                    }
                    return OrderAPI.CreateOrderItem(
                        menuItemId: menuItemId,
                        size: cartItem.size,
                        spiciness: cartItem.spiciness,
                        addDrink: cartItem.addDrink,
                        quantity: cartItem.quantity
                    )
                }
                let payload = OrderAPI.CreateOrderPayload(
                    restaurantId: restaurantId,
                    items: itemsPayload,
                    deliveryLocation: .init(name: selectedLocation.name),
                    notes: notes.isEmpty ? nil : notes,
                    requestedTime: ISO8601DateFormatter().string(from: deliveryTime)
                )
                try await OrderAPI.createOrder(payload: payload, token: token)
                cart.clear()
                selectedTab = .status
                await orderStore.refresh(token: token)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

struct DeliveryLocation: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let detail: String?

    static let sample: [DeliveryLocation] = [
        .init(name: "電資大樓", detail: "面向新生南路入口"),
        .init(name: "資工系館", detail: "正門大廳"),
        .init(name: "河工系館", detail: "一樓側門")
    ]
}

struct OrderStatusView: View {
    @EnvironmentObject private var orderStore: CustomerOrderStore
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                Section("進行中") {
                    if orderStore.activeOrders.isEmpty {
                        ContentUnavailableView("目前沒有進行中的訂單", systemImage: "tray")
                    } else {
                        ForEach(orderStore.activeOrders) { order in
                            OrderStatusRow(order: order)
                        }
                    }
                }

                Section("歷史訂單") {
                    ForEach(orderStore.historyOrders) { order in
                        OrderStatusRow(order: order)
                    }
                }
            }
            .navigationTitle("訂單狀態")
            .task {
                await refreshOrders()
            }
            .refreshable {
                await refreshOrders()
            }
        }
    }

    private func refreshOrders() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let token = UserDefaults.standard.string(forKey: "auth_token")
        await orderStore.refresh(token: token)
    }
}

struct SettingsView: View {
    var onLogout: () -> Void
    var onSwitchRole: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("帳號") {
                    Button {
                        onSwitchRole()
                    } label: {
                        Label("切換身份", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button(role: .destructive) {
                        onLogout()
                    } label: {
                        Label("登出", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("偏好設定") {
                    Toggle(isOn: .constant(true)) {
                        Label("推播通知", systemImage: "bell.badge.fill")
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
final class CustomerOrderStore: ObservableObject {
    @Published var activeOrders: [CustomerOrder] = []
    @Published var historyOrders: [CustomerOrder] = []

    func refresh(token: String?) async {
        do {
            let actives = try await OrderAPI.fetchOrders(status: "active", token: token)
            let histories = try await OrderAPI.fetchOrders(status: "history", token: token)
            await MainActor.run {
                activeOrders = actives.map { $0.toCustomerOrder(isHistory: false) }
                historyOrders = histories.map { $0.toCustomerOrder(isHistory: true) }
            }
        } catch {
            print("⚠️ refresh orders failed:", error)
        }
    }

    func addDemoOrder(title: String, location: String, etaMinutes: Int) {
        let order = CustomerOrder(id: UUID().uuidString, title: title, location: location, status: .preparing, etaMinutes: etaMinutes, placedAt: Date())
        activeOrders.append(order)
        // 模擬狀態更新：10 秒後配送中，再 10 秒後已送達
        scheduleLocalNotification(body: "\(title) 訂單已建立，準備中")
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self else { return }
            self.update(orderID: order.id, to: .delivering)
            self.scheduleLocalNotification(body: "\(title) 已開始配送")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self else { return }
            self.complete(orderID: order.id)
            self.scheduleLocalNotification(body: "\(title) 已送達，感謝使用")
        }
    }

    private func update(orderID: String, to status: CustomerOrderStatus) {
        guard let idx = activeOrders.firstIndex(where: { $0.id == orderID }) else { return }
        activeOrders[idx].status = status
    }

    private func complete(orderID: String) {
        guard let idx = activeOrders.firstIndex(where: { $0.id == orderID }) else { return }
        var order = activeOrders.remove(at: idx)
        order.status = .delivered
        historyOrders.insert(order, at: 0)
    }

    private func scheduleLocalNotification(body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "OceanExpress"
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }
}

enum CustomerOrderStatus: String, Codable {
    case preparing
    case delivering
    case delivered
    case available
    case assigned
    case enRouteToPickup = "en_route_to_pickup"
    case pickedUp = "picked_up"
    case cancelled

    var displayText: String {
        switch self {
        case .preparing, .available: return "準備中"
        case .assigned, .enRouteToPickup: return "準備配送"
        case .pickedUp, .delivering: return "配送中"
        case .delivered: return "已送達"
        case .cancelled: return "已取消"
        }
    }
}

struct CustomerOrder: Identifiable {
    let id: String
    let title: String
    let location: String
    var status: CustomerOrderStatus
    let etaMinutes: Int?
    let placedAt: Date
}

struct OrderStatusRow: View {
    let order: CustomerOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(order.title)
                    .font(.headline)
                Spacer()
                Text(order.status.displayText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(order.status == .delivered || order.status == .cancelled ? Color.secondary : Color.accentColor)
            }
            HStack(spacing: 8) {
                Label(order.status == .delivered ? "已完成" : (order.status == .cancelled ? "已取消" : "預計抵達"),
                      systemImage: order.status == .delivered ? "checkmark.seal" : (order.status == .cancelled ? "xmark.seal" : "clock"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let eta = order.etaMinutes, order.status != .delivered {
                    Text("約 \(eta) 分鐘")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(Self.displayFormatter.string(from: order.placedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private static let displayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()
}

private extension OrderAPI.OrderSummary {
    func toCustomerOrder(isHistory: Bool) -> CustomerOrder {
        let date = placedAt ?? Date()
        let statusEnum = CustomerOrderStatus(rawValue: status) ?? .preparing
        return CustomerOrder(id: id, title: restaurantName, location: "", status: statusEnum, etaMinutes: etaMinutes, placedAt: date)
    }
}
