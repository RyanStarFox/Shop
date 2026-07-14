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
    public var updatedAt: Date = Date(timeIntervalSince1970: 0)
    public var deletedAt: Date? = nil
    public var lastEditorDeviceID: String = ""
    public var recordSchemaVersion: Int = 0
    @Relationship(deleteRule: .nullify) public var tags: [Tag]

    public init(
        id: UUID = UUID(),
        name: String,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        sortOrder: Int = 0,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        lastEditorDeviceID: String = "",
        recordSchemaVersion: Int = 2,
        tags: [Tag] = []
    ) {
        self.id = id
        self.name = name
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
        self.lastEditorDeviceID = lastEditorDeviceID
        self.recordSchemaVersion = recordSchemaVersion
        self.tags = tags
    }
}
