import SwiftUI
import AppKit
import ShopCore

// MARK: - Focus Diagnostics

enum MacFocusDiag {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[MACFOCUS] \(message())")
        #endif
    }
}

// MARK: - Palette

enum MacTagPalette {
    static let colorHexes: [String] = [
        "#007AFF", "#34C759", "#FF9500", "#FF3B30", "#AF52DE",
        "#FF2D55", "#5856D6", "#00C7BE", "#FFD60A", "#8E8E93"
    ]

    static var colors: [(String, Color)] {
        colorHexes.map { hex in
            (hex, Color(shopHex: hex) ?? .gray)
        }
    }
}

struct MacTagColorPicker: View {
    @Binding var selectedColor: String
    let colors: [(String, Color)]
    var dotSize: CGFloat = 20
    var maxVisible: Int = 5

    var body: some View {
        HStack(spacing: ShopTheme.spacingXS) {
            ForEach(colors.prefix(maxVisible), id: \.0) { hex, color in
                Button {
                    selectedColor = hex
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: dotSize, height: dotSize)
                        .overlay {
                            if selectedColor == hex {
                                Circle()
                                    .stroke(.white, lineWidth: 2)
                                    .frame(width: dotSize + 2, height: dotSize + 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hex)
            }
        }
    }
}

// MARK: - Editor Focus

enum MacDateSegment: Hashable, CaseIterable {
    case year, month, day, hour, minute, dayPeriod
}

enum MacEditorFocus: Hashable {
    case name
    case tag(UUID)
    case newTagName
    case createdAt(MacDateSegment)
    case completedAt(MacDateSegment)

    /// AppKit first-responder fields. Dates use a custom locale-aware control instead.
    var usesTextInput: Bool {
        switch self {
        case .name, .newTagName: true
        default: false
        }
    }

    var isDateField: Bool {
        switch self {
        case .createdAt, .completedAt: true
        default: false
        }
    }
}

private struct MacEditorFocusRing: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isFocused ? ShopTheme.brandColor.opacity(0.1) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isFocused ? ShopTheme.brandColor : Color.clear, lineWidth: 2)
            }
    }
}

private extension View {
    func macEditorFocusRing(_ isFocused: Bool) -> some View {
        modifier(MacEditorFocusRing(isFocused: isFocused))
    }
}

// MARK: - Selectable Tag Row

struct MacTagSelectableRow: View {
    let tag: Tag
    let isSelected: Bool
    let isFocused: Bool
    let onFocus: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: ShopTheme.spacingSM) {
            Circle()
                .fill(tag.displayColor)
                .frame(width: 10, height: 10)
            Text(tag.name)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(ShopTheme.brandColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isFocused ? ShopTheme.brandColor.opacity(0.1) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFocused ? ShopTheme.brandColor : Color.clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            onFocus()
            onToggle()
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(tag.name)
        .accessibilityHint(ShopStrings.tagToggleHint)
    }
}

// MARK: - Inline New Tag

struct MacInlineNewTagRow: View {
    @Binding var selectedTagIDs: Set<UUID>
    @Binding var editorField: MacEditorFocus?
    let onNavigate: (Bool) -> Void
    let onSelectField: () -> Void

    @EnvironmentObject private var dataStore: DataStore

    @State private var newTagName = ""
    @State private var newTagColor = "#007AFF"

