# Changelog

All notable changes to this project will be documented in this file.

## [3.17.1] - 2026-04-27

### Fixed

- **Settings panel: fixed "Options.lua not loaded" error.** The font fallback check used `pcall` to detect missing fonts, but `SetFont` returns `false` (not an error) when a font file is missing, so the fallback never triggered for users without ElvUI installed. The settings panel would fail to build, leaving `/del` unable to open it. Now uses `SetFont`'s return value directly.

## [3.17] - 2026-04-26

### Fixed

- **Auto-Invite: whispering "inv" to someone no longer invites them.** The outgoing whisper handler (`CHAT_MSG_WHISPER_INFORM`) has been completely removed. Auto-Invite now only responds when someone whispers you a keyword, never when you whisper someone else.

### Improved

- **Pet Management: idempotent summons.** Scavenger and Merchant summon helpers now check if the pet is already summoned before calling `CallCompanion`, eliminating unnecessary dismiss-and-resummon cycles and duplicate chat prints.
- **Pet Detection: creature-ID-based lookup.** Companion detection now uses cached creature IDs (26537 for Scavenger, 26536 for Merchant) with name-substring fallback, making pet identification faster and more reliable.
- **Combat Safety: combat-only default flipped to ON.** Fresh installs and new profiles now default `summonOnlyInCombat = true`. Existing user data is preserved. All automatic summon paths (mount/dismount restore, stuck-detection re-summon, distance-based teleport, bag-full merchant trigger, and reactive `COMPANION_UPDATE` handler) respect this gate.
- **Bag-full delay reduced from 3.0s to 1.5s.** Goblin Merchant summons faster when bags fill up.
- **Bag-full re-arm fix.** If the merchant despawns while bags are still full, the trigger re-arms automatically (previously it stayed disarmed until a slot freed).
- **Loot-event-based stuck detection.** Scavenger is re-summoned when the player loots 2+ times in 60 seconds but the scavenger hasn't said any chat line since the oldest loot. More reliable than summoned-flag-only detection on servers where pets teleport unpredictably.
- **Auto-attach on `COMPANION_UPDATE`.** When the scavenger or merchant becomes summoned and `activeTracked == nil` (user summoned via portrait/macro), the addon automatically attaches tracking so stuck-detection and mount-awareness work for user-initiated summons.
- **Reactive `COMPANION_UPDATE` event handler** with 0.5s debounce and timing-based classification. Distinguishes user-dismiss (within 5s of summon) vs server-leash (after 5s), suppressing restore-on-dismiss for 30s when the user deliberately dismisses.
- **Modifier-click split: shift = search fill (non-destructive), alt = add to Keep.** Shift-click on any item (bag, chat link, AtlasLoot, etc.) now fills the search box when the panel is visible and never intercepts default WoW behavior (stack split, AH search, bank moves, equipment compare, chat link insert all work normally). Alt-click is the new "add to Keep" shortcut. Both skip when any of these frames are open: AuctionFrame, BankFrame, GuildBankFrame, MerchantFrame, TradeSkillFrame, CraftFrame. Stackable items (`maxStack > 1`) are skipped. 0.5s dedupe per itemId prevents double-triggers from chat links firing both paths.

### Added

- **Sell Filters info banner** above the BoE Armor card on the Sell tab. Black background, teal border, teal "i" icon, 24px tall. Single line: "Sell filters: rules below run at vendors. Items matching are auto-sold for gold."
- **Welcome popup updated** with sell filters explanation in the "How it works" section. Body height increased from 82 to 110, popup height from 600 to 628, warning frame repositioned.
- **X clear button** on search box (16x16) and keyword box (14x14). Red on hover.
- **Raw search filter.** Search box now filters the Raw view text. Editor goes read-only (text dims) while filtered. Stash-and-restore pattern preserves edits made before searching. Stash cleared on Raw toggle off, list mode switch, or filter clear.
- **`/del pet` slash command** (alias: `/del pos`). Dumps pet stuck-detection diagnostics: activeTracked, scav last chat time, player loots in window, summonScavenger/summonOnlyInCombat/enabled, in-combat, mounted.
- **`/del debug` now toggles `_G.AutoDelete_DebugSell` flag.** All debug prints are gated behind it (not just sell decision traces).
- **Welcome popup "Open Settings" button diagnostics.** If the panel fails to open (Options.lua not loaded yet), the button now prints diagnostic chat lines.

