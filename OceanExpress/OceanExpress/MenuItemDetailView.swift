//
//  MenuItemDetailView.swift
//  OceanExpress
//
//  Created by 呂翰昇 on 2025/10/14.
//

import SwiftUI

struct MenuItemDetailView: View {
    let item: AppModels.MenuItem

    @EnvironmentObject private var cart: Cart
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode

    @State private var size: String
    @State private var spiciness: String
    @State private var addDrink = false
    @State private var quantity = 1
    @State private var isAdding = false

    init(item: AppModels.MenuItem) {
        self.item = item
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
                    addToCart()
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
    }

    private func addToCart() {
        guard !isAdding else { return }
        isAdding = true
        print("Added \(item.name) with \(size), \(spiciness), drink: \(addDrink)")
        cart.add(item: item, size: size, spiciness: spiciness, addDrink: addDrink, quantity: quantity)
        // Dual dismiss for safety across iOS versions
        DispatchQueue.main.async {
            dismiss()
            presentationMode.wrappedValue.dismiss()
            isAdding = false
        }
    }
}
