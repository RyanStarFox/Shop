# Shop! 🛒

A beautiful, bilingual (中文/English) shopping list app for iPhone, iPad, Apple Watch, and Mac — with gorgeous Liquid Glass UI, dark mode, and seamless cross-device sync.

## Features

- **Liquid Glass UI** – Translucent, frosted-glass interface that adapts beautifully to light and dark mode
- **Dark Mode + Dark Icons** – Full dark mode support with alternate dark app icons
- **Multi-Platform** – Runs natively on iOS, watchOS, and macOS from a single Swift codebase
- **WiFi Sync** – iOS ↔ watchOS sync via WatchConnectivity (auto-syncs when devices are nearby)
- **WebDAV Sync** – iOS/macOS sync via any WebDAV server (Nextcloud, ownCloud, Synology, etc.)
- **Tags** – Organize items with color-coded tags (manage tags in Settings)
- **Auto Timestamp** – Every item records when it was added
- **Smart Filtering** – Filter by status (active/completed), time period (today/week/month), or tags
- **Bilingual** – Full English and Simplified Chinese (简体中文) localization
- **SwiftData** – Modern persistence with automatic iCloud sync capability

## Project Structure

```
Shop!/
├── Shared/                     # Swift Package – shared across all targets
│   ├── Package.swift
│   └── Sources/ShopCore/
│       ├── Models/             # ShoppingItem, Tag, PlatformColor
│       ├── Storage/            # DataStore (SwiftData)
│       ├── Sync/               # WiFiSyncService, WebDAVSyncService
│       └── Localization/       # Strings (en + zh-Hans)
├── iOS/Shop/                   # iOS app target
│   ├── ShopApp.swift
│   ├── ContentView.swift
│   └── Views/                  # ItemListView, AddItemView, FilterView, etc.
├── watchOS/ShopWatch/          # watchOS app target
│   ├── ShopWatchApp.swift
│   └── ContentView.swift
├── macOS/ShopMac/              # macOS app target
│   ├── ShopMacApp.swift
│   └── ContentView.swift
├── Resources/Localization/     # Base localization strings
├── project.yml                 # XcodeGen project spec
└── README.md
```

## Getting Started

### Prerequisites

- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (to generate the `.xcodeproj`)
- macOS 15.0+, iOS 18.0+, watchOS 11.0+

### Generate Xcode Project

```bash
# Install XcodeGen if needed
brew install xcodegen

# Generate the project
cd "Shop!"
xcodegen generate

# Open the project
open Shop.xcodeproj
```

### Build & Run

1. Select the **Shop** scheme (iOS)
2. Choose your target device/simulator
3. Press **⌘R** to build and run

For watchOS: select the **ShopWatch** scheme and a watch simulator.

For macOS: select the **ShopMac** scheme.

## Sync Setup

### iOS ↔ watchOS (WiFi)

Sync works automatically via WatchConnectivity when:
- Both devices are on the same WiFi network
- Bluetooth is enabled
- The apps are installed on both iPhone and Apple Watch

### iOS/macOS ↔ WebDAV Server

1. Go to **Settings → WebDAV Configuration**
2. Enter your server URL (e.g., `https://nextcloud.example.com/remote.php/dav/files/user/`)
3. Enter your username and password
4. Tap/click **Sync Now**

Supported servers:
- Nextcloud
- ownCloud
- Synology NAS
- Any WebDAV-compatible server

## Architecture

### Data Flow

```
SwiftData (ModelContainer)
    └── DataStore (ObservableObject)
         ├── iOS App (SwiftUI)
         │    ├── WiFiSyncService → watchOS via WCSession
         │    └── WebDAVSyncService → Server via HTTP
         ├── watchOS App (SwiftUI)
         │    └── WiFiSyncService → iOS via WCSession
         └── macOS App (SwiftUI)
              └── WebDAVSyncService → Server via HTTP
```

### Models

- **ShoppingItem** – name, completion status, timestamps, tags
- **Tag** – name, color (hex), creation date

### Key Technologies

| Feature | Technology |
|---------|-----------|
| UI Framework | SwiftUI |
| Persistence | SwiftData |
| iOS ↔ watchOS Sync | WatchConnectivity |
| WebDAV Sync | URLSession + HTTP Basic Auth |
| Glass UI | `.ultraThinMaterial`, Gradients, Blurs |
| Localization | `.strings` files (en, zh-Hans) |
| Dark Icons | `CFBundleAlternateIcons` + asset catalog |

## Localization

All strings are in `Resources/Localization/`:

- **English** – `en.lproj/Localizable.strings`
- **Simplified Chinese** – `zh-Hans.lproj/Localizable.strings`

The `ShopStrings` enum in the shared package provides type-safe access to all localized strings.

## License

MIT
