local ADDON_NAME = ...

-- cachedProfile is used throughout the file (Hide Greedy Spam filter, Auto-Invite
-- handlers, sell/delete logic). It MUST be declared before any function that
-- references it, otherwise Lua resolves `cachedProfile` to the global env (nil)
-- in those functions instead of this local. RefreshCachedProfile() below writes
-- to this same upvalue, so all closures see the latest value.
local cachedProfile = nil

-- Declared here (before any function that calls it) as a forward-assignable
-- local. The real body is assigned later once GetDB / GetActiveProfile are
-- defined. Do NOT redeclare with `local function` below — that shadows this.
local RefreshCachedProfile

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
	enabled = false,
	listText = "",
	sellListText = "",
	whitelistText = "",
	autoGray = false,
	scanInterval = 0.5,
	sellIlvlEnabled = false,
	sellIlvlMin = 1,
	sellIlvlMax = 199,
	sellBoE = false,
	sellBoEWeapons = false,
	sellBoEWeaponMinIlvl = 1,
	sellBoEWeaponMaxIlvl = 199,
	sellJunk = false,
	sellGreen = true,
	sellBlue = false,
	sellEpic = false,
	summonScavenger = false,
	summonAfterSell = true,
	summonAfterClose = false,
	-- Auto-repair at vendor
	autoRepair = false,
	autoRepairUseGuildBank = false,
	-- Hide Greedy Scavenger chat/bubble spam
	hideGreedySpam = false,
	-- Auto-Invite
	autoInviteEnabled = false,
	autoInviteKeywords = "inv,invite",
	-- Loot rule on invite (values: "freeforall" | "roundrobin" | "group" | "needbeforegreed" | "master")
	autoInviteApplyLootRule = false,
	autoInviteLootRule = "freeforall",
	-- Party management
	autoInviteConvertToRaid = false,
	autoInviteInviteRequester = false,
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

local function BuildWantedSets(listText)
	local nameSet, idSet = {}, {}
	for line in string.gmatch(listText or "", "[^\r\n]+") do
		local raw = Trim(line)
		-- Strip comments
		raw = string.gsub(raw, "%s*#.*$", "")
		raw = Trim(raw)
		-- Match item:ID (lenient — don't require end anchor)
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
			.. " — already on the " .. ListLabelForKey(conflictKey)
			.. " list. Remove it from there first.")
		return false
	end

	profile[listKey] = AddLineIfMissing(profile[listKey] or "", line)
	GetItemInfo("item:" .. itemId)
	local label = listKey == "sellListText" and "sell" or "delete"
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

-- Global functions for ElvUI buttons — always target the correct list
_G.AutoDelete_AddToDeleteList = function() HandleItemDrop("listText") end
_G.AutoDelete_AddToSellList = function() HandleItemDrop("sellListText") end

