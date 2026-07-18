# Tag Match Mode, Date Keyboard, Draft Esc

Date: 2026-07-17  
Status: Approved

## 1. Sidebar tag AND/OR

- Always show a segmented control at the top of the Tags section: Match Any / Match All.
- Persist `tagMatchMode` on `DataStore` (default `.any`).
- Filtering:
  - Empty `selectedTags` → no tag filter (all tags).
  - `.any` → item has at least one selected tag.
  - `.all` → item has every selected tag.
- Reuse `WidgetTagMatchMode` / existing Match Any / Match All strings.

## 2. Date field keyboard (editor)

| Key | Behavior |
|-----|----------|
| Tab / Shift+Tab | Leave the date field; move to next/previous editor field (including wrap to name). |
| ← / → | Move between year/month/day/hour/minute segments. |
| ↑ / ↓ | Change the current segment value only; do not jump editor fields or reset to the first segment. |

## 3. Draft Esc

- Name non-empty (trimmed) → Esc saves the draft (same as commit) and returns focus to the list.
- Name empty → Esc discards without saving and returns focus to the list.