    private var canAdd: Bool {
        !newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ShopTheme.spacingSM) {
            MacFocusableTextField(
                placeholder: ShopStrings.tagName,
                text: $newTagName,
                isActive: editorField == .newTagName,
                onTab: { onNavigate(true) },
                onBacktab: { onNavigate(false) },
                onMoveUp: { onNavigate(false) },
                onMoveDown: { onNavigate(true) },
                onMoveLeft: { cycleColor(forward: false) },
                onMoveRight: { cycleColor(forward: true) },
                onSubmit: addTag,
                onBecomeActive: onSelectField
            )

            HStack(spacing: ShopTheme.spacingSM) {
                MacTagColorPicker(
                    selectedColor: $newTagColor,
                    colors: MacTagPalette.colors,
                    maxVisible: MacTagPalette.colors.count
                )
                Spacer(minLength: 0)
                Button(ShopStrings.addTag, action: addTag)
                    .disabled(!canAdd)
            }
        }
        .padding(.vertical, ShopTheme.spacingXS)
    }

    private func cycleColor(forward: Bool) {
        let palette = MacTagPalette.colors.map(\.0)
        guard !palette.isEmpty else { return }
        let currentIndex = palette.firstIndex(of: newTagColor) ?? 0
        let nextIndex: Int
        if forward {
            nextIndex = (currentIndex + 1) % palette.count
        } else {
            nextIndex = (currentIndex - 1 + palette.count) % palette.count
        }
        newTagColor = palette[nextIndex]
    }

    private func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let beforeIDs = Set(dataStore.tags.map(\.id))
        dataStore.addTag(name: name, colorHex: newTagColor)
        if let created = dataStore.tags.first(where: { !beforeIDs.contains($0.id) && $0.name == name }) {
            selectedTagIDs.insert(created.id)
        }
        newTagName = ""
        newTagColor = "#007AFF"
    }
}

// MARK: - Tag Picker Section

struct MacTagPickerSection: View {
    @Binding var selectedTagIDs: Set<UUID>
    @Binding var editorField: MacEditorFocus?
    var showsCompletedDate: Bool = false
    @Binding var createdAt: Date
    @Binding var completedAt: Date
    let onNavigate: (Bool) -> Void
    let onSelectTag: (UUID) -> Void
    let onSelectNewTagField: () -> Void
    let onSelectCreatedAt: (MacDateSegment) -> Void
    let onSelectCompletedAt: (MacDateSegment) -> Void
    let onEscape: () -> Void

    @EnvironmentObject private var dataStore: DataStore

    private var createdFocusedSegment: MacDateSegment? {
        if case .createdAt(let segment) = editorField { return segment }
        return nil
    }

    private var completedFocusedSegment: MacDateSegment? {
        if case .completedAt(let segment) = editorField { return segment }
        return nil
    }

    var body: some View {
        Section(ShopStrings.tags) {
            if dataStore.tags.isEmpty {
                Text(ShopStrings.noTags)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dataStore.tags) { tag in
                    MacTagSelectableRow(
                        tag: tag,
                        isSelected: selectedTagIDs.contains(tag.id),
                        isFocused: editorField == .tag(tag.id),
                        onFocus: { onSelectTag(tag.id) },
                        onToggle: { toggleTag(tag.id) }
                    )
                }
            }

            MacInlineNewTagRow(
                selectedTagIDs: $selectedTagIDs,
                editorField: $editorField,
                onNavigate: onNavigate,
                onSelectField: onSelectNewTagField
            )
        }

        Section {
            LabeledContent(ShopStrings.addedAt) {
                MacFocusableDatePicker(
                    selection: $createdAt,
                    focusedSegment: createdFocusedSegment,
                    onFocusSegment: onSelectCreatedAt,
                    onNavigateFields: onNavigate
                )
            }
            .macEditorFocusRing(createdFocusedSegment != nil)

            if showsCompletedDate {
                LabeledContent(ShopStrings.completedAtLabel) {
                    MacFocusableDatePicker(
                        selection: $completedAt,
                        focusedSegment: completedFocusedSegment,
                        onFocusSegment: onSelectCompletedAt,
                        onNavigateFields: onNavigate
                    )
                }
                .macEditorFocusRing(completedFocusedSegment != nil)
            }
        }
    }

    private func toggleTag(_ id: UUID) {
        if selectedTagIDs.contains(id) {
            selectedTagIDs.remove(id)
        } else {
            selectedTagIDs.insert(id)
        }
    }
}

// MARK: - Sidebar New Tag Sheet

struct MacSidebarNewTagSheet: View {
    @Binding var name: String
    @Binding var colorHex: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ShopTheme.spacingMD) {
            Text(ShopStrings.addTag)
                .font(.headline)

            TextField(ShopStrings.tagName, text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onAdd)

            MacTagColorPicker(
                selectedColor: $colorHex,
                colors: MacTagPalette.colors,
                maxVisible: 10
            )

            HStack {
                Spacer()
                Button(ShopStrings.dismiss, role: .cancel, action: onCancel)
                Button(ShopStrings.addTag, action: onAdd)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(ShopTheme.spacingMD)
        .frame(width: 320)
    }
}

