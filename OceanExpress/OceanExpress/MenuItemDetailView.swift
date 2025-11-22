//
//  MenuItemDetailView.swift
//  OceanExpress
//
//  Created by 呂翰昇 on 2025/10/14.
//

import SwiftUI

struct MenuItemDetailView: View {
    let item: AppModels.MenuItem
    let restaurantName: String

    @EnvironmentObject private var cart: Cart
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode

    @State private var size: String
    @State private var spiciness: String
    @State private var addDrink = false
    @State private var quantity = 1
    @State private var isAdding = false
    @State private var showClearConfirm = false

    init(item: AppModels.MenuItem, restaurantName: String) {
        self.item = item
        self.restaurantName = restaurantName
        _size = State(initialValue: item.sizes.first ?? "Regular")
        _spiciness = State(initialValue: item.spicinessOptions.first ?? "Mild")
    }

    var body: some View {
        Form {
            Section(header: Text("Customize")) {
                Picker("Size", selection: $size) {
                    ForEach(item.sizes, id: \.self) { Text($0) }
                }

                Picker("Spiciness", selection: $spiciness) {
                    ForEach(item.spicinessOptions, id: \.self) { Text($0) }
                }

                Toggle("Add Drink (+$1.50)", isOn: $addDrink)
            }

            Section {
                Button {
                    attemptAdd()
                } label: {
                    Label("Add to Cart", systemImage: "cart.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(isAdding)
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
    }

    private func attemptAdd() {
        if let existing = cart.currentRestaurant, existing != restaurantName {
            showClearConfirm = true
            return
        }
        addToCart()
    }

    private func addToCart() {
        guard !isAdding else { return }
        isAdding = true
        cart.add(item: item, restaurantName: restaurantName, size: size, spiciness: spiciness, addDrink: addDrink, quantity: quantity)
        // Dual dismiss for safety across iOS versions
        DispatchQueue.main.async {
            dismiss()
            presentationMode.wrappedValue.dismiss()
            isAdding = false
        }
    }
}
