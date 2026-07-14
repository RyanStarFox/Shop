import Foundation
import SwiftData

@Model
public final class Tag: Identifiable, Hashable {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var colorHex: String
    public var createdAt: Date
    public var updatedAt: Date = Date(timeIntervalSince1970: 0)
    public var deletedAt: Date? = nil
    public var lastEditorDeviceID: String = ""
    public var recordSchemaVersion: Int = 0

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#007AFF",
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        lastEditorDeviceID: String = "",
        recordSchemaVersion: Int = 2
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
        self.lastEditorDeviceID = lastEditorDeviceID
        self.recordSchemaVersion = recordSchemaVersion
    }

    public var color: PlatformColor {
        PlatformColor(hex: colorHex) ?? .blue
    }
}
