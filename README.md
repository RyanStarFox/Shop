# Shop !

Bilingual shopping list for **iPhone**, **Apple Watch**, and **Mac**  
中英双语购物清单，支持 **iPhone**、**Apple Watch**、**Mac**

- English ↓
- [中文说明](#shop--中文)

---

## Shop ! (English)

A calm, local-first shopping list built with SwiftUI. iPhone, Watch, and Mac share one `ShopCore` package, with optional WebDAV sync and WatchConnectivity.

### Features

- Native SwiftUI apps for iOS, watchOS, and macOS
- Tags, filters, multi-select / batch actions, inline archive
- WebDAV sync (`shop_sync.json`) between iPhone and Mac
- WatchConnectivity sync between iPhone and Apple Watch
- Home Screen / Desktop widgets (where configured)
- One-level undo for common edits

### Downloads (GitHub Releases)

Release page: [https://github.com/RyanStarFox/Shop/releases](https://github.com/RyanStarFox/Shop/releases)

| Asset | Platform | Notes |
|-------|----------|--------|
| `Shop-*-macOS.dmg` | Mac | Drag `Shop !.app` to Applications |
| `Shop-*-iOS-withWatch.ipa` | iPhone (+ Watch) | Includes the Watch companion |
| `Shop-*-iOS-noWatch.ipa` | iPhone only | Smaller install; no Watch app |

#### macOS: “App is damaged” / cannot open

GitHub downloads are often quarantined by macOS. Development-signed builds are also **not notarized**, so Gatekeeper may block them.

After installing from the DMG, run one of:

```bash
# Recommended: clear quarantine on the installed app
xattr -cr "/Applications/Shop !.app"

# Or, if needed:
sudo xattr -rd com.apple.quarantine "/Applications/Shop !.app"
```

If the app is still blocked: **System Settings → Privacy & Security → Open Anyway**.

If you copied the app elsewhere, replace the path accordingly (for example the `.app` inside the DMG mount).

#### iPhone: how to install

This project is **not** distributed through the App Store in this repository flow.

You can:

1. **Build & install yourself** with Xcode (recommended for daily use on your own devices), or  
2. Install an **IPA from the GitHub Release** (`withWatch` or `noWatch`) using a tool that supports development IPAs (for example AltStore, Sideloadly, or similar), signed for **your** Apple ID / team.

Notes:

- Release IPAs are typically **development / debugging** exports. They require a valid signing identity and device registration for your team.
- Prefer **withWatch** if you use Apple Watch with Shop !.
- Prefer **noWatch** if you only need the iPhone app.

### Build from source

```bash
brew install xcodegen
cd "Shop!"
xcodegen generate
open Shop.xcodeproj
```

| Scheme | Platform |
|--------|----------|
| `Shop` | iPhone (embeds Watch + widget when configured) |
| `ShopMac` | Mac |
| `ShopWatch` | Watch only |

```bash
cd Shared && swift test
```

Requirements: Xcode 16+, macOS 15+, iOS 18+, watchOS 11+.

### WebDAV

**Settings → WebDAV**: HTTPS server, username, password (Keychain). Remote file: `shop_sync.json`.

### License

MIT

---

## Shop ! (中文)

本地优先的购物清单，SwiftUI 原生支持 iPhone / Apple Watch / Mac，可选 WebDAV 与手表同步。

### 功能概览

- iOS / watchOS / macOS 原生界面，共享 `ShopCore`
- 标签、筛选、多选批量、归档区
- iPhone ↔ Mac：WebDAV（`shop_sync.json`）
- iPhone ↔ Apple Watch：WatchConnectivity
- 小组件（按平台配置）
- 常见操作支持一级撤销

### 下载（GitHub Releases）

发布页：[https://github.com/RyanStarFox/Shop/releases](https://github.com/RyanStarFox/Shop/releases)

| 文件 | 平台 | 说明 |
|------|------|------|
| `Shop-*-macOS.dmg` | Mac | 将 `Shop !.app` 拖入「应用程序」 |
| `Shop-*-iOS-withWatch.ipa` | iPhone（含 Watch） | 带手表 companion |
| `Shop-*-iOS-noWatch.ipa` | 仅 iPhone | 不含手表应用 |

#### Mac：提示「已损坏」或无法打开

从 GitHub 下载的文件常被系统加上隔离属性（quarantine）；当前 DMG 多为 **开发证书签名且未公证**，容易被拦截。

安装后可在终端执行：

```bash
# 推荐：清除应用程序上的隔离属性
xattr -cr "/Applications/Shop !.app"

# 如有需要也可：
sudo xattr -rd com.apple.quarantine "/Applications/Shop !.app"
```

若仍无法打开：打开 **系统设置 → 隐私与安全性 → 仍要打开**。

若 App 不在「应用程序」目录，请把路径改成实际 `.app` 位置。

#### iPhone：如何安装

本仓库发布流程 **不走 App Store**。

你可以：

1. **用 Xcode 自行编译安装**到自己的 iPhone（日常自用推荐），或  
2. 下载 Release 里的 **IPA**（`withWatch` / `noWatch`），用支持开发版 IPA 的工具（如 AltStore、Sideloadly 等）安装，并使用 **你自己的** Apple ID / 开发者团队签名。

说明：

- Release 中的 IPA 一般为 **development / debugging** 导出，需要有效签名与设备注册。
- 需要手表同步请选 **withWatch**。
- 只要手机请选 **noWatch**。

### 从源码构建

```bash
brew install xcodegen
cd "Shop!"
xcodegen generate
open Shop.xcodeproj
```

| Scheme | 平台 |
|--------|------|
| `Shop` | iPhone（按配置嵌入 Watch / 小组件） |
| `ShopMac` | Mac |
| `ShopWatch` | 仅 Watch |

```bash
cd Shared && swift test
```

环境：Xcode 16+，macOS 15+，iOS 18+，watchOS 11+。

### WebDAV

**设置 → WebDAV**：HTTPS 地址、用户名、密码（存 Keychain）。远端文件为 `shop_sync.json`。

### 许可证

MIT
