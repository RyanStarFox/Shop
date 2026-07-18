# 标签和/或模式、日期键盘、草稿 Esc

## 已确认决策

| 主题 | 决策 |
|------|------|
| 侧栏标签匹配 | 标签区顶部常驻分段：**任一匹配** / **全部匹配** |
| 默认 | `.any`（任一），并持久化 |
| 空选标签 | 仍表示全部物品；模式不生效；**不显示**任一/全部 |
| 有选中标签 | 「新建标签」**下方**显示任一/全部 |
| 日期字段 Tab / Shift+Tab / ↑ / ↓ / ← / → | 时间每个小段都是循环中的一项：名称 → 标签 → 年/月/日/时/分… |
| 日期格式 | 使用系统短日期+短时间格式（`DateFormatter` short/short） |
| 标签匹配按钮 | 「新建标签」下方，整行可点、无间隙 |
| 新建 Esc | 名称非空 → 保存；名称为空 → 丢弃 |

## DataStore

- 新增 `tagMatchMode: WidgetTagMatchMode`（复用 Widget 枚举）
- `filteredItems`：`.any` = OR，`.all` = AND（所选标签是物品标签的子集）
- 偏好键：`shop.list.tagMatchMode`

## macOS UI

- `Section(ShopStrings.tags)` 顶部：`Picker` 分段绑定 `dataStore.tagMatchMode`
- 文案：`ShopStrings.widgetMatchAny` / `widgetMatchAll`

## 日期键盘（MacEditorNavigationMonitor）

- 焦点在 `createdAt` / `completedAt`（或 first responder 在 `NSDatePicker` 内）时：
  - Tab / Shift+Tab / ↑ / ↓ → `onNavigate`，不交给 AppKit 改值
  - ← / → → 放行给 `NSDatePicker` 换段
- 删除「把 Tab 永久交给日期控件」的逻辑

## 草稿 Esc

```
if isDrafting:
  if draftName.trim 非空 → commitDraft()
  else → discardDraft()
  restoreListKeyboardFocus()
```
