<div align="center">

# AutoDelete

WoW 3.3.5a inventory manager for Project Ebonhold. Mark items to **Delete**, **Sell**, **Keep**, **KeepOne**, or **KeepStack**. Every automatic feature is opt-in.

![Project Ebonhold 3.3.5a](https://img.shields.io/badge/Project%20Ebonhold-3.3.5a-e6cc80.svg?style=for-the-badge)

[**Latest Release**](https://github.com/disarrayed/AutoDelete/releases/latest) · [**All Releases**](https://github.com/disarrayed/AutoDelete/releases) · [**Source**](https://github.com/disarrayed/AutoDelete)

<img src="screenshots/panel.png" alt="AutoDelete settings panel" width="540" />

</div>

---

## 🧠 How it works

Five lists per character:

| List | Behavior |
|------|----------|
| **Delete** | Destroyed on the next bag scan |
| **Sell** | Sold the next time you open a vendor |
| **Keep** | Protected from every auto-rule |
| **KeepOne** | Cleanup list: keeps one unit and deletes extra units |
| **KeepStack** | Cleanup list: keeps one bag stack and deletes extra stacks |

Drag items onto the Delete / Sell / Keep buttons next to your bags, or open the settings panel and edit each list directly.

Quest items are protected from every auto-rule, regardless of list state.

---

## ✨ Features

**Lists**
- Drag-and-drop or shift-click to add items
- Per-character lists with profile copy
- Built-in search and raw view
- **Import Raw** (Profile tab): paste item names, item links, `item:<id>`, or plain numeric IDs, then pick Delete, Sell, Keep, KeepOne, or KeepStack. AutoDelete resolves cached names, current bag items, and known list entries, while reporting ambiguous or unresolved names instead of guessing.
- **Import Lists** (Profile tab): copy lists from a known item-name catalog
- **Export Raw** (Profile tab): dumps any list as plain names by default, or stable `item:<id>` lines with name comments when Raw is checked. Pre-selected on open so Ctrl+C grabs it.
- **Audit Lists** (Profile tab or `/del audit`): copyable report for duplicates, cross-list conflicts, name-only entries, same-name item ID traps, and uncached item IDs. **Fix Safe** removes same-list duplicates and normalizes safe item references only.
- **Manage Ignored Items** (Filters tab): view and clear the per-item skip list that builds up when you accept Keep-override popups

**Bag buttons**
- ElvUI and Bagnon bag windows can show Delete, Sell, and Keep buttons.
- Drop an item on a button to add it to that list.
- Right-click a button to jump to that list's tab.
- Alt+Right-click works on both Blizzard's native bags and ElvUI bags to open the item quick-action menu.

**Sell rules**

Four independent categories.
- Sell Known Recipes (only recipes whose tooltip says Already known; unknown or unreadable recipes stay kept from automatic sell rules while this rule is on)
- Sell Known Recipes has BoE / BoP and white / green / blue / purple toggles, so soulbound and non-soulbound known recipes can be controlled separately
- Recipe decisions appear in **Why?**, `/del history`, `/del report`, and `/del processdebug` with knowledge state, quality-toggle status, and BoE/BoP status
- BoE Armor (bind-on-equip gear)
- BoP (bind-on-pickup gear)
- BoE Weapons (bind-on-equip weapon-slot items, priority over BoE Armor)

**Auto Actions** (General and Filters tabs)
- Delete Junk is a checkbox on the General tab: checked deletes gray junk during bag scans, unchecked sells gray junk at vendors.
- Common, Greens, and Rares have Del / Sell pills on the Filters tab.
- Click a pill to light it red (delete) or blue (sell). Click again to turn it off.
- If ElvUI is loaded, Delete Junk hides ElvUI's junk coin while that mode is active.
- Greens and Rares default to off. Green and blue gear stay in bags unless you opt in.
- Auto-Add Equipped also adds Blizzard equipment set items to Keep.
- Cosmetic slots (shirts, tabards) and quest items are always protected

**Affix Protection** (Affix tab)
- Tier I-VI checkboxes protect matching affix tiers before Delete, Sell, or One-Key Disenchant rules
- "Refresh List" scans your Delete / Sell lists for items the filter would now save
- "Update Affix List" asks the server for your learned affixes and opens AutoDelete's PEEv1-style affix mirror with Armor, Weapon, and Learned filters, search, family selection, tier icons, descriptions, and learned/locked states. It does not depend on PEE being loaded.
- **Show/Keep Missing Affix**: only show the affix dot on items whose affixes you haven't learned yet and protect those missing affixes from Delete, Sell, and One-Key Disenchant cleanup.
- **Missing Affix Color**: choose the dot color for affixes your account has not learned. Defaults to `#ff3b41`.
- **KeepOne Missing Affix**: protect one gear item for each missing affix from Delete, Sell, and One-Key Disenchant rules. Duplicate missing-affix gear can still clear through normal cleanup rules. It is a toggle, not a list, and learned affixes are ignored.
- Affix dots are limited to eligible armor/weapon gear slots; cosmetic items such as tabards do not inherit dots from matching names.

**Companion management**
- Auto-summon Greedy Scavenger and Goblin Merchant
- **Auto-Close after sell** is on the Pets tab in the Summon Merchant card: checked closes the vendor after AutoDelete finishes selling, unchecked leaves the vendor open.
- **Only in Combat** gates every automatic Greedy Scavenger summon, including After sell and After vendor close
- **No Group Summons** blocks automatic Greedy Scavenger and Goblin Merchant summons while you are in a party or raid

**Project Ebonhold Scrap coexistence**
- PEE's Scrap/Junk Selling module is a separate server-side seller. It does not read AutoDelete's Keep list, affix protection, or Sell/DE decisions.
- Keep PEE's **Sell EVERYTHING** off, and avoid PEE always-sell rules for gear you protect in AutoDelete. Both sellers can react to the same merchant window.
- Decision History and `/del report` label PEE Scrap, external merchant, player, and other-addon actions as **not AutoDelete** when they can be attributed. Manual vendor sales are confirmed from a bag delta; PEE confirmations are correlated to request-time Scrap candidates, with a batch-level entry when the server provides no item-level delta.
- Mount-aware dismiss and re-summon
- Stuck detection via loot-event tracking
- Three-state Goblin defer: won't summon until AutoDelete has had a chance to clear bags

**One-Key actions** (Keybinds tab)
- Bind a key to any of: Disenchant, Mill, Prospect, or Open a container
- Each press acts on the next eligible item in your bags
- Keep-list override warnings only appear when the matching one-key action is pressed
- Status line per row shows the next target, or "Requires <profession>" if the character can't perform the action
- Per-action Filters button to tune what each one targets

**Process Bags panel** (`/del process`)
- Standalone window showing what AutoDelete would do to each bag slot
- Filter rows by All, Sell, Delete, DE, Mill, Prospect, Open, or Kept
- Inspect what's about to happen before it does
- Items with the same item ID are grouped together to reduce repeated rows when affix names differ
- Hover a row to see the matching rule and reason, including Affix Protection and KeepOne/KeepStack blockers
- Left-click DE / Mill / Prospect / Open rows to arm that item for the matching keybind
- Left-click Sell / Delete / Kept rows to open Why?
- Right-click a row for quick actions: Keep, Sell, Delete, or Why? Ignore for Process appears only for DE, Mill, and Prospect rows and removes that item from those one-key targets.
- Refresh rebuilds the list from current bag contents when new items appear.
- Alt+Right-click a real bag item for the same quick actions, without changing normal right-click item use

**Why? and report**
- Right-click a Process Bags row, then choose **Why?** for a copyable item decision report
- `/del report` opens a copyable diagnostic summary
- `/del processdebug` opens a copyable Process Bags gate report for every current bag item
- `/del de history` opens recent One-Key Disenchant actions from this session
- `/del history` opens a copyable recent decision log for this session, including recipe sales and recipe protection
- The Help tab has topic buttons with practical how-to guidance for each main area

**Quality of life**
- Minimap button: square AD mark; left-click opens or closes settings, right-click opens a quick menu with Enable/Disable plus safe panels and reports, and drag moves the button
- Enable Addon on the General tab and the minimap menu are synced. Turning it off stops automatic delete, sell, repair, summon, invite, spam hiding, and equipped-item sync actions.
- Bags stay open when the vendor closes
- Auto-repair dropdown with None, Player, and Guild choices
- Hide Greedy Scavenger spam while AutoDelete is enabled
- Auto-invite on whisper keyword while AutoDelete is enabled, with loot rule and raid conversion options
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

Run `/del help`, `/del ?`, or `/del commands` in-game for the same list.

```
/del               Open the settings panel
/del help          Show the command list (also: /del ? or /del commands)
/del clean         Remove duplicate or conflicting item-list entries
/del sell          Force a sell pass at the current vendor
/del setup         Reopen the welcome popup
/del process       Open the Process Bags inspection window
/del report        Open a copyable diagnostic report
/del processdebug  Open a Process Bags gate-by-gate diagnostic
/del processdebug clear
                   Clear Process Bags diagnostic caches and refresh the panel
/del de history    Open recent One-Key Disenchant actions
/del de history clear
                   Clear One-Key Disenchant history for this session
/del history       Open searchable recent sell / delete / keep decisions, including recipes
/del history clear Clear the decision history for this session
/del audit         Open a copyable item-list audit
/del audit lists   Alias for /del audit
/del audit fix     Apply safe list cleanup only
/del audit lists fix
                   Alias for /del audit fix
/del affix         Open AutoDelete's server-fed PEEv1-style affix mirror
/del debug         Toggle the auto-sell / auto-delete debug trace
/del perf          Toggle performance instrumentation
/del perf report   Print performance stats collected since /del perf was enabled
/del perf reset    Clear performance stats and start counting from zero
/del spike         Show spike-debug state and threshold
/del spike on      Enable frame-level spike capture
/del spike off     Disable frame-level spike capture
/del spike <ms>    Set the spike threshold from 5 to 500 ms
/del spike report  Open the saved spike report
/del spike chat    Print the spike report to chat
/del spike clear   Clear saved spike samples
/del elvuihook     Show the ElvUI bag-hook diagnostic state
/del elvuihook on  Enable AutoDelete's ElvUI bag-hook work
/del elvuihook off Disable AutoDelete's ElvUI bag-hook work
/del bench         Toggle the loot-burst performance benchmark
/del bench start   Arm the benchmark
/del bench stop    Stop and save the active benchmark
/del bench cancel  Cancel the active benchmark without saving
/del bench list    List saved benchmark runs
/del bench compare Compare the last two benchmark runs
/del bench show <name>
                   Show one saved benchmark report
/del bench delete <name>
                   Delete one saved benchmark run
/del bench <name>  Arm a benchmark with an explicit name
/del goblin        Open a copyable Goblin Merchant summon diagnostic
/del scav          Open a copyable Scavenger summon / retry / stuck-detection diagnostic
/del pet           Alias for /del scav (also: /del pos)
/del pos           Alias for /del scav
/autodelete        Alias for /del
```

The diagnostic commands do not change item lists or automatic sell/delete
settings. `/del perf` and `/del spike` collect local performance data, while
`/del bench` manages saved benchmark runs. `/del elvuihook off` is an ElvUI
troubleshooting switch and stops AutoDelete's ElvUI bag-slot work until it is
turned on again.

---

## 🙏 Credits

Feature ideas and patterns from the community.

- **Affix Protection**, suggested by Biboup! [SBTL] on 5/13/26 at 4:23 PM:
  > Would it be possible to have an option to not delete items with affix or that's hard to do ?
- **Delete queue throttle pattern**, adapted from [Qloot](https://github.com/mmobrain/Qloot) by **Skulltrail**. AutoDelete v3.20 uses the same OnUpdate-drained queue approach to spread bag-delete API costs across frames instead of bursting them.
- **Performance feedback and Qloot pointer.** **Xurkon** flagged the delete-burst stutter on PE Discord and pointed at Qloot's throttle implementation.
- **Auto-Sell options for Junk and Common** (Filters tab), suggested by Sanavesa on 5/21/26 at 8:48 AM:
  > thanks for this addon. is it possible to add auto-sell junk/common? currently i see there is auto-delete options
- **KeepStack**, credited to @lazzat as the inspiration for the KeepStack list name and keep-one-stack cleanup idea. AutoDelete's KeepStack code is an original implementation for this addon.
- **Sell Known Recipes**, suggested by @Lazzat: auto-sell already-known recipes while keeping unknown recipes safe from automatic sell rules, with BoE/BoP and white/green/blue/purple filters.

---

## 📜 Influence

AutoDelete started February 5, 2026. EbonholdStuff by Badutski2 (GitHub repo created February 13, 2026, last commit February 17) is another addon in the same niche. Both use the same Blizzard 3.3.5a API surface; some ideas crossed over. The code is original, written from scratch, with no shared snippets.

AutoDelete has been re-implemented in part by EbonClearance, which is itself a fork of EbonholdStuff. We appreciate the shoutouts in their source comments, even when one cites "AutoDelete v3.14," a version we apparently forgot to ship. We'll get to it.

The chocolate box stays. We appreciate the passion. The chocolate would like you to know it is in a safe place.

Got good ideas? Use 'em anytime. Thanks for the shoutouts!

---

### A note on Auto-Open Containers

Auto-open was tested in development and removed before public release.

Why it was removed:
- WoW 3.3.5a blocks many container uses when an addon tries to fire them automatically.
- The client raises `ADDON_ACTION_BLOCKED` unless the action comes from a real click or key press.

What to do now:
- Right-click those containers manually.
- Use keybind-driven tools where available.

We may revisit this later as a keybind-first feature.

---

<div align="center">
<sub>Made with ❤️ and 🤖 for the Project Ebonhold community. Fork it. Rebrand it. I don't care.</sub>
</div>
