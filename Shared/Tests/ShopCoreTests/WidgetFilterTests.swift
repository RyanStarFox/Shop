import XCTest
@testable import ShopCore

final class WidgetFilterTests: XCTestCase {
    private let dairy = UUID()
    private let bakery = UUID()
    private let produce = UUID()
    private let unknown = UUID()

    private func entry(name: String, tags: [(UUID, String)]) -> WidgetSnapshotStore.Entry {
        WidgetSnapshotStore.Entry(
            id: UUID(),
            name: name,
            sortOrder: 0,
            tags: tags.map { WidgetSnapshotStore.TagInfo(id: $0.0, name: $0.1, colorHex: "#000000") }
        )
    }

    func testFilterAllTagsOrEmptySelectionReturnsAll() {
        let items = [
            entry(name: "Milk", tags: [(dairy, "Dairy")]),
            entry(name: "Bread", tags: [(bakery, "Bakery")])
        ]
        XCTAssertEqual(
            WidgetItemFilter.filtered(items: items, selectedTagIDs: [], matchMode: .any).map(\.name),
            ["Milk", "Bread"]
        )
        XCTAssertEqual(
            WidgetItemFilter.filtered(
                items: items,
                selectedTagIDs: [WidgetItemFilter.allTagsSentinel],
                matchMode: .all
            ).map(\.name),
            ["Milk", "Bread"]
        )
    }

    func testFilterORMatchesAnySelectedTag() {
        let items = [
            entry(name: "Milk", tags: [(dairy, "Dairy")]),
            entry(name: "Bread", tags: [(bakery, "Bakery")]),
            entry(name: "Butter", tags: [(dairy, "Dairy"), (bakery, "Bakery")])
        ]
        let result = WidgetItemFilter.filtered(
            items: items,
            selectedTagIDs: [dairy, produce],
            matchMode: .any
        )
        XCTAssertEqual(Set(result.map(\.name)), ["Milk", "Butter"])
    }

    func testFilterANDRequiresEverySelectedTag() {
        let items = [
            entry(name: "Milk", tags: [(dairy, "Dairy")]),
            entry(name: "Butter", tags: [(dairy, "Dairy"), (bakery, "Bakery")])
        ]
        let result = WidgetItemFilter.filtered(
            items: items,
            selectedTagIDs: [dairy, bakery],
            matchMode: .all
        )
        XCTAssertEqual(result.map(\.name), ["Butter"])
    }

    func testFilterIgnoresMissingTagIDsAndFallsBackWhenAllInvalid() {
        let items = [entry(name: "Milk", tags: [(dairy, "Dairy")])]
        let allInvalid = WidgetItemFilter.filtered(
            items: items,
            selectedTagIDs: [unknown],
            matchMode: .any
        )
        XCTAssertEqual(allInvalid.map(\.name), ["Milk"])

        let mixed = WidgetItemFilter.filtered(
            items: items,
            selectedTagIDs: [dairy, unknown],
            matchMode: .any
        )
        XCTAssertEqual(mixed.map(\.name), ["Milk"])
    }

    func testSmallNamedLimitShowsOneNameRestColorOnly() {
        let tags = (0..<4).map {
            WidgetSnapshotStore.TagInfo(id: UUID(), name: "T\($0)", colorHex: "#111111")
        }
        let result = WidgetTagDisplay.presentation(tags: tags, namedLimit: 1)
        XCTAssertEqual(result.named.count, 1)
        XCTAssertEqual(result.named.first?.name, "T0")
        XCTAssertEqual(result.colorOnly.count, 3)
    }

    func testMediumNamedLimitShowsThreeNames() {
        let tags = (0..<5).map {
            WidgetSnapshotStore.TagInfo(id: UUID(), name: "T\($0)", colorHex: "#111111")
        }
        let result = WidgetTagDisplay.presentation(tags: tags, namedLimit: 3)
        XCTAssertEqual(result.named.map(\.name), ["T0", "T1", "T2"])
        XCTAssertEqual(result.colorOnly.map(\.name), ["T3", "T4"])
    }

