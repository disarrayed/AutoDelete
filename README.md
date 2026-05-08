# AutoDelete

<div align="center">
<img src="https://img.shields.io/badge/version-v3.18-ff8000?style=for-the-badge" /><br>
<img src="https://img.shields.io/github/downloads/disarrayed/AutoDelete/total?style=for-the-badge&color=ff8000" /><br>
<img src="https://img.shields.io/badge/PLATFORM-PROJECT%20EBONHOLD-e6cc80?style=for-the-badge" />
<br><br>
<a href="https://github.com/disarrayed/AutoDelete/releases/latest"><b>Download Latest</b></a> &nbsp;·&nbsp; <a href="https://github.com/disarrayed/AutoDelete">View Source</a>
</div>

---

A WoW 3.3.5a addon for Project Ebonhold. Mark items to **Delete**, **Sell**, or **Keep**. The addon handles them on bag scan and at vendors. Every automatic feature is opt-in.

<div align="center">
<img src="screenshots/panel.png" alt="AutoDelete settings panel" width="540" />
</div>

---

## 🧠 How it works

Three lists per character:

| List | Behavior |
|------|----------|
| **Delete** | Destroyed on the next bag scan |
| **Sell** | Sold the next time you open a vendor |
| **Keep** | Protected from every auto-rule |

Drag items onto the Delete / Sell / Keep buttons next to your bags, or open the settings panel and edit each list directly.

Quest items are protected from every auto-rule, regardless of list state.

---

## ✨ Features

**Lists**
- Drag-and-drop or shift-click to add items
- Per-character lists with profile copy and import
- Built-in search and raw view

**ElvUI bag buttons**
- Three buttons next to your bag frame: Delete, Sell, Keep
- Drop to add. Right-click to jump to that list's tab.

**Sell rules**

Three independent categories, each with its own iLvl range and Rare/Epic toggles.
- BoE Armor (bind-on-equip gear)
- BoP (bind-on-pickup gear)
- BoE Weapons (bind-on-equip weapon-slot items, priority over BoE Armor)

**Quality actions** (General tab)
- Auto-Delete junk (gray)
- Auto-Delete common (white gear)
- Auto-Sell greens (uncommon gear)

**Companion management**
- Auto-summon Greedy Scavenger and Goblin Merchant
- Mount-aware dismiss and re-summon
- Stuck detection via loot-event tracking

**Quality of life**
- Bags stay open when the vendor closes
- Auto-repair with optional guild bank fallback
- Hide Greedy Scavenger spam
- Auto-invite on whisper keyword, with loot rule and raid conversion options
- Per-character stats: gold earned, items sold or deleted, repairs, average inventory worth
- Welcome popup walks new users through setup. Reopen with `/del setup`.

---

## 📦 Install

1. Download the latest zip from [Releases](https://github.com/disarrayed/AutoDelete/releases)
2. Extract to `WoW\Interface\AddOns`
3. Folder must be named `AutoDelete` (rename if the extract created `AutoDelete-main`)
4. Restart WoW. A `/reload` is not enough on first install.

---

## ⌨️ Slash commands

```
/del               Open the settings panel
/del clean         Remove duplicates across Delete and Sell lists
/del sell          Force a sell pass at the current vendor
/del setup         Reopen the welcome popup
/autodelete        Alias for /del
```

---

## 📜 Influence

AutoDelete started February 5, 2026. EbonholdStuff by Badutski2 (GitHub repo created February 13, 2026, last commit February 17) is another addon in the same niche. Both use the same Blizzard 3.3.5a API surface; some ideas crossed over. The code is original, written from scratch, with no shared snippets.

AutoDelete has been re-implemented in part by EbonClearance, which is itself a fork of EbonholdStuff. We appreciate the shoutouts in their source comments, even when one cites "AutoDelete v3.14," a version we apparently forgot to ship. We'll get to it.

The chocolate box stays. We appreciate the passion. The chocolate would like you to know it is in a safe place.

GitHub timestamps every commit, not us. Dates are public. Knock yourself out.

---

<div align="center">
<sub>Made with ❤️ and 🤖 for the Project Ebonhold community. Fork it. Rebrand it. I don't care.</sub>
</div>
