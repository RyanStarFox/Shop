# Shop! 体验增强：Mac 添加、日期编辑、小组件、教程与同步

日期：2026-07-15

## 目标

在现有 Shop! 架构（SwiftUI + SwiftData + ShopCore + WebDAV + WatchConnectivity）上，交付一批跨端体验增强，重点解决 Mac 添加流程、选中高亮冲突、可编辑日期、首次教程、下拉同步、触控板反馈，以及 iPhone / Mac 可交互小组件。

## 非目标

- 不降低最低系统版本（iOS 18 / macOS 15 / watchOS 11）。
- Watch 不做首次教程、不做桌面小组件。
- 小组件不支持添加新物品或编辑名称/标签（仅标记完成）。
- 不引入账号系统或 CloudKit。

## 主题色

- 品牌色值更新为 **`#C53A32`**。
- 统一使用 **`ShopTheme.brandColor`** 作为唯一主题色入口。
- 删除 `naturalGreen`、`brandRed` 等易混淆别名；全仓库引用迁移到 `brandColor`。
- 默认 Tag 色、FAB、完成按钮、选中淡底等均跟随 `brandColor`。
- 小组件与教程插图同样使用 `brandColor`，并适配浅色 / 深色模式。

---

## 1. Mac 添加流程

### 现状问题

侧栏顶部 `quickAddBar` 只能输入名称，标签与日期需事后在右侧编辑，与「编辑已有物品」体验割裂。

### 目标行为

- **移除**侧栏快速添加输入框。
- **右下角**固定加号 FAB；**⌘N** 等效触发。
- 点击加号进入**草稿模式**：
  - 待买列表**最上方**出现占位行（如「新物品」），自动选中。
  - **右侧详情栏**复用与编辑已有物品相同的表单：名称、标签、添加时间、完成时间。
- **名称非空并确认**（回车 / 与现编辑一致的失焦保存）后才调用 `addItem` 写入数据库；写入后占位行变为真实条目并保持选中。
- **空名称草稿丢弃规则**（选项 1）：
  - 选中其他物品、再次按加号、关闭窗口 → 直接丢弃草稿，不写库。
- **⌘Z** 继续走现有 `UndoCoordinator`；未入库的草稿不在撤销栈内。

### 数据层

- 扩展 `addItem` 支持可选 `createdAt`（草稿确认时写入用户选择的添加时间）。
- Mac 草稿状态由 `MacContentView` 本地 `@State` 管理，不入 SwiftData，直到确认保存。

---

## 2. Mac 选中高亮、快捷键完成、触控板反馈

### 选中高亮

- 保留自定义**淡色选中底**（`brandColor` 低透明度）。
- **移除** `List(selection:)` 带来的系统灰/蓝选中层（避免与完成按钮点击冲突）。
- 选中状态继续由 `selectedItemID` 驱动右侧详情，不依赖系统 List selection 样式。

### 空格 / 回车完成

- 当列表有选中物品，且焦点**不在**名称 / 日期等输入框时：
  - **空格**或**回车** → 切换完成状态（等同点击圆圈）。
- 焦点在输入框时：回车 / 空格仅用于编辑确认，不触发完成。

### 触控板震动

- Mac 完成 / 恢复时调用已有 `ShopHaptics`（`NSHapticFeedbackManager`）。
- 在 `setCompleted` / toggle 完成路径上补齐调用（当前共享层已实现，Mac UI 未全部接入）。

---

## 3. 可编辑日期（iPhone + Mac + Watch）

### 字段

- **添加时间**（`createdAt`）：新建与编辑均可改。
- **完成时间**（`completedAt`）：仅物品已完成时显示并可改。

### iPhone

- 延续 `ItemEditorView` 日期折叠区 `DatePicker`（日期 + 时分）。
- **修复**：新建保存时须将用户修改过的 `createdAt` 写入数据库（当前编辑模式已支持，新建模式需补齐）。
- 编辑已完成物品时继续支持 `completedAt` 更新。

### Mac

- 右侧 `MacItemDetailView` 将只读日期改为可编辑 `DatePicker`，与名称 / 标签同样即时保存。
- 草稿模式右侧详情同样展示可编辑添加时间；确认保存时一并写入。

### Watch

- **新建**（`WatchAddItemView`）：增加添加时间 `DatePicker`，支持**数码表冠**滚轮调节（系统默认 `DatePicker` 行为）。
- **已有物品**：新增简易编辑入口（列表行进入编辑页），可改添加时间；若已完成则显示并可改完成时间。
- 保存后经现有 WatchConnectivity 同步到 iPhone。

### 数据层

- `addItem(name:tags:createdAt:)` 增加可选 `createdAt` 参数。
- `updateItem` 已有 `createdAt` / `completedAt` / `updateCompletedAt` 路径；确保三端 UI 均正确传入。
- 日期修改进入现有撤销栈（通过 `UndoCoordinator` 记录的 `updateItem` 变更）。

---

## 4. iPhone + Mac 小组件

### 尺寸与内容

