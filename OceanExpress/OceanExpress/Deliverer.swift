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

struct Place: Hashable {
    var name: String
    var address: String
    var coordinate: CLLocationCoordinate2D
    static func == (lhs: Place, rhs: Place) -> Bool {
        lhs.name == rhs.name &&
        lhs.address == rhs.address &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(address)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }
}

struct Customer: Hashable {
    var displayName: String
    var phone: String
    var address: String
}

struct Order: Identifiable, Hashable {
    var id: UUID = UUID()
    var code: String // 顯示編號用
    var fee: Double // 外送費
    var distanceKm: Double // 粗估距離（列表展示）
    var etaMinutes: Int // 粗估時間（列表展示）
    var createdAt: Date

    var merchant: Place
    var customer: Customer
    var dropoff: Place

    var notes: String
    var canPickup: Bool
    var status: OrderStatus

    var routePolyline: MKPolyline? = nil

    var isActive: Bool { status != .delivered && status != .cancelled }
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

// MARK: - Services (Mock)

protocol OrderServiceProtocol {
    func streamAvailableOrders() -> AsyncStream<[Order]>
    func accept(order: Order) async throws -> Order
    func updateStatus(order: Order, to status: OrderStatus) async throws -> Order
}

@MainActor
final class MockOrderService: OrderServiceProtocol {
    private var available: [Order] = []

    init() {
        available = Self.sampleOrders()
    }

    static func sampleOrders() -> [Order] {
        let merchant1 = Place(name: "小林便當 - 公館店", address: "台北市中正區羅斯福路四段1號", coordinate: .init(latitude: 25.0143, longitude: 121.5323))
        let drop1 = Place(name: "台大電機系館", address: "台北市大安區辛亥路二段1號", coordinate: .init(latitude: 25.0172, longitude: 121.5395))
        let cust1 = Customer(displayName: "王先生", phone: "0912-345-678", address: drop1.address)

        let merchant2 = Place(name: "珍煮丹 - 羅斯福店", address: "台北市中正區羅斯福路三段100號", coordinate: .init(latitude: 25.0211, longitude: 121.5280))
        let drop2 = Place(name: "公館捷運站出口2", address: "台北市中正區羅斯福路四段", coordinate: .init(latitude: 25.0149, longitude: 121.5331))
        let cust2 = Customer(displayName: "林小姐", phone: "0988-555-666", address: drop2.address)

        let now = Date()

        return [
            Order(code: "A1-892", fee: 85, distanceKm: 1.2, etaMinutes: 12, createdAt: now.addingTimeInterval(-300), merchant: merchant1, customer: cust1, dropoff: drop1, notes: "多加辣，飲料去冰", canPickup: true, status: .available),
            Order(code: "B7-443", fee: 62, distanceKm: 0.8, etaMinutes: 10, createdAt: now.addingTimeInterval(-120), merchant: merchant2, customer: cust2, dropoff: drop2, notes: "請先聯繫再上樓", canPickup: false, status: .available),
        ]
    }

    func streamAvailableOrders() -> AsyncStream<[Order]> {
        var current = available
        return AsyncStream { continuation in
            // 初始 emit
            continuation.yield(current)

            // 模擬即時新增/變動
            let timer = Timer.scheduledTimer(withTimeInterval: 7, repeats: true) { _ in
                // 偶爾新增一筆
                if Bool.random() {
                    current.append(Self.sampleOrders().randomElement()!)
                }
                // 偶爾更新距離與時間（模擬動態估算）
                current = current.map { o in
                    var o2 = o
                    let drift = Double.random(in: -0.1...0.1)
                    o2.distanceKm = max(0.3, o.distanceKm + drift)
                    o2.etaMinutes = max(5, Int(Double(o.etaMinutes) + drift * 10))
                    return o2
                }
                continuation.yield(current)
            }
            continuation.onTermination = { _ in timer.invalidate() }
        }
    }

    func accept(order: Order) async throws -> Order {
        var updated = order
        updated.status = .assigned
        return updated
    }

