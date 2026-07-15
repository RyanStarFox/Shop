import Foundation

public enum ShopStrings {
    // MARK: - App
    public static var appName: String {
        NSLocalizedString("app.name", comment: "App name")
    }

    // MARK: - Items
    public static var addItem: String {
        NSLocalizedString("item.add", comment: "Add item")
    }
    public static var itemName: String {
        NSLocalizedString("item.name", comment: "Item name")
    }
    public static var deleteItem: String {
        NSLocalizedString("item.delete", comment: "Delete item")
    }
    public static var itemSearch: String {
        NSLocalizedString("item.search", comment: "Search items")
    }
    public static var emptyList: String {
        NSLocalizedString("item.empty", comment: "No items yet")
    }
    public static var markComplete: String {
        NSLocalizedString("item.mark_complete", comment: "Mark complete")
    }
    public static var markIncomplete: String {
        NSLocalizedString("item.mark_incomplete", comment: "Mark incomplete")
    }
    public static var editItem: String {
        NSLocalizedString("item.edit", comment: "Edit item")
    }
    public static var saveItem: String {
        NSLocalizedString("item.save", comment: "Save item")
    }
    public static var discardChanges: String {
        NSLocalizedString("item.discard_changes", comment: "Discard changes")
    }
    public static var archiveSection: String {
        NSLocalizedString("item.archive_section", bundle: .module, comment: "Archive section")
    }
    public static func pendingCount(_ count: Int) -> String {
        String(
            format: NSLocalizedString("item.pending_count", comment: "Pending item count"),
            locale: .current,
            count
        )
    }

    // MARK: - Tags
    public static var tags: String {
        NSLocalizedString("tags.title", comment: "Tags")
    }
    public static var addTag: String {
        NSLocalizedString("tag.add", comment: "Add tag")
    }
    public static var tagName: String {
        NSLocalizedString("tag.name", comment: "Tag name")
    }
    public static var tagColor: String {
        NSLocalizedString("tag.color", comment: "Tag color")
    }
    public static var manageTags: String {
        NSLocalizedString("tag.manage", comment: "Manage tags")
    }
    public static var noTags: String {
        NSLocalizedString("tag.none", comment: "No tags")
    }

    // MARK: - Filter
    public static var filter: String {
        NSLocalizedString("filter.title", comment: "Filter")
    }
    public static var filterAll: String {
        NSLocalizedString("filter.all", comment: "All")
    }
    public static var filterActive: String {
        NSLocalizedString("filter.active", comment: "Active")
    }
    public static var filterCompleted: String {
        NSLocalizedString("filter.completed", comment: "Completed")
    }
    public static var filterToday: String {
        NSLocalizedString("filter.today", comment: "Today")
    }
    public static var filterWeek: String {
        NSLocalizedString("filter.week", comment: "This week")
    }
    public static var filterMonth: String {
        NSLocalizedString("filter.month", comment: "This month")
    }
    public static var filterReset: String {
        NSLocalizedString("filter.reset", comment: "Reset filters")
    }
    public static var filterCustomDateRange: String {
        NSLocalizedString("filter.custom_date_range", comment: "Custom date range")
    }
    public static var filterStartDate: String {
        NSLocalizedString("filter.start_date", comment: "Start date")
    }
    public static var filterEndDate: String {
        NSLocalizedString("filter.end_date", comment: "End date")
    }

    // MARK: - Settings
    public static var settings: String {
        NSLocalizedString("settings.title", comment: "Settings")
    }
    public static var sync: String {
        NSLocalizedString("settings.sync", comment: "Sync")
    }
    public static var webdavConfig: String {
        NSLocalizedString("settings.webdav", comment: "WebDAV Configuration")
    }
    public static var webdavServer: String {
        NSLocalizedString("settings.webdav_server", comment: "Server URL")
    }
    public static var webdavUsername: String {
        NSLocalizedString("settings.webdav_username", comment: "Username")
    }
    public static var webdavPassword: String {
        NSLocalizedString("settings.webdav_password", comment: "Password")
    }
    public static var syncNow: String {
        NSLocalizedString("settings.sync_now", comment: "Sync Now")
    }
    public static var language: String {
        NSLocalizedString("settings.language", comment: "Language")
    }
    public static var appearance: String {
        NSLocalizedString("settings.appearance", comment: "Appearance")
    }
    public static var appearanceSystem: String {
        NSLocalizedString("appearance.system", bundle: .module, comment: "System appearance")
    }
    public static var appearanceLight: String {
        NSLocalizedString("appearance.light", bundle: .module, comment: "Light appearance")
    }
    public static var darkMode: String {
        NSLocalizedString("settings.dark_mode", comment: "Dark Mode")
    }
    public static var about: String {
        NSLocalizedString("settings.about", comment: "About")
    }
    public static var appTagline: String {
        NSLocalizedString("app.tagline", bundle: .module, comment: "App tagline")
    }
    public static var appVersion: String {
        NSLocalizedString("app.version", bundle: .module, comment: "App version label")
    }
    public static var cancel: String {
        NSLocalizedString("common.cancel", bundle: .module, comment: "Cancel")
    }

    // MARK: - Time
    public static var addedAt: String {
        NSLocalizedString("time.added_at", comment: "Added at")
    }
    public static var justNow: String {
        NSLocalizedString("time.just_now", comment: "Just now")
    }
    public static var minutesAgo: String {
        NSLocalizedString("time.minutes_ago", comment: "%d minutes ago")
    }
    public static var hoursAgo: String {
        NSLocalizedString("time.hours_ago", comment: "%d hours ago")
    }
    public static var daysAgo: String {
        NSLocalizedString("time.days_ago", comment: "%d days ago")
    }

