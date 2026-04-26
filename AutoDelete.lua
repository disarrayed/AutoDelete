local ADDON_NAME = ...

-- cachedProfile is used throughout the file (Hide Greedy Spam filter, Auto-Invite
-- handlers, sell/delete logic). It MUST be declared before any function that
-- references it, otherwise Lua resolves `cachedProfile` to the global env (nil)
-- in those functions instead of this local. RefreshCachedProfile() below writes
-- to this same upvalue, so all closures see the latest value.
local cachedProfile = nil

-- Declared here (before any function that calls it) as a forward-assignable
-- local. The real body is assigned later once GetDB / GetActiveProfile are
-- defined. Do NOT redeclare with `local function` below - that shadows this.
local RefreshCachedProfile

-- ============================================================================
-- Shared Timer Helper
-- ============================================================================
-- 3.3.5 has no C_Timer. Several features need to "run something in N seconds":
-- DelayedSummon, the MerchantFrame.Hide flag-release, the post-login ElvUI
-- button setup, and so on.
--
-- The naive approach is CreateFrame("Frame") + SetScript("OnUpdate", ...) per
-- one-shot timer. WoW frames are never garbage-collected, so each call leaks a
-- frame for the rest of the session. Across hundreds of vendor visits or pet
-- summons this accumulates measurable garbage.
--
-- Instead: one persistent frame with an OnUpdate that walks a queue of pending
-- tasks. The OnUpdate detaches itself when the queue is empty so we pay zero
-- per-frame cost while idle. AfterDelay(seconds, fn) is the only API anyone
-- needs.
local timerQueue = {}  -- list of { fireAt = <GetTime> + delay, fn = <function> }
local timerFrame = CreateFrame("Frame")

local function PumpTimers(_, _)
	if #timerQueue == 0 then
		-- Nothing left; detach so this OnUpdate stops costing CPU until the
		-- next AfterDelay re-attaches it.
		timerFrame:SetScript("OnUpdate", nil)
		return
	end
	local now = GetTime()
	-- Walk in-place. Removing the entry shifts later items, so don't increment
	-- when we removed; otherwise advance.
	local i = 1
	while i <= #timerQueue do
		local t = timerQueue[i]
		if now >= t.fireAt then
			-- pcall so a buggy task can't break later tasks in the same frame.
			local ok, err = pcall(t.fn)
			if not ok then
				print("|cffff8000[AutoDelete]|r timer error: " .. tostring(err))
			end
			table.remove(timerQueue, i)
		else
			i = i + 1
		end
	end
end

local function AfterDelay(delaySeconds, fn)
	if type(fn) ~= "function" then return end
	tinsert(timerQueue, { fireAt = GetTime() + (delaySeconds or 0), fn = fn })
	-- Re-attach if we were idle. Setting the same script repeatedly is a no-op.
	timerFrame:SetScript("OnUpdate", PumpTimers)
end

-- ============================================================================
-- Database
-- ============================================================================

local function GetCharKey()
	local name = UnitName("player")
	local realm = GetRealmName and GetRealmName() or nil
	if not name then return nil end
	if realm and realm ~= "" then return name .. "-" .. realm end
	return name
end

local DEFAULT_PROFILE = {
	-- ============================================================
	-- Master switch
	-- ============================================================
	-- Gates the periodic delete/sell scanner, vendor auto-repair,
	-- vendor auto-sell, and the companion watcher (mount-aware
	-- dismiss/re-summon, stuck-detection, bag-full merchant summon).
	-- Auto-Invite and Hide Greedy Spam are deliberately INDEPENDENT
	-- of this switch - they run regardless.
	enabled = false,

	-- ============================================================
	-- Item lists (newline-delimited "item:<id>" strings)
	-- ============================================================
	-- Three mutually-exclusive lists. AddItemToList enforces this:
	-- adding an item to one list rejects the add if it's already on
	-- another. The Keep list always wins at scan time; nothing on it
	-- can be auto-sold or auto-deleted by any rule.
	listText      = "",   -- Delete list  (auto-destroyed every scan)
	sellListText  = "",   -- Sell list    (auto-sold at any vendor)
	whitelistText = "",   -- Keep list    (protected from all rules)

	-- ============================================================
	-- Periodic scan
	-- ============================================================
	scanInterval = 0.5,    -- seconds; floored at 0.5 in the scanner

	-- ============================================================
	-- Auto-Delete / Auto-Sell by quality (General tab, three rows)
	-- ============================================================
	-- These three run on every scan and are independent of the BoE
	-- Armor / BoP / BoE Weapons category sections below. They all
	-- skip quest items, items on the Keep list, and shirts/tabards.
	autoGray         = false,  -- Auto-Delete Junk   (gray quality, any item)
	autoDeleteCommon = false,  -- Auto-Delete Common (white quality, equippable gear only)
	autoSellGreens   = false,  -- Auto-Sell Greens   (green quality, equippable gear only)

	-- ============================================================
	-- Sell categories (Sell tab, three cards)
	-- ============================================================
	-- Each section is independent. An item only ever matches one
	-- category at scan time. Priority order: BoE Weapons > BoP >
	-- BoE Armor (so a BoE weapon never gets caught by BoE Armor's
	-- "all weapon slots excluded" rule because BoE Weapons fires
	-- first). Each section sells items whose iLvl is inside
	-- [Min, Max] AND whose rarity matches an enabled toggle.

	-- BoE Armor: BoE items NOT in WEAPON_SLOTS (i.e. armor and
	-- accessories). WEAPON_SLOTS covers everything Hand Affix
	-- Enchant can target on Project Ebonhold.
	boeArmorEnabled = false,
	boeArmorIlvlMin = 1,
	boeArmorIlvlMax = 199,
	boeArmorRare    = false,
	boeArmorEpic    = false,

	-- BoP: any Bind-on-Pickup gear (any slot, including weapons).
	bopEnabled = false,
	bopIlvlMin = 1,
	bopIlvlMax = 199,
	bopRare    = false,
	bopEpic    = false,

	-- BoE Weapons: BoE items in WEAPON_SLOTS (weapons, shields,
	-- holdables, ranged, thrown, relics). Takes priority over BoE
	-- Armor for items that match both.
	boeWeaponsEnabled = false,
	boeWeaponsIlvlMin = 1,
	boeWeaponsIlvlMax = 199,
	boeWeaponsRare    = false,
	boeWeaponsEpic    = false,

	-- ============================================================
	-- Companion management (Goblin tab)
	-- ============================================================
	-- summonScavenger is the master toggle for ALL companion
	-- features: it gates mount-aware dismiss/re-summon, the
	-- stuck-detection re-summon, the after-sell + after-close
	-- summons, AND the bag-full Goblin Merchant trigger. The
	-- master AutoDelete `enabled` flag also gates this feature
	-- group as a whole.
	summonScavenger            = false,
	summonAfterSell            = true,    -- summon scav after vendor sell completes
	summonAfterClose           = false,   -- summon scav after vendor window closes
	summonOnlyInCombat         = true,    -- gate ALL auto-summon paths on UnitAffectingCombat("player")
	summonMerchantWhenBagsFull = false,   -- summon Goblin Merchant when bags hit 0 free for 3s+

	-- ============================================================
	-- Vendor extras (Goblin tab)
	-- ============================================================
	-- Both fire at MERCHANT_SHOW. Gated by `enabled`.
	autoRepair             = false,
	autoRepairUseGuildBank = false,   -- prefer guild bank funds when available

	-- ============================================================
	-- Hide Greedy Scavenger spam (Goblin tab)
	-- ============================================================
	-- Suppresses the scavenger's chat lines AND chat bubbles.
	-- Independent of the master `enabled` toggle.
	hideGreedySpam = false,

	-- ============================================================
	-- Auto-Invite (AutoInv tab)
	-- ============================================================
	-- Independent of the master `enabled` toggle.
	-- autoInviteLootRule values: "freeforall" | "roundrobin"
	--                           | "group" | "needbeforegreed" | "master"
	autoInviteEnabled         = false,
	autoInviteKeywords        = "inv,invite",
	autoInviteApplyLootRule   = false,
	autoInviteLootRule        = "freeforall",
	autoInviteConvertToRaid   = false,    -- convert party→raid when 6th player joins
}

local function NewProfile(overrides)
	local p = {}
	for k, v in pairs(DEFAULT_PROFILE) do p[k] = v end
	if overrides then
		for k, v in pairs(overrides) do p[k] = v end
	end
	return p
end

local function MigrateDB(db)
	if db.profiles then return end
	db.profiles = {}
	db.chars = {}
	local charKey = GetCharKey() or "Default"
	db.profiles[charKey] = NewProfile({
		enabled = db.enabled and true or false,
		listText = db.listText or "",
	})
	db.chars[charKey] = charKey
end

local function EnsureProfileFields(p)
	-- Invert old dontSellBoEWeapons field into sellBoEWeapons.
	if p.dontSellBoEWeapons ~= nil then
		p.sellBoEWeapons = not p.dontSellBoEWeapons
		p.dontSellBoEWeapons = nil
	end
	-- Old profiles stored the weapon iLvl threshold in sellBoEWeaponMinIlvl
	-- as a floor. The range model renamed it to sellBoEWeaponMaxIlvl as the
	-- ceiling. Only migrate if the new field is still absent so legitimate
	-- range-min values on current profiles are preserved.
	if p.sellBoEWeaponMinIlvl ~= nil and p.sellBoEWeaponMaxIlvl == nil then
		p.sellBoEWeaponMaxIlvl = p.sellBoEWeaponMinIlvl
		p.sellBoEWeaponMinIlvl = nil
	end

	-- v3.02 schema migration: collapse the old split (sell filters + sell
	-- conditions) into category cards. Runs only once per profile thanks to
	-- the _v302Migrated flag. Detection: any of the old field names present.
	local hasOldFields = (p.sellJunk ~= nil) or (p.sellGreen ~= nil)
		or (p.sellBlue ~= nil) or (p.sellEpic ~= nil)
		or (p.sellBoE ~= nil) or (p.sellBoEWeapons ~= nil)
		or (p.sellIlvlEnabled ~= nil)
	if hasOldFields and not p._v302Migrated then
		-- Old global rarity toggles: Junk/Common become DELETE actions,
		-- Greens become a SELL action.
		-- Junk: existing autoGray field is the canonical Auto-Delete Junk
		-- toggle (was already wired). If a profile had sellJunk=true but
		-- autoGray was unset/false, prefer the user's intent.
		if p.sellJunk == true then p.autoGray = true end
		p.autoDeleteCommon = false                 -- old schema had no Common toggle
		p.autoSellGreens   = (p.sellGreen == true)

		-- Old sellBoE was a generic "BoE gear" flag with shared iLvl range
		-- (sellIlvlMin/Max if sellIlvlEnabled). Map it to BoE Armor.
		local hadIlvlRange = (p.sellIlvlEnabled == true)
		p.boeArmorEnabled = (p.sellBoE == true)
		p.boeArmorRare    = (p.sellBoE == true) and (p.sellBlue == true)
		p.boeArmorEpic    = (p.sellBoE == true) and (p.sellEpic == true)
		if hadIlvlRange and p.sellIlvlMin then
			p.boeArmorIlvlMin = p.sellIlvlMin
		end
		if hadIlvlRange and p.sellIlvlMax then
			p.boeArmorIlvlMax = p.sellIlvlMax
		end

		-- BoP didn't exist in the old schema as its own category. Default off.
		p.bopEnabled = false
		p.bopRare    = false
		p.bopEpic    = false

		-- BoE Weapons had its own toggle and iLvl range.
		p.boeWeaponsEnabled = (p.sellBoEWeapons == true)
		p.boeWeaponsRare    = (p.sellBoEWeapons == true) and (p.sellBlue == true)
		p.boeWeaponsEpic    = (p.sellBoEWeapons == true) and (p.sellEpic == true)
		if p.sellBoEWeaponMinIlvl then
			p.boeWeaponsIlvlMin = p.sellBoEWeaponMinIlvl
		end
		if p.sellBoEWeaponMaxIlvl then
			p.boeWeaponsIlvlMax = p.sellBoEWeaponMaxIlvl
		end

		-- Strip the old fields so they can't accidentally still be read.
		p.sellJunk = nil
		p.sellGreen = nil
		p.sellBlue = nil
		p.sellEpic = nil
		p.sellBoE = nil
		p.sellBoEWeapons = nil
		p.sellBoEWeaponMinIlvl = nil
		p.sellBoEWeaponMaxIlvl = nil
		p.sellIlvlEnabled = nil
		p.sellIlvlMin = nil
		p.sellIlvlMax = nil

		p._v302Migrated = true
		-- Flag that the chat notice is owed for this profile. The notice
		-- itself is printed once at PLAYER_LOGIN; this just marks it.
		_G._AutoDelete_NeedMigrationNotice = true
	end

	for k, v in pairs(DEFAULT_PROFILE) do
		if p[k] == nil then p[k] = v end
	end
end

local function GetDB()
	_G.AutoDeleteDB = _G.AutoDeleteDB or {}
	local db = _G.AutoDeleteDB
	if not db.profiles then MigrateDB(db) end
	db.profiles = db.profiles or {}
	db.chars = db.chars or {}
	local charKey = GetCharKey() or "Default"
	local profileKey = db.chars[charKey] or charKey
	if not db.profiles[profileKey] then
		db.profiles[profileKey] = NewProfile()
	end
	EnsureProfileFields(db.profiles[profileKey])
	if not db.chars[charKey] then db.chars[charKey] = profileKey end
	return db
end

local function GetActiveProfile(db)
	local charKey = GetCharKey() or "Default"
	local profileKey = (db and db.chars and db.chars[charKey]) or charKey
	if not db.profiles[profileKey] then
		db.profiles[profileKey] = NewProfile()
	end
	EnsureProfileFields(db.profiles[profileKey])
	return db.profiles[profileKey], profileKey, charKey
end

-- ============================================================================
-- Tracking Stats (per-character, saved in AutoDeleteStatsDB)
-- ============================================================================
-- Lifetime stats persist across sessions. Session stats reset on /reload or
-- login. Both are per-character via the SavedVariablesPerCharacter TOC line.

local DEFAULT_STATS = {
	-- Lifetime totals (persisted)
	goldEarned = 0,           -- copper total from selling
	itemsSold = 0,            -- count of sell actions
	itemsDeleted = 0,         -- count of delete actions
	repairs = 0,              -- count of repair events
	repairSpend = 0,          -- copper total spent on repairs
	inventoryWorthTotal = 0,  -- running sum of inventory worth samples
	inventoryWorthCount = 0,  -- number of samples (for avg = total / count)
}

-- Session counters (in-memory only, not saved). Reset on login/reload.
local sessionStats = {
	goldEarned = 0,
	itemsSold = 0,
	itemsDeleted = 0,
	repairs = 0,
	repairSpend = 0,
	inventoryWorthTotal = 0,
	inventoryWorthCount = 0,
}

local function EnsureStatsDB()
	if AutoDeleteStatsDB == nil then AutoDeleteStatsDB = {} end
	for k, v in pairs(DEFAULT_STATS) do
		if type(AutoDeleteStatsDB[k]) ~= "number" then
			AutoDeleteStatsDB[k] = v
		end
	end
	return AutoDeleteStatsDB
end

local function GetStats()
	return EnsureStatsDB()
end

-- Record lifetime + session increments for any of the tracked fields.
local function BumpStat(key, amount)
	if not key or not amount or amount == 0 then return end
	local s = EnsureStatsDB()
	s[key] = (s[key] or 0) + amount
	sessionStats[key] = (sessionStats[key] or 0) + amount
end

-- Reset ALL tracking stats (lifetime + session). Fires from the Tracking tab
-- Reset button.
local function ResetAllStats()
	local s = EnsureStatsDB()
	for k, v in pairs(DEFAULT_STATS) do
		s[k] = v
	end
	for k, v in pairs(DEFAULT_STATS) do
		sessionStats[k] = v
	end
end

-- Expose to Options.lua via a shared namespace.
_G.AutoDelete_Stats = {
	GetLifetime = GetStats,
	GetSession = function() return sessionStats end,
	Reset = ResetAllStats,
	-- Format helpers so the UI doesn't have to reimplement these.
	FormatMoney = function(copper)
		copper = tonumber(copper) or 0
		if copper <= 0 then return "0c" end
		local gold = math.floor(copper / 10000)
		local silver = math.floor((copper % 10000) / 100)
		local cop = copper % 100
		local parts = {}
		if gold > 0 then table.insert(parts, gold .. "g") end
		if silver > 0 then table.insert(parts, silver .. "s") end
		if cop > 0 or #parts == 0 then table.insert(parts, cop .. "c") end
		return table.concat(parts, " ")
	end,
	-- Insert thousand separators: 14532 → "14,532"
	FormatNumber = function(n)
		n = tonumber(n) or 0
		local s = tostring(math.floor(n))
		-- Repeatedly insert commas from the right until no more groups of 3.
		local k
		while true do
			s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
			if k == 0 then break end
		end
		return s
	end,
}

-- ============================================================================
-- String Helpers
-- ============================================================================

local function Trim(s)
	-- Parens around the whole expression truncate gsub's multi-return (string
	-- plus substitution count) down to just the string. Without this, calls
	-- like `table.insert(t, Trim(x))` silently pass the count as a third arg
	-- and Lua treats the result as the 3-arg form of table.insert.
	return (string.gsub(string.gsub(tostring(s or ""), "^%s+", ""), "%s+$", ""))
end

local function Normalize(s) return string.lower(Trim(s)) end

local function GetItemIDFromLink(link)
	if not link then return nil end
	return tonumber(string.match(link, "item:(%d+)"))
end

local function HasExactLine(listText, line)
	line = Trim(line)
	if line == "" then return true end
	for l in string.gmatch(listText or "", "[^\r\n]+") do
		if Trim(l) == line then return true end
	end
	return false
end

local function AddLineIfMissing(listText, line)
	line = Trim(line)
	if line == "" then return listText or "" end
	if HasExactLine(listText, line) then return listText or "" end
	local t = tostring(listText or "")
	if t ~= "" and string.sub(t, -1) ~= "\n" then t = t .. "\n" end
	return t .. line .. "\n"
end

-- ============================================================================
-- Item Set Builders
-- ============================================================================
-- BuildWantedSets parses a Delete or Sell list's text and returns two tables:
-- one keyed by item id, one keyed by lowercased+trimmed item name. The scan
-- loop uses these for O(1) "is this item on the list" lookups.

