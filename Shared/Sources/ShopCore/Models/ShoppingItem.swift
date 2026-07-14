import Foundation
import SwiftData

@Model
public final class ShoppingItem: Identifiable, Hashable {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var isCompleted: Bool
    public var createdAt: Date
    public var completedAt: Date?
    public var sortOrder: Int
    @Relationship(deleteRule: .nullify) public var tags: [Tag]

    public init(
        id: UUID = UUID(),
        name: String,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        sortOrder: Int = 0,
        tags: [Tag] = []
    ) {
        self.id = id
        self.name = name
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.sortOrder = sortOrder
        self.tags = tags
    }
}
