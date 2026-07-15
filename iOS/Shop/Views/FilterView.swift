import SwiftUI
import ShopCore

struct FilterView: View {
    @EnvironmentObject private var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var localFilter: DataStore.FilterOption
    @State private var localTags: Set<UUID>
    @State private var showDatePicker = false
    @State private var startDate = Date().addingTimeInterval(-7 * 86400)
    @State private var endDate = Date()

    init() {
        _localFilter = State(initialValue: .all)
        _localTags = State(initialValue: [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(ShopStrings.filter) {
                    ForEach(DataStore.FilterOption.allCases, id: \.self) { option in
                        Button {
                            localFilter = option
                        } label: {
                            HStack {
                                Text(filterLabel(for: option))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if localFilter == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(ShopTheme.naturalGreen)
                                }
                            }
                            .frame(minHeight: ShopTheme.minTouchTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(localFilter == option ? .isSelected : [])
                        .accessibilityLabel(filterLabel(for: option))
                    }
                }

                if !dataStore.tags.isEmpty {
                    Section(ShopStrings.tags) {
                        ForEach(dataStore.tags) { tag in
                            Button {
                                toggleTag(tag.id)
                            } label: {
                                HStack(spacing: ShopTheme.spacingSM) {
                                    Circle()
                                        .fill(tag.displayColor)
                                        .frame(width: 10, height: 10)
                                    Text(tag.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if localTags.contains(tag.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(ShopTheme.naturalGreen)
                                    }
                                }
                                .frame(minHeight: ShopTheme.minTouchTarget)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(localTags.contains(tag.id) ? .isSelected : [])
                            .accessibilityLabel(tag.name)
                        }
                    }
                }

                Section {
                    Toggle(ShopStrings.filterCustomDateRange, isOn: $showDatePicker)
                        .tint(ShopTheme.naturalGreen)

                    if showDatePicker {
                        DatePicker(
                            ShopStrings.filterStartDate,
                            selection: $startDate,
                            displayedComponents: [.date]
                        )
                        DatePicker(
                            ShopStrings.filterEndDate,
                            selection: $endDate,
                            displayedComponents: [.date]
                        )
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ShopSurfaceBackground())
            .navigationTitle(ShopStrings.filter)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(ShopStrings.filterReset) {
                        resetFilters()
                    }
                    .accessibilityLabel(ShopStrings.filterReset)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ShopStrings.filter) {
                        applyFilter()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel(ShopStrings.filter)
                }
            }
            .onAppear {
                localFilter = dataStore.selectedFilter
                localTags = dataStore.selectedTags
                if let range = dataStore.dateRange {
                    showDatePicker = true
                    startDate = range.lowerBound
                    endDate = range.upperBound
                }
            }
        }
        .tint(ShopTheme.naturalGreen)
    }

    private func filterLabel(for option: DataStore.FilterOption) -> String {
        switch option {
        case .all: ShopStrings.filterAll
        case .active: ShopStrings.filterActive
        case .completed: ShopStrings.filterCompleted
        case .today: ShopStrings.filterToday
        case .week: ShopStrings.filterWeek
        case .month: ShopStrings.filterMonth
        }
    }

    private func toggleTag(_ id: UUID) {
        if localTags.contains(id) {
            localTags.remove(id)
        } else {
            localTags.insert(id)
        }
    }

    private func resetFilters() {
        localFilter = .all
        localTags = []
        showDatePicker = false
        startDate = Date().addingTimeInterval(-7 * 86400)
        endDate = Date()
    }

    private func applyFilter() {
        dataStore.selectedFilter = localFilter
        dataStore.selectedTags = localTags
        if showDatePicker {
            dataStore.dateRange = startDate...endDate
        } else {
            dataStore.dateRange = nil
        }
    }
}
