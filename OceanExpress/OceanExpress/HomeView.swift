import SwiftUI
import Combine
import UserNotifications
import CoreLocation

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
    @State private var restaurants: [RestaurantListItem] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(restaurants) { r in
                        NavigationLink(destination: RestaurantMenuView(restaurantId: r.id, restaurantName: r.name, restaurantRating: r.rating)) {
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
        do {
            let data = try await RestaurantAPI.fetchRestaurants()
            restaurants = data.map { RestaurantListItem(id: $0.id, name: $0.name, imageURL: URL(string: $0.imageUrl ?? ""), rating: $0.rating) }
        } catch {
            // 無資料時維持空清單
        }
    }
}

fileprivate struct RestaurantListItem: Identifiable, Hashable {
    let id: String
    let name: String
    let imageURL: URL?
    let rating: Double?

    init(id: String, name: String, imageURL: URL?, rating: Double? = nil) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
        self.rating = rating
    }
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
            if let rating = item.rating {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f", rating))
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 4)
                .foregroundStyle(.secondary)
            } else {
                Text("尚無評分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

fileprivate struct RestaurantMenuView: View {
    let restaurantId: String
    let restaurantName: String
    let restaurantRating: Double?
    @State private var items: [MenuItem] = []
    @State private var isLoading = false
    @State private var reviews: [RestaurantAPI.Review] = []
    @State private var isLoadingReviews = false
    @State private var showReviews = false

    var body: some View {
        List {
            Section("餐廳評分") {
                if let rating = restaurantRating {
                    Button {
                        showReviews = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f / 5.0", rating))
                                .font(.headline)
                            Spacer()
                            Text("查看評論")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("尚無評分")
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text("菜單")) {

                ForEach(items) { item in
                    NavigationLink(destination: MenuItemDetailView(item: item, restaurantId: restaurantId, restaurantName: restaurantName)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.headline)
                            HStack(spacing: 8) {
                                Text("$\(item.price)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                if let firstSize = item.sizes.first {
                                    Text(firstSize)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            if !item.isAvailable {
                                Label("暫停販售", systemImage: "pause.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.orange)
                            }
                            if !item.tags.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(item.tags.prefix(3), id: \.self) { tag in
                                        Text(tag)
                                            .font(.caption2)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.accentColor.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            if !item.allergens.isEmpty {
                                Text("過敏原：\(item.allergens.joined(separator: "、"))")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(!item.isAvailable)
                    .opacity(item.isAvailable ? 1 : 0.6)
                }
            }
        }
        .navigationTitle(restaurantName)
        .task {
            await loadMenu()
            await loadReviews()
        }
        .sheet(isPresented: $showReviews) {
            RestaurantReviewsView(restaurantId: restaurantId, restaurantName: restaurantName, rating: restaurantRating, initialReviews: reviews)
        }
    }

    private func loadMenu() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
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

    private func loadReviews() async {
        guard !isLoadingReviews else { return }
        isLoadingReviews = true
        defer { isLoadingReviews = false }
        do {
            let data = try await RestaurantAPI.fetchReviews(restaurantId: restaurantId)
            reviews = data
        } catch {
            // 若後端未實作，保持空列表
            print("⚠️ RestaurantMenuView.loadReviews error:", error)
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
                    Text("購物車目前沒有商品")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(cart.items) { ci in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ci.item.name)
                                    .font(.body)
        Text("\(ci.size) • \(ci.spiciness)\(ci.drinkOption.addsDrink ? " • 加飲料" : "")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("x\(ci.quantity)")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                            Text("$\(ci.lineTotal)")
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
                            Text("小計")
                            Spacer()
                            Text("$\(cart.subtotal)")
                                .bold()
                                .monospacedDigit()
                        }
                        HStack {
                            Text("外送費")
                            Spacer()
                            Text("$\(deliveryFee)")
                                .monospacedDigit()
                        }
                        HStack {
                            Text("總計")
                            Spacer()
                            Text("$\(total)")
                                .font(.title3.weight(.semibold))
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
            .navigationTitle("購物車")
        }
    }

    private var deliveryFee: Int { 20 }
    private var total: Int { cart.subtotal + deliveryFee }
}

struct DeliverySetupView: View {
    @EnvironmentObject private var cart: Cart
    @EnvironmentObject private var orderStore: CustomerOrderStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTab: HomeTab
    @AppStorage("default_delivery_location_name") private var defaultDeliveryLocationName: String = DeliveryCatalog.defaultDestination.name
    @State private var selectedLocation: DeliveryDestination = DeliveryCatalog.defaultDestination
    @State private var deliveryTime: Date = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
    @State private var notes: String = ""
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var locationCategories: [DeliveryLocationCategory] = []
    @State private var selectedCategory: String = ""
    @State private var isLoadingLocations = false
    private let timeRange: ClosedRange<Date> = {
        let now = Date()
        let upper = Calendar.current.date(byAdding: .hour, value: 3, to: now) ?? now
        return now...upper
    }()

    var body: some View {
        Form {
            Section("送餐地點") {
                Picker("分類", selection: $selectedCategory) {
                    ForEach(locationCategories) { category in
                        Text(category.name).tag(category.name)
                    }
                }
                Picker("地點", selection: $selectedLocation) {
                    ForEach(destinationsForSelectedCategory) { loc in
                        Text(loc.name).tag(loc)
                    }
                }
                Button("設為預設外送地點") {
                    defaultDeliveryLocationName = selectedLocation.name
                }
                .font(.footnote)
                .buttonStyle(.borderless)
            }

            Section("送達時間") {
                DatePicker("希望送達", selection: $deliveryTime, in: timeRange, displayedComponents: .hourAndMinute)
            }

            Section("備註（可選）") {
                TextField("備註（選填）", text: $notes, axis: .vertical)
            }

            Section("金額") {
                HStack {
                    Text("小計")
                    Spacer()
                    Text("$\(cart.subtotal)")
                        .monospacedDigit()
                }
                HStack {
                    Text("外送費")
                    Spacer()
                    Text("$\(deliveryFee)")
                        .monospacedDigit()
                }
                HStack {
                    Text("總計")
                    Spacer()
                    Text("$\(total)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
            }

            Section {
                Button {
                    submitOrder()
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("送出訂單（含外送費 $\(deliveryFee))")
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
        .task { await loadDeliveryLocations() }
        .onChange(of: selectedCategory) { _, _ in
            if let match = destinationsForSelectedCategory.first(where: { $0.name == selectedLocation.name }) {
                selectedLocation = match
            } else if let first = destinationsForSelectedCategory.first {
                selectedLocation = first
            }
        }
    }

    private func submitOrder() {
        guard !isSubmitting else { return }
        isSubmitting = true
        let eta = Int(max(10, deliveryTime.timeIntervalSinceNow / 60))
        let noteText = notes

        Task {
            defer { isSubmitting = false }
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
                        addDrink: cartItem.drinkOption.addsDrink,
                        quantity: cartItem.quantity
                    )
                }
                let payload = OrderAPI.CreateOrderPayload(
                    restaurantId: restaurantId,
                    items: itemsPayload,
                    deliveryLocation: .init(name: selectedLocation.name, lat: selectedLocation.latitude, lng: selectedLocation.longitude),
                    notes: noteText.isEmpty ? nil : noteText,
                    requestedTime: ISO8601DateFormatter().string(from: deliveryTime),
                    deliveryFee: deliveryFee,
                    totalAmount: total
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

    private var deliveryFee: Int { 20 }
    private var total: Int { cart.subtotal + deliveryFee }

    private func loadDeliveryLocations() async {
        guard !isLoadingLocations else { return }
        isLoadingLocations = true
        defer { isLoadingLocations = false }
        do {
            let categories = try await DeliveryLocationAPI.fetchCategories()
            let mapped: [DeliveryLocationCategory] = categories.map { cat in
                DeliveryLocationCategory(
                    name: cat.category,
                    destinations: cat.items.map { DeliveryDestination(name: $0.name, latitude: $0.lat, longitude: $0.lng) }
                )
            }
            if !mapped.isEmpty {
                locationCategories = mapped
            } else {
                locationCategories = fallbackCategories()
            }
        } catch {
            locationCategories = fallbackCategories()
        }
        syncSelectionWithCategories()
    }

    private func syncSelectionWithCategories() {
        // 選分類：若已有預設地點，找出其分類；否則取第一個分類
        if selectedCategory.isEmpty {
            if let foundCategory = locationCategories.first(where: { category in
                category.destinations.contains(where: { $0.name == defaultDeliveryLocationName })
            }) {
                selectedCategory = foundCategory.name
            } else {
                selectedCategory = locationCategories.first?.name ?? ""
            }
        }

        // 選地點：優先用預設地點名稱，其次分類內第一個
        if let preset = destinationsForSelectedCategory.first(where: { $0.name == defaultDeliveryLocationName }) {
            selectedLocation = preset
        } else if let match = destinationsForSelectedCategory.first(where: { $0.name == selectedLocation.name }) {
            selectedLocation = match
        } else if let first = destinationsForSelectedCategory.first {
            selectedLocation = first
        }
    }

    private var destinationsForSelectedCategory: [DeliveryDestination] {
        locationCategories.first(where: { $0.name == selectedCategory })?.destinations
        ?? locationCategories.first?.destinations
        ?? []
    }

    private func fallbackCategories() -> [DeliveryLocationCategory] {
        let name = defaultDeliveryLocationName.isEmpty ? DeliveryCatalog.defaultDestination.name : defaultDeliveryLocationName
        let dest = DeliveryDestination(name: name, latitude: nil, longitude: nil)
        return [DeliveryLocationCategory(name: "預設地點", destinations: [dest])]
    }
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
                            NavigationLink {
                                CustomerOrderDetailView(order: order)
                                    .environmentObject(orderStore)
                            } label: {
                                OrderStatusRow(order: order)
                            }
                        }
                    }
                }

                Section("歷史訂單") {
                    ForEach(orderStore.historyOrders) { order in
                        NavigationLink {
                            CustomerOrderDetailView(order: order)
                                .environmentObject(orderStore)
                        } label: {
                            OrderStatusRow(order: order)
                        }
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
            .onAppear {
                requestNotificationPermissionIfNeeded()
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

    private func requestNotificationPermissionIfNeeded() {
        guard NotificationManager.shared.isPushEnabled,
              UserDefaults.standard.bool(forKey: "customer_push_enabled") else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}

struct SettingsView: View {
    var onLogout: () -> Void
    var onSwitchRole: () -> Void
    @AppStorage("customer_push_enabled") private var pushEnabled = true
    @AppStorage("default_delivery_location_name") private var defaultDeliveryLocationName: String = DeliveryCatalog.defaultDestination.name
    @State private var locationCategories: [DeliveryLocationCategory] = []
    @State private var selectedCategory: String = ""
    @State private var isLoadingLocations = false

    var body: some View {
        NavigationStack {
            Form {
                Section("帳號") {
                    Button {
                        onSwitchRole()
                    } label: {
                        Label("切換成外送員", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button(role: .destructive) {
                        onLogout()
                    } label: {
                        Label("登出", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("偏好設定") {
                    Toggle(isOn: $pushEnabled) {
                        Label("推播通知", systemImage: "bell.badge.fill")
                    }
                    .tint(.accentColor)
                    .onChange(of: pushEnabled) { _, newValue in
                        if newValue { requestNotificationPermission() }
                    }
                }

                Section("預設外送地點") {
                    if destinationsForSelectedCategory.isEmpty {
                        Text("尚未載入地點清單，請在下單時選擇一次即可記錄。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("分類", selection: $selectedCategory) {
                            ForEach(locationCategories) { category in
                                Text(category.name).tag(category.name)
                            }
                        }
                        Picker("預設地點", selection: $defaultDeliveryLocationName) {
                            ForEach(destinationsForSelectedCategory) { loc in
                                Text(loc.name).tag(loc.name)
                            }
                        }
                        Text("此設定會在下單時自動帶入，可隨時於下單頁更改。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
            .task { await loadLocationPresets() }
            .onChange(of: selectedCategory) { _, _ in
                syncDefaultLocationWithCategory()
            }
        }
    }

    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private var destinationsForSelectedCategory: [DeliveryDestination] {
        locationCategories.first(where: { $0.name == selectedCategory })?.destinations
        ?? locationCategories.first?.destinations
        ?? []
    }

    private func loadLocationPresets() async {
        guard !isLoadingLocations else { return }
        isLoadingLocations = true
        defer { isLoadingLocations = false }
        do {
            let categories = try await DeliveryLocationAPI.fetchCategories()
            let mapped: [DeliveryLocationCategory] = categories.map { cat in
                DeliveryLocationCategory(
                    name: cat.category,
                    destinations: cat.items.map { DeliveryDestination(name: $0.name, latitude: $0.lat, longitude: $0.lng) }
                )
            }
            locationCategories = mapped
            if selectedCategory.isEmpty {
                if let cat = mapped.first(where: { $0.destinations.contains(where: { $0.name == defaultDeliveryLocationName }) }) {
                    selectedCategory = cat.name
                } else {
                    selectedCategory = mapped.first?.name ?? ""
                }
            }
            syncDefaultLocationWithCategory()
        } catch {
            locationCategories = fallbackCategories()
            syncDefaultLocationWithCategory()
        }
    }

    private func fallbackCategories() -> [DeliveryLocationCategory] {
        let name = defaultDeliveryLocationName.isEmpty ? DeliveryCatalog.defaultDestination.name : defaultDeliveryLocationName
        let dest = DeliveryDestination(name: name, latitude: nil, longitude: nil)
        return [DeliveryLocationCategory(name: "預設地點", destinations: [dest])]
    }

    private func syncDefaultLocationWithCategory() {
        if selectedCategory.isEmpty {
            selectedCategory = locationCategories.first?.name ?? ""
        }
        if let match = destinationsForSelectedCategory.first(where: { $0.name == defaultDeliveryLocationName }) {
            defaultDeliveryLocationName = match.name
        } else if let first = destinationsForSelectedCategory.first {
            defaultDeliveryLocationName = first.name
        }
    }
}

@MainActor
final class CustomerOrderStore: ObservableObject {
    @Published var activeOrders: [CustomerOrder] = []
    @Published var historyOrders: [CustomerOrder] = []
    private var lastStatusById: [String: CustomerOrderStatus] = [:]

    init() {
        UserDefaults.standard.register(defaults: ["customer_push_enabled": true])
    }

    func refresh(token: String?) async {
        do {
            let existingRatings: [String: OrderAPI.OrderRating] = Dictionary(uniqueKeysWithValues: (activeOrders + historyOrders).compactMap { order in
                guard let rating = order.rating else { return nil }
                return (order.id, rating)
            })
            let actives = try await OrderAPI.fetchOrders(status: "active", token: token)
            let histories = try await OrderAPI.fetchOrders(status: "history", token: token)
            await MainActor.run {
                activeOrders = actives.map { $0.toCustomerOrder(isHistory: false, existingRating: existingRatings[$0.id]) }
                historyOrders = histories.map { $0.toCustomerOrder(isHistory: true, existingRating: existingRatings[$0.id]) }
                notifyStatusChanges(with: activeOrders + historyOrders)
            }
        } catch {
            print("⚠️ refresh orders failed:", error)
        }
    }

    private func notifyStatusChanges(with orders: [CustomerOrder]) {
        guard NotificationManager.shared.isPushEnabled,
              UserDefaults.standard.bool(forKey: "customer_push_enabled") else { return }
        let center = UNUserNotificationCenter.current()
        orders.forEach { order in
            let previous = lastStatusById[order.id]
            if let previous, previous != order.status {
                let content = UNMutableNotificationContent()
                content.title = "OceanExpress"
                content.body = "\(order.title) \(order.status.displayText)"
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.6, repeats: false)
                center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger))
            }
            lastStatusById[order.id] = order.status
        }
    }

    func updateRating(orderId: String, rating: OrderAPI.OrderRating) {
        if let idx = historyOrders.firstIndex(where: { $0.id == orderId }) {
            historyOrders[idx].rating = rating
        }
        if let idx = activeOrders.firstIndex(where: { $0.id == orderId }) {
            activeOrders[idx].rating = rating
        }
    }

    func applyDetail(_ detail: OrderAPI.OrderDetail) {
        func merge(into order: inout CustomerOrder) {
            if let newStatus = CustomerOrderStatus(rawValue: detail.status) {
                order.status = newStatus
            }
            if let loc = detail.deliveryLocation?.name {
                order.location = loc
            }
            if let eta = detail.etaMinutes {
                order.etaMinutes = eta
            }
            if let total = detail.totalAmount {
                order.totalAmount = total
            }
            if let fee = detail.deliveryFee {
                order.deliveryFee = fee
            }
            if let rating = detail.rating {
                order.rating = rating
            }
            if let riderName = detail.riderName {
                order.riderName = riderName
            }
            if let riderPhone = detail.riderPhone {
                order.riderPhone = riderPhone
            }
        }

        if let idx = activeOrders.firstIndex(where: { $0.id == detail.id }) {
            merge(into: &activeOrders[idx])
        }
        if let idx = historyOrders.firstIndex(where: { $0.id == detail.id }) {
            merge(into: &historyOrders[idx])
        }
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
    var location: String
    var status: CustomerOrderStatus
    var etaMinutes: Int?
    let placedAt: Date
    var totalAmount: Int?
    var deliveryFee: Int?
    var rating: OrderAPI.OrderRating?
    var riderName: String?
    var riderPhone: String?
}

extension CustomerOrder: Equatable {
    static func == (lhs: CustomerOrder, rhs: CustomerOrder) -> Bool {
        lhs.id == rhs.id
    }
}

extension CustomerOrder: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
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
            if let total = order.totalAmount {
                Text("總計 $\(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if order.status == .delivered {
                if let rating = order.rating {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { idx in
                            Image(systemName: idx <= rating.score ? "star.fill" : "star")
                                .foregroundColor(.yellow)
                                .font(.caption2)
                        }
                        if let comment = rating.comment, !comment.isEmpty {
                            Text(comment)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("待評分")
                        .font(.caption2)
                        .foregroundStyle(.orange)
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
    func toCustomerOrder(isHistory: Bool, existingRating: OrderAPI.OrderRating? = nil) -> CustomerOrder {
        let date = placedAt ?? Date()
        let statusEnum = CustomerOrderStatus(rawValue: status) ?? .preparing
        return CustomerOrder(
            id: id,
            title: restaurantName,
            location: "",
            status: statusEnum,
            etaMinutes: etaMinutes,
            placedAt: date,
            totalAmount: totalAmount,
            deliveryFee: nil,
            rating: rating ?? existingRating,
            riderName: nil,
            riderPhone: nil
        )
    }
}