struct MacSidebarRenameTagSheet: View {
    @Binding var name: String
    @Binding var colorHex: String
    let tag: Tag
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ShopTheme.spacingMD) {
            Text(String(localized: "mac.tag_rename_title"))
                .font(.headline)

            TextField(ShopStrings.tagName, text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onSave)

            MacTagColorPicker(
                selectedColor: $colorHex,
                colors: MacTagPalette.colors,
                maxVisible: 10
            )

            HStack {
                Spacer()
                Button(ShopStrings.dismiss, role: .cancel, action: onCancel)
                Button(ShopStrings.saveItem, action: onSave)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(ShopTheme.spacingMD)
        .frame(width: 320)
    }
}

// MARK: - Keyboard Focus Helpers

@MainActor
enum MacKeyboardFocusHelper {
    /// Resigns AppKit first-responder so SwiftUI `@FocusState` can reclaim the list column.
    static func resignKeyFocus() {
        guard let window = NSApp.keyWindow else { return }
        window.makeFirstResponder(nil)
    }
}

// MARK: - List Navigation Monitor

/// Captures arrow / Tab keys for the item list when SwiftUI `@FocusState` does not receive them.
struct MacListNavigationMonitor: NSViewRepresentable {
    var isEnabled: Bool
    var onNavigate: (Bool) -> Void
    var onCommandSave: () -> Void
    var consumesCommandSaveWhenIdle: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var monitor: Any?
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let monitor = context.coordinator.monitor {
            NSEvent.removeMonitor(monitor)
            context.coordinator.monitor = nil
        }
        guard isEnabled else { return }

        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === NSApp.keyWindow else { return event }

            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "s" {
                if consumesCommandSaveWhenIdle {
                    return nil
                }
                onCommandSave()
                return nil
            }

            guard !event.modifierFlags.contains(.command) else { return event }

            switch event.keyCode {
            case 48: // Tab
                onNavigate(!event.modifierFlags.contains(.shift))
                return nil
            case 126: // Up
                onNavigate(false)
                return nil
            case 125: // Down
                onNavigate(true)
                return nil
            default:
                return event
            }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Editor Navigation Monitor

/// Captures Tab / arrow / Space keys inside the detail editor form.
struct MacEditorNavigationMonitor: NSViewRepresentable {
    var isEnabled: Bool
    var editorField: MacEditorFocus?
    var onNavigate: (Bool) -> Void
    var onSpace: () -> Void
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var monitor: Any?
        var isEnabled = false
        var editorField: MacEditorFocus?
        var onNavigate: ((Bool) -> Void)?
        var onSpace: (() -> Void)?
        var onEscape: (() -> Void)?

        func syncMonitor(for nsView: NSView) {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard isEnabled else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard event.window === NSApp.keyWindow else { return event }
                guard !event.modifierFlags.contains(.command) else { return event }

                if event.keyCode == 53 { // Escape
                    MacFocusDiag.log("EditorMonitor Escape")
                    self.onEscape?()
                    return nil
                }

                // Date field has its own monitor (segment ←→ + field Tab/↑↓).
                // Pass those keys through so we don't navigate twice.
                if Self.isDateEditorField(self.editorField) {
                    switch event.keyCode {
                    case 48, 126, 125, 123, 124:
                        return event
                    default:
                        break
                    }
                }

                if Self.isEditingText(in: event.window), !Self.isInsideDatePicker(in: event.window) {
                    switch event.keyCode {
                    case 48, 126, 125, 123, 124:
                        return event
                    default:
                        break
                    }
                }

                switch event.keyCode {
                case 48: // Tab
                    MacFocusDiag.log("EditorMonitor Tab shift=\(event.modifierFlags.contains(.shift)) field=\(String(describing: self.editorField))")
                    self.onNavigate?(!event.modifierFlags.contains(.shift))
                    return nil
                case 126: // Up
                    MacFocusDiag.log("EditorMonitor Up field=\(String(describing: self.editorField))")
                    self.onNavigate?(false)
                    return nil
                case 125: // Down
                    MacFocusDiag.log("EditorMonitor Down field=\(String(describing: self.editorField))")
                    self.onNavigate?(true)
                    return nil
                case 49: // Space
                    if case .tag = self.editorField {
                        MacFocusDiag.log("EditorMonitor Space on tag")
                        self.onSpace?()
                        return nil
                    }
                    return event
                default:
                    return event
                }
            }
        }

