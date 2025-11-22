
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var cart: Cart

    // Demo restaurant list (fileprivate to avoid type clashes)
    fileprivate let restaurants: [RestaurantListItem] = [
        .init(name: "Marina Burger", imageURL: URL(string: "https://images.unsplash.com/photo-1550547660-d9450f859349?w=1200&q=80")),
        .init(name: "Harbor Coffee", imageURL: URL(string: "https://images.unsplash.com/photo-1504754524776-8f4f37790ca0?w=1200&q=80")),
        .init(name: "Green Bowl", imageURL: URL(string: "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=1200&q=80"))
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(restaurants) { r in
                        NavigationLink(destination: RestaurantMenuView(restaurantName: r.name)) {
                            RestaurantCard(item: r)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("Discover")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: CartView()) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "cart")
                                .imageScale(.large)
                            if cart.itemCount > 0 {
                                Text("\(cart.itemCount)")
                                    .font(.caption2).bold()
                                    .padding(4)
                                    .background(Circle().fill(Color.red))
                                    .foregroundColor(.white)
                                    .offset(x: 8, y: -8)
                            }
                        }
                    }
                }
            }
        }
    }
}

fileprivate struct RestaurantListItem: Identifiable, Hashable {
    // Use a stable id so SwiftUI can diff correctly across view reloads
    var id: String { name }
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
    let restaurantName: String

    var body: some View {
        List {
            Section(header: Text("Menu")) {
                ForEach(AppModels.SampleMenu.items) { item in
                    NavigationLink(destination: MenuItemDetailView(item: item, restaurantName: restaurantName)) {
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
    }
}

fileprivate struct CartView: View {
    @EnvironmentObject private var cart: Cart

    var body: some View {
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
                        DeliverySetupView()
                            .environmentObject(cart)
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

struct DeliverySetupView: View {
    @EnvironmentObject private var cart: Cart
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLocation: DeliveryLocation = DeliveryLocation.sample.first!
    @State private var deliveryTime: Date = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
    @State private var notes: String = ""
    @State private var isSubmitting = false
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
                if let detail = selectedLocation.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    }

    private func submitOrder() {
        guard !isSubmitting else { return }
        isSubmitting = true
        // TODO: 接後端 API；暫時直接清空購物車
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            cart.clear()
            isSubmitting = false
            dismiss()
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

#Preview {
    HomeView()
        .environmentObject(Cart())
}
