import Foundation

public struct SnapshotMerger: Sendable {
    public init() {}

    public func merge(local: SyncSnapshot, remote: SyncSnapshot) -> SyncSnapshot {
        let tags = mergeTags(local.tags, remote.tags)
        let availableTagIDs = Set(tags.lazy.filter { $0.deletedAt == nil }.map(\.id))
        let items = mergeItems(local.items, remote.items).map { item in
            ItemSnapshot(
                id: item.id,
                name: item.name,
                isCompleted: item.isCompleted,
                createdAt: item.createdAt,
                completedAt: item.completedAt,
                updatedAt: item.updatedAt,
                deletedAt: item.deletedAt,
                sortOrder: item.sortOrder,
                tagIDs: Array(Set(item.tagIDs.filter { availableTagIDs.contains($0) }))
                    .sorted { $0.uuidString < $1.uuidString },
                lastEditorDeviceID: item.lastEditorDeviceID
            )
        }

        return SyncSnapshot(
            version: SyncSnapshot.currentVersion,
            generatedAt: max(local.generatedAt, remote.generatedAt),
            items: items,
            tags: tags
        )
    }

    private func mergeItems(
        _ local: [ItemSnapshot],
        _ remote: [ItemSnapshot]
    ) -> [ItemSnapshot] {
        var records: [UUID: ItemSnapshot] = [:]
        for item in local + remote {
            if let existing = records[item.id] {
                records[item.id] = winner(between: existing, and: item)
            } else {
                records[item.id] = item
            }
        }
        return records.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func mergeTags(
        _ local: [TagSnapshot],
        _ remote: [TagSnapshot]
    ) -> [TagSnapshot] {
        var records: [UUID: TagSnapshot] = [:]
        for tag in local + remote {
            if let existing = records[tag.id] {
                records[tag.id] = winner(between: existing, and: tag)
            } else {
                records[tag.id] = tag
            }
        }
        return records.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func winner(between lhs: ItemSnapshot, and rhs: ItemSnapshot) -> ItemSnapshot {
        let lhsVersion = (lhs.updatedAt, lhs.lastEditorDeviceID)
        let rhsVersion = (rhs.updatedAt, rhs.lastEditorDeviceID)
        if lhsVersion != rhsVersion {
            return lhsVersion > rhsVersion ? lhs : rhs
        }
        return itemFingerprint(lhs) >= itemFingerprint(rhs) ? lhs : rhs
    }

    private func winner(between lhs: TagSnapshot, and rhs: TagSnapshot) -> TagSnapshot {
        let lhsVersion = (lhs.updatedAt, lhs.lastEditorDeviceID)
        let rhsVersion = (rhs.updatedAt, rhs.lastEditorDeviceID)
        if lhsVersion != rhsVersion {
            return lhsVersion > rhsVersion ? lhs : rhs
        }
        return tagFingerprint(lhs) >= tagFingerprint(rhs) ? lhs : rhs
    }

    private func itemFingerprint(_ item: ItemSnapshot) -> String {
        [
            item.id.uuidString,
            item.name,
            item.isCompleted.description,
            item.createdAt.timeIntervalSinceReferenceDate.description,
            item.completedAt?.timeIntervalSinceReferenceDate.description ?? "",
            item.deletedAt?.timeIntervalSinceReferenceDate.description ?? "",
            item.sortOrder.description,
            item.tagIDs.map(\.uuidString).sorted().joined(separator: ",")
        ].joined(separator: "\u{1F}")
    }

    private func tagFingerprint(_ tag: TagSnapshot) -> String {
        [
            tag.id.uuidString,
            tag.name,
            tag.colorHex,
            tag.createdAt.timeIntervalSinceReferenceDate.description,
            tag.deletedAt?.timeIntervalSinceReferenceDate.description ?? ""
        ].joined(separator: "\u{1F}")
    }
}
