# Changelog

All notable changes to AutoDelete are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.2.1] - 2025-02-06

### Fixed
- Auto-delete no longer fires while dragging an item, which was preventing drag-and-drop from working properly
- Gray item scanner also pauses when cursor is holding an item

## [1.2.0] - 2025-02-06

### Added
- Auto-add gray (junk) items checkbox — automatically adds quality-0 items to the deletion list on loot
- ElvUI bag button is now a drop target — drag items onto it to add them to the list
- Right-click ElvUI bag button to open settings
- List box itself now accepts drag-and-drop (removed separate drop zone)
- Empty state hint text when list is empty: "Drag items here to add to deletion list"
- Each list row also accepts drag-and-drop
- Profile dropdown skinned with thin ElvUI-style border
- Search box restyled with thin border and dark background (no more default InputBoxTemplate)

### Changed
- All UI borders changed from thick Blizzard tooltip borders to thin 1px ElvUI-style borders (`Interface\Buttons\WHITE8X8`)
- ElvUI bag button changed from click-to-open to drop-target with red highlight on hover
- Drop zone removed in favor of list box accepting drops directly

### Fixed
- Backdrop colors unified across all UI elements for consistent look

## [1.1.0] - 2025-02-06

### Added
- Auto-add gray items feature (checkbox + scanning logic)
- ElvUI bag button that opens settings panel
- `autoGray` field added to profile data

### Changed
- All UI borders updated to thin 1px style using `Interface\Buttons\WHITE8X8`

## [1.0.1] - 2025-02-05

### Fixed
- UI sizing to fit properly in interface panel (360x180 list)
- Raw list now shows item IDs with name comments (`item:12345 # Item Name`)
- Removed combat lockdown restriction — items delete during combat

### Added
- Item icons next to names with proper caching via `GET_ITEM_INFO_RECEIVED`
- Empty state message when list is empty

### Changed
- List itself accepts drag-and-drop (removed separate drop zone in earlier iteration)

## [1.0.0] - 2025-02-05

### Added
- Initial release
- Core auto-deletion engine with throttled bag scanning (0.75s between scans)
- Drag & drop interface for adding items
- Visual item list with icons, names, and remove buttons
- Profile system with per-character deletion lists
- Search filter for finding items in the list
- Raw list view for advanced editing
- Slash commands: `/del` and `/autodelete`
- `SavedVariables` database with migration support
- Periodic scanning every 2 seconds when enabled
