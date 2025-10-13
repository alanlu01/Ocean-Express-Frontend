//
//  HomeView.swift
//  OceanExpress
//
//  Created by 呂翰昇 on 2025/10/13.
//

import SwiftUI
import UIKit

struct HomeView: View {
    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBackground
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
    // MARK: - Grid layout
    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16)
    ]

    // MARK: - Sample Data (for demo)
    private let restaurants: [Restaurant] = SampleData.restaurants

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(restaurants) { r in
                        NavigationLink(destination: RestaurantDetailPlaceholder(restaurant: r)) {
                            RestaurantCard(restaurant: r)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .top) { Color(.systemBackground).frame(height: 8) }
                .background(Color(.systemBackground))
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(.accentColor)
    }
}

// MARK: - Card View
private struct RestaurantCard: View {
    let restaurant: Restaurant

    private func placeholderURL(for id: UUID) -> URL? {
        // Stable 21:9 placeholder per restaurant using its UUID as seed
        URL(string: "https://picsum.photos/seed/\(id.uuidString)/2100/900")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Big image (strict 21:9 from width; crop overflow without distortion)
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(21.0/9.0, contentMode: .fit) // height = width * 9/21
                .overlay(
                    AsyncImage(url: restaurant.imageURL ?? placeholderURL(for: restaurant.id)) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                Rectangle().fill(Color(.secondarySystemFill))
                                ProgressView()
                            }
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill() // fill the 21:9 container
                        case .failure:
                            ZStack {
                                Rectangle().fill(Color(.secondarySystemFill))
                                Image(systemName: "photo")
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                )
                .clipped()
                .cornerRadius(12)

            // Name
            Text(restaurant.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Optional meta (cuisine + rating + ETA)
            HStack(spacing: 6) {
                if let cuisine = restaurant.cuisine { Text(cuisine).foregroundStyle(.secondary) }
                if let rating = restaurant.rating { Text("• \(String(format: "%.1f", rating))★").foregroundStyle(.secondary) }
                if let eta = restaurant.etaMinutes { Text("• \(eta) min").foregroundStyle(.secondary) }
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Detail Placeholder
private struct RestaurantDetailPlaceholder: View {
    let restaurant: Restaurant
    var body: some View {
        VStack(spacing: 16) {
            AsyncImage(url: restaurant.imageURL) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        Rectangle().fill(Color(.secondarySystemFill))
                        ProgressView()
                    }
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    Image(systemName: "photo").font(.largeTitle)
                @unknown default:
                    Color(.secondarySystemFill)
                }
            }
            .frame(height: 220)
            .cornerRadius(12)

            Text(restaurant.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let cuisine = restaurant.cuisine {
                Text(cuisine).foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Restaurant")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Model & Sample Data (in-file to avoid new files)
private struct Restaurant: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let imageURL: URL?
    let cuisine: String?
    let rating: Double?
    let etaMinutes: Int?

    init(id: UUID = UUID(), name: String, imageURL: URL?, cuisine: String? = nil, rating: Double? = nil, etaMinutes: Int? = nil) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
        self.cuisine = cuisine
        self.rating = rating
        self.etaMinutes = etaMinutes
    }
}

private enum SampleData {
    static let restaurants: [Restaurant] = [
        Restaurant(name: "Blue Whale Sushi", imageURL: URL(string: "https://images.unsplash.com/photo-1544025162-d76694265947?w=1200&q=80"), cuisine: "Japanese", rating: 4.7, etaMinutes: 25),
        Restaurant(name: "Panda Noodles", imageURL: URL(string: "https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?w=1200&q=80"), cuisine: "Chinese", rating: 4.5, etaMinutes: 20),
        Restaurant(name: "Marina Burger", imageURL: URL(string: "https://images.unsplash.com/photo-1550547660-d9450f859349?w=1200&q=80"), cuisine: "Burgers", rating: 4.3, etaMinutes: 18),
        Restaurant(name: "Harbor Coffee", imageURL: URL(string: "https://images.unsplash.com/photo-1504754524776-8f4f37790ca0?w=1200&q=80"), cuisine: "Cafe", rating: 4.6, etaMinutes: 15),
        Restaurant(name: "Ocean Curry House", imageURL: URL(string: "https://images.unsplash.com/photo-1604908176997-43162b14b4f9?w=1200&q=80"), cuisine: "Indian", rating: 4.4, etaMinutes: 30),
        Restaurant(name: "Seagull Pizza", imageURL: URL(string: "https://images.unsplash.com/photo-1548365328-9f547fb09530?w=1200&q=80"), cuisine: "Pizza", rating: 4.2, etaMinutes: 22),
    ]
}

#Preview {
    HomeView()
}