local function BuildWantedSets(listText)
	local nameSet, idSet = {}, {}
	for line in string.gmatch(listText or "", "[^\r\n]+") do
		local raw = Trim(line)
		-- Strip comments
		raw = string.gsub(raw, "%s*#.*$", "")
		raw = Trim(raw)
		-- Match item:ID (lenient - don't require end anchor)
		local itemId = tonumber(string.match(raw, "^item:(%d+)"))
		if itemId then
			idSet[itemId] = true
		elseif raw ~= "" then
			nameSet[Normalize(raw)] = true
		end
	end
	return nameSet, idSet
end

local function IsWhitelisted(profile, itemId, itemName)
	local wlText = profile.whitelistText or ""
	if wlText == "" then return false end
	for line in string.gmatch(wlText, "[^\r\n]+") do
		local raw = Trim(line)
		raw = string.gsub(raw, "%s*#.*$", "")
		raw = Trim(raw)
		local wlId = tonumber(string.match(raw, "^item:(%d+)"))
		if wlId and itemId and wlId == itemId then return true end
		if raw ~= "" and itemName and Normalize(raw) == Normalize(itemName) then return true end
	end
	return false
end

-- ============================================================================
-- Add Item to List (used by ElvUI buttons and Options panel)
-- ============================================================================

-- Check if `line` already exists on either of the OTHER two lists
-- (delete/sell/whitelist). Returns (hasConflict, conflictingListKey).
local function FindCrossListConflict(profile, targetKey, line)
	local otherKeys
	if targetKey == "listText" then
		otherKeys = { "sellListText", "whitelistText" }
	elseif targetKey == "sellListText" then
		otherKeys = { "listText", "whitelistText" }
	elseif targetKey == "whitelistText" then
		otherKeys = { "listText", "sellListText" }
	else
		return false, nil
	end
	for _, k in ipairs(otherKeys) do
		if HasExactLine(profile[k] or "", line) then return true, k end
	end
	return false, nil
end

local function ListLabelForKey(key)
	if key == "listText" then return "Delete" end
	if key == "sellListText" then return "Sell" end
	if key == "whitelistText" then return "Keep" end
	return key
end

local function AddItemToList(listKey, itemId)
	local db = GetDB()
	local profile = GetActiveProfile(db)
	local line = "item:" .. tostring(itemId)
	local itemName = GetItemInfo(itemId) or ("Item " .. itemId)

	if HasExactLine(profile[listKey], line) then
		print("|cffff8000[AutoDelete]|r: " .. itemName .. " is already in the list")
		return false
	end

	-- Refuse to add if item is on another list; user must remove there first.
	local hasConflict, conflictKey = FindCrossListConflict(profile, listKey, line)
	if hasConflict then
		print("|cffff4444[AutoDelete]|r: Cannot add " .. itemName
			.. " to " .. ListLabelForKey(listKey)
			.. " - already on the " .. ListLabelForKey(conflictKey)
			.. " list. Remove it from there first.")
		return false
	end

	profile[listKey] = AddLineIfMissing(profile[listKey] or "", line)
	GetItemInfo("item:" .. itemId)
	local label
	if listKey == "sellListText" then label = "sell"
	elseif listKey == "whitelistText" then label = "keep"
	else label = "delete" end
	print("|cffff8000[AutoDelete]|r: Added " .. itemName .. " to " .. label .. " list")
	return true
end

local function HandleItemDrop(listKey)
	local cursorType, itemID, itemLink = GetCursorInfo()
	if cursorType ~= "item" then ClearCursor() return end
	local id = (type(itemID) == "number") and itemID or GetItemIDFromLink(itemLink)
	ClearCursor()
	if not id then return end
	if AddItemToList(listKey, id) then
		local panel = _G.AutoDeleteOptionsPanel
		if panel and panel._built and panel:IsVisible() and not (panel._rawBoxHolder and panel._rawBoxHolder:IsShown()) then
			panel:Refresh()
		end
	end
end

-- Global functions for ElvUI buttons - always target the correct list
_G.AutoDelete_AddToDeleteList = function() HandleItemDrop("listText") end
_G.AutoDelete_AddToSellList = function() HandleItemDrop("sellListText") end
_G.AutoDelete_AddToKeepList = function() HandleItemDrop("whitelistText") end

-- Opens the AutoDelete options panel and switches the Delete/Sell/Keep
-- list tab to the requested mode. Used by the ElvUI bag buttons so a
-- right-click on Delete jumps straight to the Delete list, etc.
-- Accepts: "delete", "sell", "whitelist".
_G.AutoDelete_OpenPanelToList = function(mode)
	local panel = _G.AutoDeleteOptionsPanel
	if not panel then return end
	if not panel:IsShown() then panel:Show() end
	-- The Options.lua panel exposes a SwitchListMode helper for this.
	if panel.SwitchListMode then panel:SwitchListMode(mode) end
end

-- ============================================================================
-- Manual Sell Tracking (hooksecurefunc UseContainerItem + bag snapshot)
-- ============================================================================
-- Blizzard's merchant UI sells an item by calling UseContainerItem(bag, slot)
-- when you right-click a bag item while the merchant window is open. We track
-- those manual sells so the gold/items session counters work.
--
-- IMPORTANT: We use hooksecurefunc, NOT a global override. Replacing
-- UseContainerItem globally (UseContainerItem = TrackedUseContainerItem)
-- breaks the secure-action call path on 3.3.5 because UseContainerItem is
-- protected for items that trigger spells/casts (Hearthstone, potions,
-- mounts, scrolls, food, anything castable). Blizzard's secure dispatch
-- silently rejects calls to a non-Blizzard function, so right-click on those
-- items stops working entirely. hooksecurefunc preserves the original.
--
-- Implementation: hooksecurefunc fires AFTER Blizzard's handler, by which
-- time the bag slot has already been emptied or shifted. So we can't read
-- the item from the slot post-call. Instead we keep a snapshot of bag
-- contents (link + count per slot) that we refresh on:
--   * MERCHANT_SHOW (initial full snapshot when vendor opens)
--   * After every hooked UseContainerItem call (refresh just that slot)
-- When the hook fires, we look up (bag, slot) in the snapshot to know what
-- was just sold.
--
-- The autoDeleteSelling flag keeps our own SellItems() calls from being
-- double-counted - those record the stat directly, not via this hook.

local autoDeleteSelling = false
local merchantBagSnapshot = {}

local function SnapshotAllBags()
	merchantBagSnapshot = {}
	for bag = 0, 4 do
		local n = GetContainerNumSlots(bag) or 0
		for slot = 1, n do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local _, count = GetContainerItemInfo(bag, slot)
				merchantBagSnapshot[bag .. ":" .. slot] = {
					link = link, count = count or 1,
				}
			end
		end
	end
end

local function RefreshSnapshotSlot(bag, slot)
	local key = bag .. ":" .. slot
	local link = GetContainerItemLink(bag, slot)
	if link then
		local _, count = GetContainerItemInfo(bag, slot)
		merchantBagSnapshot[key] = { link = link, count = count or 1 }
	else
		merchantBagSnapshot[key] = nil
	end
end

hooksecurefunc("UseContainerItem", function(bag, slot)
	-- Skip our own SellItems() path - it records BumpStat directly.
	if autoDeleteSelling then return end
	if not bag or not slot then return end
	if not (MerchantFrame and MerchantFrame:IsShown()) then return end

	local key = bag .. ":" .. slot
	local snap = merchantBagSnapshot[key]
	if snap and snap.link then
		local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(snap.link)
		if sellPrice and sellPrice > 0 then
			local copper = sellPrice * (snap.count or 1)
			BumpStat("itemsSold", 1)
			BumpStat("goldEarned", copper)
		end
	end

	-- Refresh the snapshot for this slot after the sell completes. Use a
	-- short delay so the bag has time to update.
	AfterDelay(0.1, function() RefreshSnapshotSlot(bag, slot) end)
end)

-- ============================================================================
-- Profile Management (copy settings from another character)
-- ============================================================================
-- Every character has its own profile keyed in db.profiles. The Profiles tab
-- in the UI exposes a "copy from another character" action: pick a source
-- character, confirm, and their full profile (lists + toggles + everything)
-- gets deep-copied onto the current character's profile key.
--
-- This is intentionally NOT a named-profile system - just a one-way copy
-- across alts. Tracking stats are NOT copied (those are per-character data,
-- not settings).

-- Deep copy a table (handles nested tables). Values that aren't tables are
-- copied by value - functions, userdata, etc. get reference-copied but we
-- don't store those in profiles anyway.
local function DeepCopyTable(src)
	if type(src) ~= "table" then return src end
	local out = {}
	for k, v in pairs(src) do
		if type(v) == "table" then
			out[k] = DeepCopyTable(v)
		else
			out[k] = v
		end
	end
	return out
end

-- Returns an array of character names that have profiles in the DB,
-- EXCLUDING the current character. Sorted alphabetically for stable UI.
local function GetOtherCharacterNames()
	local db = GetDB()
	local currentKey = GetCharKey() or "Default"
	local out = {}
	if db and db.profiles then
		for name in pairs(db.profiles) do
			if name ~= currentKey then
				table.insert(out, name)
			end
		end
	end
	table.sort(out)
	return out
end

-- Returns ALL character profile names (current included), alphabetically sorted.
-- Used by the Profiles tab dropdown which shows every profile so the user can
-- even delete the current character's (which then re-initializes to defaults).
local function GetAllCharacterNames()
	local db = GetDB()
	local out = {}
	if db and db.profiles then
		for name in pairs(db.profiles) do
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

-- Copy the full profile from `sourceCharKey` onto the current character.
-- Overwrites everything in the current profile. Returns true on success,
-- false + reason string on failure.
local function CopyProfileFromCharacter(sourceCharKey)
	if not sourceCharKey or sourceCharKey == "" then
		return false, "no source specified"
	end
	local db = GetDB()
	local currentKey = GetCharKey() or "Default"

	if sourceCharKey == currentKey then
		return false, "source is current character"
	end
	if not db.profiles[sourceCharKey] then
		return false, "source profile not found"
	end

	-- Deep copy so no shared table references between characters.
	local copied = DeepCopyTable(db.profiles[sourceCharKey])
	db.profiles[currentKey] = copied
	db.chars[currentKey] = currentKey

	-- Keep migrations applied in case the source had pre-migration fields.
	EnsureProfileFields(db.profiles[currentKey])

	-- Refresh the cached profile immediately so active toggles reflect the
	-- new data without waiting for a bag event.
	if RefreshCachedProfile then RefreshCachedProfile() end
	return true
end

-- Delete a character's saved profile. If the target is the current character,
-- their profile is cleared and re-initialized to defaults on next access.
-- Otherwise the entry is removed entirely from the DB.
local function DeleteProfile(targetCharKey)
	if not targetCharKey or targetCharKey == "" then
		return false, "no target specified"
	end
	local db = GetDB()
	local currentKey = GetCharKey() or "Default"

	if not db.profiles[targetCharKey] then
		return false, "profile not found"
	end

	if targetCharKey == currentKey then
		-- Current character: reset to defaults (we can't remove the entry
		-- entirely because the addon immediately re-creates it on next access).
		db.profiles[currentKey] = NewProfile()
		db.chars[currentKey] = currentKey
	else
		-- Other character: fully remove.
		db.profiles[targetCharKey] = nil
		if db.chars then
			-- Also clear any chars-alias pointing at the deleted profile.
			for char, key in pairs(db.chars) do
				if key == targetCharKey then db.chars[char] = nil end
			end
		end
	end

	if RefreshCachedProfile then RefreshCachedProfile() end
	return true
end

-- Reset the current character's profile to all defaults. Does not touch other
-- characters' profiles.
local function ResetCurrentProfile()
	local db = GetDB()
	local currentKey = GetCharKey() or "Default"
	db.profiles[currentKey] = NewProfile()
	db.chars[currentKey] = currentKey
	if RefreshCachedProfile then RefreshCachedProfile() end
	return true
end

-- Clear one list or all three lists on the current character's profile.
-- `target` is "Delete" / "Sell" / "Keep" / "All". Returns true, cleared-count
-- on success, or false, reason on failure.
local function ClearListOnCurrent(target)
	local db = GetDB()
	local profile = GetActiveProfile(db)
	if not profile then return false, "no active profile" end

	local function CountEntries(listText)
		local n = 0
		for line in string.gmatch(listText or "", "[^\r\n]+") do
			local trimmed = Trim(line)
			if trimmed ~= "" and not string.match(trimmed, "^#") then n = n + 1 end
		end
		return n
	end

	local clearedCount = 0
	if target == "Delete" then
		clearedCount = CountEntries(profile.listText)
		profile.listText = ""
	elseif target == "Sell" then
		clearedCount = CountEntries(profile.sellListText)
		profile.sellListText = ""
	elseif target == "Keep" then
		clearedCount = CountEntries(profile.whitelistText)
		profile.whitelistText = ""
	elseif target == "All" then
		clearedCount = CountEntries(profile.listText)
			+ CountEntries(profile.sellListText)
			+ CountEntries(profile.whitelistText)
		profile.listText = ""
		profile.sellListText = ""
		profile.whitelistText = ""
	else
		return false, "invalid target"
	end

	if RefreshCachedProfile then RefreshCachedProfile() end
	return true, clearedCount
end

-- Scan the Delete and Sell lists. For each entry that resolves to a real
-- item (item:ID), check its quality via GetItemInfo; if quality == 0 (gray
-- junk), remove that entry from the list. Entries that can't be resolved
-- (cache miss, or plain-name entries we can't identify) are preserved.
-- Returns true, { deleteRemoved=N, sellRemoved=N, uncached=N }.
local function RemoveJunkFromLists()
	local db = GetDB()
	local profile = GetActiveProfile(db)
	if not profile then return false, "no active profile" end

	local uncachedCount = 0

	local function CleanList(listText)
		local kept = {}
		local removed = 0
		for line in string.gmatch(listText or "", "[^\r\n]+") do
			local trimmed = Trim(line)
			local keep = true
			if trimmed ~= "" and not string.match(trimmed, "^#") then
				-- Try to pull an item id from "item:NNN" form
				local id = tonumber(string.match(trimmed, "^item:(%d+)"))
				if id then
					local name, _, quality = GetItemInfo("item:" .. id)
					if name then
						-- Got cached info. Quality 0 = gray/junk.
						if quality == 0 then
							keep = false
							removed = removed + 1
						end
					else
						-- Item not in client cache. Skip cleanup for this entry
						-- rather than guessing, and count it so we can tell the user.
						uncachedCount = uncachedCount + 1
					end
				end
				-- Plain-name entries (no item:ID) we can't identify reliably
				-- without a bag scan; leave them alone.
			end
			if keep then table.insert(kept, trimmed) end
		end
		local rebuilt = table.concat(kept, "\n")
		if #kept > 0 then rebuilt = rebuilt .. "\n" end
		return rebuilt, removed
	end

	local newDelete, delRemoved   = CleanList(profile.listText)
	local newSell,   sellRemoved  = CleanList(profile.sellListText)
	profile.listText     = newDelete
	profile.sellListText = newSell

	if RefreshCachedProfile then RefreshCachedProfile() end
	return true, {
		deleteRemoved = delRemoved,
		sellRemoved   = sellRemoved,
		uncached      = uncachedCount,
	}
end

-- Scan ONLY the Delete list. Remove entries whose item has a vendor sell
-- price > 0 (i.e. items that could be sold instead of deleted). Entries
-- that can't be resolved (cache miss, or plain-name entries) are preserved.
-- Returns true, { removed=N, uncached=N } on success.
local function RemoveSellableFromDeleteList()
	local db = GetDB()
	local profile = GetActiveProfile(db)
	if not profile then return false, "no active profile" end

	local uncachedCount = 0
	local kept = {}
	local removed = 0
	for line in string.gmatch(profile.listText or "", "[^\r\n]+") do
		local trimmed = Trim(line)
		local keep = true
		if trimmed ~= "" and not string.match(trimmed, "^#") then
			local id = tonumber(string.match(trimmed, "^item:(%d+)"))
			if id then
				-- GetItemInfo returns: name, link, quality, iLevel, reqLevel,
				-- type, subType, stackCount, equipLoc, texture, sellPrice
				local name, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo("item:" .. id)
				if name then
					if sellPrice and sellPrice > 0 then
						keep = false
						removed = removed + 1
					end
				else
					uncachedCount = uncachedCount + 1
				end
			end
		end
		if keep then table.insert(kept, trimmed) end
	end

	local rebuilt = table.concat(kept, "\n")
	if #kept > 0 then rebuilt = rebuilt .. "\n" end
	profile.listText = rebuilt

	if RefreshCachedProfile then RefreshCachedProfile() end
	return true, { removed = removed, uncached = uncachedCount }
end

-- Exposed API for Options.lua.
_G.AutoDelete_Profiles = {
	GetOtherCharacters = GetOtherCharacterNames,
	GetAllCharacters = GetAllCharacterNames,
	GetCurrentCharacter = function() return GetCharKey() or "Default" end,
	CopyFrom = CopyProfileFromCharacter,
	DeleteProfile = DeleteProfile,
	ResetCurrent = ResetCurrentProfile,
	ClearList = ClearListOnCurrent,
	RemoveJunk = RemoveJunkFromLists,
	RemoveSellableFromDelete = RemoveSellableFromDeleteList,
}

-- ============================================================================
-- Deletion Scanner
-- ============================================================================
-- Periodic + event-driven scanner that walks the player's bags and either
-- deletes (Delete list, Auto-Delete Junk, Auto-Delete Common) or - when at
-- a vendor - sells (handled by SellItems below). Quest items are hard-
-- exempt: they short-circuit before any rule evaluation.

local nextScanAt = 0
local periodicInterval = 2.0
local nextPeriodicAt = 0
local scanRequested = false

local function RequestScan() scanRequested = true end

local DELETE_BATCH_SIZE = 20

-- Cosmetic slots (shirts + tabards). Items in these slots are NEVER touched
-- by the automatic rules (Auto-Delete Junk, Auto-Delete Common, Auto-Sell
-- Greens, the BoE/BoP/BoE Weapons sell categories). They must be explicitly
-- added to the Delete or Sell list to be removed. Used by DeleteItems.
local COSMETIC_SLOTS = {
	INVTYPE_BODY = true,    -- shirts
	INVTYPE_TABARD = true,  -- tabards
}
local function IsCosmeticSlot(itemLink)
	if not itemLink then return false end
	local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
	return equipLoc and COSMETIC_SLOTS[equipLoc] or false
end

local function DeleteItems()
	if CursorHasItem() then return end
	local db = GetDB()
	local profile = GetActiveProfile(db)
	if not profile.enabled then
		if _G.AutoDelete_DebugSell then
			-- Print at most once per scan attempt to avoid spam.
			if not _G._AutoDelete_DebugDelGateLogged then
				print("|cffff8000[AutoDelete DEBUG]|r delete scan SKIPPED: master Enable is OFF (profile.enabled=false). Turn it on in the General tab.")
				_G._AutoDelete_DebugDelGateLogged = true
			end
		end
		return
	end
	_G._AutoDelete_DebugDelGateLogged = false

	local wantedNames, wantedIDs = BuildWantedSets(profile.listText)
	local hasWanted = next(wantedNames) or next(wantedIDs)
	local doGray = profile.autoGray
	local doCommon = profile.autoDeleteCommon

	if not hasWanted and not doGray and not doCommon then
		if _G.AutoDelete_DebugSell and not _G._AutoDelete_DebugDelEmptyLogged then
			print("|cffff8000[AutoDelete DEBUG]|r delete scan: no work - Delete list empty AND Auto-Delete Junk/Common both off.")
			_G._AutoDelete_DebugDelEmptyLogged = true
		end
		return
	end
	_G._AutoDelete_DebugDelEmptyLogged = false

	local deleted = 0

	for bag = 0, 4 do
		for slot = 1, GetContainerNumSlots(bag) do
			if deleted >= DELETE_BATCH_SIZE then return end
			local _, _, locked, _, _, _, itemLink = GetContainerItemInfo(bag, slot)
			if itemLink and not locked then
				-- 6th return = itemType. Quest items (itemType "Quest") are
				-- normally protected from auto-rules - but the Delete list is
				-- explicit user intent and overrides quest protection. Auto
				-- rules (autoGray, autoDeleteCommon) still respect it.
				local itemName, _, itemQuality, _, _, itemClass = GetItemInfo(itemLink)
				local isQuestItem = (itemClass == "Quest")
				local itemId = GetItemIDFromLink(itemLink)
				local shouldDelete = false
				local onDeleteList = false

				-- Check delete list FIRST. If listed, user wants it gone
				-- regardless of quest type.
				if hasWanted then
					if itemId and wantedIDs[itemId] then onDeleteList = true end
					if not onDeleteList and itemName and wantedNames[Normalize(itemName)] then onDeleteList = true end
				end

				if onDeleteList then
					shouldDelete = true
				elseif not isQuestItem then
					-- Auto rules: only run when item is NOT on Delete list AND
					-- NOT a quest item. Quest protection still applies here.

					-- Check gray auto-delete (quality 0 = Poor/gray).
					-- Shirts and tabards are always protected from auto-gray even
					-- if they somehow came through as gray quality. Put them on
					-- the Delete list explicitly if you want them gone.
					if doGray and itemQuality and itemQuality == 0
						and not IsCosmeticSlot(itemLink) then
						shouldDelete = true
					end

					-- Check Common (white) auto-delete. Only deletes equippable
					-- gear so reagents/consumables/keys are safe. Cosmetic slots
					-- (shirts/tabards) are also protected.
					if not shouldDelete and doCommon and itemQuality and itemQuality == 1
						and not IsCosmeticSlot(itemLink) then
						-- Only equippable gear (must have an equipSlot).
						local _, _, _, _, _, _, _, _, equipSlot = GetItemInfo(itemLink)
						if equipSlot and equipSlot ~= "" and equipSlot ~= "INVTYPE_BAG" then
							shouldDelete = true
						end
					end
				end

				-- Execute the delete. Keep list always overrides - even Delete
				-- list entries can't bypass it (Keep is the safety net of
				-- last resort).
				if shouldDelete and not IsWhitelisted(profile, itemId, itemName) then
					if _G.AutoDelete_DebugSell then
						local reason = onDeleteList and "DeleteList" or "auto"
						local questNote = (onDeleteList and isQuestItem) and " [QUEST ITEM, overridden by Delete list]" or ""
						print(string.format(
							"|cffff8000[AutoDelete DEBUG]|r DELETING: %s (id=%s) | quality=%s | reason=%s%s",
							tostring(itemName), tostring(itemId), tostring(itemQuality), reason, questNote
						))
					end
					ClearCursor()
					PickupContainerItem(bag, slot)
					if CursorHasItem() then DeleteCursorItem(); ClearCursor() end
					deleted = deleted + 1
					BumpStat("itemsDeleted", 1)
				elseif shouldDelete and _G.AutoDelete_DebugSell then
					-- Matched a delete rule but the Keep list overrode it.
					print(string.format(
						"|cffff8000[AutoDelete DEBUG]|r delete BLOCKED by Keep list: %s (id=%s)",
						tostring(itemName), tostring(itemId)
					))
				end
			end
		end
	end
end

-- ============================================================================
-- Sell Logic
-- ============================================================================
-- SellItems scans bags at a vendor and sells items matching the rules.
-- Called from MERCHANT_SHOW (gated by master Enable), from the periodic
-- scanner while a vendor window is open, and from /del sell (manual,
-- ungated). The decision chain is documented inline at the top of the
-- per-slot loop.
--
-- Two slot tables drive what's eligible:
--   GEAR_SLOTS    = every equippable slot the rules can act on
--   WEAPON_SLOTS  = the subset that counts as a "weapon" for BoE Weapons
--                   (everything Hand-Affix-Enchant targets on PE)

local GEAR_SLOTS = {
	INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true,
	INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
	INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
	INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true,
	INVTYPE_ROBE = true, INVTYPE_WAIST = true, INVTYPE_LEGS = true,
	INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
	INVTYPE_CLOAK = true, INVTYPE_SHIELD = true,
	-- Accessories: rings, necks, trinkets, held off-hands, relics.
	-- INVTYPE_BODY (shirts), INVTYPE_TABARD, INVTYPE_BAG, INVTYPE_AMMO,
	-- and INVTYPE_QUIVER are DELIBERATELY excluded - they're either
	-- cosmetic or non-gear and should never be auto-sold by category
	-- rules. The Delete and Sell lists can still touch them via explicit
	-- entries (which bypass these filters).
	INVTYPE_FINGER = true, INVTYPE_NECK = true, INVTYPE_TRINKET = true,
	INVTYPE_HOLDABLE = true, INVTYPE_RELIC = true,
}

-- "Weapon" for the BoE weapons iLvl range covers anything a Hands/Weapon
-- affix can be applied to on PE: main-hand, off-hand, two-handers, shields,
-- off-hand holdables (tomes, orbs), ranged (bows), ranged-right (guns,
-- crossbows, wands), thrown, and relics (idols, librams, totems, sigils).
local WEAPON_SLOTS = {
	INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true,
	INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
	INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
	INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_RELIC = true,
}

-- Hidden tooltip used to read "Binds when equipped" text from bag items.
-- 3.3.5 has no API to query bind type directly, so we scan the actual
-- tooltip lines.
--
-- Important quirk: setting the owner to UIParent with ANCHOR_NONE works on
-- a vanilla client but on some setups (notably PE-ElvUI) SetBagItem leaves
-- the tooltip with 0 lines until the tooltip is actually shown. The fix is
-- to give it a real off-screen owner frame and force a Show/Hide cycle
-- around the read so the engine populates lines synchronously.
local boeTipOwner = CreateFrame("Frame", nil, UIParent)
boeTipOwner:SetSize(1, 1)
boeTipOwner:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
boeTipOwner:Hide()  -- never visible; just an owner anchor

local boeTip = CreateFrame("GameTooltip", "AutoDelete_BoETip", UIParent, "GameTooltipTemplate")
boeTip:SetClampedToScreen(false)

local function IsBindOnEquip(bag, slot)
	boeTip:Hide()
	boeTip:SetOwner(boeTipOwner, "ANCHOR_NONE")
	boeTip:ClearLines()
	boeTip:SetBagItem(bag, slot)
	-- Force population on environments where SetBagItem alone leaves
	-- NumLines == 0 until the tooltip is shown.
	boeTip:Show()
	local n = boeTip:NumLines()

	local foundBoE = false
	local debug = _G.AutoDelete_DebugSell
	local lines = debug and {} or nil
	for i = 2, n do
		local text = _G["AutoDelete_BoETipTextLeft" .. i]
		if text then
			local line = text:GetText()
			if debug and line then
				table.insert(lines, "  ["..i.."] "..line)
			end
			if line and string.find(line, "Binds when equipped") then
				foundBoE = true
				if not debug then
					boeTip:Hide()
					return true
				end
			end
		end
	end
	if debug then
		print("|cffff8000[AutoDelete DEBUG]|r tooltip scan ("..n.." lines, foundBoE="..tostring(foundBoE).."):")
		for _, l in ipairs(lines) do print(l) end
	end
	boeTip:Hide()
	return foundBoE
end

-- Merchant name tracking for Greedy Scavenger summon
local lastMerchantName = nil

-- Copper → "Xg Ys Zc" string. Defined before functions that use it.
local function FormatMoney(totalCopper)
	local gold = math.floor(totalCopper / 10000)
	local silver = math.floor((totalCopper % 10000) / 100)
	local copper = totalCopper % 100
	local money = ""
	if gold > 0 then money = money .. gold .. "g " end
	if silver > 0 then money = money .. silver .. "s " end
	if copper > 0 then money = money .. copper .. "c" end
	return money
end

-- Creature IDs for the PE companions we care about. These are the canonical
-- identifiers Blizzard's GetCompanionInfo returns. Caching them lets us
-- look up by ID instead of a fragile name-string-match. We discover the IDs
-- on first use (the user must own the companion for it to appear in the
-- companion list, so we can't hardcode the ID here without risk of staleness
-- on future server changes).
local SCAVENGER_CREATURE_ID = nil  -- discovered on first lookup
local MERCHANT_CREATURE_ID  = nil  -- discovered on first lookup

-- Find a companion by name and cache its creature ID for future lookups.
-- Returns: (index, isSummoned, creatureID) or (nil, false, nil)
local function FindCompanionByName(name)
	if not name or name == "" then return nil, false, nil end
	local numCritters = GetNumCompanions("CRITTER") or 0
	local needle = string.lower(name)
	for i = 1, numCritters do
		local cId, cName, _, _, summoned = GetCompanionInfo("CRITTER", i)
		if cName and string.find(string.lower(cName), needle) then
			return i, (summoned == 1 or summoned == true), cId
		end
	end
	return nil, false, nil
end

-- ID-first companion lookup. If the cached ID isn't found (rare: server
-- reshuffled companion list), falls back to name search and re-caches.
local function FindCompanionById(creatureId, fallbackName)
	if not creatureId then
		return FindCompanionByName(fallbackName)
	end
	local numCritters = GetNumCompanions("CRITTER") or 0
	for i = 1, numCritters do
		local cId, _, _, _, summoned = GetCompanionInfo("CRITTER", i)
		if cId == creatureId then
			return i, (summoned == 1 or summoned == true), cId
		end
	end
	-- ID not found - re-resolve from name. This also re-caches the ID.
	return FindCompanionByName(fallbackName)