    func testCollapsedTagDisplayShowsSingleNameOnlyWhenThereIsOneTag() {
        let one = [WidgetSnapshotStore.TagInfo(id: UUID(), name: "Only", colorHex: "#111111")]
        let oneResult = WidgetTagDisplay.presentation(
            tags: one,
            namedLimit: 1,
            colorOnlyLimit: 3,
            collapseToColorsWhenOverNamedLimit: true
        )
        XCTAssertEqual(oneResult.named.map(\.name), ["Only"])
        XCTAssertTrue(oneResult.colorOnly.isEmpty)

        let many = (0..<5).map {
            WidgetSnapshotStore.TagInfo(id: UUID(), name: "T\($0)", colorHex: "#111111")
        }
        let manyResult = WidgetTagDisplay.presentation(
            tags: many,
            namedLimit: 1,
            colorOnlyLimit: 3,
            collapseToColorsWhenOverNamedLimit: true
        )
        XCTAssertTrue(manyResult.named.isEmpty)
        XCTAssertEqual(manyResult.colorOnly.map(\.name), ["T0", "T1", "T2"])
    }

    func testOneColumnMediumTagDisplayUsesNamesUntilThreeThenSevenColorDots() {
        let many = (0..<9).map {
            WidgetSnapshotStore.TagInfo(id: UUID(), name: "T\($0)", colorHex: "#111111")
        }
        let result = WidgetTagDisplay.presentation(
            tags: many,
            namedLimit: 3,
            colorOnlyLimit: 7,
            collapseToColorsWhenOverNamedLimit: true
        )
        XCTAssertTrue(result.named.isEmpty)
        XCTAssertEqual(result.colorOnly.map(\.name), ["T0", "T1", "T2", "T3", "T4", "T5", "T6"])
    }

    func testWidgetLayoutColumnsFillLeftColumnFirst() {
        let items = (0..<4).map {
            WidgetSnapshotStore.Entry(id: UUID(), name: "Item \($0)", sortOrder: $0)
        }
        let medium = WidgetLayoutRules.activeColumns(for: items, family: .medium)
        XCTAssertEqual(medium.map { $0.map(\.name) }, [
            ["Item 0", "Item 1"],
            ["Item 2", "Item 3"]
        ])

        let largeItems = (0..<12).map {
            WidgetSnapshotStore.Entry(id: UUID(), name: "Item \($0)", sortOrder: $0)
        }
        let large = WidgetLayoutRules.activeColumns(for: largeItems, family: .large)
        XCTAssertEqual(large[0].map(\.name), (0..<6).map { "Item \($0)" })
        XCTAssertEqual(large[1].map(\.name), (6..<12).map { "Item \($0)" })
        XCTAssertEqual(WidgetLayoutRules.activeReservedRows(family: .small), 3)
        XCTAssertEqual(WidgetLayoutRules.activeReservedRows(family: .medium), 2)
        XCTAssertEqual(WidgetLayoutRules.activeReservedRows(family: .large), 6)
        XCTAssertEqual(WidgetLayoutRules.recentReservedRows(family: .small), 1)
        XCTAssertEqual(WidgetLayoutRules.recentReservedRows(family: .medium), 1)
        XCTAssertEqual(WidgetLayoutRules.recentReservedRows(family: .large), 2)
    }

    func testRecentColumnsAdaptByCountForMediumAndLarge() {
        let items = (0..<7).map {
            WidgetSnapshotStore.Entry(id: UUID(), name: "Done \($0)", sortOrder: $0)
        }

        let medium = WidgetLayoutRules.recentColumns(for: items, family: .medium)
        XCTAssertEqual(medium.map { $0.map(\.name) }, [
            ["Done 0"],
            ["Done 1"],
            ["Done 2"]
        ])

        XCTAssertEqual(
            WidgetLayoutRules.recentColumns(for: Array(items.prefix(1)), family: .large).map { $0.map(\.name) },
            [["Done 0"]]
        )
        XCTAssertEqual(
            WidgetLayoutRules.recentColumns(for: Array(items.prefix(2)), family: .large).map { $0.map(\.name) },
            [["Done 0", "Done 1"]]
        )
        XCTAssertEqual(
            WidgetLayoutRules.recentColumns(for: Array(items.prefix(4)), family: .large).map { $0.map(\.name) },
            [["Done 0", "Done 1"], ["Done 2", "Done 3"]]
        )
        XCTAssertEqual(
            WidgetLayoutRules.recentColumns(for: Array(items.prefix(6)), family: .large).map { $0.map(\.name) },
            [["Done 0", "Done 1"], ["Done 2", "Done 3"], ["Done 4", "Done 5"]]
        )
    }
}
