import Foundation

public enum WidgetTagDisplay {
    public static func presentation(
        tags: [WidgetSnapshotStore.TagInfo],
        namedLimit: Int,
        colorOnlyLimit: Int? = nil,
        collapseToColorsWhenOverNamedLimit: Bool = false
    ) -> (named: [WidgetSnapshotStore.TagInfo], colorOnly: [WidgetSnapshotStore.TagInfo]) {
        let limit = max(0, namedLimit)
        let colorLimit = colorOnlyLimit ?? tags.count
        let shouldCollapse = collapseToColorsWhenOverNamedLimit && tags.count > limit
        let named = shouldCollapse ? [] : Array(tags.prefix(limit))
        let colorSource = shouldCollapse ? tags : Array(tags.dropFirst(limit))
        let colorOnly = Array(colorSource.prefix(max(0, colorLimit)))
        return (named, colorOnly)
    }
}
