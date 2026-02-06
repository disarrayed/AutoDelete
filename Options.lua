if _G.AutoDeleteOptionsPanel then return end

local ADDON_NAME = ...

-- ============================================================================
-- Database Functions (duplicated for standalone options)
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
		db.profiles[profileKey] = { enabled = false, listText = "", autoGray = false }
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
		db.profiles[profileKey] = { enabled = false, listText = "", autoGray = false }
	end
	return db.profiles[profileKey], profileKey, charKey
end

-- ============================================================================
-- String Utility Functions
-- ============================================================================

local function Trim(s)
	s = tostring(s or "")
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	return s
end

local function Normalize(s)
	return string.lower(Trim(s))
end

local function EnsureEndsWithNewline(text)
	text = tostring(text or "")
	if text == "" then return "" end
	if string.sub(text, -1) ~= "\n" then
		return text .. "\n"
	end
	return text
end

-- ============================================================================
-- Item Functions
-- ============================================================================

local function GetItemIDFromLink(link)
	if not link then return nil end
	return tonumber(string.match(link, "item:(%d+)"))
end

local function ParseListText(listText)
	local entries = {}
	for line in string.gmatch(listText or "", "[^\r\n]+") do
		local raw = Trim(line)
		if raw ~= "" then
			local itemId = tonumber(string.match(raw, "^item:(%d+)$"))
			if itemId then
				table.insert(entries, { kind = "id", id = itemId, raw = "item:" .. itemId })
			else
				table.insert(entries, { kind = "name", name = raw, raw = raw })
			end
		end
	end
	return entries
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
	local t = EnsureEndsWithNewline(listText or "")
	return t .. line .. "\n"
end

