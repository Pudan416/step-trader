import Foundation
import CoreLocation

struct EnergyDrop: Identifiable, Codable, Equatable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let energy: Int
    let expiresAt: Date
    let spawnedAt: Date
    
    var isExpired: Bool {
        Date() > expiresAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, energy, expiresAt, spawnedAt
    }
    
    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, energy: Int, expiresAt: Date, spawnedAt: Date = Date()) {
        self.id = id
        self.coordinate = coordinate
        self.energy = energy
        self.expiresAt = expiresAt
        self.spawnedAt = spawnedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        energy = try container.decode(Int.self, forKey: .energy)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        spawnedAt = try container.decode(Date.self, forKey: .spawnedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(energy, forKey: .energy)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(spawnedAt, forKey: .spawnedAt)
    }
    
    static func == (lhs: EnergyDrop, rhs: EnergyDrop) -> Bool {
        lhs.id == rhs.id
    }
}

