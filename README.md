# AutoDelete

<div align="center">
<img src="https://img.shields.io/badge/version-v3.10-a335ee?style=for-the-badge" /><br>
<img src="https://img.shields.io/github/downloads/disarrayed/AutoDelete/total?style=for-the-badge&color=ff8000" /><br>
<img src="https://img.shields.io/badge/PLATFORM-PROJECT%20EBONHOLD-e6cc80?style=for-the-badge" />
<br><br>
<b>Automatically delete and sell items from your bags on Project Ebonhold (3.3.5a)</b>
<br><br>
<a href="https://github.com/disarrayed/AutoDelete/releases/latest">⬇ Download Latest</a>   •   <a href="https://github.com/disarrayed/AutoDelete">📂 View Source</a>
</div>

---

AutoDelete handles the repetitive parts of inventory management so you don't have to.
Mark items to Delete, Sell, or Keep. Set up category-based sell rules. Let the addon do the rest while you play.

## How it works

Three lists drive everything:

- **Delete** — items destroyed on the next bag scan
- **Sell** — items sold the next time you open a vendor
- **Keep** — items protected and never auto-sold or auto-deleted

Drop items onto the Delete / Sell / Keep buttons next to your bags, or open the settings panel and use the matching tabs. Quest items are always protected from every automatic rule.

## Features

- **Drag-and-drop list management** with search and per-character lists
- **ElvUI bag frame integration** with three quick-action buttons (Delete | Sell | Keep) — drop to add, right-click to jump to that list's tab
- **Three sell categories** with independent settings: BoE Armor, BoP, and BoE Weapons. Each has its own iLvl range and Rare/Epic toggles.
- **Global auto-actions** for Junk (Auto-Delete), Common gear (Auto-Delete), and Greens (Auto-Sell at vendor)
- **Auto-repair** with optional guild bank funds
- **Goblin Merchant summon** when bags hit zero free slots (with 3-second debounce to prevent stray summons)
- **Mount-aware companion handling** — dismisses your Scavenger when mounting, re-summons on dismount
- **Stuck detection** — re-summons companions that despawn or get left behind
- **Auto-invite on whisper keyword** with loot-rule and raid-conversion options
- **Hide Greedy Scavenger** chat and emote spam
- **Per-character tracking** — gold earned, items sold/deleted, repairs, inventory average
- **Profile tools** — copy from alts, import lists, clear lists
- **Shift-click any item** to filter the active list
- **Welcome popup** with optional Goblin Merchant macro creation and keybind walkthrough (reopen with `/del setup`)

## Installation

1. Download the latest `zip` from the [Releases](https://github.com/disarrayed/AutoDelete/releases) page
2. Extract to your `WoW\Interface\AddOns` folder
3. **Important:** the folder must be named `AutoDelete`
   <sub>If it shows `AutoDelete-main`, rename it</sub>
4. **Restart WoW**
   <sub>`/reload` is not enough for a fresh install</sub>

## Slash Commands

- `/del` — open settings panel
- `/del clean` — remove duplicates across Delete and Sell lists
- `/del sell` — force a sell pass at the current vendor (manual override)
- `/del setup` — reopen the welcome popup
- `/autodelete` — alias for `/del`

## About

AutoDelete is built for Project Ebonhold (WoW 3.3.5a) to simplify inventory management without changing gameplay. Every automatic feature is opt-in and gated behind toggles so the addon does nothing until you tell it what you want.
