import Foundation
import SwiftData

@Model
public final class Tag: Identifiable, Hashable {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var colorHex: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#007AFF",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }

    public var color: PlatformColor {
        PlatformColor(hex: colorHex) ?? .systemBlue
    }
}
