import WidgetKit
import SwiftUI
import AppIntents
import ShopCore

// MARK: - Deep link

enum ShopWidgetLinks {
    static let addItem = URL(string: "shop://add")!
}

// MARK: - Intents

struct CompleteItemIntent: AppIntent {
    static var title: LocalizedStringResource { "Complete Item" }
    static var description: IntentDescription {
        IntentDescription("Marks a shopping item as purchased.")
    }

    @Parameter(title: "Item ID")
    var itemID: String

    init() { itemID = "" }
    init(itemID: UUID) { self.itemID = itemID.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemID) else { return .result() }
        WidgetSnapshotStore.markCompleteInSnapshot(itemID: id)
        BackgroundSyncRequest.noteWidgetMutation()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct RestoreItemIntent: AppIntent {
    static var title: LocalizedStringResource { "Restore Item" }
    static var description: IntentDescription {
        IntentDescription("Restores a completed shopping item to pending.")
    }

    @Parameter(title: "Item ID")
    var itemID: String

    init() { itemID = "" }
    init(itemID: UUID) { self.itemID = itemID.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemID) else { return .result() }
        WidgetSnapshotStore.restoreInSnapshot(itemID: id)
        BackgroundSyncRequest.noteWidgetMutation()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Configuration entities

enum WidgetMatchModeAppEnum: String, AppEnum {
    case any
    case all

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Match Mode")
    }

    static var caseDisplayRepresentations: [WidgetMatchModeAppEnum: DisplayRepresentation] {
        [
            .any: DisplayRepresentation(title: "Match Any"),
            .all: DisplayRepresentation(title: "Match All")
        ]
    }
}

struct ShopTagEntity: AppEntity {
    let id: UUID
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Tag")
    }

    static var defaultQuery: ShopTagEntityQuery {
        ShopTagEntityQuery()
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ShopTagEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ShopTagEntity] {
        let all = try await suggestedEntities()
        let map = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return identifiers.compactMap { map[$0] }
    }

    func suggestedEntities() async throws -> [ShopTagEntity] {
        let snapshot = WidgetSnapshotStore.load()
        let activeTagIDs = Set(snapshot.items.flatMap { $0.tags.map(\.id) })
        let allTags = ShopTagEntity(
            id: WidgetItemFilter.allTagsSentinel,
            name: ShopStrings.widgetFilterAllTags
        )
        let activeTags = snapshot.availableTags
            .filter { activeTagIDs.contains($0.id) }
            .map { ShopTagEntity(id: $0.id, name: $0.name) }
        return [allTags] + activeTags
    }
}

struct ShopWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Shop Widget" }
    static var description: IntentDescription {
        IntentDescription("Shows pending shopping items filtered by tags.")
    }

    @Parameter(title: "Tags", default: [])
    var tags: [ShopTagEntity]?

    @Parameter(title: "Match Mode", default: .any)
    var matchMode: WidgetMatchModeAppEnum
}

// MARK: - Timeline

struct ShopWidgetEntry: TimelineEntry {
    let date: Date
    let items: [WidgetSnapshotStore.Entry]
    let recentlyCompleted: [WidgetSnapshotStore.Entry]
    let isFiltered: Bool
    let isSharedStoreAvailable: Bool
}

