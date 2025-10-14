
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

    // 21:9 cover style card height based on screen width minus horizontal padding
    private var cardHeight: CGFloat { ((UIScreen.main.bounds.width - 32) * 9.0) / 21.0 }

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
                    NavigationLink(destination: MenuItemDetailView(item: item)) {
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
                    Button {
                        // TODO: 結帳流程（後續接功能）
                    } label: {
                        Text("結帳")
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

#Preview {
    HomeView()
        .environmentObject(Cart())
}
