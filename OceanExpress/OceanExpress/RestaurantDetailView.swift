import Foundation

// Shared Restaurant model (moved here so it is visible project-wide)
struct Restaurant: Identifiable, Hashable, Codable {
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
