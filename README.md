# AutoDelete

A World of Warcraft addon for Wrath of the Lich King (3.3.5) that automatically deletes specified items from your bags as soon as they're looted.

Perfect for getting rid of junk items, vendor trash, or anything you don't want cluttering your inventory.

## Features

- **Drag & Drop** — Drag items onto the list or the ElvUI bag button to add them
- **Visual Item List** — Shows item icons and names with easy remove buttons
- **Profile System** — Different deletion lists for different characters
- **Search Filter** — Quickly find items in your deletion list
- **Raw List View** — Advanced editing with `item:12345 # Item Name` format
- **Auto-Add Gray Items** — Optionally auto-add all gray (junk) quality items on loot
- **ElvUI Integration** — Drop target button on ElvUI bags (right-click for settings)
- **Works in Combat** — Deletes items even during fights
- **Throttled Scanning** — 0.75s between scans to avoid performance issues
- **ElvUI-Style UI** — Clean thin borders matching modern UI addons

## Installation

1. Download or clone this repository
2. Copy the `AutoDelete` folder into your `Interface/AddOns/` directory:
   ```
   World of Warcraft/Interface/AddOns/AutoDelete/
   ├── AutoDelete.toc
   ├── AutoDelete.lua
   └── Options.lua
   ```
3. Restart WoW or type `/reload` if already in-game

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `/del` | Opens the AutoDelete settings panel |
| `/autodelete` | Same as above |

### Adding Items

There are several ways to add items to the deletion list:

1. **Drag & drop onto the item list** in the settings panel
2. **Drag & drop onto the ElvUI bag button** (if ElvUI is installed)
3. **Enable "Auto-add gray items"** to automatically catch all junk items
4. **Use the raw list editor** to manually type item names or `item:ID` entries

### ElvUI Bag Button

If you use ElvUI, a small button appears on your bag frame:
- **Drop items on it** to add them to the auto-delete list
- **Right-click** to open the settings panel
- Hover for a tooltip with instructions

## Files

| File | Description |
|------|-------------|
| `AutoDelete.toc` | Addon metadata and load order |
| `AutoDelete.lua` | Core deletion logic, event handlers, ElvUI integration, slash commands |
| `Options.lua` | Interface options panel with all UI elements |

## Compatibility

- **WoW Version:** 3.3.5 (Wrath of the Lich King)
- **ElvUI:** Optional — bag button appears automatically if ElvUI is detected
- **Other addons:** No known conflicts

## License

MIT License — see [LICENSE](LICENSE) for details.