local function RemoveExactLine(listText, line)
	line = Trim(line)
	if line == "" then return listText or "" end

	local out = {}
	for l in string.gmatch(listText or "", "[^\r\n]+") do
		local tl = Trim(l)
		if tl ~= "" and tl ~= line then
			table.insert(out, tl)
		end
	end

	return table.concat(out, "\n") .. (#out > 0 and "\n" or "")
end

local function GetDisplayForEntry(entry)
	if entry.kind == "id" then
		local name, link, quality, level, reqLevel, class, subclass, maxStack, equipSlot, icon = GetItemInfo(entry.id)
		if name then
			return name, icon, link
		end
		-- Force cache the item if not loaded yet
		local itemString = "item:" .. entry.id
		GetItemInfo(itemString)
		return "Loading item " .. entry.id, nil, itemString
	else
		return entry.name, nil, nil
	end
end

local function GenerateRawViewText(listText)
	-- Generate a more readable raw view with item names as comments
	local lines = {}
	for line in string.gmatch(listText or "", "[^\r\n]+") do
		local raw = Trim(line)
		if raw ~= "" then
			local itemId = tonumber(string.match(raw, "^item:(%d+)$"))
			if itemId then
				local itemName = GetItemInfo(itemId)
				if itemName then
					table.insert(lines, raw .. "    # " .. itemName)
				else
					table.insert(lines, raw .. "    # Loading...")
				end
			else
				table.insert(lines, raw)
			end
		end
	end
	return table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")
end

local function ParseRawViewText(text)
	-- Remove comments and extract just the item IDs and names
	local lines = {}
	for line in string.gmatch(text or "", "[^\r\n]+") do
		local raw = Trim(line)
		-- Remove comment part (everything after #)
		raw = string.gsub(raw, "%s*#.*$", "")
		raw = Trim(raw)
		if raw ~= "" then
			table.insert(lines, raw)
		end
	end
	return table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")
end

local function SortEntries(entries)
	table.sort(entries, function(a, b)
		local an = GetDisplayForEntry(a)
		local bn = GetDisplayForEntry(b)
		return Normalize(an) < Normalize(bn)
	end)
end

-- ============================================================================
-- Options Panel UI
-- ============================================================================

local panel = CreateFrame("Frame", "AutoDeleteOptionsPanel", InterfaceOptionsFramePanelContainer)
panel.name = "AutoDelete"
panel:Hide()

local function BuildPanelUI(self)
	local db = GetDB()
	local profile, profileKey, charKey = GetActiveProfile(db)

	self._db = db
	self._charKey = charKey

	-- Title
	local title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("AutoDelete")

	-- Subtitle
	local subtitle = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	subtitle:SetWidth(450)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetText("Automatically delete items when they enter your bags.")

	-- Profile Label
	local profileLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	profileLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
	profileLabel:SetText("Profile:")

	-- Profile Dropdown
	local profileDropdown = CreateFrame("Frame", "AutoDelete_ProfileDropdown", self, "UIDropDownMenuTemplate")
	profileDropdown:SetPoint("LEFT", profileLabel, "RIGHT", -12, -2)
	self._profileDropdown = profileDropdown

	-- Enable Checkbox
	local check = CreateFrame("CheckButton", "AutoDelete_Enable", self, "InterfaceOptionsCheckButtonTemplate")
	check:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", 0, -8)
	_G[check:GetName() .. "Text"]:SetText("Enable Auto Delete")
	self._check = check

	-- Auto-add Gray Items Checkbox
	local grayCheck = CreateFrame("CheckButton", "AutoDelete_AutoGray", self, "InterfaceOptionsCheckButtonTemplate")
	grayCheck:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 0, 0)
	_G[grayCheck:GetName() .. "Text"]:SetText("Auto-add gray (junk) items on loot")
	self._grayCheck = grayCheck

	-- Search Label
	local searchLabel = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	searchLabel:SetPoint("TOPLEFT", grayCheck, "BOTTOMLEFT", 8, -12)
	searchLabel:SetText("Search:")

	-- Search Box (custom styled, no InputBoxTemplate)
	local searchBoxHolder = CreateFrame("Frame", nil, self)
	searchBoxHolder:SetSize(224, 24)
	searchBoxHolder:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
	searchBoxHolder:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = false, tileSize = 16, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 }
	})
	searchBoxHolder:SetBackdropColor(0, 0, 0, 0.6)
	searchBoxHolder:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

	local searchBox = CreateFrame("EditBox", "AutoDelete_SearchBox", searchBoxHolder)
	searchBox:SetAutoFocus(false)
	searchBox:SetFontObject("ChatFontNormal")
	searchBox:SetTextColor(1, 1, 1)
	searchBox:SetPoint("TOPLEFT", 6, -2)
	searchBox:SetPoint("BOTTOMRIGHT", -6, 2)
	searchBox:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
	self._searchBox = searchBox

	-- List Container (also the drop target)
	local listBox = CreateFrame("Frame", "AutoDelete_ListBox", self)
	listBox:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -8)
	listBox:SetSize(360, 180)
	listBox:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = false, tileSize = 16, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 }
	})
	listBox:SetBackdropColor(0, 0, 0, 0.6)
	listBox:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
	self._listBox = listBox

	-- Empty state / drop hint text
	local emptyText = listBox:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	emptyText:SetPoint("CENTER")
	emptyText:SetText("Drag items here to add to deletion list")
	self._emptyText = emptyText

	-- Scroll Frame
	local scroll = CreateFrame("ScrollFrame", "AutoDelete_ListScroll", listBox, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	self._scroll = scroll

	-- List Rows
	self._rows = {}
	for i = 1, 9 do
		local row = CreateFrame("Button", nil, listBox)
		row:SetHeight(18)
		row:SetPoint("TOPLEFT", 10, -6 - (i - 1) * 18)
		row:SetPoint("RIGHT", -32, 0)

		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(16, 16)
		row.icon:SetPoint("LEFT", 2, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- Trim edges for cleaner look

		row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.text:SetPoint("RIGHT", -24, 0)
		row.text:SetJustifyH("LEFT")

		row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
		row.remove:SetSize(18, 18)
		row.remove:SetPoint("RIGHT", 18, 0)

		self._rows[i] = row
	end

	-- Show Raw Checkbox
	local showRawCheck = CreateFrame("CheckButton", "AutoDelete_ShowRaw", self, "InterfaceOptionsCheckButtonTemplate")
	showRawCheck:SetPoint("TOPLEFT", listBox, "BOTTOMLEFT", 0, -8)
	_G[showRawCheck:GetName() .. "Text"]:SetText("Show raw list (advanced)")
	showRawCheck:SetChecked(false)
	self._showRawCheck = showRawCheck

	-- Raw Text Container (positioned same as listBox, will be toggled)
	local rawBoxHolder = CreateFrame("Frame", "AutoDelete_RawBox", self)
	rawBoxHolder:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -8)
	rawBoxHolder:SetSize(360, 180)
	rawBoxHolder:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		tile = false, tileSize = 16, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 }
	})
	rawBoxHolder:SetBackdropColor(0, 0, 0, 0.6)
	rawBoxHolder:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
	rawBoxHolder:Hide()
	self._rawBoxHolder = rawBoxHolder

	-- Raw Text Scroll Frame
	local rawScroll = CreateFrame("ScrollFrame", "AutoDelete_RawScroll", rawBoxHolder, "UIPanelScrollFrameTemplate")
	rawScroll:SetPoint("TOPLEFT", 6, -6)
	rawScroll:SetPoint("BOTTOMRIGHT", -28, 6)

	local rawChild = CreateFrame("Frame", nil, rawScroll)
	rawChild:SetSize(320, 500)
	rawScroll:SetScrollChild(rawChild)

	-- Raw Text Edit Box
	local rawEditBox = CreateFrame("EditBox", "AutoDelete_RawEditBox", rawChild)
	rawEditBox:SetMultiLine(true)
	rawEditBox:SetAutoFocus(false)
	rawEditBox:EnableMouse(true)
	rawEditBox:SetFontObject("ChatFontNormal")
	rawEditBox:SetTextColor(1, 1, 1)
	rawEditBox:SetPoint("TOPLEFT")
	rawEditBox:SetPoint("BOTTOMRIGHT")
	rawEditBox:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
	self._rawEditBox = rawEditBox

	self._filterText = ""
	self._entries = {}
	self._filtered = {}

	-- Register for item info events to refresh when items load
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	self:SetScript("OnEvent", function(self, event, itemID)
		if event == "GET_ITEM_INFO_RECEIVED" then
			-- Refresh the list when item info becomes available
			if self._built and self:IsVisible() then
				if rawBoxHolder:IsShown() then
					-- Update raw view with new item names
					local p = GetActiveProfile(db)
					local cursorPos = rawEditBox:GetCursorPosition()
					rawEditBox:SetText(GenerateRawViewText(p.listText))
					rawEditBox:SetCursorPosition(cursorPos)
				else
					self:UpdateListRows()
				end
			end
		end
	end)

	-- ========================================================================
	-- Event Handlers
	-- ========================================================================

	-- Enable checkbox
	check:SetScript("OnClick", function(btn)
		local p = GetActiveProfile(db)
		p.enabled = btn:GetChecked() and true or false
		if p.enabled then
			print("|cff00ff00AutoDelete|r is now |cff00ff00enabled|r")
		else
			print("|cff00ff00AutoDelete|r is now |cffff0000disabled|r")
		end
	end)

	-- Auto-add gray items checkbox
	grayCheck:SetScript("OnClick", function(btn)
		local p = GetActiveProfile(db)
		p.autoGray = btn:GetChecked() and true or false
		if p.autoGray then
			print("|cff00ff00AutoDelete|r: Auto-add gray items |cff00ff00enabled|r")
		else
			print("|cff00ff00AutoDelete|r: Auto-add gray items |cffff0000disabled|r")
		end
	end)

	-- Add item via drag and drop
	local function AddDraggedItem()
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

		local line = "item:" .. tostring(id)
		local p = GetActiveProfile(db)
		
		if HasExactLine(p.listText, line) then
			local itemName = GetItemInfo(id) or ("Item " .. id)
			print("|cff00ff00AutoDelete|r: " .. itemName .. " is already in the list")
			return
		end
		
		p.listText = AddLineIfMissing(p.listText or "", line)
		
		-- Cache the item info (forces it to load)
		GetItemInfo("item:" .. id)
		
		local itemName = GetItemInfo(id) or ("Item " .. id)
		print("|cff00ff00AutoDelete|r: Added " .. itemName)
		
		self:Refresh()
	end

	-- Make this available globally for the ElvUI bag button
	_G.AutoDelete_AddDraggedItem = AddDraggedItem

	-- List box accepts drag and drop
	listBox:EnableMouse(true)
	listBox:RegisterForDrag("LeftButton")
	listBox:SetScript("OnReceiveDrag", AddDraggedItem)
	listBox:SetScript("OnMouseUp", function()
		if CursorHasItem() then
			AddDraggedItem()
		end
	end)

	-- Also make each row accept drag and drop (so items on rows work too)
	for i = 1, #self._rows do
		local row = self._rows[i]
		row:RegisterForDrag("LeftButton")
		row:SetScript("OnReceiveDrag", AddDraggedItem)
		row:SetScript("OnMouseUp", function()
			if CursorHasItem() then
				AddDraggedItem()
			end
		end)
	end

	-- Skin the profile dropdown to match ElvUI style
	local function SkinDropdown(dd)
		local left = _G[dd:GetName() .. "Left"]
		local middle = _G[dd:GetName() .. "Middle"]
		local right = _G[dd:GetName() .. "Right"]
		if left then left:SetAlpha(0) end
		if middle then middle:SetAlpha(0) end
		if right then right:SetAlpha(0) end

		-- Create thin border backdrop behind the dropdown
		local ddBG = CreateFrame("Frame", nil, dd)
		ddBG:SetPoint("TOPLEFT", 20, -4)
		ddBG:SetPoint("BOTTOMRIGHT", -20, 4)
		ddBG:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Buttons\\WHITE8X8",
			tile = false, tileSize = 16, edgeSize = 1,
			insets = { left = 1, right = 1, top = 1, bottom = 1 }
		})
		ddBG:SetBackdropColor(0, 0, 0, 0.6)
		ddBG:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
		ddBG:SetFrameLevel(dd:GetFrameLevel())
	end
	SkinDropdown(profileDropdown)

	-- Search box handler
	searchBox:SetScript("OnTextChanged", function(eb)
		self._filterText = eb:GetText() or ""
		self:Refresh()
	end)

	-- Show raw checkbox handler
	showRawCheck:SetScript("OnClick", function(btn)
		local show = btn:GetChecked() and true or false
		if show then
			-- Hide normal list, show raw editor
			listBox:Hide()
			rawBoxHolder:Show()
			local p = GetActiveProfile(db)
			-- Show enhanced view with item names as comments
			rawEditBox:SetText(GenerateRawViewText(p.listText))
			rawEditBox:SetCursorPosition(0)
		else
			-- Show normal list, hide raw editor
			rawBoxHolder:Hide()
			listBox:Show()
			self:Refresh()
		end
	end)

	-- Raw edit box handler
	rawEditBox:SetScript("OnTextChanged", function(eb, userInput)
		if userInput then
			local p = GetActiveProfile(db)
			-- Parse the text to remove comments and save clean data
			p.listText = ParseRawViewText(eb:GetText() or "")
			-- Don't refresh while typing - it resets the cursor!
		end
	end)

	-- Profile dropdown
	local function ProfileDropdown_Initialize()
		local info = UIDropDownMenu_CreateInfo()
		for key in pairs(db.profiles) do
			info.text = key
			info.value = key
			info.func = function(btn)
				db.chars[charKey] = btn.value
				print("|cff00ff00AutoDelete|r: Switched to profile '" .. btn.value .. "'")
				self:Refresh()
			end
			info.checked = (key == (select(2, GetActiveProfile(db))))
			UIDropDownMenu_AddButton(info)
		end
	end

	UIDropDownMenu_Initialize(profileDropdown, ProfileDropdown_Initialize)
	UIDropDownMenu_SetWidth(profileDropdown, 180)
	UIDropDownMenu_JustifyText(profileDropdown, "LEFT")

	-- Row remove handlers
	for i = 1, #self._rows do
		local row = self._rows[i]
		row.remove:SetScript("OnClick", function()
			if row.entry then
				local p = GetActiveProfile(db)
				local itemName = GetDisplayForEntry(row.entry)
				p.listText = RemoveExactLine(p.listText or "", row.entry.raw)
				print("|cff00ff00AutoDelete|r: Removed " .. itemName)
				self:Refresh()
			end
		end)
	end

	-- Scroll handler
	scroll:SetScript("OnVerticalScroll", function(selfScroll, offset)
		FauxScrollFrame_OnVerticalScroll(selfScroll, offset, 18, function()
			self:UpdateListRows()
		end)
	end)

	-- ========================================================================
	-- Refresh Functions
	-- ========================================================================

	function self:Refresh()
		local p, pkey = GetActiveProfile(db)

		check:SetChecked(p.enabled and true or false)
		grayCheck:SetChecked(p.autoGray and true or false)

		UIDropDownMenu_SetSelectedValue(profileDropdown, pkey)
		UIDropDownMenu_SetText(profileDropdown, pkey)

		-- Only update the visible view
		if rawBoxHolder:IsShown() then
			-- Show enhanced view with item names as comments
			rawEditBox:SetText(GenerateRawViewText(p.listText))
			rawEditBox:SetCursorPosition(0)
		else
			self._entries = ParseListText(p.listText or "")
			
			-- Cache all item IDs to ensure icons load
			for _, entry in ipairs(self._entries) do
				if entry.kind == "id" then
					GetItemInfo("item:" .. entry.id)
				end
			end
			
			SortEntries(self._entries)

			self._filtered = {}
			local f = Normalize(self._filterText or "")
			for _, e in ipairs(self._entries) do
				local name = GetDisplayForEntry(e)
				if f == "" or string.find(Normalize(name), f, 1, true) then
					table.insert(self._filtered, e)
				end
			end

			FauxScrollFrame_Update(scroll, #self._filtered, #self._rows, 18)
			self:UpdateListRows()
		end
	end

	function self:UpdateListRows()
		local offsetIdx = FauxScrollFrame_GetOffset(scroll)
		local hasItems = #self._filtered > 0
		if hasItems then
			emptyText:Hide()
		else
			emptyText:Show()
		end

		for i = 1, #self._rows do
			local idx = i + offsetIdx
			local row = self._rows[i]
			local entry = self._filtered[idx]

			row.entry = entry
			if entry then
				local dispName, icon = GetDisplayForEntry(entry)
				if icon then
					row.icon:SetTexture(icon)
					row.icon:Show()
				else
					row.icon:Hide()
				end
				row.text:SetText(dispName)
				row:Show()
			else
				row:Hide()
			end
		end
	end

	self._built = true
	self:Refresh()
end

-- Show handler
panel:SetScript("OnShow", function(self)
	if not self._built then
		BuildPanelUI(self)
	else
		self:Refresh()
	end
end)

-- Register with interface options
InterfaceOptions_AddCategory(panel)
