import Foundation
import CoreLocation

struct DeliveryDestination: Identifiable, Hashable {
    let id: String
    let name: String
    let latitude: Double?
    let longitude: Double?

    init(name: String, latitude: Double?, longitude: Double?) {
        self.id = name
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

struct DeliveryLocationCategory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let destinations: [DeliveryDestination]
}

enum DeliveryCatalog {
    static let defaultDestination: DeliveryDestination = DeliveryDestination(name: "未設定", latitude: nil, longitude: nil)
}
