// Source compatibility for callers compiled against the former Wi-Fi-only name.
#if os(iOS) || os(watchOS)
public typealias WiFiSyncService = WatchSyncService
#endif
