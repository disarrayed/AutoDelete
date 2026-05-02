# AutoDelete

<div align="center">
<img src="https://img.shields.io/badge/version-v3.17.2-a335ee?style=for-the-badge" /><br>
<img src="https://img.shields.io/github/downloads/disarrayed/AutoDelete/total?style=for-the-badge&color=ff8000" /><br>
<img src="https://img.shields.io/badge/PLATFORM-PROJECT%20EBONHOLD-e6cc80?style=for-the-badge" />
<br><br>
<b>Automatically delete and sell items from your bags on Project Ebonhold (3.3.5a)</b>
<br><br>
<a href="https://github.com/disarrayed/AutoDelete/releases/latest">⬇ Download Latest</a>   •   <a href="https://github.com/disarrayed/AutoDelete">📂 View Source</a>
</div>

---

AutoDelete handles the repetitive parts of inventory management so you don't have to. Mark items to Delete, Sell, or Keep. Set up category-based sell rules. Let the addon do the rest while you play.

---

## 🧠 How It Works

Three lists drive everything:

| List | Behavior |
|------|----------|
| 🔴 **Delete** | Items are destroyed on the next bag scan |
| 🟡 **Sell** | Items are sold the next time you open a vendor |
| 🔵 **Keep** | Items are protected and never auto-sold or auto-deleted |

Drop items onto the **Delete / Sell / Keep** buttons next to your bags, or open the settings panel and use the matching tabs.

> 📜 **Quest items are always protected** from every automatic rule.

---

## ✨ Features

### 📋 List Management
- Drag-and-drop **Delete**, **Sell**, and **Keep** lists with built-in search
- **Per-character lists** with profile tools (copy from alts, import, clear)

### 🎒 ElvUI Bag Frame Integration
- Three quick-action buttons: **Delete | Sell | Keep**
- Drop items to add them; right-click to jump to that list's tab in the panel

### ⚔️ Sell Rules
- **Three independent categories**, each with its own iLvl range and Rare/Epic toggles:
  - 🛡️ **BoE Armor** — bind-on-equip gear
  - 🔒 **BoP** — bind-on-pickup gear
  - 🗡️ **BoE Weapons** — bind-on-equip weapon-slot items (priority over BoE Armor)
- **Global quality actions** on the General tab:
  - 🗑️ Auto-Delete Junk (gray)
  - 🗑️ Auto-Delete Common (white gear)
  - 💰 Auto-Sell Greens (uncommon gear)

### 🐾 Companion Management
- 🐰 **Summon Scavenger** automatically at the Goblin Merchant
- 🛍️ **Auto-summon Goblin Merchant** when bags hit zero free slots (3-second debounce)
- 🐎 **Mount-aware** — dismisses on mount, re-summons on dismount
- 🪄 **Stuck detection** — re-summons companions that despawn or get left behind

### 🔧 Quality of Life
- 🛒 Bags stay open when the vendor window closes
- 🛠️ **Auto-repair** at vendors, with optional guild bank funds
- 🔇 **Hide Greedy Scavenger** chat and emote spam
- 💌 **Auto-invite on whisper keyword** with loot-rule and raid-conversion options
- 📊 **Per-character tracking** — gold earned, items sold/deleted, repairs, inventory average
- 👋 **Welcome popup** walks new users through setup (reopen with `/del setup`)

---

## 📦 Installation

1. Download the latest `zip` from the [Releases](https://github.com/disarrayed/AutoDelete/releases) page
2. Extract to your `WoW\Interface\AddOns` folder
3. **Important:** the folder must be named `AutoDelete`
   <sub>If it shows `AutoDelete-main`, rename it</sub>
4. **Restart WoW**
   <sub>`/reload` is not enough for a fresh install</sub>

---

## ⌨️ Slash Commands

```
/del               Open the settings panel
/del clean         Remove duplicates across Delete and Sell lists
/del sell          Force a sell pass at the current vendor (manual override)
/del setup         Reopen the welcome popup
/autodelete        Alias for /del
```

---

## 💬 About

AutoDelete is built for **Project Ebonhold (WoW 3.3.5a)** to simplify inventory management without changing gameplay. Every automatic feature is **opt-in** and gated behind toggles, so the addon does nothing until you tell it what you want.

<div align="center">
<sub>Made with ❤️ and 🤖 for the Project Ebonhold community. Fork it. Rebrand it. I don't care.</sub>
</div>
