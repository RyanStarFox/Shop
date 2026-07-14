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
    public static var darkMode: String {
        NSLocalizedString("settings.dark_mode", comment: "Dark Mode")
    }
    public static var about: String {
        NSLocalizedString("settings.about", comment: "About")
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
    public static var syncWifiStatus: String {
        NSLocalizedString("sync.wifi_status", comment: "WiFi Sync")
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

    // MARK: - WebDAV
    public static var webdavConfigured: String {
        NSLocalizedString("webdav.configured", comment: "WebDAV configured")
    }
    public static var webdavNotConfigured: String {
        NSLocalizedString("webdav.not_configured", comment: "Not configured")
    }

    // MARK: - Helper
    public static func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return justNow }
        if interval < 3600 { return String(format: minutesAgo, Int(interval / 60)) }
        if interval < 86400 { return String(format: hoursAgo, Int(interval / 3600)) }
        return String(format: daysAgo, Int(interval / 86400))
    }
}
