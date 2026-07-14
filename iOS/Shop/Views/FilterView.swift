import SwiftUI
import ShopCore

struct FilterView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss

    @State private var localFilter: DataStore.FilterOption
    @State private var localTags: Set<UUID>
    @State private var showDatePicker = false
    @State private var startDate = Date().addingTimeInterval(-7 * 86400)
    @State private var endDate = Date()

    init() {
        _localFilter = State(initialValue: DataStore.FilterOption.all)
        _localTags = State(initialValue: [])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        // Time filter
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(ShopStrings.filter, systemImage: "clock.arrow.2.circlepath")
                                    .font(.headline)

                                Picker(ShopStrings.filter, selection: $localFilter) {
                                    ForEach(DataStore.FilterOption.allCases, id: \.self) { opt in
                                        Text(filterLabel(for: opt)).tag(opt)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        .padding(.horizontal)

                        // Tags filter
                        if !dataStore.tags.isEmpty {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Label(ShopStrings.tags, systemImage: "tag")
                                        .font(.headline)

                                    LazyVGrid(
                                        columns: [GridItem(.adaptive(minimum: 90), spacing: 8)],
                                        spacing: 8
                                    ) {
                                        ForEach(dataStore.tags) { tag in
                                            TagChip(
                                                tag: tag,
                                                isSelected: localTags.contains(tag.id),
                                                onTap: {
                                                    if localTags.contains(tag.id) {
                                                        localTags.remove(tag.id)
                                                    } else {
                                                        localTags.insert(tag.id)
                                                    }
                                                }
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }

                        // Date range
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Button {
                                    showDatePicker.toggle()
                                } label: {
                                    HStack {
                                        Label("Custom date range", systemImage: "calendar")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: showDatePicker ? "chevron.up" : "chevron.down")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)

                                if showDatePicker {
                                    DatePicker("Start", selection: $startDate, displayedComponents: [.date])
                                        .datePickerStyle(.compact)
                                    DatePicker("End", selection: $endDate, displayedComponents: [.date])
                                        .datePickerStyle(.compact)
                                }
                            }
                        }
                        .padding(.horizontal)

                        // Apply button
                        GlassButton(ShopStrings.filter, systemImage: "checkmark", isFullWidth: true) {
                            applyFilter()
                            dismiss()
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle(ShopStrings.filter)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        localFilter = .all
                        localTags = []
                        startDate = Date().addingTimeInterval(-7 * 86400)
                        endDate = Date()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear {
                localFilter = dataStore.selectedFilter
                localTags = dataStore.selectedTags
            }
        }
    }

    private func filterLabel(for opt: DataStore.FilterOption) -> String {
        switch opt {
        case .all: return ShopStrings.filterAll
        case .active: return ShopStrings.filterActive
        case .completed: return ShopStrings.filterCompleted
        case .today: return ShopStrings.filterToday
        case .week: return ShopStrings.filterWeek
        case .month: return ShopStrings.filterMonth
        }
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