        private static func isEditingText(in window: NSWindow?) -> Bool {
            guard let textView = window?.firstResponder as? NSTextView else {
                return false
            }
            return textView.delegate is NSControl
        }

        private static func isDateEditorField(_ field: MacEditorFocus?) -> Bool {
            field?.isDateField == true
        }

        private static func isInsideDatePicker(in window: NSWindow?) -> Bool {
            guard let window else { return false }
            if let textView = window.firstResponder as? NSTextView,
               textView.delegate is NSDatePicker {
                return true
            }
            var view: NSView? = window.firstResponder as? NSView
            while let current = view {
                if current is NSDatePicker {
                    return true
                }
                view = current.superview
            }
            return false
        }
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        let wasEnabled = coordinator.isEnabled
        coordinator.isEnabled = isEnabled
        coordinator.editorField = editorField
        coordinator.onNavigate = onNavigate
        coordinator.onSpace = onSpace
        coordinator.onEscape = onEscape
        if isEnabled != wasEnabled {
            coordinator.syncMonitor(for: nsView)
        } else if isEnabled, coordinator.monitor == nil {
            coordinator.syncMonitor(for: nsView)
        } else if !isEnabled, coordinator.monitor != nil {
            coordinator.syncMonitor(for: nsView)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Focusable Text Field (NSTextField + doCommandBy)

/// AppKit-backed name field so Tab / Shift+Tab / ↑ / ↓ are captured reliably
/// via the field editor's `doCommandBy`, independent of SwiftUI `@FocusState`.
struct MacFocusableTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var isActive: Bool
    var onTab: () -> Void
    var onBacktab: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onMoveLeft: (() -> Void)? = nil
    var onMoveRight: (() -> Void)? = nil
    var onSubmit: () -> Void
    var onBecomeActive: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = .preferredFont(forTextStyle: .body)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isActive = isActive
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        guard let window = nsView.window else { return }
        let editingThisField = (window.firstResponder as? NSTextView)?.delegate === nsView
        if isActive, !editingThisField {
            DispatchQueue.main.async { [weak coordinator = context.coordinator] in
                guard coordinator?.isActive == true, nsView.window === window else { return }
                let stillEditing = (window.firstResponder as? NSTextView)?.delegate === nsView
                guard !stillEditing else { return }
                MacFocusDiag.log("FocusableTextField makeFirstResponder async")
                window.makeFirstResponder(nsView)
            }
        } else if !isActive, editingThisField {
            MacFocusDiag.log("FocusableTextField resign")
            window.makeFirstResponder(nil)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacFocusableTextField
        var isActive = false
        init(_ parent: MacFocusableTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            MacFocusDiag.log("FocusableTextField beginEditing")
            parent.onBecomeActive()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertTab(_:)):
                MacFocusDiag.log("FocusableTextField doCommand Tab")
                parent.onTab()
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                MacFocusDiag.log("FocusableTextField doCommand Backtab")
                parent.onBacktab()
                return true
            case #selector(NSResponder.moveUp(_:)):
                MacFocusDiag.log("FocusableTextField doCommand Up")
                parent.onMoveUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                MacFocusDiag.log("FocusableTextField doCommand Down")
                parent.onMoveDown()
                return true
            case #selector(NSResponder.moveLeft(_:)):
                parent.onMoveLeft?()
                return parent.onMoveLeft != nil
            case #selector(NSResponder.moveRight(_:)):
                parent.onMoveRight?()
                return parent.onMoveRight != nil
            case #selector(NSResponder.insertNewline(_:)):
                MacFocusDiag.log("FocusableTextField doCommand Return")
                parent.onSubmit()
                return true
            default:
                return false
            }
        }
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        coordinator.isActive = false
    }
}

// MARK: - Focusable Date Picker

