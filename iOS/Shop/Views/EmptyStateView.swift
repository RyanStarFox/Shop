import SwiftUI
import ShopCore

struct EmptyStateView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: ShopTheme.spacingLG) {
            Spacer()

            Image(systemName: "cart")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: ShopTheme.spacingSM) {
                Text(ShopStrings.appName)
                    .font(.title2.weight(.semibold))

                Text(ShopStrings.emptyList)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            GlassButton(
                ShopStrings.addItem,
                systemImage: "plus.circle.fill"
            ) {
                onAdd()
            }

            Spacer()
        }
        .padding(ShopTheme.spacingMD)
    }
}

struct ActiveFilterBar: View {
    @Binding var currentFilter: DataStore.FilterOption
    @Binding var selectedTags: Set<UUID>
    let allTags: [Tag]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ShopTheme.spacingSM) {
                if currentFilter != .all {
                    FilterChip(
                        label: filterLabel,
                        color: ShopTheme.naturalGreen
                    ) {
                        currentFilter = .all
                    }
                }

                ForEach(allTags.filter { selectedTags.contains($0.id) }) { tag in
                    FilterChip(label: tag.name, color: tag.displayColor) {
                        selectedTags.remove(tag.id)
                    }
                }
            }
        }
    }

    private var filterLabel: String {
        switch currentFilter {
        case .all: ShopStrings.filterAll
        case .active: ShopStrings.filterActive
        case .completed: ShopStrings.filterCompleted
        case .today: ShopStrings.filterToday
        case .week: ShopStrings.filterWeek
        case .month: ShopStrings.filterMonth
        }
    }
}

struct FilterChip: View {
    let label: String
    let color: Color
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: ShopTheme.spacingXS) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, ShopTheme.spacingSM + 4)
            .frame(minHeight: ShopTheme.minTouchTarget)
            .background {
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(color.opacity(0.25), lineWidth: 1)
                    }
            }
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ShopStrings.filterReset)
        .accessibilityValue(label)
    }
}