    func updateStatus(order: Order, to status: OrderStatus) async throws -> Order {
        var updated = order
        updated.status = status
        return updated
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

    private let service: OrderServiceProtocol
    private var streamTask: Task<Void, Never>? = nil

    init(service: any OrderServiceProtocol) {
        self.service = service
        self.dailyEarnings = Self.mockEarnings()
        startStreaming()
    }

    deinit { streamTask?.cancel() }

    func startStreaming() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            for await list in service.streamAvailableOrders() {
                self.availableOrders = list.filter { $0.status == .available }
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
        } catch {
            print("Accept error: \(error)")
        }
    }

    func updateStatus(for order: Order, to status: OrderStatus) async {
        do {
            let updated = try await service.updateStatus(order: order, to: status)
            if let idx = activeTasks.firstIndex(where: { $0.id == order.id }) {
                activeTasks[idx] = updated
            }
            if status == .delivered || status == .cancelled {
                // 移入歷史
                if let idx = activeTasks.firstIndex(where: { $0.id == order.id }) {
                    let finished = activeTasks.remove(at: idx)
                    history.insert(finished, at: 0)
                    // 結帳：累計收入
                    let today = Calendar.current.startOfDay(for: Date())
                    if let eidx = dailyEarnings.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
                        dailyEarnings[eidx].amount += finished.fee
                    } else {
                        dailyEarnings.append(.init(date: today, amount: finished.fee))
                    }
                }
            }
        } catch {
            print("Status update error: \(error)")
        }
    }

    static func mockEarnings() -> [DailyEarning] {
        let cal = Calendar.current
        return (0..<10).map { i in
            let d = cal.date(byAdding: .day, value: -i, to: Date())!
            return DailyEarning(date: cal.startOfDay(for: d), amount: Double(Int.random(in: 350...1200)))
        }.sorted { $0.date < $1.date }
    }
}

// MARK: - Views

@MainActor struct DelivererModule: View {
    @StateObject private var appState: AppState
    @StateObject private var loc: LocationManager
    

    init() {
        _appState = StateObject(wrappedValue: AppState(service: MockOrderService()))
        _loc = StateObject(wrappedValue: LocationManager())
    }

    var body: some View {
        RootView()
            .environmentObject(appState)
            .environmentObject(loc)
    }
}

