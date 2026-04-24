# Changelog

All notable changes to this project will be documented in this file.

## [3.01] - 2026-04-24

### Fixed
- Blue/Rare and Epic items above the "Sell all items by iLvl" max were being auto-sold. Now all rarity checkboxes strictly obey the iLvl range when the range is enabled.
- Uncommon (green) items now also respect the iLvl range when it is enabled, matching the behavior of Rare and Epic.
- Raw-mode list edits on the Keep list now refresh the in-memory cached profile immediately, so scanner sees new entries without a /reload.

### Changed
- "Sell BoE weapons by iLvl" now covers the full set of weapon-slot items, matching Project Ebonhold's Hands/Weapon affix system: main-hand, off-hand, two-hand, shields, holdables (tomes/orbs), ranged (bows), ranged-right (guns, crossbows, wands), thrown, and relics (idols, librams, totems, sigils). All of these obey the BoE weapons iLvl range and count as weapons throughout the sell rules, not as separate misc items.

### Textures
- Replaced checkmark texture with a cleaner version. *Thanks Fish!*
- Added dedicated directional arrow textures (arrowdown/left/right, doublearrowdown/left/right) so pagination and spinner arrows render at identical sizes. Previously rotation was applied in code, which caused slight size inconsistencies.
- Pagination first/last buttons now use a pre-composed double-arrow texture instead of stacking two single arrows.

## [3.0] - 2026-04-24

Initial public release.

### Features
- Drag-and-drop Delete, Sell, and Keep lists with search and filtering
- Auto-sell at vendors by rarity with iLvl range support
- Auto-repair with optional guild bank funds
- Summon Scavenger companion automation at the Goblin Merchant
- Hide Greedy Scavenger chat and emote spam
- Auto-invite on whisper keyword with loot rule and raid conversion
- Per-character tracking (gold, items sold/deleted, repairs, inventory avg)
- Profile tools (copy from alts, import lists, clear lists, remove junk/sellable)
- Shift-click bag items to search lists
- ElvUI bag frame integration with quick Sell/Delete buttons
- ElvUI-style UI with matching fonts and textures