extension MacDateSegment {
    static var systemOrdered: [MacDateSegment] {
        MacDateLayout.segments(from: MacDateLayout.parts())
    }

    func displayText(from date: Date, uses24HourClock: Bool) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        switch self {
        case .year:
            return String(format: "%04d", components.year ?? 0)
        case .month:
            return String(format: "%02d", components.month ?? 0)
        case .day:
            return String(format: "%02d", components.day ?? 0)
        case .hour:
            let hour24 = components.hour ?? 0
            if uses24HourClock {
                return String(format: "%02d", hour24)
            }
            let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
            return String(hour12)
        case .minute:
            return String(format: "%02d", components.minute ?? 0)
        case .dayPeriod:
            let hour24 = components.hour ?? 0
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.setLocalizedDateFormatFromTemplate("a")
            var periodComponents = DateComponents()
            periodComponents.hour = hour24
            let probe = calendar.date(from: periodComponents) ?? date
            return formatter.string(from: probe)
        }
    }

    var maxDigits: Int {
        switch self {
        case .year: 4
        case .dayPeriod: 0
        case .hour: 2
        default: 2
        }
    }

    func clamped(_ raw: Int, uses24HourClock: Bool) -> Int {
        switch self {
        case .year:
            return min(max(raw, 1), 9999)
        case .month:
            return min(max(raw, 1), 12)
        case .day:
            return min(max(raw, 1), 31)
        case .hour:
            if uses24HourClock {
                return min(max(raw, 0), 23)
            }
            return min(max(raw, 1), 12)
        case .minute:
            return min(max(raw, 0), 59)
        case .dayPeriod:
            return raw
        }
    }
}

enum MacDateLayout {
    enum Part: Hashable {
        case segment(MacDateSegment)
        case separator(String)
    }

    static func systemFormatString(locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar.autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.dateFormat ?? "yyyy/M/d H:mm"
    }

    static var uses24HourClock: Bool {
        let format = systemFormatString()
        return format.contains("H") || format.contains("k")
    }

    static func parts(locale: Locale = .autoupdatingCurrent) -> [Part] {
        let format = systemFormatString(locale: locale)
        var parts: [Part] = []
        var separator = ""
        var index = format.startIndex

        while index < format.endIndex {
            let character = format[index]
            if character == "'" {
                let next = format.index(after: index)
                guard next < format.endIndex else { break }
                if format[next] == "'" {
                    separator.append("'")
                    index = format.index(after: next)
                } else if let end = format[next...].firstIndex(of: "'") {
                    separator.append(contentsOf: format[next..<end])
                    index = format.index(after: end)
                } else {
                    break
                }
                continue
            }

            let segment: MacDateSegment?
            switch character {
            case "y": segment = .year
            case "M": segment = .month
            case "d": segment = .day
            case "H", "h", "K", "k": segment = .hour
            case "m": segment = .minute
            case "a": segment = .dayPeriod
            default: segment = nil
            }

            if let segment {
                if !separator.isEmpty {
                    parts.append(.separator(separator))
                    separator = ""
                }
                if !parts.contains(where: {
                    if case .segment(segment) = $0 { return true }
                    return false
                }) {
                    parts.append(.segment(segment))
                }
                var cursor = format.index(after: index)
                while cursor < format.endIndex, format[cursor] == character {
                    cursor = format.index(after: cursor)
                }
                index = cursor
            } else {
                separator.append(character)
                index = format.index(after: index)
            }
        }

        if !separator.isEmpty {
            parts.append(.separator(separator))
        }

        let hasSegments = parts.contains {
            if case .segment = $0 { return true }
            return false
        }
        if hasSegments { return parts }
        return [
            .segment(.year), .separator("/"),
            .segment(.month), .separator("/"),
            .segment(.day), .separator(" "),
            .segment(.hour), .separator(":"),
            .segment(.minute)
        ]
    }

    static func segments(from parts: [Part]) -> [MacDateSegment] {
        parts.compactMap {
            if case .segment(let segment) = $0 { return segment }
            return nil
        }
    }
}

/// Each date/time segment is a peer focus target in the editor field cycle.
struct MacFocusableDatePicker: View {
    @Binding var selection: Date
    var focusedSegment: MacDateSegment?
    var onFocusSegment: (MacDateSegment) -> Void
    var onNavigateFields: (Bool) -> Void

