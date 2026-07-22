import Foundation

public struct SyncSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public let version: Int
    public let generatedAt: Date
    public var items: [ItemSnapshot]
    public var tags: [TagSnapshot]

    public init(
        version: Int = Self.currentVersion,
        generatedAt: Date,
        items: [ItemSnapshot],
        tags: [TagSnapshot]
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.items = items
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case generatedAt
        case items
        case tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        let items = try container.decode([ItemSnapshot].self, forKey: .items)
        let tags = try container.decode([TagSnapshot].self, forKey: .tags)

        self.version = version
        self.generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date(timeIntervalSince1970: 0)
        self.items = items
        self.tags = tags
    }
}

public struct ItemSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let isCompleted: Bool
    public let createdAt: Date
    public let completedAt: Date?
    public let updatedAt: Date
    public let deletedAt: Date?
    public let sortOrder: Int
    public let tagIDs: [UUID]
    /// Advances only when tag membership changes. Scalar edits (complete/rename) use `updatedAt`.
    public let tagMembershipUpdatedAt: Date
    public let lastEditorDeviceID: String

    public init(
        id: UUID,
        name: String,
        isCompleted: Bool,
        createdAt: Date,
        completedAt: Date?,
        updatedAt: Date,
        deletedAt: Date?,
        sortOrder: Int,
        tagIDs: [UUID],
        tagMembershipUpdatedAt: Date? = nil,
        lastEditorDeviceID: String
    ) {
        self.id = id
        self.name = name
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.sortOrder = sortOrder
        self.tagIDs = tagIDs
        // Prefer createdAt over updatedAt so legacy/missing membership does not inherit
        // scalar edits (complete/rename) as if they changed tags.
        self.tagMembershipUpdatedAt = tagMembershipUpdatedAt ?? createdAt
        self.lastEditorDeviceID = lastEditorDeviceID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isCompleted
        case createdAt
        case completedAt
        case updatedAt
        case deletedAt
        case sortOrder
        case tagIDs
        case tagIds
        case tagMembershipUpdatedAt
        case lastEditorDeviceID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        self.createdAt = createdAt
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        let updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        self.updatedAt = updatedAt
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        self.sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        self.tagIDs = try container.decodeIfPresent([UUID].self, forKey: .tagIDs)
            ?? container.decodeIfPresent([UUID].self, forKey: .tagIds)
            ?? []
        self.tagMembershipUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .tagMembershipUpdatedAt)
            ?? createdAt
        self.lastEditorDeviceID = try container.decodeIfPresent(String.self, forKey: .lastEditorDeviceID) ?? "legacy"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(tagIDs, forKey: .tagIDs)
        try container.encode(tagMembershipUpdatedAt, forKey: .tagMembershipUpdatedAt)
        try container.encode(lastEditorDeviceID, forKey: .lastEditorDeviceID)
    }
}

public struct TagSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let colorHex: String
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?
    public let lastEditorDeviceID: String

    public init(
        id: UUID,
        name: String,
        colorHex: String,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        lastEditorDeviceID: String
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.lastEditorDeviceID = lastEditorDeviceID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorHex
        case createdAt
        case updatedAt
        case deletedAt
        case lastEditorDeviceID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.colorHex = try container.decode(String.self, forKey: .colorHex)
        self.createdAt = createdAt
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        self.lastEditorDeviceID = try container.decodeIfPresent(String.self, forKey: .lastEditorDeviceID) ?? "legacy"
    }
}