### Internal

- **`UseContainerItem` uses `hooksecurefunc`, NOT global override.** The 3.16 global-replace approach broke right-click on Hearthstone, potions, scrolls, mounts, and food. Switched to hook + bag snapshot for sell tracking. This fix is critical and must not regress.
- **Ring buffer pruning.** `recentPlayerLootTimes` is pruned to entries within the 60s window on every companion watcher tick and cleared on scavenger re-summon. Maximum realistic size: 10-15 entries. No manual bounding needed.
- **Comment audit.** Enhanced `recentPlayerLootTimes` comment to clarify bounded nature. Auto-invite section docs updated to reflect outgoing handler removal.
- **Architecture.md added to addon folder** for future reference.

## [3.16] - 2026-04-25

### Added

- **Shift-click any item link to add it to the Keep list.** Works in chat, AtlasLoot, whispers, tooltips. If a text box has keyboard focus (chat input, search box, mail subject, etc.), WoW's default insert-link behavior takes priority. Items already on Delete or Sell are refused with a chat message (cross-list conflict protection).
- **Enter clears focus on single-line text fields.** The Search & Manage search box now drops focus when you press Enter, so subsequent keypresses go to the game (or chat) instead of the field. The Auto-Invite keyword box already had this; it's now consistent across the addon.
- **Clear (x) button on single-line text fields.** Click the x in the Search & Manage box to clear the filter. Click it on the Auto-Invite keyword box to reset to the default `inv,invite`.
- **Search now works on the Raw view.** Type in the search box while Raw is open and the editor narrows to matching lines. The editor becomes read-only while filtered (text dims) so you can't accidentally type into a hidden-line view. Clearing the search restores the full editable text. Edits made before searching are preserved.

### Fixed

- **Right-click on usable bag items (Hearthstone, potions, mounts, scrolls, food) now works.** Earlier versions globally replaced `UseContainerItem`, which poisoned WoW 3.3.5's secure-action call path and silently rejected use of any castable item. Switched to `hooksecurefunc` with a bag-snapshot mechanism so manual sell tracking still works at vendors without breaking item use.
- **Shift-click of a chat item link no longer double-prints.** A single click was firing both `ChatEdit_InsertLink` and `HandleModifiedItemClick` paths, producing two "added to keep list" or "already in the list" messages. Added a 0.5-second per-item dedupe.

## [3.15] - 2026-04-25

### Added

- **Shift-click any item link to add it to the Keep list.** Works in chat, AtlasLoot, whispers, tooltips, anywhere a link appears. If a text box has keyboard focus (chat input, search box, mail subject, etc.), WoW's default insert-link behavior takes priority and the addon does nothing - so existing workflows aren't disrupted. Items already on Delete or Sell are refused with a chat message (cross-list conflict protection still applies).

## [3.14] - 2026-04-25

### Changed

- **Delete and Sell lists now override quest item protection.** Previously, items reporting `itemType == "Quest"` were hard-exempt from every rule including the user's explicit lists. Now an item on the Delete list deletes, and an item on the Sell list sells, regardless of quest type. Keep list still wins over both. Auto-rules (Junk/Common/Greens/BoE Armor/BoP/BoE Weapons) continue to respect quest item protection.

### Added

- **Cross-list conflict detector** runs once at login. If any item appears on more than one list (Delete + Sell, Delete + Keep, or Sell + Keep), a yellow chat warning prints with `/del clean` as the resolution path. The add-time conflict check already prevents new ones; this catches legacy entries from imports, manual text edits, or older saves.

## [3.13] - 2026-04-25

### Fixed

- **BoE detection failed on PE-ElvUI environments**, causing every BoE item to be misclassified as BoP and incorrectly sold by the BoP rule. The hidden tooltip used to scan for "Binds when equipped" was returning zero lines on certain setups. Fix: tooltip now uses a real off-screen owner frame and forces a Show/Hide cycle around the line read so the engine populates lines synchronously.

### Added