end

local function SummonGreedyScavenger(force)
	local idx, isUp, cId = FindCompanionById(SCAVENGER_CREATURE_ID, "greedy scavenger")
	if cId then SCAVENGER_CREATURE_ID = cId end  -- cache for next time
	if not idx then return end  -- player doesn't own it
	-- Idempotent: already summoned, don't toggle off and re-call.
	-- Skipped when force=true (used by distance-based stuck detection where
	-- we just dismissed the pet and need to re-summon at the new position
	-- regardless of what the API still claims).
	if isUp and not force then
		if _G.AutoDelete_SetActiveTrackedPet then
			_G.AutoDelete_SetActiveTrackedPet("scavenger")
		end
		return
	end
	CallCompanion("CRITTER", idx)
	print("|cffff8000[AutoDelete]|r: Summoned Greedy Scavenger")
	if _G.AutoDelete_SetActiveTrackedPet then
		_G.AutoDelete_SetActiveTrackedPet("scavenger")
	end
	-- Mark when we summoned so the user-dismiss-vs-leash classification can
	-- distinguish a fast manual dismiss (within USER_DISMISS_WINDOW) from a
	-- slow range-leash. See companion watcher state for full rationale.
	if _G.AutoDelete_RecordSummonAt then
		_G.AutoDelete_RecordSummonAt(GetTime())
	end
end

-- Summon the Goblin Merchant companion (PE vendor pet).
local function SummonGoblinMerchant(force)
	local idx, isUp, cId = FindCompanionById(MERCHANT_CREATURE_ID, "goblin merchant")
	if cId then MERCHANT_CREATURE_ID = cId end  -- cache for next time
	if not idx then return end  -- player doesn't own it
	-- Idempotent unless force=true. See SummonGreedyScavenger for rationale.
	if isUp and not force then
		if _G.AutoDelete_SetActiveTrackedPet then
			_G.AutoDelete_SetActiveTrackedPet("merchant")
		end
		return
	end
	CallCompanion("CRITTER", idx)
	print("|cffff8000[AutoDelete]|r: Summoned Goblin Merchant. Target it and press your Interact With Target keybind to open the vendor.")
	if _G.AutoDelete_SetActiveTrackedPet then
		_G.AutoDelete_SetActiveTrackedPet("merchant")
	end
	if _G.AutoDelete_RecordSummonAt then
		_G.AutoDelete_RecordSummonAt(GetTime())
	end
end

-- Fire SummonGreedyScavenger after a delay. Guarded so concurrent callers
-- (e.g. dismount restore + after-sell trigger) don't stack two pending summons.
local summonPending = false
local function DelayedSummon(delaySeconds)
	if summonPending then return end
	summonPending = true
	AfterDelay(delaySeconds or 1.5, function()
		summonPending = false
		SummonGreedyScavenger()
	end)
end

-- ============================================================================
-- Hide Greedy Scavenger spam (chat filter + bubble suppressor)
-- Gated at runtime by cachedProfile.hideGreedySpam. Installed once at load;
-- the filter/bubble functions become no-ops when the toggle is off.
-- ============================================================================

-- Author-name matcher: true if the speaker is the Greedy Scavenger.
-- Strips color codes since monster-say events can include them.
local function IsGreedyAuthor(author)
	if not author or author == "" then return false end
	-- Strip color codes: |cAARRGGBB...|r  and texture codes |TpATH|t
	author = author:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	author = author:gsub("|T[^|]+|t", "")
	return string.find(string.lower(author), "greedy scavenger") ~= nil
end

-- Track recent greedy-say messages so we can match them to chat bubbles.
-- Bubbles aren't tagged with author, so we match by text content within a window.
local greedyRecentMessages = {}   -- [msg] = timestamp
local GREEDY_MSG_TTL = 8          -- seconds to remember each message for bubble matching

local function RememberGreedyMessage(msg)
	if not msg or msg == "" then return end
	greedyRecentMessages[msg] = GetTime()
end

local function IsRecentGreedyMessage(msg)
	if not msg or msg == "" then return false end
	local t = greedyRecentMessages[msg]
	if not t then return false end
	if GetTime() - t > GREEDY_MSG_TTL then
		greedyRecentMessages[msg] = nil
		return false
	end
	return true
end

-- Chat event filter: runs for EVERY message on the listed event types.
-- Returns true to suppress. Always remembers matched greedy lines so the
-- bubble killer can silence the matching chat bubble even when the chat
-- toggle is on (bubbles appear regardless of chat filters).
local function GreedyChatFilter(_, _, msg, author)
	if IsGreedyAuthor(author) then
		RememberGreedyMessage(msg)
		-- Mark the scav as "alive and looting" for stuck detection. Every
		-- monster-chat line from the scav corresponds to a successful pickup.
		if _G.AutoDelete_RecordScavLootChat then
			_G.AutoDelete_RecordScavLootChat(GetTime())
		end
		if cachedProfile and cachedProfile.hideGreedySpam then
			return true   -- swallow the message
		end
	end
	return false
end

-- Install chat filters once. Covers say/yell/whisper/emote/monster_* variants.
local greedyFiltersInstalled = false
local function InstallGreedyChatFilters()
	if greedyFiltersInstalled then return end
	greedyFiltersInstalled = true
	local events = {
		"CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL",
		"CHAT_MSG_MONSTER_WHISPER", "CHAT_MSG_MONSTER_EMOTE",
		"CHAT_MSG_MONSTER_PARTY",
		"CHAT_MSG_SAY", "CHAT_MSG_YELL",
		"CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
	}
	for _, ev in ipairs(events) do
		ChatFrame_AddMessageEventFilter(ev, GreedyChatFilter)
	end
end

-- Chat bubble suppression. Bubbles are WorldFrame children whose only region
-- is a FontString matching the message. We scan at 0.1s intervals and hide
-- bubbles whose text matches a recent Greedy message.
local bubbleWatcher = CreateFrame("Frame")
local bubbleTimer = 0
local BUBBLE_CHECK_INTERVAL = 0.1
local killedBubbles = setmetatable({}, { __mode = "k" })   -- weak keys so GC works

local function KillBubble(frame)
	if not frame or killedBubbles[frame] then return end
	killedBubbles[frame] = true
	frame:Hide()
	-- Defensive: also kill its regions in case something re-shows the parent
	if frame.SetAlpha then frame:SetAlpha(0) end
end

bubbleWatcher:SetScript("OnUpdate", function(self, dt)
	bubbleTimer = bubbleTimer + dt
	if bubbleTimer < BUBBLE_CHECK_INTERVAL then return end
	bubbleTimer = 0
	if not cachedProfile or not cachedProfile.hideGreedySpam then return end
	if not next(greedyRecentMessages) then return end

	for i = 1, WorldFrame:GetNumChildren() do
		local f = select(i, WorldFrame:GetChildren())
		if f and not killedBubbles[f] and f:GetName() == nil and f.GetRegions then
			-- Chat bubbles: no name, small region count, has a FontString
			local isBubble = false
			local text = nil
			for r = 1, f:GetNumRegions() do
				local region = select(r, f:GetRegions())
				if region and region.GetObjectType and region:GetObjectType() == "FontString" then
					isBubble = true
					text = region:GetText()
					break
				end
			end
			if isBubble and text and IsRecentGreedyMessage(text) then
				KillBubble(f)
			end
		end
	end
end)

-- Install filters once (bubble watcher is already running above).
InstallGreedyChatFilters()

-- ============================================================================
-- Auto-Invite
-- ============================================================================
-- Invites players who whisper you any of the configured keywords (default:
-- "inv,invite"). Matching is case-insensitive and triggers when the keyword
-- appears at a word-start (so "inv" matches "inv", "invite", "invited", but
-- not "binv"). Comma-separated list in profile.autoInviteKeywords.
--
-- Gated by:
--   cachedProfile.autoInviteEnabled (master toggle for this feature)
--   player must be group leader OR raid assistant (silently ignored otherwise)
-- INDEPENDENT of the AutoDelete master Enable toggle by design.
--
-- Active everywhere (party, raid, BG, solo).
--
-- Extras (all off by default):
--   autoInviteApplyLootRule + autoInviteLootRule: apply a loot rule after inviting
--   autoInviteConvertToRaid: convert to raid when party is full (5 members)
-- ============================================================================

-- Loot rule values for SetLootMethod (3.3.5 API).
-- Maps profile string → (method, threshold-arg-for-master-loot).
local LOOT_METHOD_MAP = {
	freeforall      = { method = "freeforall" },
	roundrobin      = { method = "roundrobin" },
	group           = { method = "group" },
	needbeforegreed = { method = "needbeforegreed" },
	master          = { method = "master" },
}