struct ShopWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ShopWidgetEntry {
        let dairy = WidgetSnapshotStore.TagInfo(id: UUID(), name: "Dairy", colorHex: "#007AFF")
        let bakery = WidgetSnapshotStore.TagInfo(id: UUID(), name: "Bakery", colorHex: "#FF9500")
        return ShopWidgetEntry(
            date: Date(),
            items: [
                WidgetSnapshotStore.Entry(id: UUID(), name: "Milk", sortOrder: 0, tags: [dairy]),
                WidgetSnapshotStore.Entry(id: UUID(), name: "Bread", sortOrder: 1, tags: [bakery])
            ],
            recentlyCompleted: [
                WidgetSnapshotStore.Entry(
                    id: UUID(),
                    name: "Eggs",
                    sortOrder: 0,
                    tags: [],
                    completedAt: Date()
                )
            ],
            isFiltered: false,
            isSharedStoreAvailable: true
        )
    }

    func snapshot(for configuration: ShopWidgetConfigurationIntent, in context: Context) async -> ShopWidgetEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: ShopWidgetConfigurationIntent, in context: Context) async -> Timeline<ShopWidgetEntry> {
        let entry = entry(for: configuration)
        return Timeline(
            entries: [entry],
            policy: .after(BackgroundSyncSchedule.nextEarliestBeginDate())
        )
    }

    private func entry(for configuration: ShopWidgetConfigurationIntent) -> ShopWidgetEntry {
        let snapshot = WidgetSnapshotStore.load()
        let selected = Set((configuration.tags ?? []).map(\.id))
        let mode: WidgetTagMatchMode = configuration.matchMode == .all ? .all : .any
        let isFiltered = !selected.isEmpty && !selected.contains(WidgetItemFilter.allTagsSentinel)
        return ShopWidgetEntry(
            date: Date(),
            items: WidgetItemFilter.filtered(
                items: snapshot.items,
                selectedTagIDs: selected,
                matchMode: mode
            ),
            recentlyCompleted: WidgetItemFilter.filtered(
                items: snapshot.recentlyCompleted,
                selectedTagIDs: selected,
                matchMode: mode
            ),
            isFiltered: isFiltered,
            isSharedStoreAvailable: WidgetSnapshotStore.isSharedContainerAvailable
        )
    }
}

// MARK: - Views

