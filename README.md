<div align="center">

# AutoDelete

WoW 3.3.5a inventory manager for Project Ebonhold. Mark items to **Delete**, **Sell**, or **Keep**. Every automatic feature is opt-in.

![version](https://img.shields.io/badge/version-v3.20-ff8000?style=for-the-badge) ![downloads](https://img.shields.io/github/downloads/disarrayed/AutoDelete/total?style=for-the-badge&color=ff8000) ![platform](https://img.shields.io/badge/PROJECT%20EBONHOLD-3.3.5a-e6cc80?style=for-the-badge)

[**Download**](https://github.com/disarrayed/AutoDelete/releases/latest) · [**Source**](https://github.com/disarrayed/AutoDelete)

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
- Per-character lists with profile copy
- Built-in search and raw view
- **Import Raw** (Profile tab): paste item names or links into a popup, then pick Delete, Sell, or Keep. Bulk-loads a list from text in one go.
- **Import Lists** (Profile tab): copy lists from a known item-name catalog
- **Export Raw** (Profile tab): dumps any list as plain text for sharing or backup. Pre-selected on open so Ctrl+C grabs it.
- **Manage Ignored Items** (Filters tab): view and clear the per-item skip list that builds up when you accept Keep-override popups

**ElvUI bag buttons**
- Three buttons next to your bag frame: Delete, Sell, Keep
- Drop to add. Right-click to jump to that list's tab.

**Sell rules**

Three independent categories, each with its own iLvl range and Rare/Epic toggles.
- BoE Armor (bind-on-equip gear)
- BoP (bind-on-pickup gear)
- BoE Weapons (bind-on-equip weapon-slot items, priority over BoE Armor)

**Auto Actions** (Filters tab)
- Per-quality Del / Sell pills for Junk, Common, and Greens
- Click a pill to light it red (delete) or blue (sell). Click again to turn it off.
- Greens defaults to off. Green gear stays in bags unless you opt in.
- Cosmetic slots (shirts, tabards) and quest items are always protected

**Affix Protection** (Affix tab)
- Skip Auto-Delete and Auto-Sell for items carrying Project Ebonhold's affix marker
- Optional minimum iLvl floor so low-iLvl affix junk can still be cleared
- "Audit Lists" button scans your Delete / Sell lists for items the filter would now save
- "Scan Learned Affixes" opens a scrollable window of every PE affix you've learned, grouped by tier
- **Affix Collection Mode** (`/del collection`): only show the affix dot on items whose affixes you haven't learned yet. Helps you spot fresh affixes worth keeping.

**Companion management**
- Auto-summon Greedy Scavenger and Goblin Merchant
- Mount-aware dismiss and re-summon
- Stuck detection via loot-event tracking
- Three-state Goblin defer: won't summon until AutoDelete has had a chance to clear bags

**One-Key actions** (Keybinds tab)
- Bind a key to any of: Disenchant, Mill, Prospect, or Open a container
- Each press acts on the next eligible item in your bags
- Status line per row shows the next target, or "Requires <profession>" if the character can't perform the action
- Per-action Filters button to tune what each one targets

**Process Bags panel** (`/del process`)
- Standalone window showing what AutoDelete would do to each bag slot
- Inspect what's about to happen before it does

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
/del process       Open the Process Bags inspection window
/del collection    Toggle Affix Collection Mode (show only unlearned affixes)
/del debug         Toggle the auto-sell / auto-delete debug trace
/del bench         Run a loot-burst performance benchmark (diagnostic)
/del spike         Capture frame-level performance spikes (diagnostic)
/del goblin        Show the auto-summon decision state (diagnostic)
/autodelete        Alias for /del
```

---

## 🙏 Credits

Feature ideas and patterns from the community.

- **Affix Protection**, suggested by Biboup! [SBTL] on 5/13/26 at 4:23 PM:
  > Would it be possible to have an option to not delete items with affix or that's hard to do ?
- **Delete queue throttle pattern**, adapted from [Qloot](https://github.com/mmobrain/Qloot) by **Skulltrail**. AutoDelete v3.20 uses the same OnUpdate-drained queue approach to spread bag-delete API costs across frames instead of bursting them.
- **Performance feedback and Qloot pointer.** **Xurkon** flagged the delete-burst stutter on PE Discord and pointed at Qloot's throttle implementation.
- **Auto-Sell options for Junk and Common** (Filters tab), suggested by Sanavesa on 5/21/26 at 8:48 AM:
  > thanks for this addon. is it possible to add auto-sell junk/common? currently i see there is auto-delete options

---

## 📜 Influence

AutoDelete started February 5, 2026. EbonholdStuff by Badutski2 (GitHub repo created February 13, 2026, last commit February 17) is another addon in the same niche. Both use the same Blizzard 3.3.5a API surface; some ideas crossed over. The code is original, written from scratch, with no shared snippets.

AutoDelete has been re-implemented in part by EbonClearance, which is itself a fork of EbonholdStuff. We appreciate the shoutouts in their source comments, even when one cites "AutoDelete v3.14," a version we apparently forgot to ship. We'll get to it.

The chocolate box stays. We appreciate the passion. The chocolate would like you to know it is in a safe place.

Got good ideas? Use 'em anytime. Thanks for the shoutouts!

### A note on Auto-Open Containers

An attempt to auto-open lootable containers (clams, crates, mysterious eggs, etc.) on bag update shipped in development but was removed before the public release.

WoW 3.3.5a flags `UseContainerItem` as a protected function for many container types. When called from an addon scan or event handler (rather than from a real player click or keypress) the client rejects the call and fires `ADDON_ACTION_BLOCKED`. This is documented Blizzard behavior, not a server modification, and it affects every addon that attempts the same approach. The supported workaround is a secure button bound to a user keybind or macro, which is a manual interaction rather than a true automatic open.

We may revisit this as a keybind-driven feature in a future release. Until then, containers that don't respond to automatic opens must be right-clicked manually.

---

<div align="center">
<sub>Made with ❤️ and 🤖 for the Project Ebonhold community. Fork it. Rebrand it. I don't care.</sub>
</div>