-- Strip WoW cross-realm suffix and normalize whitespace for name comparison.
local function NormalizePlayerName(name)
	if not name or name == "" then return "" end
	name = name:gsub("%-.+$", "")   -- strip "-RealmName" if present
	return (name:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Parse the keyword string ("inv,invite") into a normalized array of lowercase
-- keywords. Trims whitespace, drops blanks.
local function ParseInviteKeywords(rawStr)
	local out = {}
	for word in string.gmatch(rawStr or "", "[^,]+") do
		local w = word:gsub("^%s+", ""):gsub("%s+$", ""):lower()
		if w ~= "" then table.insert(out, w) end
	end
	return out
end

-- Does `msg` contain any of the `keywords` as the start of a word?
-- "Word start" means the keyword is preceded by start-of-string or a
-- non-alphanumeric character. What comes AFTER the keyword doesn't matter,
-- the keyword acts as a prefix. Examples for keyword "inv":
--   "inv"                → yes
--   "invite"             → yes
--   "invited"            → yes
--   "please invite me"   → yes
--   "invent"             → yes
--   "investigation"      → yes
--   "uninvited"          → NO  ('inv' is mid-word, not at a word start)
-- Keyword "invite" → matches any word starting with "invite"
--   (so "invite", "invites", "invited" all match).
local function MessageMatchesKeyword(msg, keywords)
	if not msg or msg == "" or not keywords or #keywords == 0 then return false end
	local lower = msg:lower()

	for _, kw in ipairs(keywords) do
		local start = 1
		while true do
			local s, e = lower:find(kw, start, true)   -- plain find (no magic)
			if not s then break end

			-- Check char BEFORE the match (must be start-of-string or non-alphanumeric).
			-- This ensures the keyword is at a WORD START. No check after the match,
			-- so "inv" matches "invite", "invent", "invited", etc.
			local okBefore = (s == 1)
			if not okBefore then
				local prev = lower:sub(s - 1, s - 1)
				okBefore = (prev:match("[%w]") == nil)
			end

			if okBefore then return true end
			start = e + 1
		end
	end
	return false
end

-- True if the player has invite authority:
--   - Solo (not in party/raid) → always true (can start a group)
--   - In party → must be leader
--   - In raid → must be leader OR assistant
local function PlayerCanInvite()
	local inRaid = GetNumRaidMembers and GetNumRaidMembers() > 0
	local inParty = GetNumPartyMembers and GetNumPartyMembers() > 0

	if inRaid then
		-- IsRaidLeader() and IsRaidOfficer() exist on 3.3.5
		if IsRaidLeader and IsRaidLeader() then return true end
		if IsRaidOfficer and IsRaidOfficer() then return true end
		return false
	end

	if inParty then
		if IsPartyLeader and IsPartyLeader() then return true end
		return false
	end

	-- Solo → we can start a party
	return true
end

-- True if the current group is a 5-person party at capacity.
local function IsPartyFullForRaidConvert()
	if GetNumRaidMembers and GetNumRaidMembers() > 0 then return false end   -- already in raid
	if not GetNumPartyMembers then return false end
	-- GetNumPartyMembers counts members EXCLUDING the player; 4 means 5 total.
	return GetNumPartyMembers() >= 4
end

-- Apply the configured loot rule. Silent. Only applies if toggle is on AND
-- the player actually has loot-setting authority.
local function ApplyConfiguredLootRule()
	if not cachedProfile or not cachedProfile.autoInviteApplyLootRule then return end
	local ruleKey = cachedProfile.autoInviteLootRule or "freeforall"
	local info = LOOT_METHOD_MAP[ruleKey]
	if not info or not SetLootMethod then return end

	-- Loot method can only be changed by party leader (and raid leader).
	local inRaid = GetNumRaidMembers and GetNumRaidMembers() > 0
	if inRaid then
		if not (IsRaidLeader and IsRaidLeader()) then return end
	else
		if not (IsPartyLeader and IsPartyLeader()) then return end
	end

	if info.method == "master" then
		-- Master loot needs a master looter name; use self.
		local me = UnitName("player")
		if me then SetLootMethod("master", me) end
	else
		SetLootMethod(info.method)
	end
end

-- Convert party to raid if configured AND the party is full.
local function MaybeConvertToRaid()
	if not cachedProfile or not cachedProfile.autoInviteConvertToRaid then return end
	if not IsPartyFullForRaidConvert() then return end
	if not (IsPartyLeader and IsPartyLeader()) then return end
	if ConvertToRaid then ConvertToRaid() end
end

-- Invite the given player. Silent. Handles solo→party transition naturally.
local function SafeInvitePlayer(targetName)
	if not targetName or targetName == "" then return end
	if not InviteUnit then return end

	-- Don't re-invite someone already in our group.
	if UnitInParty and UnitInParty(targetName) then return end
	if UnitInRaid and UnitInRaid(targetName) then return end

	InviteUnit(targetName)
end

-- After a successful invite, we want to apply loot rules + raid-convert ON A
-- DELAY, because the party state doesn't update instantly when the target
-- accepts. We schedule a follow-up check via the shared AfterDelay timer
-- (same machinery that powers DelayedSummon and other one-shots).
local function ScheduleInviteFollowup(delaySec, fn)
	AfterDelay(delaySec or 3, fn)
end

-- Incoming whisper handler. Called for CHAT_MSG_WHISPER events.
-- If the message matches a keyword → invite the whisperer.
local function HandleIncomingWhisper(msg, author)
	-- Always refresh cached profile here; UI toggles don't fire any event
	-- that would otherwise update it, so stale data would silently block invites.
	RefreshCachedProfile()
	if not cachedProfile or not cachedProfile.autoInviteEnabled then return end
	if not PlayerCanInvite() then return end

	local keywords = ParseInviteKeywords(cachedProfile.autoInviteKeywords)
	if not MessageMatchesKeyword(msg, keywords) then return end

	local target = NormalizePlayerName(author)
	if target == "" then return end

	SafeInvitePlayer(target)

	-- Follow up: apply loot rule + convert to raid if configured.
	-- 3s gives the invited player time to accept.
	ScheduleInviteFollowup(3, function()
		ApplyConfiguredLootRule()
		MaybeConvertToRaid()
	end)
end



-- Dedicated event frame for whisper events (kept separate from the main
-- scanner to avoid clutter).
local inviteFrame = CreateFrame("Frame")
inviteFrame:RegisterEvent("CHAT_MSG_WHISPER")
inviteFrame:SetScript("OnEvent", function(_, event, msg, author)
	if event == "CHAT_MSG_WHISPER" then
		HandleIncomingWhisper(msg, author)
	end
end)

-- Inventory worth sampler: called from MERCHANT_SHOW.
-- Walks all bag slots, sums vendor sell prices, adds one sample to the running
-- lifetime stats (total + count; average = total / count). Also adds to the
-- session counters. Non-vendorable items contribute 0 to the sample.
local function SampleInventoryWorth()
	local totalCopper = 0
	for bag = 0, 4 do
		local slots = GetContainerNumSlots(bag)
		if slots and slots > 0 then
			for slot = 1, slots do
				local _, itemCount, locked, _, _, _, itemLink = GetContainerItemInfo(bag, slot)
				if itemLink and not locked then
					local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemLink)
					if sellPrice and sellPrice > 0 then
						totalCopper = totalCopper + (sellPrice * (itemCount or 1))
					end
				end
			end
		end
	end
	BumpStat("inventoryWorthTotal", totalCopper)
	BumpStat("inventoryWorthCount", 1)
end

-- Auto-repair: called from MERCHANT_SHOW.
-- Respects profile.autoRepair and profile.autoRepairUseGuildBank.
local function TryAutoRepair()
	if not cachedProfile or not cachedProfile.autoRepair then return end
	if not CanMerchantRepair or not CanMerchantRepair() then return end
	if not GetRepairAllCost or not RepairAllItems then return end

	local cost, canRepair = GetRepairAllCost()
	if not canRepair or not cost or cost <= 0 then return end

	-- Use Guild Bank money if the toggle is on AND the player is in a guild
	-- AND has guild-bank withdraw/repair permission.
	local useGuild = cachedProfile.autoRepairUseGuildBank
		and IsInGuild and IsInGuild()
		and CanGuildBankRepair and CanGuildBankRepair()
		and GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() >= cost

	if useGuild then
		RepairAllItems(1)  -- 1 = use guild bank funds
		BumpStat("repairs", 1)
		BumpStat("repairSpend", cost)
		print("|cffff8000[AutoDelete]|r: Repaired from guild bank (" .. FormatMoney(cost) .. ")")
	else
		-- Fall back to personal gold; skip if the player can't afford it.
		if GetMoney and GetMoney() >= cost then
			RepairAllItems()
			BumpStat("repairs", 1)
			BumpStat("repairSpend", cost)
			print("|cffff8000[AutoDelete]|r: Repaired for " .. FormatMoney(cost))
		else
			print("|cffff8000[AutoDelete]|r: Not enough gold to repair (need " .. FormatMoney(cost) .. ")")
		end
	end
end

local SELL_BATCH_SIZE = 20
local sellSessionCount = 0
local sellSessionCopper = 0
local sellDryTicks = 0

local function SellItems(silent)
	if not MerchantFrame or not MerchantFrame:IsShown() then
		if not silent then print("|cffff8000[AutoDelete]|r: You must be at a vendor to sell.") end
		return
	end
	if CursorHasItem() then return end

	local db = GetDB()
	local profile = GetActiveProfile(db)

	local sellNames, sellIDs = BuildWantedSets(profile.sellListText)

	local batchCount = 0

	for bag = 0, 4 do
		for slot = 1, GetContainerNumSlots(bag) do
			if batchCount >= SELL_BATCH_SIZE then break end
			local _, itemCount, locked, _, _, _, itemLink = GetContainerItemInfo(bag, slot)
			if itemLink and not locked then
				-- 6th return from GetItemInfo = itemType (top-level category, e.g.
				-- "Armor", "Weapon", "Quest", "Consumable", "Miscellaneous").
				-- We use this as a defensive second-layer gear check alongside
				-- equipSlot so that books, glyphs, consumables, and other
				-- miscellaneous items with unexpected equipSlot values can
				-- never be caught by the quality-based auto-sell rules.
				local name, _, itemQuality, ilvl, _, itemClass, _, _, equipSlot, _, vendorPrice = GetItemInfo(itemLink)

				-- Quest items are normally protected from auto-rules, but
				-- the explicit Sell list overrides quest protection (user
				-- intent wins). Auto rules still respect quest items.
				local isQuestItem = (itemClass == "Quest")

				if vendorPrice and vendorPrice > 0 then
					-- "Gear" = equippable slot.
					-- For weapon-slot items (weapons, shields, holdables, ranged,
					-- thrown, relics) we accept ANY itemClass because on PE these
					-- are all treated uniformly as Weapon-affix targets.
					-- For non-weapon gear we still require itemClass to be Armor.
					local isGearItem = false
					local isWeaponSlot = false
					if equipSlot and GEAR_SLOTS[equipSlot] then
						if WEAPON_SLOTS[equipSlot] then
							isGearItem = true
							isWeaponSlot = true
						elseif itemClass == "Armor" or itemClass == "Weapon" then
							isGearItem = true
						end
					end

					-- ============================================================
					-- SELL DECISION CHAIN (this function handles vendoring only;
					-- Auto-Delete Junk/Common live in the delete scanner).
					--
					-- Priority order (highest first):
					--   1. Keep list  - always wins, skips everything below
					--   2. Sell list  - explicit user intent (overrides quest protection)
					--   3. Greens     - auto-sell, gear only, skips quest items
					--   4. BoE Weapons - Rare/Epic, iLvl gated, skips quest items
					--   5. BoP         - Rare/Epic, iLvl gated, skips quest items
					--   6. BoE Armor   - Rare/Epic, iLvl gated, skips quest items
					-- An item can only match one rule per scan.
					-- ============================================================

					local shouldSell = false
					local sellReason = nil   -- "list" | "greens" | "boeArmor" | "bop" | "boeWeapons"
					local itemId = GetItemIDFromLink(itemLink)

					-- Step 1: Keep list short-circuits the whole chain.
					local isOnKeepList = IsWhitelisted(profile, itemId, name)

					if not isOnKeepList then

						-- Step 2: Explicit Sell list entry.
						if itemId and sellIDs[itemId] then
							shouldSell = true; sellReason = "list"
						elseif name and sellNames[Normalize(name)] then
							shouldSell = true; sellReason = "list"
						end

						-- Steps 3-6 only run for non-quest items. A quest
						-- item only sells if Step 2 matched it explicitly.
						if not shouldSell and not isQuestItem then

							-- Step 3: Auto-Sell Greens (global). Junk and Common
							-- are DELETED by the delete scanner, not sold here.
							if not shouldSell and itemQuality == 2 and profile.autoSellGreens and isGearItem then
								shouldSell = true; sellReason = "greens"
							end

							-- Steps 4-6: Sell-tab category sections. Each is
							-- independent. An item is matched to exactly one
							-- category (the first that fits in priority order).
							if not shouldSell and isGearItem
								and (itemQuality == 3 or itemQuality == 4) then

								local isBoE = IsBindOnEquip(bag, slot)
								local rarityIsRare = (itemQuality == 3)
								local rarityIsEpic = (itemQuality == 4)

								-- Helper: is the item's iLvl inside [min, max]?
								local function inRange(min, max)
									return ilvl and ilvl >= (min or 1) and ilvl <= (max or 199)
								end

								-- Step 4: BoE Weapons (BoE + WEAPON_SLOTS).
								if isBoE and isWeaponSlot and profile.boeWeaponsEnabled then
									local rarityOn = (rarityIsRare and profile.boeWeaponsRare)
										or (rarityIsEpic and profile.boeWeaponsEpic)
									if rarityOn and inRange(profile.boeWeaponsIlvlMin, profile.boeWeaponsIlvlMax) then
										shouldSell = true; sellReason = "boeWeapons"
									end

								-- Step 5: BoP (any non-BoE gear).
								elseif (not isBoE) and profile.bopEnabled then
									local rarityOn = (rarityIsRare and profile.bopRare)
										or (rarityIsEpic and profile.bopEpic)
									if rarityOn and inRange(profile.bopIlvlMin, profile.bopIlvlMax) then
										shouldSell = true; sellReason = "bop"
									end

								-- Step 6: BoE Armor (BoE, NOT weapon-slot).
								elseif isBoE and (not isWeaponSlot) and profile.boeArmorEnabled then
									local rarityOn = (rarityIsRare and profile.boeArmorRare)
										or (rarityIsEpic and profile.boeArmorEpic)
									if rarityOn and inRange(profile.boeArmorIlvlMin, profile.boeArmorIlvlMax) then
										shouldSell = true; sellReason = "boeArmor"
									end
								end
							end
						end  -- close: if not shouldSell and not isQuestItem
					end

					if shouldSell then
						-- DEBUG TRACE: print why the item is selling. Toggle with /del debug.
						-- Shows every input that fed the decision chain so the user can
						-- pinpoint which rule is matching when something unexpected sells.
						if _G.AutoDelete_DebugSell then
							local idStr = itemId and tostring(itemId) or "nil"
							local boeStr = "?"
							if sellReason ~= "list" and sellReason ~= "greens" then
								-- isBoE was already computed in the rule chain above
								boeStr = (sellReason == "bop") and "BoP" or "BoE"
							end
							print(string.format(
								"|cffff8000[AutoDelete DEBUG]|r SOLD: %s (id=%s) | reason=%s | quality=%s | ilvl=%s | equipSlot=%s | itemClass=%s | isGear=%s | isWeaponSlot=%s | bind=%s",
								tostring(name), idStr, tostring(sellReason),
								tostring(itemQuality), tostring(ilvl),
								tostring(equipSlot), tostring(itemClass),
								tostring(isGearItem), tostring(isWeaponSlot), boeStr
							))
						end
						-- Flag this call so the UseContainerItem hook skips
						-- (we record the BumpStat directly below).
						autoDeleteSelling = true
						UseContainerItem(bag, slot)
						autoDeleteSelling = false
						batchCount = batchCount + 1
						sellSessionCount = sellSessionCount + 1
						local soldCopper = vendorPrice * (itemCount or 1)
						sellSessionCopper = sellSessionCopper + soldCopper
						-- Tracking: one sell action = one item stack sold (not one unit).
						-- Gold earned counts the actual copper received.
						BumpStat("itemsSold", 1)
						BumpStat("goldEarned", soldCopper)
					end
				end
			end
		end
		if batchCount >= SELL_BATCH_SIZE then break end
	end

	if batchCount > 0 then
		sellDryTicks = 0
	else
		sellDryTicks = sellDryTicks + 1
		if sellDryTicks >= 2 and sellSessionCount > 0 then
			print("|cffff8000[AutoDelete]|r: Sold " .. sellSessionCount .. " item(s) for " .. FormatMoney(sellSessionCopper))
			sellSessionCount = 0
			sellSessionCopper = 0
			sellDryTicks = 0
			-- After-sell summon: gated by summonScavenger master + summonAfterSell.
			-- Vendor window is still open here (MERCHANT_CLOSED fires later).
			-- Only trigger at Goblin Merchant. If summonOnlyInCombat is set, the
			-- player must be in combat at THIS moment for the summon to fire.
			if cachedProfile and cachedProfile.summonScavenger and cachedProfile.summonAfterSell then
				local combatOk = (not cachedProfile.summonOnlyInCombat) or (UnitAffectingCombat and UnitAffectingCombat("player"))
				if combatOk then
					local merchant = string.lower(lastMerchantName or "")
					if string.find(merchant, "goblin merchant") then
						DelayedSummon(1.5)
					end
				end
			end
		end
	end
end

