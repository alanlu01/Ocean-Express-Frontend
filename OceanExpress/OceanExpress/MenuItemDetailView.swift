//
//  MenuItemDetailView.swift
//  OceanExpress
//
//  Created by 呂翰昇 on 2025/10/14.
//

import SwiftUI

struct MenuItemDetailView: View {
    let item: AppModels.MenuItem
    let restaurantId: String?
    let restaurantName: String

    @EnvironmentObject private var cart: Cart
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode

    @State private var size: String
    @State private var spiciness: String
    @State private var quantity = 1
    @State private var isAdding = false
    @State private var showClearConfirm = false

    init(item: AppModels.MenuItem, restaurantId: String?, restaurantName: String) {
        self.item = item
        self.restaurantId = restaurantId
        self.restaurantName = restaurantName
        _size = State(initialValue: item.sizes.first ?? "中份")
        _spiciness = State(initialValue: item.spicinessOptions.first ?? "不辣")
    }

    var body: some View {
        Form {
            Section(header: Text("客製化")) {
                Picker("份量", selection: $size) {
                    ForEach(item.sizes, id: \.self) { Text($0) }
                }

                Picker("辣度", selection: $spiciness) {
                    ForEach(item.spicinessOptions, id: \.self) { Text($0) }
                }

                Stepper("數量：\(quantity)", value: $quantity, in: 1...10)
            }

            Section("餐點資訊") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.description).font(.subheadline)
                    HStack {
                        ForEach(item.tags, id: \.self) { tag in
                            Label(tag, systemImage: "tag.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    if !item.allergens.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("過敏原：\(item.allergens.joined(separator: "、"))")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

        }
        .navigationTitle(item.name)
        .onChange(of: cart.itemCount) { _, _ in
            // Auto-pop back to the menu when the cart updates
            dismiss()
        }
        .alert("切換餐廳？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) { }
            Button("清空並加入", role: .destructive) {
                cart.clear()
                addToCart()
            }
        } message: {
            Text("購物車已有其他餐廳的餐點，清空後才能加入 \(restaurantName)。")
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                attemptAdd()
            } label: {
                Label("加入購物車", systemImage: "cart.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(isAdding)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }

    private func attemptAdd() {
        if let existingId = cart.currentRestaurantId, let newId = restaurantId, existingId != newId {
            showClearConfirm = true
            return
        }
        if cart.currentRestaurantId == nil, let existingName = cart.currentRestaurantName, existingName != restaurantName {
            showClearConfirm = true
            return
        }
        addToCart()
    }

    private func addToCart() {
        guard !isAdding else { return }
        isAdding = true
        cart.add(item: item, restaurantId: restaurantId, restaurantName: restaurantName, size: size, spiciness: spiciness, drinkOption: DrinkOption.defaultOptions[0], quantity: quantity)
        // Dual dismiss for safety across iOS versions
        DispatchQueue.main.async {
            dismiss()
            presentationMode.wrappedValue.dismiss()
            isAdding = false
        }
    }
}