    @State private var typingBuffer = ""

    private var layoutParts: [MacDateLayout.Part] { MacDateLayout.parts() }
    private var segments: [MacDateSegment] { MacDateLayout.segments(from: layoutParts) }
    private var uses24HourClock: Bool { MacDateLayout.uses24HourClock }
    private var isActive: Bool { focusedSegment != nil }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(layoutParts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .separator(let text):
                    Text(text)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                case .segment(let segment):
                    let focused = focusedSegment == segment
                    Text(segment.displayText(from: selection, uses24HourClock: uses24HourClock))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .background {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(focused ? ShopTheme.brandColor.opacity(0.22) : Color.clear)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            typingBuffer = ""
                            onFocusSegment(segment)
                        }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            typingBuffer = ""
            onFocusSegment(focusedSegment ?? segments.first ?? .day)
        }
        .background {
            MacDateKeyboardMonitor(
                isEnabled: isActive,
                focusedSegment: focusedSegment,
                typingBuffer: $typingBuffer,
                selection: $selection,
                uses24HourClock: uses24HourClock,
                onNavigateFields: onNavigateFields,
                onFocusSegment: onFocusSegment
            )
        }
        .onChange(of: focusedSegment) { _, _ in
            typingBuffer = ""
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            selection.formatted(
                .dateTime
                    .year().month().day()
                    .hour().minute()
                    .locale(.autoupdatingCurrent)
            )
        )
    }
}

private struct MacDateKeyboardMonitor: NSViewRepresentable {
    var isEnabled: Bool
    var focusedSegment: MacDateSegment?
    @Binding var typingBuffer: String
    @Binding var selection: Date
    var uses24HourClock: Bool
    var onNavigateFields: (Bool) -> Void
    var onFocusSegment: (MacDateSegment) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var monitor: Any?
        var isEnabled = false
        var focusedSegment: MacDateSegment?
        var typingBuffer = ""
        var selection = Date()
        var uses24HourClock = true
        var onNavigateFields: ((Bool) -> Void)?
        var onFocusSegment: ((MacDateSegment) -> Void)?
        var onTypingBufferChange: ((String) -> Void)?
        var onSelectionChange: ((Date) -> Void)?

        func syncMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard isEnabled else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled else { return event }
                guard event.window === NSApp.keyWindow else { return event }
                guard !event.modifierFlags.contains(.command) else { return event }

                switch event.keyCode {
                case 48: // Tab
                    self.onNavigateFields?(!event.modifierFlags.contains(.shift))
                    return nil
                case 126, 123: // Up / Left — previous editor field (including date segments)
                    self.onNavigateFields?(false)
                    return nil
                case 125, 124: // Down / Right — next editor field
                    self.onNavigateFields?(true)
                    return nil
                default:
                    break
                }

                if self.focusedSegment == .dayPeriod {
                    if event.keyCode == 49 { // Space toggles AM/PM
                        self.toggleDayPeriod()
                        return nil
                    }
                    return event
                }

                if let digit = Self.digit(from: event) {
                    self.applyDigit(digit)
                    return nil
                }

