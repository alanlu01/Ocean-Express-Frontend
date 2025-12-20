import SwiftUI

struct RestaurantReviewsView: View {
    let restaurantId: String
    let restaurantName: String
    let rating: Double?
    var initialReviews: [RestaurantAPI.Review] = []

    @State private var reviews: [RestaurantAPI.Review] = []
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let rating {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f / 5.0", rating))
                            .font(.headline)
                    }
                    .padding(.vertical, 4)
                }

                if reviews.isEmpty {
                    ContentUnavailableView("目前沒有評論", systemImage: "text.bubble")
                } else {
                    ForEach(reviews) { review in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(review.userName ?? "匿名用戶")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                HStack(spacing: 2) {
                                    ForEach(1...5, id: \.self) { idx in
                                        Image(systemName: idx <= review.rating ? "star.fill" : "star")
                                            .foregroundColor(.yellow)
                                    }
                                }
                                .font(.caption)
                            }
                            if let comment = review.comment, !comment.isEmpty {
                                Text(comment)
                                    .font(.subheadline)
                            }
                            if let created = review.createdAt {
                                Text(created, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("所有評論")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        if !initialReviews.isEmpty {
            reviews = initialReviews
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await RestaurantAPI.fetchReviews(restaurantId: restaurantId)
            if !data.isEmpty {
                reviews = data
            }
        } catch {
            // ignore errors, keep current list
        }
    }
}