struct RootView: View {
    @EnvironmentObject var loc: LocationManager
    var body: some View {
        TabView {
            TaskListView()
                .tabItem { Label("任務清單", systemImage: "list.bullet.rectangle") }

            ActiveTasksView()
                .tabItem { Label("進行中", systemImage: "bolt.car") }

            HistoryView()
                .tabItem { Label("歷史紀錄", systemImage: "clock.arrow.circlepath") }
        }
        .onAppear { loc.request() }
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
                Label(order.canPickup ? "可取餐" : "商家準備中", systemImage: order.canPickup ? "checkmark.seal" : "hourglass")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "house")
                VStack(alignment: .leading) {
                    Text(order.merchant.name).font(.subheadline)
                    Text(order.merchant.address).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person")
                VStack(alignment: .leading) {
                    Text(order.customer.displayName).font(.subheadline)
                    Text(order.dropoff.address).font(.caption).foregroundStyle(.secondary)
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
                Button(actionTitle) { action() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: 進行中（多任務） & 訂單詳情頁 + 狀態更新頁

struct ActiveTasksView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationStack {
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
                .navigationDestination(for: Order.self) { order in
                    OrderDetailView(order: order)
                }
                .navigationTitle("進行中任務")
            }
        }
    }
}

struct OrderProgressRow: View {
    let order: Order
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("#\(order.code)").font(.headline)
                Spacer()
                Text(order.status.title).font(.subheadline).foregroundStyle(.blue)
            }
            ProgressView(value: progressValue)
            HStack(spacing: 16) {
                Label("$\(Int(order.fee))", systemImage: "dollarsign")
                Label("\(String(format: "%.1f", order.distanceKm)) km", systemImage: "location")
                Label("\(order.etaMinutes) 分", systemImage: "clock")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
    private var progressValue: Double {
        max(0, min(1, Double(order.status.stepIndex) / 5.0))
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
    let order: Order
    @State private var region: MKCoordinateRegion
    @State private var showUpdateSheet = false
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var routeDistanceMeters: CLLocationDistance = 0
    @State private var routeETASecs: TimeInterval = 0

    private func computeRoute() {
        let startCoord: CLLocationCoordinate2D
        let endCoord: CLLocationCoordinate2D
        if order.status == .enRouteToPickup, let u = loc.userLocation?.coordinate {
            startCoord = u
            endCoord = order.merchant.coordinate
        } else if order.status == .delivering || order.status == .pickedUp {
            startCoord = order.merchant.coordinate
            endCoord = order.dropoff.coordinate
        } else {
            startCoord = order.merchant.coordinate
            endCoord = order.dropoff.coordinate
        }
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: startCoord))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: endCoord))
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
                Annotation("取餐：\(order.merchant.name)", coordinate: order.merchant.coordinate) {
                    Label("取餐", systemImage: "bag")
                        .padding(8).background(.thinMaterial).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Annotation("送達：\(order.customer.displayName)", coordinate: order.dropoff.coordinate) {
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
                InfoRow(title: "顧客", value: "\(order.customer.displayName)  (☎︎ \(order.customer.phone))")
                InfoRow(title: "送達地址", value: order.dropoff.address)
                InfoRow(title: "商家", value: order.merchant.name)
                InfoRow(title: "商家地址", value: order.merchant.address)
                InfoRow(title: "備註", value: order.notes.isEmpty ? "無" : order.notes)
                InfoRow(title: "取餐狀態", value: order.canPickup ? "可取餐" : "準備中")
                Divider()
                HStack(spacing: 16) {
                    Label("$\(Int(order.fee))", systemImage: "dollarsign")
                    Label("\(String(format: "%.1f", order.distanceKm)) km", systemImage: "location")
                    Label("\(order.etaMinutes) 分", systemImage: "clock")
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
        .navigationTitle("訂單詳情 #\(order.code)")
        .sheet(isPresented: $showUpdateSheet) {
            StatusUpdateSheet(order: order)
                .presentationDetents([.height(360), .medium])
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showUpdateSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                    Text("更新狀態")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .background(.ultraThinMaterial)
        }
        .onAppear { computeRoute() }
        .onChange(of: order.status) { _ in computeRoute() }
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
                    // TODO: 上報客服／商家（此處為示意）
                    incidentNote = ""
                    dismiss()
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
        .controlSize(.large)
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
                if let user = loc.userLocation?.coordinate {
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

struct HistoryView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                Text("收益統計").font(.headline).padding(.horizontal)
                Chart(app.dailyEarnings) { item in
                    LineMark(
                        x: .value("日期", item.date),
                        y: .value("金額", item.amount)
                    )
                    PointMark(
                        x: .value("日期", item.date),
                        y: .value("金額", item.amount)
                    )
                }
                .chartYScale(domain: 0...max(1400, (app.dailyEarnings.map{ $0.amount }.max() ?? 0) * 1.2))
                .frame(height: 180)
                .padding(.horizontal)

                List {
                    Section("已完成訂單") {
                        ForEach(app.history) { order in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("#\(order.code)").font(.headline)
                                    Spacer()
                                    Text("$\(Int(order.fee))")
                                }
                                Text(order.dropoff.address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("歷史紀錄")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


// MARK: - Utilities

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: Int(pointCount))
        getCoordinates(&coords, range: NSRange(location: 0, length: Int(pointCount)))
        return coords
    }
}

extension MKCoordinateRegion {
    init(_ rect: MKMapRect) {
        self = MKCoordinateRegion(rect)
    }
}

extension CLLocationCoordinate2D: Codable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(latitude)
        try container.encode(longitude)
    }
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let lat = try container.decode(Double.self)
        let lon = try container.decode(Double.self)
        self.init(latitude: lat, longitude: lon)
    }
}