-- ============================================================================
-- ElvUI Bag Buttons
-- ============================================================================
-- Three buttons attached to the top-right of ElvUI's main bag frame, ordered
-- left-to-right to match the Delete | Sell | Keep tabs in the options panel:
--
--   Delete (red X)         → drop item to add to Delete list; right-click
--                            opens the panel and jumps to the Delete tab
--   Sell (gold coin)       → drop item to add to Sell list; left-click while
--                            at a vendor triggers a sell pass; right-click
--                            opens the panel and jumps to the Sell tab
--   Keep (chocolate box)   → drop item to add to Keep list; right-click
--                            opens the panel and jumps to the Keep tab
--
-- Anchor: Delete is pinned at TOPRIGHT -98 -4 so the row of three (each 20px
-- wide + 4px gap) lands at roughly the same right-edge position as the
-- single-button layout did historically. Sell anchors RIGHT of Delete; Keep
-- RIGHT of Sell. CreateElvUIBagButton runs once at PLAYER_LOGIN (after a 2s
-- delay so ElvUI's container frame is constructed first); no anti-restack
-- guard is needed because there's only one call site.

local function CreateElvUIBagButton()
	local bagFrame = _G.ElvUI_ContainerFrame
	if not bagFrame then return end

	-- =====================================================
	-- Delete button (red X) - leftmost in the Delete | Sell | Keep row
	-- =====================================================
	local btn = CreateFrame("Button", "AutoDelete_ElvUIBagBtn", bagFrame)
	btn:SetSize(20, 20)
	btn:SetPoint("TOPRIGHT", bagFrame, "TOPRIGHT", -98, -4)
	btn:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		tile = false, tileSize = 16, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 }
	})
	btn:SetBackdropColor(0, 0, 0, 0.6)
	btn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 2, -2)
	icon:SetPoint("BOTTOMRIGHT", -2, 2)
	icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")

	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
		GameTooltip:AddLine("AutoDelete", 0, 1, 0)
		GameTooltip:AddLine("Drop item to add to delete list.", 1, 1, 1)
		GameTooltip:AddLine("Right-click to open settings.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
		btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
		icon:SetVertexColor(1, 0.2, 0.2)
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
		btn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
		icon:SetVertexColor(1, 1, 1)
	end)

	btn:RegisterForDrag("LeftButton")
	btn:RegisterForClicks("AnyUp")
	btn:SetScript("OnReceiveDrag", function() _G.AutoDelete_AddToDeleteList() end)
	btn:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			-- Right-click: open the panel and jump straight to the Delete
			-- list tab so the user lands on the right list.
			_G.AutoDelete_OpenPanelToList("delete")
		elseif CursorHasItem() then
			_G.AutoDelete_AddToDeleteList()
		end
	end)

	-- =====================================================
	-- Sell button (gold coin) - middle of the row
	-- =====================================================
	local sellBtn = CreateFrame("Button", "AutoDelete_ElvUISellBtn", bagFrame)
	sellBtn:SetSize(20, 20)
	sellBtn:SetPoint("LEFT", btn, "RIGHT", 4, 0)
	sellBtn:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		tile = false, tileSize = 16, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 }
	})
	sellBtn:SetBackdropColor(0, 0, 0, 0.6)
	sellBtn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

	local sellIcon = sellBtn:CreateTexture(nil, "ARTWORK")
	sellIcon:SetPoint("TOPLEFT", 2, -2)
	sellIcon:SetPoint("BOTTOMRIGHT", -2, 2)
	sellIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
	sellIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	sellBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
		GameTooltip:AddLine("Sell Items", 0.12, 1, 0)
		GameTooltip:AddLine("Click to sell at vendor.", 1, 1, 1)
		GameTooltip:AddLine("Drop item to add to sell list.", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("Right-click to open settings.", 0.7, 0.7, 0.7)
		if not MerchantFrame or not MerchantFrame:IsShown() then
			GameTooltip:AddLine("Not at a vendor.", 1, 0.3, 0.3)
		end
		GameTooltip:Show()
		sellBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
		sellIcon:SetVertexColor(1, 1, 0.6)
	end)
	sellBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
		sellBtn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
		sellIcon:SetVertexColor(1, 1, 1)
	end)

	sellBtn:RegisterForDrag("LeftButton")
	sellBtn:RegisterForClicks("AnyUp")
	sellBtn:SetScript("OnReceiveDrag", function() _G.AutoDelete_AddToSellList() end)
	sellBtn:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			-- Right-click: open the panel and jump to the Sell list tab.
			_G.AutoDelete_OpenPanelToList("sell")
		elseif CursorHasItem() then
			_G.AutoDelete_AddToSellList()
		else
			SellItems()
		end
	end)

	-- =====================================================
	-- Keep button (chocolate box) - rightmost in the row
	-- =====================================================
	-- Drop item to add to Keep list; right-click opens the panel and jumps
	-- to the Keep tab. No left-click action (Keep has no vendor/destroy
	-- equivalent - it's a passive protection list).
	local keepBtn = CreateFrame("Button", "AutoDelete_ElvUIKeepBtn", bagFrame)
	keepBtn:SetSize(20, 20)
	keepBtn:SetPoint("LEFT", sellBtn, "RIGHT", 4, 0)
	keepBtn:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		tile = false, tileSize = 16, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 }
	})
	keepBtn:SetBackdropColor(0, 0, 0, 0.6)
	keepBtn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

	local keepIcon = keepBtn:CreateTexture(nil, "ARTWORK")
	keepIcon:SetPoint("TOPLEFT", 2, -2)
	keepIcon:SetPoint("BOTTOMRIGHT", -2, 2)
	keepIcon:SetTexture("Interface\\Icons\\INV_ValentinesBoxOfChocolates02")
	keepIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	keepBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
		GameTooltip:AddLine("Keep List", 0.4, 0.7, 1)
		GameTooltip:AddLine("Drop item to add to keep list.", 1, 1, 1)
		GameTooltip:AddLine("Right-click to open settings.", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("Items on this list are never auto-sold or auto-deleted.", 0.55, 0.55, 0.55)
		GameTooltip:Show()
		keepBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
		keepIcon:SetVertexColor(0.6, 0.85, 1)
	end)
	keepBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
		keepBtn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
		keepIcon:SetVertexColor(1, 1, 1)
	end)

	keepBtn:RegisterForDrag("LeftButton")
	keepBtn:RegisterForClicks("AnyUp")
	keepBtn:SetScript("OnReceiveDrag", function() _G.AutoDelete_AddToKeepList() end)
	keepBtn:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			-- Right-click: open the panel and jump to the Keep list tab.
			_G.AutoDelete_OpenPanelToList("whitelist")
		elseif CursorHasItem() then
			_G.AutoDelete_AddToKeepList()
		end
	end)
end

-- ============================================================================
-- Cached Profile + Event Frame
-- ============================================================================
-- RefreshCachedProfile updates the upvalue declared at the top of the file
-- (do NOT use `local function` here - that would shadow the forward-declared
-- local that all the closures captured).
--
-- The `scanner` Frame is the single event hub for the addon. Its OnEvent
-- handler lives further down (after Welcome Popup is defined, because that
-- handler calls ShowWelcomePopup). Its OnUpdate handler is at the very
-- bottom of this file. The frame is created here only so its event
-- registrations happen before any of the function bodies that depend on
-- those events.

RefreshCachedProfile = function()
	local db = GetDB()
	cachedProfile = GetActiveProfile(db)
end
_G.AutoDelete_RefreshCachedProfile = RefreshCachedProfile

local scanner = CreateFrame("Frame")
scanner:RegisterEvent("ADDON_LOADED")
scanner:RegisterEvent("PLAYER_LOGIN")
scanner:RegisterEvent("BAG_UPDATE")
scanner:RegisterEvent("BAG_UPDATE_DELAYED")
scanner:RegisterEvent("MERCHANT_SHOW")
scanner:RegisterEvent("MERCHANT_CLOSED")

-- ============================================================================
-- Welcome Popup
-- ============================================================================
-- A first-run / persistent setup popup. Shown at PLAYER_LOGIN unless the user
-- has dismissed it via "Don't show again". Walks the user through:
--   1. Notice that all settings default to off.
--   2. Optional: create a "/target Goblin Merchant" macro (Account or Char).
--   3. Optional: walk through binding "Interact With Target" in Esc menu.
-- After all steps, opens the main settings panel.

local function ShowWelcomePopup()
	if _G.AutoDelete_WelcomePopup then
		_G.AutoDelete_WelcomePopup:Show()
		return
	end

	local FONT = "Fonts\\FRIZQT__.TTF"
	local WHITE8 = "Interface\\Buttons\\WHITE8x8"

	-- Outer frame
	local f = CreateFrame("Frame", "AutoDelete_WelcomePopup", UIParent)
	f:SetSize(440, 628)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetFrameLevel(100)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetBackdrop({
		bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1,
	})
	f:SetBackdropColor(0.04, 0.04, 0.04, 0.97)
	f:SetBackdropBorderColor(1, 0.50, 0, 0.85)  -- legendary orange border
	-- Deliberately NOT registered in UISpecialFrames. Escape should not close
	-- this popup; the X button is the only intended way out. This keeps the
	-- popup visible when the user opens the keybinds panel and presses Esc
	-- to leave keybinds (otherwise the same Esc keystroke closes our popup).

	-- Title bar
	local titleBar = CreateFrame("Frame", nil, f)
	titleBar:SetPoint("TOPLEFT", 1, -1)
	titleBar:SetPoint("TOPRIGHT", -1, -1)
	titleBar:SetHeight(28)
	titleBar:SetBackdrop({ bgFile = WHITE8 })
	titleBar:SetBackdropColor(0.08, 0.08, 0.08, 1)

	local title = titleBar:CreateFontString(nil, "OVERLAY")
	title:SetFont(FONT, 14, "OUTLINE")
	title:SetPoint("LEFT", 12, 0)
	title:SetTextColor(1, 0.50, 0, 1)
	title:SetText("Welcome to AutoDelete")

	-- Close X
	local closeBtn = CreateFrame("Button", nil, titleBar)
	closeBtn:SetSize(24, 24)
	closeBtn:SetPoint("RIGHT", -4, 0)
	local closeText = closeBtn:CreateFontString(nil, "OVERLAY")
	closeText:SetFont(FONT, 16, "OUTLINE")
	closeText:SetPoint("CENTER", 0, 1)
	closeText:SetTextColor(0.7, 0.7, 0.7, 1)
	closeText:SetText("x")
	closeBtn:SetScript("OnEnter", function() closeText:SetTextColor(1, 0.3, 0.3, 1) end)
	closeBtn:SetScript("OnLeave", function() closeText:SetTextColor(0.7, 0.7, 0.7, 1) end)
	closeBtn:SetScript("OnClick", function() f:Hide() end)

	-- Intro text
	local intro = f:CreateFontString(nil, "OVERLAY")
	intro:SetFont(FONT, 12)
	intro:SetPoint("TOPLEFT", 16, -42)
	intro:SetPoint("TOPRIGHT", -16, -42)
	intro:SetJustifyH("LEFT")
	intro:SetWordWrap(true)
	intro:SetTextColor(0.9, 0.9, 0.9, 1)
	intro:SetText("All AutoDelete settings start |cffff8000OFF|r by default. Open the settings panel after this dialog to enable features and configure your Delete, Sell, and Keep lists.")
	intro:SetHeight(50)

	-- Section: Macro creation
	local macroLabel = f:CreateFontString(nil, "OVERLAY")
	macroLabel:SetFont(FONT, 12, "OUTLINE")
	macroLabel:SetPoint("TOPLEFT", 16, -106)
	macroLabel:SetTextColor(1, 0.82, 0, 1)
	macroLabel:SetText("Create a Goblin Merchant macro?")

	local macroDesc = f:CreateFontString(nil, "OVERLAY")
	macroDesc:SetFont(FONT, 11)
	macroDesc:SetPoint("TOPLEFT", 16, -124)
	macroDesc:SetPoint("TOPRIGHT", -16, -124)
	macroDesc:SetJustifyH("LEFT")
	macroDesc:SetWordWrap(true)
	macroDesc:SetTextColor(0.75, 0.75, 0.75, 1)
	macroDesc:SetText("Quick way to target your summoned Goblin Merchant. After creation, drag it to a hotbar from |cffffd700/macro|r.")
	macroDesc:SetHeight(28)

	-- Macro scope selection (only used if Yes is clicked)
	local macroScope = "char"  -- default
	local accBox, charBox

	local function MakeRadio(parent, label, x, y, getValue, setValue)
		local btn = CreateFrame("Button", nil, parent)
		btn:SetSize(160, 18)
		btn:SetPoint("TOPLEFT", x, y)

		local dot = btn:CreateTexture(nil, "ARTWORK")
		dot:SetTexture(WHITE8)
		dot:SetSize(10, 10)
		dot:SetPoint("LEFT", 2, 0)
		dot:SetVertexColor(0.2, 0.2, 0.2, 1)

		local txt = btn:CreateFontString(nil, "OVERLAY")
		txt:SetFont(FONT, 11)
		txt:SetPoint("LEFT", 18, 0)
		txt:SetTextColor(0.85, 0.85, 0.85, 1)
		txt:SetText(label)

		btn._dot = dot
		btn._update = function()
			if getValue() then
				dot:SetVertexColor(1, 0.5, 0, 1)
			else
				dot:SetVertexColor(0.25, 0.25, 0.25, 1)
			end
		end
		btn:SetScript("OnClick", function()
			setValue()
			if accBox then accBox._update() end
			if charBox then charBox._update() end
		end)
		btn._update()
		return btn
	end

	charBox = MakeRadio(f, "Per-character macro", 32, -156,
		function() return macroScope == "char" end,
		function() macroScope = "char" end)
	accBox = MakeRadio(f, "Account-wide macro", 200, -156,
		function() return macroScope == "account" end,
		function() macroScope = "account" end)

	-- Yes/No buttons for the macro section
	local function MakeButton(parent, label, w)
		local btn = CreateFrame("Button", nil, parent)
		btn:SetSize(w or 80, 24)
		btn:SetBackdrop({
			bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1,
		})
		btn:SetBackdropColor(0.10, 0.10, 0.10, 1)
		btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
		local txt = btn:CreateFontString(nil, "OVERLAY")
		txt:SetFont(FONT, 11, "OUTLINE")
		txt:SetPoint("CENTER")
		txt:SetTextColor(0.9, 0.9, 0.9, 1)
		txt:SetText(label)
		btn:SetScript("OnEnter", function(self)
			self:SetBackdropColor(0.18, 0.18, 0.18, 1)
			self:SetBackdropBorderColor(1, 0.50, 0, 0.85)
		end)
		btn:SetScript("OnLeave", function(self)
			self:SetBackdropColor(0.10, 0.10, 0.10, 1)
			self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
		end)
		return btn, txt
	end

	local macroYes, macroYesTxt = MakeButton(f, "Create Macro", 110)
	macroYes:SetPoint("TOPLEFT", 16, -180)

	local macroNo, _ = MakeButton(f, "Skip", 60)
	macroNo:SetPoint("TOPLEFT", macroYes, "TOPRIGHT", 8, 0)

	-- Macro feedback label (shown after click). Anchored BELOW the buttons
	-- so the text never overlaps them even when it wraps to two lines.
	local macroResult = f:CreateFontString(nil, "OVERLAY")
	macroResult:SetFont(FONT, 10)
	macroResult:SetPoint("TOPLEFT", macroYes, "BOTTOMLEFT", 0, -4)
	macroResult:SetPoint("RIGHT", f, "RIGHT", -16, 0)
	macroResult:SetJustifyH("LEFT")
	macroResult:SetWordWrap(true)
	macroResult:SetTextColor(0.20, 0.85, 0.20, 1)
	macroResult:SetText("")

	macroYes:SetScript("OnClick", function()
		local perChar = (macroScope == "char")
		-- 3.3.5 expects an iconIndex (number) into the GetMacroIcons() table,
		-- not a string name. Walk the table looking for our icon.
		local body = "/target Goblin Merchant"
		local existing = GetMacroIndexByName("AutoDelete-Goblin")
		if existing and existing > 0 then
			macroResult:SetTextColor(1, 0.82, 0, 1)
			macroResult:SetText("Macro 'AutoDelete-Goblin' already exists. Open |cffffd700/macro|r and drag it to your action bar.")
			return
		end

		-- Resolve icon name to icon index. The Goblin Merchant pet uses the
		-- Pack Hobgoblin racial icon. GetMacroIcons() returns names without
		-- the path prefix, in upper or mixed case depending on client.
		-- We compare case-insensitively to be safe.
		local iconIdx = 1
		local wantedLower = "ability_racial_packhobgoblin"
		if GetMacroIcons then
			local icons = GetMacroIcons()
			if type(icons) == "table" then
				for i, name in ipairs(icons) do
					if name and string.lower(name) == wantedLower then
						iconIdx = i
						break
					end
				end
			end
		end

		local ok, idx = pcall(CreateMacro, "AutoDelete-Goblin", iconIdx, body, perChar)
		if ok and idx and idx > 0 then
			macroResult:SetTextColor(0.20, 0.85, 0.20, 1)
			macroResult:SetText("Created macro 'AutoDelete-Goblin'. Open |cffffd700/macro|r and drag it to your action bar.")
		else
			macroResult:SetTextColor(1, 0.30, 0.30, 1)
			local err = (not ok) and tostring(idx) or "unknown"
			macroResult:SetText("Could not create the macro. Error: " .. err)
		end
	end)

	macroNo:SetScript("OnClick", function()
		macroResult:SetTextColor(0.6, 0.6, 0.6, 1)
		macroResult:SetText("Skipped macro creation.")
	end)

	-- Section: Keybind walkthrough
	local kbLabel = f:CreateFontString(nil, "OVERLAY")
	kbLabel:SetFont(FONT, 12, "OUTLINE")
	kbLabel:SetPoint("TOPLEFT", 16, -226)
	kbLabel:SetTextColor(1, 0.82, 0, 1)
	kbLabel:SetText("Bind Interact With Target?")

	local kbDesc = f:CreateFontString(nil, "OVERLAY")
	kbDesc:SetFont(FONT, 11)
	kbDesc:SetPoint("TOPLEFT", 16, -244)
	kbDesc:SetPoint("TOPRIGHT", -16, -244)
	kbDesc:SetJustifyH("LEFT")
	kbDesc:SetWordWrap(true)
	kbDesc:SetTextColor(0.75, 0.75, 0.75, 1)
	kbDesc:SetText("Once the merchant is targeted, this keybind opens the vendor window. Look under |cffffd700Targeting Functions|r > |cffffd700Interact With Target|r.")
	kbDesc:SetHeight(32)

	local kbYes, _ = MakeButton(f, "Open Keybinds", 110)
	kbYes:SetPoint("TOPLEFT", 16, -290)
	kbYes:SetScript("OnClick", function()
		-- Open Blizzard's keybinding panel.
		if KeyBindingFrame_LoadUI then KeyBindingFrame_LoadUI() end
		if KeyBindingFrame then
			KeyBindingFrame:Show()
		elseif ShowUIPanel then
			ShowUIPanel(KeyBindingFrame)
		end
		-- Scroll to the INTERACTTARGET binding. The keybind UI is a faux
		-- scroll frame backed by the GetBinding(i) iteration. We walk the
		-- list, find the row index for "INTERACTTARGET", set the scroll
		-- offset to put it near the top, then refresh the visible rows.
		local KBF = _G.KeyBindingFrame
		if not KBF or not GetNumBindings then return end

		local targetIdx
		for i = 1, GetNumBindings() do
			local action = GetBinding(i)
			if action == "INTERACTTARGET" then
				targetIdx = i
				break
			end
		end
		if not targetIdx then return end

		-- KeyBindingFrameScrollFrame uses FauxScrollFrame: KEYBINDINGS_PER_PAGE
		-- rows are visible, scroll offset is in rows. Set it so target row
		-- sits near the top (offset = targetIdx - 1, clamped).
		local SF = _G.KeyBindingFrameScrollFrame
		if SF and FauxScrollFrame_OnVerticalScroll and KeyBindingFrame_Update then
			local KEYS_PER_PAGE = (_G.KEY_BINDINGS_DISPLAYED or 19)
			local maxOffset = math.max(0, GetNumBindings() - KEYS_PER_PAGE)
			local offset = math.max(0, math.min(targetIdx - 2, maxOffset))
			-- Each row is 16px tall in 3.3.5's keybind frame.
			FauxScrollFrame_OnVerticalScroll(SF, offset * 16, 16, KeyBindingFrame_Update)
		end
	end)

	local kbNo, _ = MakeButton(f, "Skip", 60)
	kbNo:SetPoint("TOPLEFT", kbYes, "TOPRIGHT", 8, 0)
	kbNo:SetScript("OnClick", function() end)  -- no-op, just visual choice

	-- Divider above the 'How it works' section so the eye separates it from
	-- the macro/keybind walkthrough above.
	local divider = f:CreateTexture(nil, "ARTWORK")
	divider:SetTexture(WHITE8)
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", 16, -334)
	divider:SetPoint("TOPRIGHT", -16, -334)
	divider:SetVertexColor(0.18, 0.18, 0.18, 1)

	-- Section: How it works (simple explanation of the 3-list system).
	local hiwLabel = f:CreateFontString(nil, "OVERLAY")
	hiwLabel:SetFont(FONT, 12, "OUTLINE")
	hiwLabel:SetPoint("TOPLEFT", 16, -344)
	hiwLabel:SetTextColor(1, 0.82, 0, 1)
	hiwLabel:SetText("How it works")

	local hiwBody = f:CreateFontString(nil, "OVERLAY")
	hiwBody:SetFont(FONT, 11)
	hiwBody:SetPoint("TOPLEFT", 16, -362)
	hiwBody:SetPoint("TOPRIGHT", -16, -362)
	hiwBody:SetJustifyH("LEFT")
	hiwBody:SetWordWrap(true)
	hiwBody:SetTextColor(0.85, 0.85, 0.85, 1)
	hiwBody:SetText(
		"AutoDelete uses three lists. Drop an item onto the icons next to your bag, or open the panel and use the tabs.\n" ..
		"|cffff5050Delete|r: items are destroyed on next scan.\n" ..
		"|cffffd700Sell|r: items are sold the next time you open a vendor.\n" ..
		"|cff80c0ffKeep|r: items are protected and never auto-sold or auto-deleted.\n\n" ..
		"|cff66ddffSell filters|r (on the Sell tab, BoE Armor / BoP / BoE Weapons): vendor-only auto-sell rules. " ..
		"Match by quality and item level, no per-item entry needed."
	)
	hiwBody:SetHeight(110)

	-- Warning callout: bright red box reminding users to put valuable items
	-- on the Keep list before enabling auto-delete/auto-sell rules. Sits
	-- between 'How it works' and the footer. Backdrop with red border for
	-- visual punch so it can't be missed.
	local warnFrame = CreateFrame("Frame", nil, f)
	warnFrame:SetPoint("TOPLEFT", 16, -482)
	warnFrame:SetPoint("TOPRIGHT", -16, -482)
	warnFrame:SetHeight(84)
	warnFrame:SetBackdrop({
		bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 2,
	})
	warnFrame:SetBackdropColor(0.18, 0.04, 0.04, 1)
	warnFrame:SetBackdropBorderColor(0.85, 0.15, 0.15, 1)

	local warnText = warnFrame:CreateFontString(nil, "OVERLAY")
	warnText:SetFont(FONT, 12, "OUTLINE")
	warnText:SetPoint("TOPLEFT", 10, -8)
	warnText:SetPoint("BOTTOMRIGHT", -10, 8)
	warnText:SetJustifyH("CENTER")
	warnText:SetJustifyV("MIDDLE")
	warnText:SetWordWrap(true)
	warnText:SetTextColor(1, 0.30, 0.30, 1)
	warnText:SetText("FAIR WARNING\nTo prevent valuable items from being sold or deleted, ADD THEM TO YOUR KEEP LIST BEFORE YOU TURN AUTODELETE ON.")

	-- Footer bar: darker strip with a divider line on top, separating the
	-- "Don't show again" checkbox + Open Settings button from the body.
	-- Uses absolute positioning anchored to BOTTOMLEFT/BOTTOMRIGHT of the
	-- popup so it stays glued to the bottom regardless of popup height.
	local FOOTER_H = 44
	local footerBar = CreateFrame("Frame", nil, f)
	footerBar:SetPoint("BOTTOMLEFT", 1, 1)
	footerBar:SetPoint("BOTTOMRIGHT", -1, 1)
	footerBar:SetHeight(FOOTER_H)
	footerBar:SetBackdrop({ bgFile = WHITE8 })
	footerBar:SetBackdropColor(0.02, 0.02, 0.02, 1)

	local footerDivider = f:CreateTexture(nil, "ARTWORK")
	footerDivider:SetTexture(WHITE8)
	footerDivider:SetHeight(1)
	footerDivider:SetPoint("BOTTOMLEFT", 1, FOOTER_H + 1)
	footerDivider:SetPoint("BOTTOMRIGHT", -1, FOOTER_H + 1)
	footerDivider:SetVertexColor(0.18, 0.18, 0.18, 1)

	-- Don't-show-again checkbox (left side of footer bar). Parented to
	-- footerBar so it draws on top of the footer's backdrop - children of
	-- a child frame stack above the parent's overlay regions.
	local dontShow = false
	local dsCheck = CreateFrame("Button", nil, footerBar)
	dsCheck:SetSize(14, 14)
	dsCheck:SetPoint("LEFT", footerBar, "LEFT", 16, 0)
	dsCheck:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
	dsCheck:SetBackdropColor(0.10, 0.10, 0.10, 1)
	dsCheck:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

	local dsCheckMark = dsCheck:CreateTexture(nil, "OVERLAY")
	dsCheckMark:SetTexture("Interface\\AddOns\\AutoDelete\\textures\\checkmark.tga")
	dsCheckMark:SetSize(12, 12)
	dsCheckMark:SetPoint("CENTER")
	dsCheckMark:Hide()

	local dsLabel = footerBar:CreateFontString(nil, "OVERLAY")
	dsLabel:SetFont(FONT, 11)
	dsLabel:SetPoint("LEFT", dsCheck, "RIGHT", 6, 0)
	dsLabel:SetTextColor(0.85, 0.85, 0.85, 1)
	dsLabel:SetText("Don't show this again")

	dsCheck:SetScript("OnClick", function()
		dontShow = not dontShow
		if dontShow then dsCheckMark:Show() else dsCheckMark:Hide() end
	end)

	-- Make label clickable too
	local labelBtn = CreateFrame("Button", nil, footerBar)
	labelBtn:SetPoint("LEFT", dsCheck, "RIGHT", 0, 0)
	labelBtn:SetSize(160, 14)
	labelBtn:SetScript("OnClick", function() dsCheck:Click() end)

	local openSettings, _ = MakeButton(footerBar, "Open Settings", 130)
	openSettings:SetPoint("RIGHT", footerBar, "RIGHT", -16, 0)
	openSettings:SetScript("OnClick", function()
		if dontShow then
			_G.AutoDeleteDB = _G.AutoDeleteDB or {}
			_G.AutoDeleteDB.welcomeDismissed = true
		end
		f:Hide()
		local panel = _G.AutoDeleteOptionsPanel
		-- Diagnostics: print why the panel didn't open if anything goes wrong.
		-- Helps users tell us what's happening when "Open Settings" appears
		-- to do nothing.
		if not panel then
			print("|cffff8000[AutoDelete]|r Open Settings: panel not found (Options.lua may not have loaded yet). Try /del to open settings instead.")
			return
		end
		if not panel.IsShown then
			print("|cffff8000[AutoDelete]|r Open Settings: panel object missing IsShown method. Type: " .. type(panel))
			return
		end
		if panel:IsShown() then
			print("|cffff8000[AutoDelete]|r Open Settings: panel already visible (it may be hidden behind another window).")
			return
		end
		panel:Show()
		-- Verify it actually became visible. If something else is blocking
		-- (strata, parent hidden, addon conflict) tell the user.
		if not panel:IsShown() then
			print("|cffff8000[AutoDelete]|r Open Settings: called Show() but panel did not become visible. Try /del - if that also fails, an addon conflict is likely.")
		end
	end)

	-- Hook close (X or Esc) to also persist the dismissal if checked
	f:SetScript("OnHide", function()
		if dontShow then
			_G.AutoDeleteDB = _G.AutoDeleteDB or {}
			_G.AutoDeleteDB.welcomeDismissed = true
		end
	end)
