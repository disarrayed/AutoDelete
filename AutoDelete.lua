local ADDON_NAME = ...

-- ============================================================================
-- Database Functions
-- ============================================================================

local function GetCharKey()
	local name = UnitName("player")
	local realm = GetRealmName and GetRealmName() or nil
	if not name then return nil end
	if realm and realm ~= "" then
		return name .. "-" .. realm
	end
	return name
end

local function MigrateDB(db)
	if db.profiles then return end
	db.profiles = db.profiles or {}
	db.chars = db.chars or {}

	local charKey = GetCharKey() or "Default"
	db.profiles[charKey] = {
		enabled = db.enabled and true or false,
		listText = db.listText or "",
		autoGray = false,
		scanInterval = 0.75,
	}
	db.chars[charKey] = charKey
end

local function GetDB()
	_G.AutoDeleteDB = _G.AutoDeleteDB or {}
	local db = _G.AutoDeleteDB

	if not db.profiles then
		MigrateDB(db)
	end

	db.profiles = db.profiles or {}
	db.chars = db.chars or {}

	local charKey = GetCharKey() or "Default"
	local profileKey = db.chars[charKey] or charKey
	if not db.profiles[profileKey] then
		db.profiles[profileKey] = { enabled = false, listText = "", autoGray = false, scanInterval = 0.75 }
	end
	if not db.chars[charKey] then
		db.chars[charKey] = profileKey
	end

	return db
end

local function GetActiveProfile(db)
	local charKey = GetCharKey() or "Default"
	local profileKey = (db and db.chars and db.chars[charKey]) or charKey
	if not db.profiles[profileKey] then
		db.profiles[profileKey] = { enabled = false, listText = "", autoGray = false, scanInterval = 0.75 }
	end
	return db.profiles[profileKey], profileKey, charKey
end

local function Normalize(s)
	s = tostring(s or "")
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	s = string.lower(s)
	return s
end

-- ============================================================================
-- Item Matching Functions
-- ============================================================================

local function BuildWantedSets(listText)
	local nameSet = {}
	local idSet = {}

	for line in string.gmatch(listText or "", "[^\r\n]+") do
		local raw = tostring(line or "")
		raw = string.gsub(raw, "^%s+", "")
		raw = string.gsub(raw, "%s+$", "")

		local itemId = tonumber(string.match(raw, "^item:(%d+)$"))
		if itemId then
			idSet[itemId] = true
		else
			local name = Normalize(raw)
			if name ~= "" then
				nameSet[name] = true
			end
		end
	end

	return nameSet, idSet
end

local function GetItemIDFromLink(link)
	if not link then return nil end
	return tonumber(string.match(link, "item:(%d+)"))
end

-- ============================================================================
-- Deletion Logic
-- ============================================================================

local nextScanAt = 0
local periodicInterval = 2.0
local nextPeriodicAt = 0
local scanRequested = false

local function RequestScan()
	scanRequested = true
end

-- ============================================================================
-- List Helpers (for auto-add gray items)
-- ============================================================================

local function Trim(s)
	s = tostring(s or "")
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	return s
end

local function HasExactLine(listText, line)
	line = Trim(line)
	if line == "" then return true end
	for l in string.gmatch(listText or "", "[^\r\n]+") do
		if Trim(l) == line then
			return true
		end
	end
	return false
end

local function AddLineIfMissing(listText, line)
	line = Trim(line)
	if line == "" then return listText or "" end
	if HasExactLine(listText, line) then return listText or "" end
	local t = tostring(listText or "")
	if t ~= "" and string.sub(t, -1) ~= "\n" then
		t = t .. "\n"
	end
	return t .. line .. "\n"
end

-- ============================================================================
-- Auto-Add Gray Items
-- ============================================================================

local function ScanAndAddGrayItems()
	if CursorHasItem() then return end

	local db = GetDB()
	local profile = GetActiveProfile(db)

	if not profile.enabled or not profile.autoGray then return end

	local changed = false
	for bag = 0, 4 do
		local slots = GetContainerNumSlots(bag)
		for slot = 1, slots do
			local _, _, locked, quality, _, _, itemLink = GetContainerItemInfo(bag, slot)
			if itemLink and not locked and quality == 0 then
				local itemId = GetItemIDFromLink(itemLink)
				if itemId then
					local line = "item:" .. tostring(itemId)
					if not HasExactLine(profile.listText, line) then
						profile.listText = AddLineIfMissing(profile.listText or "", line)
						local itemName = GetItemInfo(itemLink) or ("Item " .. itemId)
						print("|cff00ff00AutoDelete|r: Auto-added gray item " .. itemName)
						changed = true
					end
				end
			end
		end
	end

	if changed then
		-- Refresh the options panel if it's open
		if _G.AutoDeleteOptionsPanel and _G.AutoDeleteOptionsPanel._built and _G.AutoDeleteOptionsPanel:IsVisible() then
			_G.AutoDeleteOptionsPanel:Refresh()
		end
	end
end

local function TryDeleteOneMatchingItem()
	-- Don't interfere if the player is holding an item (dragging)
	if CursorHasItem() then return end

	local db = GetDB()
	local profile = GetActiveProfile(db)
	
	if not profile.enabled then return end
	-- Item deletion is allowed during combat, so no need to check InCombatLockdown

	local wantedNames, wantedIDs = BuildWantedSets(profile.listText)
	if not next(wantedNames) and not next(wantedIDs) then return end

	for bag = 0, 4 do
		local slots = GetContainerNumSlots(bag)
		for slot = 1, slots do
			local _, _, locked, _, _, _, itemLink = GetContainerItemInfo(bag, slot)
			if itemLink and not locked then
				-- Check by item ID first (more reliable)
				local itemId = GetItemIDFromLink(itemLink)
				if itemId and wantedIDs[itemId] then
					ClearCursor()
					PickupContainerItem(bag, slot)
					if CursorHasItem() then
						DeleteCursorItem()
						ClearCursor()
					end
					return
				end

				-- Check by item name
				local itemName = GetItemInfo(itemLink)
				if itemName and wantedNames[Normalize(itemName)] then
					ClearCursor()
					PickupContainerItem(bag, slot)
					if CursorHasItem() then
						DeleteCursorItem()
						ClearCursor()
					end
					return
				end
			end
		end
	end