-- ============================================================================
-- Manual Sell Tracking (hook UseContainerItem)
-- ============================================================================
-- Blizzard's merchant UI sells an item by calling UseContainerItem(bag, slot)
-- when you right-click a bag item while the merchant window is open. We can't
-- intercept that call, but we can hook it AFTER it fires via hooksecurefunc.
-- When our hook runs and MerchantFrame is shown, we know the player is at a
-- vendor, and the item that was in (bag, slot) was just sold.
--
-- Implementation nuance: by the time our hook runs, the item has already been
-- removed from the bag (UseContainerItem is synchronous at the client level).
-- So we read the item info BEFORE calling — but hooksecurefunc runs AFTER.
-- Solution: read the info via a short delay OR cache bag contents at
-- MERCHANT_SHOW and look up by (bag, slot). Simpler: use GetItemInfo on the
-- link we can still get via GetContainerItemLink BEFORE it clears (turns out
-- the inventory updates at the end of the frame, not mid-function).
--
-- Sanity: only track when:
--   - MerchantFrame is visible (so it's actually a sale, not a consume)
--   - vendorPrice > 0 (otherwise it wasn't sellable, call failed silently)
--   - AutoDelete is NOT the one calling UseContainerItem (our SellItems path
--     already calls BumpStat directly; double-count protection needed)
--
-- We use a flag set around our own UseContainerItem calls so the hook skips.
local autoDeleteSelling = false
local origUseContainerItem = UseContainerItem

-- Wrap hooksecurefunc so we can read the link BEFORE Blizzard's handler
-- removes/shifts the stack. At 3.3.5, hooksecurefunc runs AFTER the original,
-- which means the slot may already be empty or shifted. So we must snapshot
-- the item BEFORE calling.
-- Easiest reliable approach: wrap our own SellItems() calls in a flag, and
-- read the item link inside the hook (will be nil post-sell but that's OK —
-- we pre-capture in a separate path).
--
-- Actual working approach: override UseContainerItem globally to capture the
-- link FIRST, then delegate. This is fine for 3.3.5 where UseContainerItem is
-- unprotected for bag-slot calls.
local function TrackedUseContainerItem(bag, slot, ...)
	-- Capture BEFORE the call, while the item is still in the slot.
	local tracked = false
	if not autoDeleteSelling
	   and MerchantFrame and MerchantFrame:IsShown()
	   and bag and slot
	then
		local link = GetContainerItemLink(bag, slot)
		if link then
			local _, itemCount = GetContainerItemInfo(bag, slot)
			local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(link)
			if sellPrice and sellPrice > 0 then
				tracked = true
				-- Defer the BumpStat to AFTER the actual sell so we don't
				-- record a ghost sale if the call fails. We schedule via a
				-- 0-delay frame; hooksecurefunc would be more reliable here.
				-- Actually just record now — Blizzard returning an error would
				-- still leave the item in the slot but not trigger the bag
				-- update, so subsequent scans wouldn't double-count.
				local copper = sellPrice * (itemCount or 1)
				BumpStat("itemsSold", 1)
				BumpStat("goldEarned", copper)
			end
		end
	end
	return origUseContainerItem(bag, slot, ...)
end
UseContainerItem = TrackedUseContainerItem

-- ============================================================================
-- Profile Management (copy settings from another character)
-- ============================================================================
-- Every character has its own profile keyed in db.profiles. The Profiles tab
-- in the UI exposes a "copy from another character" action: pick a source
-- character, confirm, and their full profile (lists + toggles + everything)
-- gets deep-copied onto the current character's profile key.
--
-- This is intentionally NOT a named-profile system — just a one-way copy
-- across alts. Tracking stats are NOT copied (those are per-character data,
-- not settings).

-- Deep copy a table (handles nested tables). Values that aren't tables are
-- copied by value — functions, userdata, etc. get reference-copied but we
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

local nextScanAt = 0
local periodicInterval = 2.0
local nextPeriodicAt = 0
local scanRequested = false

local function RequestScan() scanRequested = true end

local DELETE_BATCH_SIZE = 20

-- Cosmetic slots (shirts + tabards). Items in these slots are NEVER deleted
-- or sold by the automatic rules (auto-gray delete, sell-by-quality,
-- sell-by-iLvl). They must be explicitly added to the Delete or Sell list
-- for the addon to touch them. Used by both DeleteItems and SellItems.
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
	if not profile.enabled then return end

	local wantedNames, wantedIDs = BuildWantedSets(profile.listText)
	local hasWanted = next(wantedNames) or next(wantedIDs)
	local doGray = profile.autoGray

	if not hasWanted and not doGray then return end

	local deleted = 0

	for bag = 0, 4 do
		for slot = 1, GetContainerNumSlots(bag) do
			if deleted >= DELETE_BATCH_SIZE then return end
			local _, _, locked, _, _, _, itemLink = GetContainerItemInfo(bag, slot)
			if itemLink and not locked then
				local itemName, _, itemQuality = GetItemInfo(itemLink)
				local itemId = GetItemIDFromLink(itemLink)
				local shouldDelete = false

				-- Check delete list
				if hasWanted then
					if itemId and wantedIDs[itemId] then shouldDelete = true end
					if not shouldDelete and itemName and wantedNames[Normalize(itemName)] then shouldDelete = true end
				end

				-- Check gray auto-delete (quality 0 = Poor/gray).
				-- Shirts and tabards are always protected from auto-gray even
				-- if they somehow came through as gray quality. Put them on
				-- the Delete list explicitly if you want them gone.
				if not shouldDelete and doGray and itemQuality and itemQuality == 0
					and not IsCosmeticSlot(itemLink) then
					shouldDelete = true
				end

				if shouldDelete and not IsWhitelisted(profile, itemId, itemName) then
					ClearCursor()
					PickupContainerItem(bag, slot)
					if CursorHasItem() then DeleteCursorItem(); ClearCursor() end
					deleted = deleted + 1
					BumpStat("itemsDeleted", 1)
				end
			end
		end
	end
end

-- ============================================================================
-- Sell Logic
-- ============================================================================

local GEAR_SLOTS = {
	INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true,
	INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
	INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
	INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true,
	INVTYPE_ROBE = true, INVTYPE_WAIST = true, INVTYPE_LEGS = true,
	INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
	INVTYPE_CLOAK = true, INVTYPE_SHIELD = true,
	-- Accessories: rings, necks, trinkets, held off-hands, relics.
	-- INVTYPE_BODY (shirts) and INVTYPE_TABARD are DELIBERATELY excluded.
	-- These are cosmetic items the user likely doesn't want auto-sold by
	-- quality or iLvl rules. They can still be sold/deleted only if the
	-- user puts them on an explicit list (which bypasses these filters).
	-- Intentionally excluded: INVTYPE_BAG, INVTYPE_AMMO, INVTYPE_QUIVER.
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

-- BoE scanning tooltip (hidden, reused)
local boeTip = CreateFrame("GameTooltip", "AutoDelete_BoETip", UIParent, "GameTooltipTemplate")
boeTip:SetOwner(UIParent, "ANCHOR_NONE")

local function IsBindOnEquip(bag, slot)
	boeTip:ClearLines()
	boeTip:SetBagItem(bag, slot)
	for i = 2, boeTip:NumLines() do
		local text = _G["AutoDelete_BoETipTextLeft" .. i]
		if text then
			local line = text:GetText()
			if line and string.find(line, "Binds when equipped") then
				return true
			end
		end
	end
	return false
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

local function SummonGreedyScavenger()
	local numCritters = GetNumCompanions("CRITTER")
	for i = 1, numCritters do
		local _, name = GetCompanionInfo("CRITTER", i)
		if name and string.find(string.lower(name), "greedy scavenger") then
			CallCompanion("CRITTER", i)
			print("|cffff8000[AutoDelete]|r: Summoned Greedy Scavenger")
			return
		end
	end
end

-- Fire SummonGreedyScavenger after a delay (3.3.5 has no C_Timer).
-- Guarded so we don't stack multiple pending summons.
local summonPending = false
local function DelayedSummon(delaySeconds)
	if summonPending then return end
	summonPending = true
	local delayFrame = CreateFrame("Frame")
	local elapsed = 0
	delayFrame:SetScript("OnUpdate", function(self, dt)
		elapsed = elapsed + dt
		if elapsed >= (delaySeconds or 1.5) then
			self:SetScript("OnUpdate", nil)
			summonPending = false
			SummonGreedyScavenger()
		end
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
-- Invites players who whisper you a keyword prefixed with "!" (e.g. "!inv").
-- Gated by:
--   cachedProfile.autoInviteEnabled (master toggle)
--   player must be group leader OR raid assistant (silently ignored otherwise)
-- Active everywhere (party, raid, BG, solo).
--
-- Extras (all off by default):
--   autoInviteApplyLootRule + autoInviteLootRule: apply a loot rule after inviting
--   autoInviteConvertToRaid: convert to raid when party is full (5 members)
--   autoInviteInviteRequester: when YOU whisper the keyword TO someone, invite THEM
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
-- non-alphanumeric character. What comes AFTER the keyword doesn't matter —
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
-- accepts. We schedule a follow-up check.
local inviteFollowupFrame = CreateFrame("Frame")
local inviteFollowupQueue = {}   -- list of { fireAt = <time>, fn = <func> }

inviteFollowupFrame:SetScript("OnUpdate", function(self)
	if #inviteFollowupQueue == 0 then return end
	local now = GetTime()
	local i = 1
	while i <= #inviteFollowupQueue do
		local entry = inviteFollowupQueue[i]
		if now >= entry.fireAt then
			entry.fn()
			table.remove(inviteFollowupQueue, i)
		else
			i = i + 1
		end
	end
end)

local function ScheduleInviteFollowup(delaySec, fn)
	table.insert(inviteFollowupQueue, { fireAt = GetTime() + (delaySec or 3), fn = fn })
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

-- Outgoing whisper handler. Called for CHAT_MSG_WHISPER_INFORM events.
-- If YOU whisper the keyword to someone AND autoInviteInviteRequester is on
-- → invite THEM (the recipient).
local function HandleOutgoingWhisper(msg, target)
	RefreshCachedProfile()
	if not cachedProfile or not cachedProfile.autoInviteEnabled then return end
	if not cachedProfile.autoInviteInviteRequester then return end
	if not PlayerCanInvite() then return end

	local keywords = ParseInviteKeywords(cachedProfile.autoInviteKeywords)
	if not MessageMatchesKeyword(msg, keywords) then return end

	local invitee = NormalizePlayerName(target)
	if invitee == "" then return end

	SafeInvitePlayer(invitee)

	ScheduleInviteFollowup(3, function()
		ApplyConfiguredLootRule()
		MaybeConvertToRaid()
	end)
end

-- Dedicated event frame for whisper events (kept separate from the main
-- scanner to avoid clutter).
local inviteFrame = CreateFrame("Frame")
inviteFrame:RegisterEvent("CHAT_MSG_WHISPER")
inviteFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
inviteFrame:SetScript("OnEvent", function(_, event, msg, author)
	if event == "CHAT_MSG_WHISPER" then
		HandleIncomingWhisper(msg, author)
	elseif event == "CHAT_MSG_WHISPER_INFORM" then
		-- For whisper-inform, `author` is actually the recipient.
		HandleOutgoingWhisper(msg, author)
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
	local ilvlEnabled = profile.sellIlvlEnabled
	local ilvlMin = tonumber(profile.sellIlvlMin) or 1
	local ilvlMax = tonumber(profile.sellIlvlMax) or 199

	local batchCount = 0

	for bag = 0, 4 do
		for slot = 1, GetContainerNumSlots(bag) do
			if batchCount >= SELL_BATCH_SIZE then break end
			local _, itemCount, locked, _, _, _, itemLink = GetContainerItemInfo(bag, slot)
			if itemLink and not locked then
				-- 6th return from GetItemInfo = itemClass (e.g. "Armor", "Weapon",
				-- "Miscellaneous", "Consumable"). We use this as a defensive
				-- second-layer gear check alongside equipSlot so that books,
				-- glyphs, consumables, and other miscellaneous items with
				-- unexpected equipSlot values can never be caught by the
				-- quality-based auto-sell rules.
				local name, _, itemQuality, ilvl, _, itemClass, _, _, equipSlot, _, vendorPrice = GetItemInfo(itemLink)
				-- "Gear" = equippable slot.
				-- For weapon-slot items (weapons, shields, holdables, ranged,
				-- thrown, relics) we accept ANY itemClass because on PE these
				-- are all treated uniformly as Weapon-affix targets. Holdables
				-- are itemClass "Miscellaneous", relics vary, and they all
				-- need to flow through the same sell rules as weapons.
				-- For non-weapon gear (armor, rings, necks, trinkets) we still
				-- require itemClass to be Armor to protect against random
				-- Miscellaneous items that happen to have a gear equipSlot.
				local isGearItem = false
				if equipSlot and GEAR_SLOTS[equipSlot] then
					if WEAPON_SLOTS[equipSlot] then
						isGearItem = true
					elseif itemClass == "Armor" or itemClass == "Weapon" then
						isGearItem = true
					end
				end
				if vendorPrice and vendorPrice > 0 then
					local shouldSell = false
					local sellReason = nil   -- "list" | "junk" | "green" | "blue" | "epic"

					local itemId = GetItemIDFromLink(itemLink)

					-- 1) Explicit sell list entry — user intent, bypasses all filters.
					if itemId and sellIDs[itemId] then
						shouldSell = true; sellReason = "list"
					elseif name and sellNames[Normalize(name)] then
						shouldSell = true; sellReason = "list"
					end

					-- Quality-based auto-sell. Runs only if the item is not already
					-- on the explicit sell list. Each quality requires its rarity
					-- checkbox to be on and obeys the iLvl range when that range
					-- is enabled. Junk (q=0) bypasses the iLvl range and every
					-- filter since gray items have no level to check against.
					if not shouldSell and itemQuality then
						if itemQuality == 0 and profile.sellJunk then
							shouldSell = true; sellReason = "junk"
						elseif itemQuality == 2 and profile.sellGreen and isGearItem then
							if not ilvlEnabled or (ilvl and ilvl >= ilvlMin and ilvl <= ilvlMax) then
								shouldSell = true; sellReason = "green"
							end
						elseif itemQuality == 3 and profile.sellBlue and isGearItem then
							if not ilvlEnabled or (ilvl and ilvl >= ilvlMin and ilvl <= ilvlMax) then
								shouldSell = true; sellReason = "blue"
							end
						elseif itemQuality == 4 and profile.sellEpic and isGearItem then
							if not ilvlEnabled or (ilvl and ilvl >= ilvlMin and ilvl <= ilvlMax) then
								shouldSell = true; sellReason = "epic"
							end
						end
					end

					-- Filters applied after a rule picks a reason. Each reason
					-- defines its own exemptions so that list and junk bypass
					-- the BoE gates while blue/epic always respect them.
					local isBoE = shouldSell and IsBindOnEquip(bag, slot)

					-- Generic BoE gate. Exempt: list, junk, green.
					if shouldSell and isBoE and not profile.sellBoE then
						local exempt = (sellReason == "list") or (sellReason == "junk") or (sellReason == "green")
						if not exempt then
							shouldSell = false
						end
					end

					-- BoE weapons gate. Exempt: list, junk.
					-- Green weapons: only check this gate if sellBoEWeapons toggle is ON;
					-- when ON, the weapon must fall inside the range. When OFF, green weapons
					-- sell without restriction (per spec).
					-- Blue/Epic weapons: protected unless sellBoEWeapons is on AND iLvl fits.
					if shouldSell and isBoE and equipSlot and WEAPON_SLOTS[equipSlot] then
						local exempt = (sellReason == "list") or (sellReason == "junk")
						if not exempt then
							if sellReason == "green" then
								-- Green weapons only blocked if the BoE weapons toggle is on
								-- AND the weapon doesn't fit the range.
								if profile.sellBoEWeapons then
									local minIlvl = tonumber(profile.sellBoEWeaponMinIlvl) or 1
									local maxIlvl = tonumber(profile.sellBoEWeaponMaxIlvl) or 199
									if not ilvl or ilvl < minIlvl or ilvl > maxIlvl then
										shouldSell = false
									end
								end
								-- If sellBoEWeapons is OFF, green weapons pass through.
							else
								-- Blue / Epic / iLvl-fallthrough weapons: protected unless
								-- sellBoEWeapons is on AND weapon fits the range.
								if not profile.sellBoEWeapons then
									shouldSell = false
								else
									local minIlvl = tonumber(profile.sellBoEWeaponMinIlvl) or 1
									local maxIlvl = tonumber(profile.sellBoEWeaponMaxIlvl) or 199
									if not ilvl or ilvl < minIlvl or ilvl > maxIlvl then
										shouldSell = false
									end
								end
							end
						end
					end

					-- Whitelist (Keep list) overrides EVERYTHING — explicit user protection.
					if shouldSell and IsWhitelisted(profile, itemId, name) then shouldSell = false end

					if shouldSell then
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
			-- Only trigger at Goblin Merchant.
			if cachedProfile and cachedProfile.summonScavenger and cachedProfile.summonAfterSell then
				local merchant = string.lower(lastMerchantName or "")
				if string.find(merchant, "goblin merchant") then
					DelayedSummon(1.5)
				end
			end
		end
	end
end

-- ============================================================================
-- ElvUI Bag Buttons
-- ============================================================================

local function CreateElvUIBagButton()
	local bagFrame = _G.ElvUI_ContainerFrame
	if not bagFrame then return end

	-- Delete drop target
	local btn = CreateFrame("Button", "AutoDelete_ElvUIBagBtn", bagFrame)
	btn:SetSize(20, 20)
	btn:SetPoint("TOPRIGHT", bagFrame, "TOPRIGHT", -50, -4)
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
			local panel = _G.AutoDeleteOptionsPanel
			if panel then
				if panel:IsShown() then panel:Hide() else panel:Show() end
			end
		elseif CursorHasItem() then
			_G.AutoDelete_AddToDeleteList()
		end
	end)

	-- Sell drop target
	local sellBtn = CreateFrame("Button", "AutoDelete_ElvUISellBtn", bagFrame)
	sellBtn:SetSize(20, 20)
	sellBtn:SetPoint("RIGHT", btn, "LEFT", -4, 0)
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
			local panel = _G.AutoDeleteOptionsPanel
			if panel then
				if panel:IsShown() then panel:Hide() else panel:Show() end
			end
		elseif CursorHasItem() then
			_G.AutoDelete_AddToSellList()
		else
			SellItems()
		end
	end)
end

-- ============================================================================
-- Event Handler
-- ============================================================================
-- cachedProfile and RefreshCachedProfile declared at top of file — don't
-- redeclare with `local function` here, that shadows the forward-declared local.

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

scanner:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		GetDB()
		RefreshCachedProfile()
		return
	end
	if event == "PLAYER_LOGIN" then
		RefreshCachedProfile()
		print("|cffff8000[AutoDelete]|r loaded. Type |cff00ff00/del|r to configure.")

		-- Keep bags open when the vendor closes (including via the X button).
		-- WoW's default MerchantFrame_OnHide calls CloseAllBags(). We hook
		-- OnHide (HookScript appends, so our handler runs AFTER the default
		-- one) and schedule a re-open on the next frame. Hooking OnHide
		-- instead of the MERCHANT_CLOSED event is more reliable because the
		-- X button path fires Hide() synchronously with OnHide, while the
		-- MERCHANT_CLOSED event can fire BEFORE Hide() runs.
		if MerchantFrame then
			MerchantFrame:HookScript("OnHide", function()
				local reopenTicker = CreateFrame("Frame")
				local e = 0
				reopenTicker:SetScript("OnUpdate", function(self, dt)
					e = e + dt
					if e >= 0.15 then
						self:SetScript("OnUpdate", nil)
						if OpenAllBags then OpenAllBags() end
					end
				end)
			end)
		end

		local delayFrame = CreateFrame("Frame")
		local elapsed = 0
		delayFrame:SetScript("OnUpdate", function(self, dt)
			elapsed = elapsed + dt
			if elapsed >= 2 then
				self:SetScript("OnUpdate", nil)
				CreateElvUIBagButton()
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
		-- Sample inventory worth BEFORE selling (otherwise we'd always sample
		-- post-sell bags, underselling the average).
		SampleInventoryWorth()
		-- Repair first (before selling) so durability gold is accounted for
		-- separately from sell revenue in chat output.
		TryAutoRepair()
		SellItems()
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
		if cachedProfile and cachedProfile.summonScavenger and cachedProfile.summonAfterClose then
			local merchant = string.lower(lastMerchantName or "")
			if string.find(merchant, "goblin merchant") then
				DelayedSummon(1.5)
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
-- Slash Commands
-- ============================================================================

-- ============================================================================
-- /del clean — remove duplicate entries from Delete + Sell lists
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

	local delEntries = Parse(profile.listText)
	local sellEntries = Parse(profile.sellListText)

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

	local keptDel, internalDelDupes = DedupeWithin(delEntries)
	local keptSell, internalSellDupes = DedupeWithin(sellEntries)

	-- 2. Find cross-list overlap and remove from BOTH
	local sellKeys = {}
	for _, e in ipairs(keptSell) do sellKeys[e.key] = true end

	local crossDupes, finalDel, finalSell = {}, {}, {}
	local crossKeys = {}
	for _, e in ipairs(keptDel) do
		if sellKeys[e.key] then
			crossKeys[e.key] = true
			table.insert(crossDupes, e.display)
		else
			table.insert(finalDel, e.raw)
		end
	end
	for _, e in ipairs(keptSell) do
		if not crossKeys[e.key] then
			table.insert(finalSell, e.raw)
		end
	end

	-- Rewrite list text (preserve trailing newline if there were entries)
	profile.listText = table.concat(finalDel, "\n")
	if #finalDel > 0 then profile.listText = profile.listText .. "\n" end
	profile.sellListText = table.concat(finalSell, "\n")
	if #finalSell > 0 then profile.sellListText = profile.sellListText .. "\n" end

	RefreshCachedProfile()

	-- Report
	print("|cffff8000[AutoDelete]|r Clean complete.")
	if #internalDelDupes > 0 then
		print("  |cff999999Removed " .. #internalDelDupes .. " internal duplicate(s) in Delete list:|r " .. table.concat(internalDelDupes, ", "))
	end
	if #internalSellDupes > 0 then
		print("  |cff999999Removed " .. #internalSellDupes .. " internal duplicate(s) in Sell list:|r " .. table.concat(internalSellDupes, ", "))
	end
	if #crossDupes > 0 then
		print("|cffff4444  Removed from BOTH lists (appeared in each):|r " .. table.concat(crossDupes, ", "))
		print("  |cffaaaaaaRe-add these manually to your preferred list.|r")
	end
	if #internalDelDupes == 0 and #internalSellDupes == 0 and #crossDupes == 0 then
		print("  |cff999999No duplicates found.|r")
	end

	-- Refresh UI if open
	local panel = _G.AutoDeleteOptionsPanel
	if panel and panel._built and panel:IsVisible() then
		panel:Refresh()
	end
end

-- ============================================================================
-- Profile Import — merge the 3 lists from another character's profile
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
-- Shift-click bag item → fill the Search & Manage filter box
-- ============================================================================
-- Hooks HandleModifiedItemClick (the global that fires on shift-click of any
-- item link or bag item). If our settings panel is open, we pull the item's
-- name out of the link and push it into the panel's search box. The existing
-- filter path then reduces the visible list to matching entries.
hooksecurefunc("HandleModifiedItemClick", function(link)
	if not link then return end
	if not IsShiftKeyDown() then return end
	local panel = _G.AutoDeleteOptionsPanel
	if not panel or not panel._built or not panel:IsVisible() then return end

	local name = GetItemInfo(link)
	if not name or name == "" then return end

	if panel._searchBox and panel._searchBox.SetText then
		panel._searchBox:SetText(name)
		panel._searchBox:SetCursorPosition(#name)
		if panel._searchPlaceholder then panel._searchPlaceholder:Hide() end
		-- OnTextChanged will update _filterText and call Refresh, but we also
		-- set _filterText directly in case the SetText call is silent in some
		-- edge case (frame not yet visible, etc.).
		panel._filterText = name
		if panel.Refresh then panel:Refresh() end
	end
end)

SLASH_AUTODELETE1 = "/del"
SLASH_AUTODELETE2 = "/autodelete"
SlashCmdList["AUTODELETE"] = function(msg)
	local arg = Trim(string.lower(msg or ""))
	if arg == "clean" then
		CleanLists()
		return
	end
	local panel = _G.AutoDeleteOptionsPanel
	if panel then
		if panel:IsShown() then panel:Hide() else panel:Show() end
	end
end

SLASH_SELLGREENS1 = "/sellgreens"
SlashCmdList["SELLGREENS"] = SellItems