- New `/del debug` slash command. Toggles a sell-decision trace that prints the inputs (item id, quality, ilvl, slot, bind status, and which rule matched) for every auto-sell. Useful for diagnosing unexpected behavior.

## [3.12] - 2026-04-25

### Added

- Welcome popup now includes a bright red warning callout near the bottom reminding users to add valuable items to the Keep list before enabling auto-delete or auto-sell rules. Reopen the popup anytime with `/del setup`.

## [3.11] - 2026-04-25

### Added

- New **Only in Combat** sub-toggle under Summon Scavenger (Goblin tab, card 2). When enabled, the After-sell and After-vendor-close summons only fire if the player is currently in combat at the moment of the trigger event. Useful if you only want the Scavenger out during fights.

## [3.10] - 2026-04-25

Initial release of the v3.10 line. Major feature set and rework consolidated from prior development.

### Sell rule system

- **Three independent sell categories** on the Sell tab: BoE Armor, BoP, BoE Weapons. Each has its own enable toggle, iLvl range, and Rare/Epic toggles.
- **Quest items are hard-exempt** from every auto-rule. Items reporting `itemType == "Quest"` short-circuit before any rule evaluation, including the explicit Delete and Sell lists.
- **Three global auto-actions** on the General tab card 2: Auto-Delete Junk (gray), Auto-Delete Common (white gear), Auto-Sell Greens (uncommon gear). Independent of the category sections.
- **BoE Weapons takes priority** over BoE Armor for items that match both. BoP is matched separately for non-BoE gear.

### Master toggle gating

- Master Enable now correctly gates auto-repair, vendor auto-sell, and the companion watcher (mount-aware dismiss/re-summon, stuck detection, bag-full Goblin Merchant summon). Previously these ran even when master was off.
- Auto-Invite and Hide Greedy Spam remain independent of master Enable by design.

### Companion management

- Bag-full Goblin Merchant summon now requires bags to stay at zero free slots for **3 seconds continuously** before firing. Prevents stray summons from transient stack merges.
- Stuck detection recognizes deliberate pet swaps (e.g. summoning Goblin Merchant when Scavenger was tracked) and stops fighting the swap.

### ElvUI bag frame integration

- Three buttons on the bag frame in Delete | Sell | Keep order, matching the options panel tabs.
- **Right-click on each button** opens the panel and jumps directly to that list's tab.
- Drop an item to add it to the corresponding list.
- Keep button uses a heart-shaped box icon, distinct from Delete's red X and Sell's gold coin.

### Keep bags open at vendor close

- Vendor window close no longer closes the bag frame. Wraps `MerchantFrame:Hide` directly to set a suppress flag before the OnHide cascade runs (hooking `OnHide` is too late on PE-ElvUI's call order).

### Welcome popup

- First-run popup walks new users through optional Goblin Merchant macro creation and Interact With Target keybinding.
- Bottom "How it works" section explains the Delete / Sell / Keep system in simple terms with color-coded labels.
- Footer bar groups the "Don't show again" checkbox and "Open Settings" button into a visually distinct zone.
- Reopen anytime via `/del setup`.

### Tooltip system

- All option tooltips now wrap to multiple lines instead of stretching across the screen.
- Tooltips reviewed for accuracy and consistency. Each clearly states what gates the option and what protections are in place.

### Internal

- Shared `AfterDelay` timer helper replaces several throwaway-frame patterns. Single persistent frame with an OnUpdate that detaches when idle. No more frame leaks across vendor visits or pet summons.
- One-shot v3.10 schema migration on first login per character: old field names from earlier sell-rule designs are mapped into the new category structure, then deleted. Chat notice prints once per profile to remind the user to review settings.
- `BAGS_FULL_DELAY` constant hoisted out of the OnUpdate loop. Dead locals and unused color constants removed.
- Comment audit across both source files. Section headers describe their contents. Stale references to removed features purged.

### Slash commands

- `/del` opens the options panel
- `/del clean` dedupes Delete and Sell lists
- `/del sell` forces a sell pass (manual override, not gated by master)
- `/del setup` reopens the welcome popup
- `/autodelete` is an alias for `/del`

### Compatibility

- WoW 3.3.5a (Wrath of the Lich King)
- Tested on Project Ebonhold with PE-ElvUI fork