    // MARK: - Sync
    public static var syncAvailable: String {
        NSLocalizedString("sync.available", comment: "Available for sync")
    }
    public static var syncNotAvailable: String {
        NSLocalizedString("sync.not_available", comment: "Not available")
    }
    public static var syncWatchStatus: String {
        NSLocalizedString("sync.watch_status", comment: "Watch Sync")
    }
    public static var syncWebdavStatus: String {
        NSLocalizedString("sync.webdav_status", comment: "WebDAV Sync")
    }
    public static var syncing: String {
        NSLocalizedString("sync.syncing", comment: "Syncing...")
    }
    public static var lastSync: String {
        NSLocalizedString("sync.last_sync", comment: "Last sync")
    }
    public static var watchInvalidSnapshot: String {
        NSLocalizedString(
            "watch.error.invalid_snapshot",
            bundle: .module,
            comment: "Invalid Watch sync snapshot"
        )
    }
    public static var watchInvalidReply: String {
        NSLocalizedString(
            "watch.error.invalid_reply",
            bundle: .module,
            comment: "Invalid Watch sync reply"
        )
    }
    public static func watchUnsupportedSnapshotVersion(_ version: Int) -> String {
        localizedFormat(
            "watch.error.unsupported_version",
            version.description,
            language: nil
        )
    }
    public static func watchFileReadFailed(_ detail: String) -> String {
        localizedFormat("watch.error.file_read_failed", detail, language: nil)
    }
    public static func watchFileCleanupFailed(_ detail: String) -> String {
        localizedFormat("watch.error.file_cleanup_failed", detail, language: nil)
    }

    // MARK: - WebDAV
    public static var webdavConfigured: String {
        NSLocalizedString("webdav.configured", comment: "WebDAV configured")
    }
    public static var webdavNotConfigured: String {
        NSLocalizedString("webdav.not_configured", comment: "Not configured")
    }
    public static var webdavUnauthorized: String {
        NSLocalizedString("webdav.error.unauthorized", bundle: .module, comment: "WebDAV authentication failed")
    }
    public static var webdavPreconditionFailed: String {
        NSLocalizedString("webdav.error.precondition_failed", bundle: .module, comment: "Remote WebDAV data changed")
    }
    public static var webdavNetworkFailed: String {
        NSLocalizedString("webdav.error.network", bundle: .module, comment: "WebDAV network error")
    }
    public static var webdavInvalidServer: String {
        NSLocalizedString("webdav.error.invalid_server", bundle: .module, comment: "Invalid WebDAV server")
    }
    public static var webdavSyncFailed: String {
        NSLocalizedString("webdav.error.sync_failed", bundle: .module, comment: "WebDAV sync failed")
    }

    // MARK: - Undo
    public static var undo: String {
        NSLocalizedString("undo.action", bundle: .module, comment: "Undo")
    }
    public static var undoItemCompleted: String {
        NSLocalizedString("undo.item_completed", bundle: .module, comment: "Item completed")
    }
    public static var undoItemRestored: String {
        NSLocalizedString("undo.item_restored", bundle: .module, comment: "Item restored")
    }
    public static var undoItemDeleted: String {
        NSLocalizedString("undo.item_deleted", bundle: .module, comment: "Item deleted")
    }
    public static var undoTagDeleted: String {
        NSLocalizedString("undo.tag_deleted", bundle: .module, comment: "Tag deleted")
    }
    public static var dismiss: String {
        NSLocalizedString("common.dismiss", bundle: .module, comment: "Dismiss an alert")
    }

    // MARK: - Shopping Store Errors
    public static func shoppingStoreContainerCreationFailed(
        _ detail: String,
        language: String? = nil
    ) -> String {
        localizedFormat(
            "error.store.container_creation_failed",
            detail,
            language: language
        )
    }

    public static func shoppingStoreFetchFailed(
        _ detail: String,
        language: String? = nil
    ) -> String {
        localizedFormat("error.store.fetch_failed", detail, language: language)
    }

    public static func shoppingStoreSaveFailed(
        _ detail: String,
        language: String? = nil
    ) -> String {
        localizedFormat("error.store.save_failed", detail, language: language)
    }

    public static func shoppingStoreItemNotFound(
        _ id: UUID,
        language: String? = nil
    ) -> String {
        localizedFormat(
            "error.store.item_not_found",
            id.uuidString,
            language: language
        )
    }

    public static func shoppingStoreTagNotFound(
        _ id: UUID,
        language: String? = nil
    ) -> String {
        localizedFormat(
            "error.store.tag_not_found",
            id.uuidString,
            language: language
        )
    }

    // MARK: - Helper
    public static func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return justNow }
        if interval < 3600 { return String(format: minutesAgo, Int(interval / 60)) }
        if interval < 86400 { return String(format: hoursAgo, Int(interval / 3600)) }
        return String(format: daysAgo, Int(interval / 86400))
    }

    private static func localizedFormat(
        _ key: String,
        _ argument: String,
        language: String?
    ) -> String {
        let bundle = localizationBundle(language: language)
        let template = bundle.localizedString(
            forKey: key,
            value: key,
            table: nil
        )
        let locale = language.map(Locale.init(identifier:)) ?? .current
        return String(format: template, locale: locale, argument)
    }

    private static func localizationBundle(language: String?) -> Bundle {
        guard let language,
              let path = Bundle.module.path(
                forResource: language,
                ofType: "lproj"
              ),
              let bundle = Bundle(path: path) else {
            return .module
        }
        return bundle
    }
}
