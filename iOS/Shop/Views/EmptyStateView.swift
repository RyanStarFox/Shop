import SwiftUI
import ShopCore

struct EmptyStateView: View {
    @Binding var showAddSheet: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 140, height: 140)

                Image(systemName: "cart")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .shadow(color: .black.opacity(0.05), radius: 20)

            VStack(spacing: 8) {
                Text(ShopStrings.appName)
                    .font(.title.weight(.bold))

                Text(ShopStrings.emptyList)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            GlassButton(
                ShopStrings.addItem,
                systemImage: "plus.circle.fill",
                isFullWidth: false
            ) {
                showAddSheet = true
            }

            Spacer()
        }
        .padding()
    }
}

struct ActiveFilterBar: View {
    @Binding var currentFilter: DataStore.FilterOption
    @Binding var selectedTags: Set<UUID>
    let allTags: [Tag]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if currentFilter != .all {
                    FilterChip(
                        label: filterLabel,
                        color: .accentColor
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
        case .all: return ShopStrings.filterAll
        case .active: return ShopStrings.filterActive
        case .completed: return ShopStrings.filterCompleted
        case .today: return ShopStrings.filterToday
        case .week: return ShopStrings.filterWeek
        case .month: return ShopStrings.filterMonth
        }
    }
}

struct FilterChip: View {
    let label: String
    let color: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(color.opacity(0.15))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                }
        }
        .foregroundStyle(color)
    }
}