                return event
            }
        }

        private func toggleDayPeriod() {
            let calendar = Calendar.autoupdatingCurrent
            var components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: selection
            )
            let hour = components.hour ?? 0
            components.hour = hour < 12 ? hour + 12 : hour - 12
            if let date = calendar.date(from: components) {
                selection = date
                onSelectionChange?(date)
            }
            if let focusedSegment {
                onFocusSegment?(focusedSegment)
            }
        }

        private func applyDigit(_ digit: Int) {
            guard let segment = focusedSegment, segment != .dayPeriod else { return }
            var buffer = typingBuffer
            if buffer.count >= segment.maxDigits {
                buffer = ""
            }
            buffer.append(String(digit))
            typingBuffer = buffer
            onTypingBufferChange?(buffer)

            let raw = Int(buffer) ?? digit
            let value = segment.clamped(raw, uses24HourClock: uses24HourClock)
            let calendar = Calendar.autoupdatingCurrent
            var components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: selection
            )

            switch segment {
            case .year:
                components.year = value
            case .month:
                components.month = value
            case .day:
                components.day = value
            case .minute:
                components.minute = value
            case .hour:
                if uses24HourClock {
                    components.hour = value
                } else {
                    let previous = components.hour ?? 0
                    let isPM = previous >= 12
                    switch value {
                    case 12:
                        components.hour = isPM ? 12 : 0
                    default:
                        components.hour = isPM ? value + 12 : value
                    }
                }
            case .dayPeriod:
                break
            }

            if let date = calendar.date(from: components) {
                selection = date
                onSelectionChange?(date)
            }
            onFocusSegment?(segment)

            if buffer.count >= segment.maxDigits {
                typingBuffer = ""
                onTypingBufferChange?("")
                onNavigateFields?(true)
            }
        }

        private static func digit(from event: NSEvent) -> Int? {
            guard let characters = event.charactersIgnoringModifiers, characters.count == 1,
                  let character = characters.first, character.isNumber,
                  let value = character.wholeNumberValue else {
                return nil
            }
            return value
        }
    }

    final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSView {
        PassthroughView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        let wasEnabled = coordinator.isEnabled
        coordinator.isEnabled = isEnabled
        coordinator.focusedSegment = focusedSegment
        coordinator.typingBuffer = typingBuffer
        coordinator.selection = selection
        coordinator.uses24HourClock = uses24HourClock
        coordinator.onNavigateFields = onNavigateFields
        coordinator.onFocusSegment = onFocusSegment
        coordinator.onTypingBufferChange = { typingBuffer = $0 }
        coordinator.onSelectionChange = { selection = $0 }

        if isEnabled != wasEnabled || (isEnabled && coordinator.monitor == nil) {
            coordinator.syncMonitor()
        } else if !isEnabled, coordinator.monitor != nil {
            coordinator.syncMonitor()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - List Focus Bridge

/// Observes clicks within the list without participating in hit testing.
struct MacListFocusBridge: NSViewRepresentable {
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var monitor: Any?
    }

    final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    func makeNSView(context: Context) -> NSView {
        PassthroughView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let monitor = context.coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard event.window === NSApp.keyWindow, nsView.window === event.window else {
                return event
            }
            let location = nsView.convert(event.locationInWindow, from: nil)
            guard nsView.bounds.contains(location) else { return event }

            // Let the List finish native mouse handling, then reclaim keyboard focus.
            DispatchQueue.main.async {
                onFocus()
            }
            return event
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Sidebar Tag Context Menu

enum MacTagColorMenuIcons {
    static func dot(hex: String, size: CGFloat = 12) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let fill = (Color(shopHex: hex).map { NSColor($0) } ?? .secondaryLabelColor)
        fill.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

final class MacTagColorMenuActionTarget: NSObject {
    nonisolated(unsafe) let onSelectPreset: (String) -> Void

    init(onSelectPreset: @escaping (String) -> Void) {
        self.onSelectPreset = onSelectPreset
    }

    @objc func selectPresetColor(_ sender: NSMenuItem) {
        guard let hex = sender.representedObject as? String else { return }
        onSelectPreset(hex)
    }
}

final class MacTagCustomColorMenuItemView: NSView, NSTextFieldDelegate {
    private let preview = NSView()
    private let textField = NSTextField()
    weak var actionTarget: MacTagColorMenuActionTarget?

    init(currentHex: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        preview.wantsLayer = true
        preview.layer?.cornerRadius = 7

        textField.stringValue = currentHex
        textField.placeholderString = "#RRGGBB"
        textField.isBordered = true
        textField.bezelStyle = .roundedBezel
        textField.font = .systemFont(ofSize: 12)
        textField.focusRingType = .none
        textField.delegate = self

        let stack = NSStackView(views: [preview, textField])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            preview.widthAnchor.constraint(equalToConstant: 14),
            preview.heightAnchor.constraint(equalToConstant: 14),
            textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 108),
            heightAnchor.constraint(equalToConstant: 30)
        ])

        updatePreview()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 220, height: 30)
    }

    func controlTextDidChange(_ obj: Notification) {
        updatePreview()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            applyIfValid()
            return true
        }
        return false
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            applyIfValid()
        }
        return resigned
    }

    private func updatePreview() {
        let normalized = ShopHexColor.normalize(textField.stringValue)
        preview.layer?.backgroundColor = (normalized.flatMap { Color(shopHex: $0) }.map { NSColor($0) } ?? .tertiaryLabelColor).cgColor
    }

    private func applyIfValid() {
        guard let normalized = ShopHexColor.normalize(textField.stringValue) else { return }
        textField.stringValue = normalized
        actionTarget?.onSelectPreset(normalized)
        enclosingMenuItem?.menu?.cancelTrackingWithoutAnimation()
    }
}