end

-- ============================================================================
-- Event Handler (scanner OnEvent)
-- ============================================================================
-- ADDON_LOADED        -> initialize SavedVariables
-- PLAYER_LOGIN        -> print loaded notice, install MerchantFrame.Hide
--                        wrappers, schedule the post-login ElvUI button
--                        creation + welcome popup (2s delay)
-- BAG_UPDATE          -> request a delete-scan
-- BAG_UPDATE_DELAYED  -> request a delete-scan
-- MERCHANT_SHOW       -> sample inventory worth, then auto-repair + auto-sell
-- MERCHANT_CLOSED     -> print sell summary, fire after-close summon if armed

scanner:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		GetDB()
		RefreshCachedProfile()
		return
	end
	if event == "PLAYER_LOGIN" then
		RefreshCachedProfile()
		print("|cffff8000[AutoDelete]|r loaded. Type |cff00ff00/del|r to configure.")

		-- One-time notice: the v3.02 schema migration moved sell rules into
		-- per-category sections. EnsureProfileFields sets this flag when it
		-- migrates a profile from the old schema.
		if _G._AutoDelete_NeedMigrationNotice then
			_G._AutoDelete_NeedMigrationNotice = nil
			print("|cffff8000[AutoDelete]|r |cffffff00Sell rules updated:|r the old Sell Filters/Conditions split has been replaced with per-category sections (BoE Armor, BoP, BoE Weapons). Your existing settings were migrated. Open |cff00ff00/del|r and review the Sell tab.")
		end

		-- Keep bags open when the vendor closes. Diagnostic trace on PE-ElvUI
		-- showed the call order is:
		--   1. ToggleBackpack fires (Blizzard ContainerFrame_OnHide cascade)
		--   2. B:CloseBags fires (ElvUI closes its bag frames)
		--   3. MerchantFrame:OnHide fires LAST
		--
		-- That means hooking OnHide is too late to set a suppress flag.
		-- We have to wrap MerchantFrame.Hide directly so the flag is set
		-- BEFORE any cascading hide handlers run.
		if MerchantFrame then
			local suppressClose = false

			-- Wrap _G.CloseAllBags
			if _G.CloseAllBags then
				local origCloseAllBags = _G.CloseAllBags
				_G.CloseAllBags = function(...)
					if suppressClose then return end
					return origCloseAllBags(...)
				end
			end

			-- Wrap _G.ToggleBackpack (cascade calls this)
			if _G.ToggleBackpack then
				local origToggleBackpack = _G.ToggleBackpack
				_G.ToggleBackpack = function(...)
					if suppressClose then return end
					return origToggleBackpack(...)
				end
			end

			-- Wrap _G.CloseBackpack just in case
			if _G.CloseBackpack then
				local origCloseBackpack = _G.CloseBackpack
				_G.CloseBackpack = function(...)
					if suppressClose then return end
					return origCloseBackpack(...)
				end
			end

			-- Wrap ElvUI's bag module CloseBags.
			if _G.ElvUI then
				local E = _G.ElvUI[1]
				local B = E and E.GetModule and E:GetModule("Bags", true)
				if B and B.CloseBags then
					local origCB = B.CloseBags
					B.CloseBags = function(self, ...)
						if suppressClose then return end
						return origCB(self, ...)
					end
				end
			end

			-- Pre-hook the Hide method on MerchantFrame. This is the EARLIEST
			-- possible interception point: the user/script calls
			-- MerchantFrame:Hide(), our wrapper sets suppressClose, then
			-- delegates to the real Hide which fires the OnHide cascade.
			-- All bag-close calls in that cascade now see suppressClose=true.
			local origHide = MerchantFrame.Hide
			MerchantFrame.Hide = function(self, ...)
				suppressClose = true
				local result = origHide(self, ...)
				-- Release the flag after the OnHide cascade settles. The
				-- cascade completes in the same frame so anything past 0
				-- works; 0.1s is conservative and means the user's manual
				-- bag toggle keypress arriving immediately after vendor
				-- close still goes through.
				AfterDelay(0.1, function() suppressClose = false end)
				return result
			end
		end

		AfterDelay(2, function()
			CreateElvUIBagButton()
			-- Show the welcome popup unless the user clicked
			-- "Don't show this again" on a previous login.
			if not (_G.AutoDeleteDB and _G.AutoDeleteDB.welcomeDismissed) then
				ShowWelcomePopup()
			end
			-- One-shot scan: detect items present on more than one list
			-- (Delete + Sell, Delete + Keep, Sell + Keep). The add-time
			-- conflict check prevents new ones, but imports, manual text
			-- edits, or older saves can leave overlaps. We warn the user
			-- in chat and direct them to /del clean.
			local p = cachedProfile
			if p then
				local function buildKeySet(text)
					local set = {}
					for line in string.gmatch(text or "", "[^\r\n]+") do
						local raw = Trim(line)
						if raw ~= "" then set[raw] = true end
					end
					return set
				end
				local delSet  = buildKeySet(p.listText)
				local sellSet = buildKeySet(p.sellListText)
				local keepSet = buildKeySet(p.whitelistText)
				local conflicts = 0
				for k in pairs(delSet)  do if sellSet[k] then conflicts = conflicts + 1 end end
				for k in pairs(delSet)  do if keepSet[k] then conflicts = conflicts + 1 end end
				for k in pairs(sellSet) do if keepSet[k] then conflicts = conflicts + 1 end end
				if conflicts > 0 then
					print("|cffff4444[AutoDelete]|r Warning: " .. conflicts ..
						" item(s) appear on more than one list. Run |cff00ff00/del clean|r to resolve.")
				end
			end
		end)
		return
	end
	if event == "MERCHANT_SHOW" then
		RefreshCachedProfile()
		lastMerchantName = UnitName("npc") or ""
		sellSessionCount = 0
		sellSessionCopper = 0
		sellDryTicks = 0
		-- Snapshot bags so the UseContainerItem hook can identify what the
		-- player just sold (the slot is empty by the time the hook fires).
		SnapshotAllBags()
		-- Sample inventory worth BEFORE selling (otherwise we'd always sample
		-- post-sell bags, underselling the average).
		SampleInventoryWorth()
		-- Master toggle gate: when AutoDelete is disabled the addon must
		-- not perform ANY action, including auto-repair or auto-sell. Bag
		-- sampling and tracking still run because they're passive.
		if cachedProfile and cachedProfile.enabled then
			-- Repair first (before selling) so durability gold is accounted
			-- for separately from sell revenue in chat output.
			TryAutoRepair()
			SellItems()
		end
		return
	end
	if event == "MERCHANT_CLOSED" then
		if sellSessionCount > 0 then
			print("|cffff8000[AutoDelete]|r: Sold " .. sellSessionCount .. " item(s) for " .. FormatMoney(sellSessionCopper))
			sellSessionCount = 0
			sellSessionCopper = 0
			sellDryTicks = 0
		end
		-- Summon Greedy Scavenger after closing the Goblin Merchant window.
		-- Gated by summonScavenger (master) AND summonAfterClose (this-moment subflag).
		-- If summonOnlyInCombat is set, the player must be in combat at THIS
		-- moment for the summon to fire.
		if cachedProfile and cachedProfile.summonScavenger and cachedProfile.summonAfterClose then
			local combatOk = (not cachedProfile.summonOnlyInCombat) or (UnitAffectingCombat and UnitAffectingCombat("player"))
			if combatOk then
				local merchant = string.lower(lastMerchantName or "")
				if string.find(merchant, "goblin merchant") then
					DelayedSummon(1.5)
				end
			end
		end
		lastMerchantName = nil
		return
	end
	-- BAG_UPDATE / BAG_UPDATE_DELAYED
	RefreshCachedProfile()
	RequestScan()
end)

scanner:SetScript("OnUpdate", function(self, elapsed)
	if not cachedProfile or not cachedProfile.enabled then return end
	local now = GetTime()
	if now >= nextPeriodicAt then
		nextPeriodicAt = now + periodicInterval
		scanRequested = true
	end
	if scanRequested and now >= nextScanAt then
		scanRequested = false
		local interval = (cachedProfile.scanInterval and cachedProfile.scanInterval >= 0.5) and cachedProfile.scanInterval or 0.5
		nextScanAt = now + interval
		DeleteItems()
		if MerchantFrame and MerchantFrame:IsShown() then SellItems(true) end
	end
end)

-- ============================================================================
-- Companion Watcher
-- ============================================================================
-- Three behaviors layered on the Summon Scavenger feature:
--   (1) Mount-aware: dismiss the active companion when the player mounts. On
--       dismount, re-summon the scavenger only if summonScavenger is still
--       enabled AND at least one scav sub-toggle (afterSell/afterClose) is on.
--   (2) Stuck detection (summoned-flag only, 3.3.5 has no distance API):
--       if the last pet we summoned stops being marked 'summoned' unexpectedly
--       (e.g. died, despawned), re-summon it. Applies to BOTH Scavenger and
--       Goblin Merchant while they're the active tracked companion.
--   (3) Bag-full auto-summon: when bags hit 0 free slots AND the feature
--       toggle is on, summon Goblin Merchant. Fires once per fill edge; only
--       re-arms after the user frees a slot or the watcher is reset.
--
-- All three features short-circuit if the Summon Scavenger master toggle is
-- off, so they never run unexpectedly for users who opt out.

-- Which companion we're currently tracking for stuck detection.
-- Values: "scavenger" | "merchant" | nil (none)
local activeTracked       = nil

-- Mount state we last saw, so we detect edges (mounting / dismounting).
local lastMountState      = nil

-- If the player was on a companion when they mounted, we store which one here
-- so we know what to re-summon on dismount.
local dismissedDueToMount = nil

-- True when bags are currently full. Flips back to false once any slot frees
-- up, which re-arms the bag-full trigger.
local bagsFullArmed       = true   -- true = next 'full' will fire
local bagsFullSince       = nil    -- GetTime() when bags first became full; reset when a slot frees

-- Bag-full auto-summon debounce window. Bags must stay at zero free slots
-- for this many seconds continuously before the Goblin Merchant is summoned.
-- Prevents transient fills (loot a stack that auto-merges with an existing
-- stack a moment later) from triggering a stray summon.
local BAGS_FULL_DELAY = 1.5

-- ============================================================================
-- User-dismiss vs leash classification (timing-based)
-- ============================================================================
-- Problem: when our pet's `summoned` flag flips to false, we can't tell from
-- the API whether the user right-clicked the portrait to dismiss it, or
-- whether it fell behind / despawned / died. Naively re-summoning every time
-- ignores user intent (they dismissed for a reason).
--
-- Approach: timing. When WE summon the pet, record GetTime() in
-- lastSummonAt. If the pet flips to "not summoned" within USER_DISMISS_WINDOW
-- of that summon, classify as "user dismissed" - they clicked it off
-- intentionally, fast and deliberate. Suppress restore for USER_DISMISS_GRACE.
-- A real range-leash takes seconds to minutes of travel before the server
-- despawns the pet, so the timing distinguishes cleanly.
--
-- This is more reliable than EbonClearance's GetUnitSpeed-at-transition
-- check, which misclassifies stationary casts as user-dismisses.
local lastSummonAt        = 0
local userDismissUntil    = 0
local USER_DISMISS_WINDOW = 5.0    -- seconds after our summon during which "gone" = user dismissed
local USER_DISMISS_GRACE  = 30.0   -- seconds to suppress restore after a user dismiss

-- COMPANION_UPDATE event debounce. The event can fire multiple times in quick
-- succession during a state transition; we only want to process the latest.
local lastCompanionUpdate = 0
local COMPANION_DEBOUNCE  = 0.5

-- ============================================================================
-- Loot-event-based stuck detection
-- ============================================================================
-- The CRITTER `summoned` flag is unreliable on PE for "pet fell behind" -
-- the API claims summoned even when the pet is geographically lost. And
-- 3.3.5 has no UnitPosition API to measure player distance from a summon
-- point. So we detect the actual symptom rather than any proxy for it:
--
--   "The scavenger has stopped doing its job."
--
-- The scavenger's job is to pick up gray items and money near the player
-- after kills. Every successful pickup, the scav says one of its monster
-- chat lines (the spam suppressed by hideGreedySpam). We track the latest
-- timestamp of any scav monster chat line. We also track when the player
-- last looted a corpse via LOOT_CLOSED.
--
-- Stuck-detection rule: if the player has looted at least
-- LOOT_STUCK_PLAYER_MIN corpses within LOOT_STUCK_WINDOW seconds AND the
-- scavenger hasn't said anything in the same window, the scav is
-- geographically lost. Re-summon.
--
-- This detects the actual symptom rather than guessing via position or
-- speed. Bonus: it costs almost nothing - we already filter every scav
-- chat line, so the timestamp update is one assignment per existing event.
local lastScavLootChatAt    = 0
-- Ring buffer of player loot timestamps (GetTime() values). Automatically
-- pruned in OnUpdate to entries within LOOT_STUCK_WINDOW (60s). Cleared on
-- scavenger re-summon. Maximum realistic size: ~10-15 entries (looting every
-- 4-6s for a full minute). No manual bounding needed.
local LOOT_STUCK_WINDOW     = 60   -- seconds: window over which we evaluate
local LOOT_STUCK_PLAYER_MIN = 2    -- min player loots in the window before we judge
local recentPlayerLootTimes = {}