| 尺寸 | 平台对应 | 内容 |
|------|----------|------|
| 小（约 2×2） | iOS small / macOS small | 待买未完成列表，约 2–3 条 |
| 中（约 2×4） | iOS medium / macOS medium | 待买未完成列表，约 4–6 条 |
| 大（约 4×4） | iOS large / macOS large | 待买未完成列表，约 8–10 条 |

- 三种尺寸展示逻辑一致，仅可见条数随高度调整。
- 排序与主 App 待买列表一致（`sortOrder` / `activeItems`）。

### 交互

- 每条旁提供完成勾选控件（`AppIntent` 或等效 Widget 交互 API）。
- 勾选完成 → 该条从小组件消失；若还有未展示的待买项，**下一条顶上**（重新取 `activeItems` 前缀）。
- 完成后更新共享数据并 `WidgetCenter.reloadTimelines`；触发主 App 同步链路（防抖 WebDAV 等）。

### 空状态

- 文案：「待买清单是空的」（本地化）。
- 点按小组件打开主 App。

### 技术

- 新增 Widget Extension target（iOS + macOS 各一，或共用逻辑）。
- **App Group** 共享 SwiftData 容器或轻量 JSON 快照供 Widget 读取（实现时选改动最小且可靠方案）。
- **深色模式**：使用系统语义色 + `brandColor` 点缀，保证浅 / 深色对比度可读。

### 非目标

- Watch 不做 WidgetKit 小组件。

---

## 5. 首次教程与下拉同步

### 首次教程（iPhone + Mac）

- 仅**第一次启动**自动弹出；`AppStorage` 记录 `hasSeenOnboarding`。
- 设置页提供「查看教程」入口可再次打开。
- 约 3–4 页短教程：
  1. 添加物品（Mac：右下角 + / ⌘N；iPhone：FAB / 添加）
  2. 完成购买（点选圆圈、左滑 / 右滑）
  3. WebDAV 同步（设置配置、自动同步）
  4. 手势与快捷键（按平台显示：下拉刷新、⌘N / ⌘Z、空格完成等）
- Watch **不做**教程。

### 下拉同步

| 平台 | 行为 |
|------|------|
| iPhone | 主列表 `.refreshable` → `syncCoordinator.syncNowIfConfigured()` |
| Mac | 主列表 `.refreshable`（触控板 overscroll 拉开）→ 同上 |
| Watch | 列表 `.refreshable` → `watchSync` 请求 / 发送最新快照 |

- WebDAV 未配置时安静结束或轻提示，不弹吓人错误横幅。

### WebDAV 密码（说明性，非新功能）

- 密码保存在本机 **Keychain**；配置成功后自动同步可持续使用，除非清钥匙串或用户在设置中清除凭据。

---

## 6. 其他修复（纳入本包）

- `ShoppingStore.updateItem` 中 `completedAt` 未使用绑定 warning：改为 `completedAt != nil` 判断（已完成）。
- 全仓库 `naturalGreen` / `brandRed` → `brandColor`，色值 `#C53A32`。

---

## 测试计划

### 单元 / 集成

- `addItem(createdAt:)` 新建带自定义添加时间。
- `updateItem` 日期修改与撤销回滚。
- 小组件 Intent 完成物品后数据源与主 App 一致。

### 手动

| 场景 | 平台 |
|------|------|
| Mac 草稿添加 → 空名切走丢弃 | Mac |
| Mac 草稿确认后右侧编辑与已有物品一致 | Mac |
| 空格 / 回车完成（输入框内外） | Mac |
| 去掉系统灰蓝选中层，完成按钮可点 | Mac |
| 完成 / 恢复触控板震动 | Mac |
| 三端日期编辑 + Watch 表冠 | iPhone / Mac / Watch |
| 首次教程仅一次 + 设置重开 | iPhone / Mac |
| 下拉同步 | 三端 |
| 小组件勾选完成 + 条目标记顶上 + 空状态 + 深色模式 | iPhone / Mac |

---

## 实现顺序建议

1. 主题色 `brandColor` 迁移（全仓库，低风险先行）。
2. Mac 添加草稿 + 选中高亮 + 快捷键 + 震动。
3. 三端可编辑日期（含 `addItem(createdAt:)`）。
4. 下拉同步 + 首次教程。
5. Widget Extension + App Group + 交互 Intent。

---

## 已确认决策摘要

| 议题 | 决定 |
|------|------|
| 实施方案 | 方案 A：一次完整交付 |
| Mac 添加 | 草稿模式 + 右侧同一详情栏；空名切走丢弃 |
| Mac 同步入口 | `.refreshable` overscroll |
| 空格 / 回车完成 | 仅无输入焦点时生效 |
| 日期编辑 | iPhone + Mac + Watch（表冠 DatePicker） |
| 教程 | iPhone + Mac；Watch 不做 |
| 下拉同步 | 三端 |
| 小组件 | iPhone + Mac；三尺寸；待买列表；勾选消失顶上；空状态；深色模式 |
| 主题色 | `#C53A32`，变量名 `brandColor` |