enum MacSidebarTagContextMenuBuilder {
    static func makeMenu(
        for tag: Tag,
        actionTarget: MacTagColorMenuActionTarget,
        menuActions: MacSidebarTagContextMenuCoordinator,
        onRename: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> NSMenu {
        menuActions.onRename = onRename
        menuActions.onDelete = onDelete

        let menu = NSMenu()

        let renameItem = NSMenuItem(
            title: String(localized: "tag.rename"),
            action: #selector(MacSidebarTagContextMenuCoordinator.rename(_:)),
            keyEquivalent: ""
        )
        renameItem.target = menuActions
        menu.addItem(renameItem)

        let colorMenu = NSMenu(title: ShopStrings.tagColor)
        for hex in MacTagPalette.colorHexes {
            let item = NSMenuItem(
                title: hex,
                action: #selector(MacTagColorMenuActionTarget.selectPresetColor(_:)),
                keyEquivalent: ""
            )
            item.target = actionTarget
            item.representedObject = hex
            item.image = MacTagColorMenuIcons.dot(hex: hex)
            if ShopHexColor.normalize(tag.colorHex) == hex {
                item.state = .on
            }
            colorMenu.addItem(item)
        }

        colorMenu.addItem(.separator())

        let customItem = NSMenuItem()
        let customView = MacTagCustomColorMenuItemView(currentHex: tag.colorHex)
        customView.actionTarget = actionTarget
        customItem.view = customView
        colorMenu.addItem(customItem)

        let colorParent = NSMenuItem(title: ShopStrings.tagColor, action: nil, keyEquivalent: "")
        colorParent.submenu = colorMenu
        menu.addItem(colorParent)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(
            title: ShopStrings.deleteItem,
            action: #selector(MacSidebarTagContextMenuCoordinator.delete(_:)),
            keyEquivalent: ""
        )
        deleteItem.target = menuActions
        deleteItem.attributedTitle = NSAttributedString(
            string: ShopStrings.deleteItem,
            attributes: [.foregroundColor: NSColor.systemRed]
        )
        menu.addItem(deleteItem)

        return menu
    }
}

final class MacSidebarTagContextMenuCoordinator: NSObject {
    nonisolated(unsafe) var onRename: (() -> Void)?
    nonisolated(unsafe) var onDelete: (() -> Void)?

    @objc func rename(_ sender: NSMenuItem) {
        onRename?()
    }

    @objc func delete(_ sender: NSMenuItem) {
        onDelete?()
    }
}

struct MacSidebarTagContextMenuInstaller: NSViewRepresentable {
    let tag: Tag
    let onRename: () -> Void
    let onDelete: () -> Void
    let onColorChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var monitor: Any?
        var actionTarget: MacTagColorMenuActionTarget?
        let menuActions = MacSidebarTagContextMenuCoordinator()
    }

    final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSView {
        PassthroughView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let monitor = context.coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }

        context.coordinator.actionTarget = MacTagColorMenuActionTarget(onSelectPreset: onColorChange)

        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            guard event.window === NSApp.keyWindow, nsView.window === event.window else {
                return event
            }
            let location = nsView.convert(event.locationInWindow, from: nil)
            guard nsView.bounds.contains(location) else { return event }

            let menu = MacSidebarTagContextMenuBuilder.makeMenu(
                for: tag,
                actionTarget: context.coordinator.actionTarget!,
                menuActions: context.coordinator.menuActions,
                onRename: onRename,
                onDelete: onDelete
            )
            NSMenu.popUpContextMenu(menu, with: event, for: nsView)
            return nil
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
