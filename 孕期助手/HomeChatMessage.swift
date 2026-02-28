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

    var id: String
    var role: Role
    var kind: Kind
    var text: String
    var createdAt: Date

    init(role: Role, kind: Kind, text: String, createdAt: Date = Date()) {
        self.id = UUID().uuidString
        self.role = role
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
    }
}
