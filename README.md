# AutoDelete
AutoDelete is a lightweight World of Warcraft addon for **Wrath of the Lich King (3.3.5a)** that automatically deletes specified items from your bags as soon as they are looted.

This addon is intended **specifically for Project Ebonhold**. It is not designed or tested for Retail, Classic Era, or other expansions.

It also works correctly with the **Greedy Scavenger pet**, ensuring unwanted items are cleaned up immediately.

---

## What It Does
- Automatically deletes items you choose when they are looted
- Helps keep bags clean while leveling, farming, or grinding
- Eliminates junk, vendor trash, or unwanted drops instantly

---

## Features
- Drag-and-drop items into a delete list
- Optional auto-delete for all gray (junk) items
- Configurable scan speed (0.75s to 10 minutes)
- Character-based profiles
- Searchable item list
- Raw item list editor for manual control
- Optional ElvUI bag button integration
- Safe throttling to avoid performance issues
- Works during combat

---

## Installation
1. Download or clone this repository
2. Copy the `AutoDelete` folder into:
3. Restart the game or run `/reload`

---

## Usage

### Commands
| Command | Action |
|-------|--------|
| `/del` | Open AutoDelete settings |
| `/autodelete` | Same as above |

### Adding Items
You can add items to the delete list by:
- Dragging items into the settings window
- Dragging items onto the ElvUI bag button (if enabled)
- Enabling automatic gray item deletion
- Manually editing the raw item list

---

## ElvUI Support
If ElvUI is installed, AutoDelete adds a small bag button:
- Drop items on it to add them
- Right-click to open settings
- Tooltip explains usage

ElvUI is optional.

---

## Files
| File | Purpose |
|----|----|
| `AutoDelete.toc` | Addon metadata |
| `AutoDelete.lua` | Core logic and event handling |
| `Options.lua` | Settings UI |

---

## Compatibility
- **WoW Version:** Wrath of the Lich King 3.3.5a
- **Server:** Project Ebonhold
- **ElvUI:** Optional
- **Greedy Scavenger:** Supported

---

## Credits & Disclaimer
This addon was built with significant assistance from **Claude (AI)**.

I do **not** claim authorship of the underlying logic or design. My role was primarily:
- Debugging
- Testing
- Iterating behavior
- Guiding changes in the right direction

My Lua knowledge is limited, and this project exists to solve a practical in-game problem rather than showcase original development work.