end

-- ============================================================================
-- ElvUI Bag Button Hook
-- ============================================================================

local function CreateElvUIBagButton()
	-- Check if ElvUI bags exist
	local bagFrame = _G.ElvUI_ContainerFrame
	if not bagFrame then return end

	local btn = CreateFrame("Button", "AutoDelete_ElvUIBagBtn", bagFrame)
	btn:SetSize(20, 20)

	-- Position at top-right area of ElvUI bag frame, next to existing buttons
	btn:SetPoint("TOPRIGHT", bagFrame, "TOPRIGHT", -50, -4)

	-- Background
	btn:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = false, tileSize = 16, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 }
	})
	btn:SetBackdropColor(0, 0, 0, 0.6)
	btn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

	-- Icon texture (trash/delete icon)
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 2, -2)
	icon:SetPoint("BOTTOMRIGHT", -2, 2)
	icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
	btn._icon = icon

	-- Tooltip
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
		GameTooltip:AddLine("AutoDelete", 0, 1, 0)
		GameTooltip:AddLine("Drop an item here to add it to", 1, 1, 1)
		GameTooltip:AddLine("the auto-delete list.", 1, 1, 1)
		GameTooltip:AddLine(" ")
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

	-- Drop handler - add items to deletion list
	btn:RegisterForDrag("LeftButton")
	local function HandleDrop()
		local addFunc = _G.AutoDelete_AddDraggedItem
		if addFunc then
			addFunc()
		else
			-- Fallback: do it manually if Options.lua hasn't built yet
			local cursorType, itemID, itemLink = GetCursorInfo()
			if cursorType ~= "item" then
				ClearCursor()
				return
			end
			local id = nil
			if type(itemID) == "number" then
				id = itemID
			else
				id = GetItemIDFromLink(itemLink)
			end
			ClearCursor()
			if not id then return end

			local db = GetDB()
			local profile = GetActiveProfile(db)
			local line = "item:" .. tostring(id)
			if HasExactLine(profile.listText, line) then
				local itemName = GetItemInfo(id) or ("Item " .. id)
				print("|cff00ff00AutoDelete|r: " .. itemName .. " is already in the list")
				return
			end
			profile.listText = AddLineIfMissing(profile.listText or "", line)
			GetItemInfo("item:" .. id)
			local itemName = GetItemInfo(id) or ("Item " .. id)
			print("|cff00ff00AutoDelete|r: Added " .. itemName)
			if _G.AutoDeleteOptionsPanel and _G.AutoDeleteOptionsPanel._built and _G.AutoDeleteOptionsPanel:IsVisible() then
				_G.AutoDeleteOptionsPanel:Refresh()
			end
		end
	end

	btn:SetScript("OnReceiveDrag", HandleDrop)
	btn:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			if InterfaceOptionsFrame_OpenToCategory then
				InterfaceOptionsFrame_OpenToCategory(_G.AutoDeleteOptionsPanel or "AutoDelete")
				InterfaceOptionsFrame_OpenToCategory(_G.AutoDeleteOptionsPanel or "AutoDelete")
			end
		elseif CursorHasItem() then
			HandleDrop()
		end
	end)
	btn:RegisterForClicks("AnyUp")
end

-- ============================================================================
-- Event Handler
-- ============================================================================

local scanner = CreateFrame("Frame")
scanner:RegisterEvent("ADDON_LOADED")
scanner:RegisterEvent("PLAYER_LOGIN")
scanner:RegisterEvent("BAG_UPDATE")
scanner:RegisterEvent("BAG_UPDATE_DELAYED")

scanner:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		GetDB()
		return
	end
	
	if event == "PLAYER_LOGIN" then
		print("|cff00ff00AutoDelete|r loaded. Type |cff00ff00/del|r to configure.")
		-- Try to hook ElvUI bags (delayed to ensure ElvUI has loaded)
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
	
	-- BAG_UPDATE or BAG_UPDATE_DELAYED
	ScanAndAddGrayItems()
	RequestScan()
end)

scanner:SetScript("OnUpdate", function(self, elapsed)
	local now = GetTime()

	-- Periodic scan every 2 seconds when enabled
	local db = GetDB()
	local profile = GetActiveProfile(db)
	if profile.enabled and now >= nextPeriodicAt then
		nextPeriodicAt = now + periodicInterval
		scanRequested = true
	end

	-- Process scan requests with throttle
	if scanRequested and now >= nextScanAt then
		scanRequested = false
		local interval = (profile.scanInterval and profile.scanInterval >= 0.75) and profile.scanInterval or 0.75
		nextScanAt = now + interval
		TryDeleteOneMatchingItem()
	end
end)

-- ============================================================================
-- Slash Command
-- ============================================================================

SLASH_AUTODELETE1 = "/del"
SLASH_AUTODELETE2 = "/autodelete"
SlashCmdList["AUTODELETE"] = function()
	if InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(_G.AutoDeleteOptionsPanel or "AutoDelete")
		InterfaceOptionsFrame_OpenToCategory(_G.AutoDeleteOptionsPanel or "AutoDelete")
	end
end
