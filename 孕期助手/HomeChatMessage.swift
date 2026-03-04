import Foundation

struct HomeChatMessage: Identifiable, Codable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    enum Kind: String, Codable {
        case text
        case cards
    }

    enum DeliveryStatus: String, Codable {
        case sent
        case failed
    }

    var id: String
    var role: Role
    var kind: Kind
    var text: String
    var createdAt: Date
    var deliveryStatus: DeliveryStatus?
    var deliveryError: String?

    init(
        role: Role,
        kind: Kind,
        text: String,
        createdAt: Date = Date(),
        deliveryStatus: DeliveryStatus? = nil,
        deliveryError: String? = nil
    ) {
        self.id = UUID().uuidString
        self.role = role
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.deliveryStatus = deliveryStatus
        self.deliveryError = deliveryError
    }
}