-- Simple periodic ticker: checks mount state changes and companion summoned
-- flag every ~1s. Not tied to scanInterval because the scanner is gated on
-- cachedProfile.enabled; this watcher must also run when Master is off but
-- scavenger features are used (rare, but correct).
local companionWatcher = CreateFrame("Frame")
local watchAccum = 0
local WATCH_INTERVAL = 1.0

local function IsPlayerMountedOrFlying()
	if IsFlying and IsFlying() then return true end
	if IsMounted and IsMounted() then return true end
	return false
end

local function ComputeTotalFreeSlots()
	local free = 0
	for bag = 0, 4 do
		local f = GetContainerNumFreeSlots and GetContainerNumFreeSlots(bag) or 0
		if f then free = free + f end
	end
	return free
end

local function AnyScavSubToggleOn(p)
	if not p then return false end
	return (p.summonAfterSell or p.summonAfterClose) and true or false
end

companionWatcher:SetScript("OnUpdate", function(_, elapsed)
	watchAccum = watchAccum + elapsed
	if watchAccum < WATCH_INTERVAL then return end
	watchAccum = 0

	local p = cachedProfile
	if not p then return end

	-- Master toggle gate: AutoDelete must not summon, dismiss, or re-summon
	-- pets when disabled. The companion-tracking features all require both
	-- the master toggle AND the per-feature toggle to be on.
	if not p.enabled then return end

	-- Master gate: all three features require summonScavenger enabled.
	if not p.summonScavenger then
		return
	end

	-- Combat gate. When summonOnlyInCombat is enabled, ALL automatic summon
	-- paths (mount/dismount restore, stuck-detection re-summon, bag-full
	-- merchant trigger) only fire while the player is in combat. Manual
	-- /del commands and after-sell/after-close summons (handled in their
	-- own code paths) check this flag separately.
	local combatOk = (not p.summonOnlyInCombat) or (UnitAffectingCombat and UnitAffectingCombat("player"))

	-- (0) Loot-based stuck detection (only for scavenger; merchant doesn't loot).
	-- We don't run this every tick - only when there's something to evaluate.
	-- The check is cheap: walk the ring buffer to count recent loots, compare
	-- to the scav's last chat timestamp.
	if activeTracked == "scavenger" and combatOk and not IsPlayerMountedOrFlying() then
		local nowLoot = GetTime()

		-- Prune the player-loot ring buffer to entries inside the window.
		local pruned = {}
		for _, t in ipairs(recentPlayerLootTimes) do
			if (nowLoot - t) <= LOOT_STUCK_WINDOW then
				table.insert(pruned, t)
			end
		end
		recentPlayerLootTimes = pruned

		-- If we've had enough player loots in the window AND the scav
		-- hasn't said anything since the OLDEST of those loots, the scav is
		-- almost certainly geographically lost.
		if #recentPlayerLootTimes >= LOOT_STUCK_PLAYER_MIN then
			local oldestLoot = recentPlayerLootTimes[1]
			if lastScavLootChatAt < oldestLoot then
				-- Re-summon. The summon helper handles state updates.
				if DismissCompanion then DismissCompanion("CRITTER") end
				AfterDelay(0.4, function() SummonGreedyScavenger(true) end)
				-- Clear the ring so we don't immediately re-fire.
				recentPlayerLootTimes = {}
			end
		end
	end

	-- (1) Mount-aware dismiss / re-summon.
	local nowMounted = IsPlayerMountedOrFlying()
	if lastMountState == nil then lastMountState = nowMounted end
	if nowMounted ~= lastMountState then
		lastMountState = nowMounted
		if nowMounted then
			-- Mounting. Dismiss whichever pet we were tracking, and remember
			-- so dismount can restore it (scav only - merchant gets summoned
			-- via bag-full trigger, not mount flow).
			local scavIdx, scavUp = FindCompanionByName("greedy scavenger")
			local merchIdx, merchUp = FindCompanionByName("goblin merchant")
			if scavUp or merchUp then
				if DismissCompanion then DismissCompanion("CRITTER") end
				dismissedDueToMount = scavUp and "scavenger" or nil
				-- If only merchant was up, we don't auto-revive it on dismount.
			end
		else
			-- Dismounting. Re-summon scavenger if we dismissed it AND the user
			-- still has the master toggle on AND a sub-toggle that would use
			-- it AND the combat gate (if enabled) is satisfied.
			if dismissedDueToMount == "scavenger" and AnyScavSubToggleOn(p) and combatOk then
				DelayedSummon(1.5)
				activeTracked = "scavenger"
			end
			dismissedDueToMount = nil
		end
	end

	-- Don't run stuck-detection or bag-full while mounted. WoW dismisses pets
	-- on mount natively and we just dismissed ours above.
	if nowMounted then return end

	-- (2) Stuck detection (summoned-flag based).
	-- If we were tracking a pet and it's no longer summoned, decide whether
	-- to re-summon. We DON'T re-summon if a DIFFERENT companion is currently
	-- up - that means the user (or our own merchant-summon) deliberately
	-- swapped pets, and forcing the old one back would fight that intent.
	local function IsAnyOtherCompanionUp(currentName)
		local n = GetNumCompanions("CRITTER")
		for i = 1, n do
			local _, cName, _, _, summoned = GetCompanionInfo("CRITTER", i)
			if (summoned == 1 or summoned == true) and cName then
				-- Don't count the one we were tracking
				local lower = string.lower(cName)
				if not string.find(lower, currentName) then
					return true
				end
			end
		end
		return false
	end

	-- Respect user-dismiss grace window. If the reactive event handler (or
	-- the previous polling tick) classified a recent transition as a user
	-- dismiss, skip the stuck-detection block so we don't re-summon over
	-- their intent.
	local pollNow = GetTime()
	local inUserDismissGrace = pollNow < userDismissUntil

	if activeTracked == "scavenger" and not inUserDismissGrace then
		local _, isUp = FindCompanionById(SCAVENGER_CREATURE_ID, "greedy scavenger")
		if not isUp then
			-- Did the user swap to a different pet? If so, stop tracking
			-- the scavenger and don't re-summon over their choice.
			if IsAnyOtherCompanionUp("greedy scavenger") then
				activeTracked = nil
			elseif (pollNow - lastSummonAt) < USER_DISMISS_WINDOW then
				-- Fast despawn after our summon = user dismissed it.
				userDismissUntil = pollNow + USER_DISMISS_GRACE
				activeTracked = nil
			elseif AnyScavSubToggleOn(p) and combatOk then
				-- Slow despawn = leash/death/zone. Re-summon fast.
				DelayedSummon(0.3)
			else
				activeTracked = nil
			end
		end
	elseif activeTracked == "merchant" and not inUserDismissGrace then
		local _, isUp = FindCompanionById(MERCHANT_CREATURE_ID, "goblin merchant")
		if not isUp then
			-- Same logic: if a different pet is up, user swapped, stop tracking.
			if IsAnyOtherCompanionUp("goblin merchant") then
				activeTracked = nil
			elseif (pollNow - lastSummonAt) < USER_DISMISS_WINDOW then
				userDismissUntil = pollNow + USER_DISMISS_GRACE
				activeTracked = nil
			elseif p.summonMerchantWhenBagsFull and ComputeTotalFreeSlots() == 0 and combatOk then
				SummonGoblinMerchant()
				-- Re-arm the bag-full timer state since we just resummoned.
				bagsFullArmed = false
				bagsFullSince = nil
			else
				activeTracked = nil
				-- Merchant despawned while bags are still full (zoned, died,
				-- etc.). Re-arm so the periodic bag-full check can fire a
				-- fresh summon on the next BAGS_FULL_DELAY tick.
				if p.summonMerchantWhenBagsFull and ComputeTotalFreeSlots() == 0 then
					bagsFullArmed = true
					bagsFullSince = nil
				end
			end
		end
	end

	-- (3) Bag-full auto-summon. See BAGS_FULL_DELAY above for debounce rationale.
	if p.summonMerchantWhenBagsFull then
		local free = ComputeTotalFreeSlots()
		if free == 0 then
			if bagsFullArmed and combatOk then
				-- Start the timer if it isn't already running.
				if not bagsFullSince then
					bagsFullSince = GetTime()
				elseif (GetTime() - bagsFullSince) >= BAGS_FULL_DELAY then
					-- Bags have stayed full long enough; fire.
					bagsFullArmed = false
					bagsFullSince = nil
					SummonGoblinMerchant()
					activeTracked = "merchant"
				end
			end
		else
			-- A slot freed up: reset the timer and re-arm for next time.
			bagsFullSince = nil
			bagsFullArmed = true
		end
	end
end)

-- Exposed so SummonGreedyScavenger / SummonGoblinMerchant can mark the
-- active tracked pet without tight coupling. Set via the helpers below.
_G.AutoDelete_SetActiveTrackedPet = function(which)
	activeTracked = which
end

-- Read-only accessor used by /del pos debug command.
_G.AutoDelete_GetActiveTrackedPet = function() return activeTracked end

-- Exposed so the Summon helpers can record the moment of summon. Used by
-- the user-dismiss-vs-leash classifier: if the pet goes "not summoned"
-- within USER_DISMISS_WINDOW of this timestamp, treat as user dismiss.
_G.AutoDelete_RecordSummonAt = function(t)
	lastSummonAt = t or GetTime()
end

-- Exposed so the GreedyChatFilter can record the scavenger's "alive and
-- looting" timestamp without forward-referencing the local variable.
_G.AutoDelete_RecordScavLootChat = function(t)
	lastScavLootChatAt = t or GetTime()
end

_G.AutoDelete_GetScavLootChatAt = function() return lastScavLootChatAt end

-- ============================================================================
-- Reactive companion event handler
-- ============================================================================
-- COMPANION_UPDATE fires when companion state changes (summon, dismiss, list
-- update). It's faster than the 1s polling tick - typically reacts within a
-- single frame. The polling tick is kept as a safety net in case
-- COMPANION_UPDATE doesn't fire reliably for range-based despawns on this
-- server build.
--
-- Logic:
--   1. Debounce against event storms (multiple fires within COMPANION_DEBOUNCE)
--   2. If we have an active tracked pet AND it's now "not summoned":
--      a. Within USER_DISMISS_WINDOW of our last summon -> user dismissed,
--         set userDismissUntil to suppress restore for USER_DISMISS_GRACE
--      b. Outside that window -> leash/despawn/death, re-summon (subject to
--         combat gate, master toggle, and the same checks as the polling tick)
local companionEventFrame = CreateFrame("Frame")
companionEventFrame:RegisterEvent("COMPANION_UPDATE")
companionEventFrame:RegisterEvent("LOOT_CLOSED")
companionEventFrame:SetScript("OnEvent", function(_, event)
	-- LOOT_CLOSED: player finished looting a corpse. Push the timestamp so
	-- the loot-based stuck detector can correlate against scav chat lines.
	if event == "LOOT_CLOSED" then
		table.insert(recentPlayerLootTimes, GetTime())
		return
	end

	if event ~= "COMPANION_UPDATE" then return end

	-- Debounce: COMPANION_UPDATE can fire several times for a single state
	-- change. Process at most once per COMPANION_DEBOUNCE seconds.
	local now = GetTime()
	if (now - lastCompanionUpdate) < COMPANION_DEBOUNCE then return end
	lastCompanionUpdate = now

	local p = cachedProfile
	if not p or not p.enabled or not p.summonScavenger then return end

	-- AUTO-ATTACH: if the user just summoned a scav or merchant via the
	-- portrait/macro and we have no active tracked pet, attach. Without this
	-- the entire stuck-detection pipeline silently does nothing for
	-- user-initiated summons.
	if not activeTracked then
		local _, scavUp = FindCompanionById(SCAVENGER_CREATURE_ID, "greedy scavenger")
		local _, merchUp = FindCompanionById(MERCHANT_CREATURE_ID, "goblin merchant")
		if scavUp then
			activeTracked = "scavenger"
			lastSummonAt = now   -- treat as if we just summoned
		elseif merchUp then
			activeTracked = "merchant"
			lastSummonAt = now
		end
	end

	if not activeTracked then return end

	-- Combat gate (when summonOnlyInCombat is on, all auto-summons require
	-- the player to be in combat).
	local combatOk = (not p.summonOnlyInCombat) or (UnitAffectingCombat and UnitAffectingCombat("player"))

	-- Suppress while mounted - WoW handles companion despawn natively.
	if IsPlayerMountedOrFlying() then return end

	-- Suppress if we recently classified a user dismiss.
	if now < userDismissUntil then return end

	if activeTracked == "scavenger" then
		local _, isUp = FindCompanionById(SCAVENGER_CREATURE_ID, "greedy scavenger")
		if not isUp then
			-- Classify: fast (within window) = user dismiss, slow = leash.
			if (now - lastSummonAt) < USER_DISMISS_WINDOW then
				userDismissUntil = now + USER_DISMISS_GRACE
				activeTracked = nil
			elseif AnyScavSubToggleOn(p) and combatOk then
				DelayedSummon(0.3)  -- fast re-summon, pet is verifiably gone
			else
				activeTracked = nil
			end
		end
	elseif activeTracked == "merchant" then
		local _, isUp = FindCompanionById(MERCHANT_CREATURE_ID, "goblin merchant")
		if not isUp then
			if (now - lastSummonAt) < USER_DISMISS_WINDOW then
				userDismissUntil = now + USER_DISMISS_GRACE
				activeTracked = nil
			elseif p.summonMerchantWhenBagsFull and ComputeTotalFreeSlots() == 0 and combatOk then
				SummonGoblinMerchant()
				bagsFullArmed = false
				bagsFullSince = nil
			else
				activeTracked = nil
				-- Keep bag-full re-arm semantics consistent with the polling tick:
				-- merchant despawned while bags still full -> re-arm.
				if p.summonMerchantWhenBagsFull and ComputeTotalFreeSlots() == 0 then
					bagsFullArmed = true
					bagsFullSince = nil
				end
			end
		end
	end
end)

-- ============================================================================
-- Slash Commands
-- ============================================================================
-- /del               -> toggle the options panel
-- /del clean         -> dedupe Delete and Sell lists (see ResolveEntryKey
--                       below for the matching rules)
-- /del sell          -> force a sell pass at the current vendor (NOT gated
--                       by master Enable; manual override)
-- /del setup         -> reopen the welcome popup (clears welcomeDismissed)
-- /autodelete        -> alias for /del

-- ----------------------------------------------------------------------------
-- /del clean - remove duplicate entries from Delete + Sell lists
-- ============================================================================
-- Rules:
--   * Within a single list: keep first occurrence, remove subsequent duplicates
--   * Across Delete + Sell lists: if an item appears on BOTH, remove from BOTH
--     (reported so the user can re-add to their preferred list)
--
-- Identity resolution: entries are either "item:N" or a plain name.
--   * "item:N" → resolved via GetItemInfo to normalized name key
--   * plain name → lower-cased and trimmed as the key
--   * Unresolvable "item:N" falls back to "id:N" so it still matches itself

local function ResolveEntryKey(rawLine)
	local entry = Trim(rawLine or "")
	if entry == "" then return nil, nil, nil end
	-- Strip comments
	entry = string.gsub(entry, "%s*#.*$", "")
	entry = Trim(entry)
	if entry == "" then return nil, nil, nil end

	local id = tonumber(string.match(entry, "^item:(%d+)"))
	if id then
		local name = GetItemInfo("item:" .. id)
		if name and name ~= "" then
			return "name:" .. string.lower(name), name, Trim(rawLine or "")
		end
		return "id:" .. id, "item:" .. id, Trim(rawLine or "")
	end
	return "name:" .. string.lower(entry), entry, Trim(rawLine or "")
end

local function CleanLists()
	local db = GetDB()
	local profile = GetActiveProfile(db)

	local function Parse(listText)
		local entries = {}
		for line in string.gmatch(listText or "", "[^\r\n]+") do
			local key, display, raw = ResolveEntryKey(line)
			if key then
				table.insert(entries, { key = key, display = display, raw = raw })
			end
		end
		return entries
	end

	local delEntries  = Parse(profile.listText)
	local sellEntries = Parse(profile.sellListText)
	local keepEntries = Parse(profile.whitelistText)

	-- 1. Dedupe within each list (first occurrence wins)
	local function DedupeWithin(entries)
		local seen, kept, dupes = {}, {}, {}
		for _, e in ipairs(entries) do
			if not seen[e.key] then
				seen[e.key] = true
				table.insert(kept, e)
			else
				table.insert(dupes, e.display)
			end
		end
		return kept, dupes
	end

	local keptDel,  internalDelDupes  = DedupeWithin(delEntries)
	local keptSell, internalSellDupes = DedupeWithin(sellEntries)
	local keptKeep, internalKeepDupes = DedupeWithin(keepEntries)

	-- 2a. Keep overrides Delete/Sell. Items on Keep AND Delete/Sell get
	-- removed from Delete/Sell (matches runtime semantics: Keep always wins).
	local keepKeys = {}
	for _, e in ipairs(keptKeep) do keepKeys[e.key] = true end

	local keepBlockedFromDel, keepBlockedFromSell = {}, {}
	local afterKeepDel, afterKeepSell = {}, {}
	for _, e in ipairs(keptDel) do
		if keepKeys[e.key] then
			table.insert(keepBlockedFromDel, e.display)
		else
			table.insert(afterKeepDel, e)
		end
	end
	for _, e in ipairs(keptSell) do
		if keepKeys[e.key] then
			table.insert(keepBlockedFromSell, e.display)
		else
			table.insert(afterKeepSell, e)
		end
	end

	-- 2b. Find Delete + Sell overlap. Both get removed (no winner; user
	-- re-adds to their preferred list manually).
	local sellKeys = {}
	for _, e in ipairs(afterKeepSell) do sellKeys[e.key] = true end

	local crossDupes, finalDel, finalSell = {}, {}, {}
	local crossKeys = {}
	for _, e in ipairs(afterKeepDel) do
		if sellKeys[e.key] then
			crossKeys[e.key] = true
			table.insert(crossDupes, e.display)
		else
			table.insert(finalDel, e.raw)
		end
	end
	for _, e in ipairs(afterKeepSell) do
		if not crossKeys[e.key] then
			table.insert(finalSell, e.raw)
		end
	end

	local finalKeep = {}
	for _, e in ipairs(keptKeep) do table.insert(finalKeep, e.raw) end

	-- Rewrite list text (preserve trailing newline if there were entries)
	profile.listText = table.concat(finalDel, "\n")
	if #finalDel > 0 then profile.listText = profile.listText .. "\n" end
	profile.sellListText = table.concat(finalSell, "\n")
	if #finalSell > 0 then profile.sellListText = profile.sellListText .. "\n" end
	profile.whitelistText = table.concat(finalKeep, "\n")
	if #finalKeep > 0 then profile.whitelistText = profile.whitelistText .. "\n" end

	RefreshCachedProfile()

	-- Report
	print("|cffff8000[AutoDelete]|r Clean complete.")
	if #internalDelDupes > 0 then
		print("  |cff999999Removed " .. #internalDelDupes .. " internal duplicate(s) in Delete list:|r " .. table.concat(internalDelDupes, ", "))
	end
	if #internalSellDupes > 0 then
		print("  |cff999999Removed " .. #internalSellDupes .. " internal duplicate(s) in Sell list:|r " .. table.concat(internalSellDupes, ", "))
	end
	if #internalKeepDupes > 0 then
		print("  |cff999999Removed " .. #internalKeepDupes .. " internal duplicate(s) in Keep list:|r " .. table.concat(internalKeepDupes, ", "))
	end
	if #keepBlockedFromDel > 0 then
		print("|cff80c0ff  Removed from Delete (already on Keep, Keep wins):|r " .. table.concat(keepBlockedFromDel, ", "))
	end
	if #keepBlockedFromSell > 0 then
		print("|cff80c0ff  Removed from Sell (already on Keep, Keep wins):|r " .. table.concat(keepBlockedFromSell, ", "))
	end
	if #crossDupes > 0 then
		print("|cffff4444  Removed from BOTH Delete and Sell (appeared in each):|r " .. table.concat(crossDupes, ", "))
		print("  |cffaaaaaaRe-add these manually to your preferred list.|r")
	end
	if #internalDelDupes == 0 and #internalSellDupes == 0 and #internalKeepDupes == 0
		and #keepBlockedFromDel == 0 and #keepBlockedFromSell == 0 and #crossDupes == 0 then
		print("  |cff999999No duplicates found.|r")
	end

	-- Refresh UI if open
	local panel = _G.AutoDeleteOptionsPanel
	if panel and panel._built and panel:IsVisible() then
		panel:Refresh()
	end
end

-- ============================================================================
-- Profile Import - merge the 3 lists from another character's profile
-- ============================================================================
-- The three list keys in a profile, with their display labels. Order matters
-- for the popup radio buttons (D / S / K).
local IMPORT_LIST_KEYS = { "listText", "sellListText", "whitelistText" }
local IMPORT_LIST_DISPLAY = {
	listText       = "Delete",
	sellListText   = "Sell",
	whitelistText  = "Keep",
}
local IMPORT_DISPLAY_TO_KEY = {
	Delete = "listText",
	Sell   = "sellListText",
	Keep   = "whitelistText",
}

-- Walk a list text and build a map: canonicalKey → rawLine.
-- First occurrence wins (matches the dedupe behavior of /del clean).
local function BuildKeyMap(listText)
	local map = {}
	for line in string.gmatch(listText or "", "[^\r\n]+") do
		local key, _, raw = ResolveEntryKey(line)
		if key and not map[key] then
			map[key] = raw
		end
	end
	return map
end

-- Remove all lines matching a given canonical key from a list text.
-- Returns the rewritten text.
local function RemoveEntriesWithKey(listText, keyToRemove)
	local out = {}
	for line in string.gmatch(listText or "", "[^\r\n]+") do
		local k = ResolveEntryKey(line)
		if k ~= keyToRemove then
			table.insert(out, Trim(line))
		end
	end
	local rebuilt = table.concat(out, "\n")
	if #out > 0 then rebuilt = rebuilt .. "\n" end
	return rebuilt
end

-- Append a single raw entry to a list text (idempotent-ish: appends if the
-- canonical key isn't already present).
local function AppendEntry(listText, rawEntry)
	local key = ResolveEntryKey(rawEntry)
	if not key then return listText or "" end
	local existing = BuildKeyMap(listText)
	if existing[key] then return listText or "" end  -- already present
	local base = listText or ""
	if base ~= "" and not string.match(base, "\n$") then base = base .. "\n" end
	return base .. Trim(rawEntry) .. "\n"
end

-- PreviewImport: detects what would change if we imported the source profile's
-- 3 lists into the current character's profile. Makes NO changes.
-- Returns:
--   {
--     additions = { {key, display, raw, targetList, targetListDisplay}, ... }
--     conflicts = { {key, display, raw, sourceList, sourceListDisplay,
--                    currentList, currentListDisplay}, ... }
--   }
-- Returns nil, reason on error.
local function PreviewImport(sourceCharKey)
	if not sourceCharKey or sourceCharKey == "" then
		return nil, "no source selected"
	end
	local db = GetDB()
	local sourceProfile = db.profiles and db.profiles[sourceCharKey]
	if not sourceProfile then return nil, "source profile not found" end
	local currentProfile = GetActiveProfile(db)
	if sourceCharKey == GetCharKey() then
		return nil, "source is the current character"
	end

	-- Build canonical-key maps for each of the current character's lists,
	-- so we can look up "is this item somewhere in my current profile?"
	local currentMaps = {}
	for _, lk in ipairs(IMPORT_LIST_KEYS) do
		currentMaps[lk] = BuildKeyMap(currentProfile[lk])
	end
	-- Reverse map: key → which list it's on (if any) in the current profile
	local currentKeyList = {}
	for _, lk in ipairs(IMPORT_LIST_KEYS) do
		for k in pairs(currentMaps[lk]) do
			currentKeyList[k] = lk
		end
	end

	local additions, conflicts = {}, {}
	local seenInThisImport = {}  -- guard against dupes across source's own lists

	for _, srcListKey in ipairs(IMPORT_LIST_KEYS) do
		local srcText = sourceProfile[srcListKey]
		for line in string.gmatch(srcText or "", "[^\r\n]+") do
			local key, display, raw = ResolveEntryKey(line)
			if key and not seenInThisImport[key] then
				seenInThisImport[key] = true
				local curList = currentKeyList[key]
				if not curList then
					-- Not in current at all → addition
					table.insert(additions, {
						key = key, display = display, raw = raw,
						targetList = srcListKey,
						targetListDisplay = IMPORT_LIST_DISPLAY[srcListKey],
					})
				elseif curList ~= srcListKey then
					-- In current on a DIFFERENT list → conflict
					table.insert(conflicts, {
						key = key, display = display, raw = raw,
						sourceList = srcListKey,
						sourceListDisplay = IMPORT_LIST_DISPLAY[srcListKey],
						currentList = curList,
						currentListDisplay = IMPORT_LIST_DISPLAY[curList],
					})
				end
				-- else: same list on both → skip (no duplicate, no change)
			end
		end
	end

	return { additions = additions, conflicts = conflicts }
end

-- ApplyImport: performs the merge. resolutions is a table keyed by canonical
-- key → chosen list display name ("Delete"/"Sell"/"Keep"). Keys not present
-- in resolutions default to the source's list (i.e., "take source").
local function ApplyImport(sourceCharKey, resolutions)
	local preview, reason = PreviewImport(sourceCharKey)
	if not preview then return false, reason end

	local db = GetDB()
	local profile = GetActiveProfile(db)
	resolutions = resolutions or {}

	local addedByList = { Delete = 0, Sell = 0, Keep = 0 }
	local movedByList = { Delete = 0, Sell = 0, Keep = 0 }

	-- Apply additions (no conflict, always add to source's list).
	for _, add in ipairs(preview.additions) do
		profile[add.targetList] = AppendEntry(profile[add.targetList], add.raw)
		addedByList[add.targetListDisplay] = (addedByList[add.targetListDisplay] or 0) + 1
	end

	-- Apply conflict resolutions.
	for _, c in ipairs(preview.conflicts) do
		local chosen = resolutions[c.key] or c.sourceListDisplay
		if chosen ~= c.currentListDisplay then
			-- Remove from current location, add to chosen.
			profile[c.currentList] = RemoveEntriesWithKey(profile[c.currentList], c.key)
			local chosenKey = IMPORT_DISPLAY_TO_KEY[chosen]
			if chosenKey then
				profile[chosenKey] = AppendEntry(profile[chosenKey], c.raw)
				movedByList[chosen] = (movedByList[chosen] or 0) + 1
			end
		end
		-- else: keep where it is, no change
	end

	if RefreshCachedProfile then RefreshCachedProfile() end

	-- Summary report
	print(string.format("|cffff8000[AutoDelete]|r Import from %s complete.", sourceCharKey))
	local addParts = {}
	for _, lbl in ipairs({"Delete","Sell","Keep"}) do
		if addedByList[lbl] > 0 then table.insert(addParts, addedByList[lbl] .. " to " .. lbl) end
	end
	if #addParts > 0 then
		print("  |cff999999Added:|r " .. table.concat(addParts, ", "))
	end
	local moveParts = {}
	for _, lbl in ipairs({"Delete","Sell","Keep"}) do
		if movedByList[lbl] > 0 then table.insert(moveParts, movedByList[lbl] .. " to " .. lbl) end
	end
	if #moveParts > 0 then
		print("  |cff999999Moved via conflict resolution:|r " .. table.concat(moveParts, ", "))
	end
	if #addParts == 0 and #moveParts == 0 then
		print("  |cff999999No changes needed. Lists already match.|r")
	end

	-- Refresh UI if open
	local panel = _G.AutoDeleteOptionsPanel
	if panel and panel._built and panel:IsVisible() then
		panel:Refresh()
	end
	return true
end

-- Expose import API alongside existing profile helpers.
_G.AutoDelete_Profiles.PreviewImport = PreviewImport
_G.AutoDelete_Profiles.ApplyImport = ApplyImport

-- ============================================================================
-- Modifier-click handlers (shift = search fill, alt = add to Keep)
-- ============================================================================
-- Shift-click and alt-click do different things:
--
--   SHIFT-CLICK is the search-box-fill shortcut. When our settings panel is
--   visible, shift-clicking an item link (chat, bag, anywhere) fills the
--   panel's search box with the item name. We do NOT intercept any default
--   shift-click behavior (stack split, AH search, link-insert-into-chat,
--   bank/guild bank moves). Just observe the click via hooksecurefunc and
--   update the search box. Returns nothing, eats nothing.
--
--   ALT-CLICK is the Keep-list shortcut. Holding alt and clicking an item
--   link adds it to the Keep list. Alt-click has no default WoW behavior
--   for items in 3.3.5, so we can intercept it cleanly without competing
--   with anything. We do skip on AH/bank/guild-bank/vendor/tradeskill/craft
--   windows out of caution (other addons may bind alt-click for compare
--   tooltip, drop, etc.) and on stackable items.
--
-- Why this split: shift-click is heavily overloaded by Blizzard. Every new
-- context we discover (stack split, AH, bank, ...) is another whack-a-mole
-- to suppress. Alt-click has no such conflicts, so the destructive feature
-- (adding to a managed list) lives there.

-- Shared skip-frame check used by both shift and alt paths. Returns true if
-- we should bail (some context is open that uses modifier-click for its own
-- purposes). Shift's search-fill is non-destructive, so technically it's
-- safe to run anywhere - we still skip in these contexts to keep the
-- behavior of both modifiers consistent and predictable.
local function ShouldSkipContext()
	local skipFrames = {
		{ frame = AuctionFrame,    name = "Auction House" },
		{ frame = BankFrame,       name = "Bank" },
		{ frame = GuildBankFrame,  name = "Guild Bank" },
		{ frame = MerchantFrame,   name = "Vendor" },
		{ frame = TradeSkillFrame, name = "Tradeskill" },
		{ frame = CraftFrame,      name = "Craft" },
	}
	for _, f in ipairs(skipFrames) do
		if f.frame and f.frame:IsShown() then
			if _G.AutoDelete_DebugSell then
				print("|cffff8000[AutoDelete DEBUG]|r " .. f.name .. " open, skipping")
			end
			return true
		end
	end
	return false
end

-- ----------------------------------------------------------------------------
-- SHIFT-CLICK: search-box fill only. Non-destructive, runs alongside default.
-- ----------------------------------------------------------------------------
local function HandleShiftClickFill(link)
	if not link then return end
	local panel = _G.AutoDeleteOptionsPanel
	if not panel or not panel._built or not panel:IsVisible() then return end
	if ShouldSkipContext() then return end
	local name = GetItemInfo(link)
	if not name or name == "" then return end
	if panel._searchBox and panel._searchBox.SetText then
		panel._searchBox:SetText(name)
		panel._searchBox:SetCursorPosition(#name)
		if panel._searchPlaceholder then panel._searchPlaceholder:Hide() end
		panel._filterText = name
		if panel.Refresh then panel:Refresh() end
	end
end

-- ----------------------------------------------------------------------------
-- ALT-CLICK: add to Keep list.
-- ----------------------------------------------------------------------------
local lastHandledItemId = nil
local lastHandledAt = 0

-- Returns true if the click was consumed (for ChatEdit_InsertLink to know
-- whether to suppress its default chat-insert behavior).
local function HandleAltClickKeep(link, source)
	if not link then return false end
	if _G.AutoDelete_DebugSell then
		print("|cffff8000[AutoDelete DEBUG]|r alt-click via " .. source .. ". link=" .. tostring(link))
	end

	local itemId = GetItemIDFromLink(link)
	if _G.AutoDelete_DebugSell then
		print("|cffff8000[AutoDelete DEBUG]|r extracted itemId=" .. tostring(itemId))
	end
	if not itemId then return false end

	if ShouldSkipContext() then return false end

	-- Skip stackable items. Even though alt-click has no default stack-split
	-- behavior, stackables (mats, consumables, currency) don't need Keep-list
	-- protection - the auto-rules only target gear quality.
	local _, _, _, _, _, _, _, maxStack = GetItemInfo(link)
	if maxStack and maxStack > 1 then
		if _G.AutoDelete_DebugSell then
			print("|cffff8000[AutoDelete DEBUG]|r stackable item (maxStack=" .. tostring(maxStack) .. "), skipping")
		end
		return false
	end

	-- Dedupe: a single alt-click in chat fires both ChatEdit_InsertLink AND
	-- HandleModifiedItemClick, which would double-print "added/already in
	-- list". Suppress the second invocation within a 0.5s window.
	local now = GetTime()
	if lastHandledItemId == itemId and (now - lastHandledAt) < 0.5 then
		if _G.AutoDelete_DebugSell then
			print("|cffff8000[AutoDelete DEBUG]|r duplicate within window, skipping")
		end
		-- Still return true on the chat-link path so we don't double-insert
		-- into the chat editbox.
		return source == "ChatEdit_InsertLink"
	end
	lastHandledItemId = itemId
	lastHandledAt = now

	-- If an editbox is focused, don't insert text or add to Keep - let the
	-- default behavior take precedence. (Alt-click has no default behavior
	-- but a focused editbox usually means the user is mid-type, so we bail
	-- to be safe.)
	local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
	if focus then return false end

	AddItemToList("whitelistText", itemId)
	return true   -- eat the chat-link insert if that's how we got here
end

-- ----------------------------------------------------------------------------
-- Hook installation
-- ----------------------------------------------------------------------------
-- Shift-click (search fill) is hooked via hooksecurefunc on
-- HandleModifiedItemClick. We also hook ChatEdit_InsertLink to catch the
-- chat-link path. Both are read-only observations - they never return true,
-- so default WoW behavior continues uninterrupted.
hooksecurefunc("HandleModifiedItemClick", function(link)
	if IsShiftKeyDown() then HandleShiftClickFill(link) end
	if IsAltKeyDown() then HandleAltClickKeep(link, "HandleModifiedItemClick") end
end)

-- Alt-click on a chat hyperlink: ChatEdit_InsertLink is the function called
-- when the user holds a modifier and clicks a chat link. We intercept on
-- alt to suppress the default behavior (insert link text into chat editbox)
-- when we're consuming the click for Keep-add. Shift-click on chat links
-- still goes through to the default (insert into chat) - we DO call the
-- search-fill path on shift but never consume the click.
local AutoDelete_Original_ChatEdit_InsertLink = ChatEdit_InsertLink
ChatEdit_InsertLink = function(link)
	-- Shift-click: just observe, never consume.
	if IsShiftKeyDown() then
		HandleShiftClickFill(link)
		return AutoDelete_Original_ChatEdit_InsertLink(link)
	end
	-- Alt-click: try to consume.
	if IsAltKeyDown() and HandleAltClickKeep(link, "ChatEdit_InsertLink") then
		return true
	end
	return AutoDelete_Original_ChatEdit_InsertLink(link)
end

SLASH_AUTODELETE1 = "/del"
SLASH_AUTODELETE2 = "/autodelete"
SlashCmdList["AUTODELETE"] = function(msg)
	local arg = Trim(string.lower(msg or ""))
	if arg == "clean" then
		CleanLists()
		return
	end
	if arg == "sell" then
		SellItems()
		return
	end
	if arg == "setup" then
		-- Re-open the welcome popup. Clears the dismissed flag so the user
		-- can see it again from this point forward unless they re-check
		-- "Don't show this again" inside the popup.
		_G.AutoDeleteDB = _G.AutoDeleteDB or {}
		_G.AutoDeleteDB.welcomeDismissed = false
		ShowWelcomePopup()
		return
	end
	if arg == "debug" then
		-- Toggle the sell-decision debug trace. When on, every item that
		-- sells via the auto-rules prints its inputs (id, quality, ilvl,
		-- equipSlot, itemClass, isWeaponSlot, bind status, sellReason).
		_G.AutoDelete_DebugSell = not _G.AutoDelete_DebugSell
		if _G.AutoDelete_DebugSell then
			print("|cffff8000[AutoDelete]|r sell debug |cff00ff00ON|r - every auto-sell will now print its decision inputs.")
		else
			print("|cffff8000[AutoDelete]|r sell debug |cffff5555OFF|r.")
		end
		return
	end
	if arg == "pet" or arg == "pos" then
		-- Diagnostic: dump pet stuck-detection state. Used to verify the
		-- loot-event-based stuck detector is firing correctly.
		local p = cachedProfile
		print("|cffff8000[AutoDelete]|r pet stuck-detection debug:")

		if _G.AutoDelete_GetActiveTrackedPet then
			print("  activeTracked: " .. tostring(_G.AutoDelete_GetActiveTrackedPet()))
		end

		local now = GetTime()
		if _G.AutoDelete_GetScavLootChatAt then
			local lastChat = _G.AutoDelete_GetScavLootChatAt() or 0
			if lastChat > 0 then
				print(string.format("  scav last 'looted' chat: %.1fs ago", now - lastChat))
			else
				print("  scav last 'looted' chat: never seen")
			end
		end

		-- Count recent player loots inside the window.
		local windowCount = 0
		local oldestInWindow = nil
		if recentPlayerLootTimes then
			for _, t in ipairs(recentPlayerLootTimes) do
				if (now - t) <= LOOT_STUCK_WINDOW then
					windowCount = windowCount + 1
					if not oldestInWindow then oldestInWindow = t end
				end
			end
		end
		print(string.format("  player loots in last %ds: %d (need %d to evaluate)",
			LOOT_STUCK_WINDOW, windowCount, LOOT_STUCK_PLAYER_MIN))
		if oldestInWindow then
			print(string.format("  oldest player loot in window: %.1fs ago", now - oldestInWindow))
		end

		if p then
			print("  summonScavenger=" .. tostring(p.summonScavenger) ..
				"  summonOnlyInCombat=" .. tostring(p.summonOnlyInCombat) ..
				"  enabled=" .. tostring(p.enabled))
			print("  in combat=" .. tostring(UnitAffectingCombat and UnitAffectingCombat("player")) ..
				"  mounted=" .. tostring(IsMounted and IsMounted()))
		end
		return
	end
	local panel = _G.AutoDeleteOptionsPanel
	if panel then
		if panel:IsShown() then panel:Hide() else panel:Show() end
	end
end