struct ShopWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ShopWidgetEntry

    private var layoutFamily: WidgetLayoutFamily {
        switch family {
        case .systemSmall: .small
        case .systemLarge: .large
        default: .medium
        }
    }

    private var activeColumns: [[WidgetSnapshotStore.Entry]] {
        WidgetLayoutRules.activeColumns(for: entry.items, family: layoutFamily)
    }

    private var recentColumns: [[WidgetSnapshotStore.Entry]] {
        WidgetLayoutRules.recentColumns(for: entry.recentlyCompleted, family: layoutFamily)
    }

    private var usesCompactTagDots: Bool {
        WidgetLayoutRules.usesCompactTagDots(activeCount: entry.items.count, family: layoutFamily)
    }

    private var showsAppTitle: Bool {
        family != .systemSmall
    }

    private var usesSmallTypography: Bool {
        layoutFamily == .small
    }

    private var contentSpacing: CGFloat { usesSmallTypography ? 4 : 8 }
    private var activeListSpacing: CGFloat { usesSmallTypography ? 3 : 8 }
    private var activeRowHeight: CGFloat { usesSmallTypography ? 22 : 28 }
    private var recentRowHeight: CGFloat { usesSmallTypography ? 20 : 22 }

    private var pinnedActiveHeight: CGFloat {
        let rows = CGFloat(WidgetLayoutRules.activeReservedRows(family: layoutFamily))
        return rows * activeRowHeight + max(0, rows - 1) * activeListSpacing
    }

    private var pinnedRecentHeight: CGFloat {
        let rows = CGFloat(WidgetLayoutRules.recentReservedRows(family: layoutFamily))
        let bandSpacing: CGFloat = usesSmallTypography ? 3 : 6
        return 1 + bandSpacing + rows * recentRowHeight + max(0, rows - 1) * bandSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            header
            activeBand
            pinnedRecentBand
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, usesSmallTypography ? 0 : 2)
        .containerBackground(for: .widget) {
            #if os(iOS)
            Color(.systemBackground)
            #else
            Color(nsColor: .windowBackgroundColor)
            #endif
        }
    }

    private var activeBand: some View {
        Group {
            if entry.items.isEmpty && entry.recentlyCompleted.isEmpty {
                emptyState
            } else if !entry.items.isEmpty {
                itemList
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, minHeight: pinnedActiveHeight, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: usesSmallTypography ? 6 : 8) {
            if showsAppTitle {
                Text(ShopStrings.appName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ShopTheme.brandColor)
                    .lineLimit(1)
            }
            Text(ShopStrings.pendingCount(entry.items.count))
                .font(showsAppTitle ? .footnote.weight(.medium) : (usesSmallTypography ? .callout.weight(.semibold) : .body.weight(.semibold)))
                .foregroundStyle(showsAppTitle ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Link(destination: ShopWidgetLinks.addItem) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(ShopTheme.brandColor)
                    .accessibilityLabel(ShopStrings.widgetAddItem)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "cart")
                .font(.title)
                .foregroundStyle(ShopTheme.brandColor)
            Text(
                !entry.isSharedStoreAvailable
                    ? ShopStrings.widgetUnavailable
                    : (entry.isFiltered ? ShopStrings.widgetFilterEmpty : ShopStrings.widgetEmpty)
            )
                .font(usesSmallTypography ? .caption : .callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var itemList: some View {
        Group {
            if activeColumns.count > 1 {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(activeColumns.enumerated()), id: \.offset) { _, column in
                        VStack(alignment: .leading, spacing: activeListSpacing) {
                            ForEach(column) { item in
                                activeRow(item, compactTags: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: activeListSpacing) {
                    ForEach(activeColumns.first ?? []) { item in
                        activeRow(item, compactTags: usesCompactTagDots)
                    }
                }
            }
        }
    }

    private func activeRow(_ item: WidgetSnapshotStore.Entry, compactTags: Bool) -> some View {
        HStack(spacing: usesSmallTypography ? 4 : 8) {
            Button(intent: CompleteItemIntent(itemID: item.id)) {
                Image(systemName: "circle")
                    .font(usesSmallTypography ? .body : .title3)
                    .foregroundStyle(ShopTheme.brandColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.name), \(ShopStrings.markComplete)")

            Text(item.name)
                .font(usesSmallTypography ? .callout.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)

            if !item.tags.isEmpty {
                Spacer(minLength: usesSmallTypography ? 2 : 4)
                WidgetTagRow(
                    tags: item.tags,
                    namedLimit: compactTags ? 1 : 3,
                    colorOnlyLimit: compactTags ? 3 : 7,
                    collapseToColorsWhenOverNamedLimit: true,
                    compact: usesSmallTypography || compactTags
                )
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: activeRowHeight, alignment: .leading)
    }

    private var pinnedRecentBand: some View {
        VStack(alignment: .leading, spacing: usesSmallTypography ? 3 : 6) {
            Divider()
            HStack(alignment: .top, spacing: usesSmallTypography ? 6 : 8) {
                if recentColumns.isEmpty {
                    Color.clear
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(Array(recentColumns.enumerated()), id: \.offset) { _, column in
                        VStack(alignment: .leading, spacing: usesSmallTypography ? 3 : 6) {
                            ForEach(column) { item in
                                recentCell(item)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: pinnedRecentHeight, alignment: .topLeading)
    }

    private func recentCell(_ item: WidgetSnapshotStore.Entry) -> some View {
        HStack(spacing: usesSmallTypography ? 4 : 6) {
            Button(intent: RestoreItemIntent(itemID: item.id)) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.name), \(ShopStrings.widgetRestoreItem)")

            Text(item.name)
                .font(.callout)
                .foregroundStyle(.secondary)
                .strikethrough()
                .lineLimit(1)
        }
    }
}

private struct WidgetTagRow: View {
    let tags: [WidgetSnapshotStore.TagInfo]
    let namedLimit: Int
    let colorOnlyLimit: Int
    let collapseToColorsWhenOverNamedLimit: Bool
    var compact: Bool = false

    var body: some View {
        let parts = WidgetTagDisplay.presentation(
            tags: tags,
            namedLimit: namedLimit,
            colorOnlyLimit: colorOnlyLimit,
            collapseToColorsWhenOverNamedLimit: collapseToColorsWhenOverNamedLimit
        )
        let dotSize: CGFloat = compact ? 5 : 7
        HStack(spacing: compact ? 2 : 4) {
            ForEach(parts.named, id: \.id) { tag in
                HStack(spacing: compact ? 2 : 3) {
                    Circle()
                        .fill(Color(shopHex: tag.colorHex) ?? .secondary)
                        .frame(width: dotSize, height: dotSize)
                    Text(tag.name)
                        .font(compact ? .callout : .footnote)
                        .foregroundStyle(Color(shopHex: tag.colorHex) ?? .secondary)
                        .lineLimit(1)
                }
            }
            ForEach(parts.colorOnly, id: \.id) { tag in
                Circle()
                    .fill(Color(shopHex: tag.colorHex) ?? .secondary)
                    .frame(width: dotSize, height: dotSize)
                    .accessibilityHidden(true)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tags.map(\.name).joined(separator: ", "))
    }
}

// MARK: - Widget

struct ShopWidget: Widget {
    let kind = "ShopWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ShopWidgetConfigurationIntent.self,
            provider: ShopWidgetProvider()
        ) { entry in
            ShopWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(ShopStrings.appName)
        .description(ShopStrings.widgetDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ShopWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShopWidget()
    }
}
