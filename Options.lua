if _G.AutoDeleteFrame then return end

local ADDON_NAME = ...

-- ============================================================================
-- Style Constants
-- ============================================================================

local WHITE8x8 = "Interface\\Buttons\\WHITE8x8"
-- FRIZQT is always present in WoW 3.3.5a, no external dependency needed.
local FONT = "Fonts\\FRIZQT__.TTF"

local function RGB(r, g, b, a) return r / 255, g / 255, b / 255, a or 1 end

-- Core colors
local C_BG        = { RGB(5, 5, 5, 1) }        -- #050505 frame bg per CSS
local C_BORDER    = { 0.16, 0.16, 0.16, 1 }   -- #2a2a2a outer frame border per CSS
local C_TITLE     = { 1.00, 0.50, 0.00, 1 }  -- #ff8000 WoW legendary orange
local C_TEXT      = { 0.85, 0.85, 0.85, 1 }   -- #D9D9D9
local C_DIM       = { 0.45, 0.45, 0.45, 1 }   -- #737373
local C_HOVER     = { 0.122, 0.435, 0.659, 1 }   -- mage blue #1F6FA8
local C_RED       = { 0.75, 0.22, 0.22, 1 }
local C_GREEN     = { 0.20, 0.75, 0.20, 1 }
local C_ACCENT    = { 1.00, 0.50, 0.00, 1 }   -- #ff8000 WoW legendary orange
local C_DK_RED    = { 0.77, 0.12, 0.23, 1 }   -- #C41E3A WoW Death Knight class color
-- Exact WoW item quality colors (used for rarity toggles)
local C_Q_POOR     = { 0.62, 0.62, 0.62, 1 }   -- #9d9d9d (Junk)
local C_Q_COMMON   = { 1.00, 1.00, 1.00, 1 }   -- #ffffff (Common / white)
local C_Q_UNCOMMON = { 0.12, 1.00, 0.00, 1 }   -- #1eff00
local C_Q_RARE     = { 0.00, 0.44, 0.87, 1 }   -- #0070dd
local C_Q_EPIC     = { 0.64, 0.21, 0.93, 1 }   -- #a335ee
local C_ROW_ODD   = { RGB(11, 11, 11, 1) }    -- #0b0b0b per CSS
local C_ROW_EVEN  = { RGB(14, 14, 14, 1) }    -- #0e0e0e per CSS
local C_ROW_HOVER = { RGB(20, 45, 70, 1) }    -- mage blue row hover #142D46
local C_DROP_BG   = { RGB(14, 14, 14, 1) }
local C_DROP_BORDER = { 0.25, 0.25, 0.25, 1 }
local C_TITLEBAR  = { RGB(16, 16, 16, 1) }

-- ============================================================================
-- Helper Functions
-- ============================================================================

local function ApplyBackdrop(frame, bgColor, borderColor)
	frame:SetBackdrop({ bgFile = WHITE8x8, edgeFile = WHITE8x8, edgeSize = 1 })
	frame:SetBackdropColor(unpack(bgColor or C_BG))
	frame:SetBackdropBorderColor(unpack(borderColor or C_BORDER))
end

local function MakeText(parent, size, color, flag, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, size, flag or "OUTLINE")
	fs:SetTextColor(unpack(color or C_TEXT))
	if justify then fs:SetJustifyH(justify) end
	return fs
end

local function MakeSeparator(parent, yOff)
	local sep = parent:CreateTexture(nil, "ARTWORK")
	sep:SetTexture(WHITE8x8)
	sep:SetHeight(1)
	sep:SetPoint("TOPLEFT", 15, yOff)
	sep:SetPoint("RIGHT", -15, 0)
	sep:SetVertexColor(0.15, 0.15, 0.15, 1)
	return sep
end

-- PEADAR-style toggle: 16x16 box + 8x8 indicator
local function MakeToggle(parent, label, color, tooltip, tooltipTitle)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(290, 20)

	local box = CreateFrame("Frame", nil, row)
	box:SetSize(14, 14)
	box:SetPoint("LEFT", 0, 0)
	ApplyBackdrop(box, C_ROW_ODD, C_BORDER)

	-- Bundled TGA check (128x128 for smooth downsample). Tried Unicode ✓ glyph
	-- but FRIZQT__.TTF on 3.3.5 renders it poorly. TGA is reliable.
	local indicator = box:CreateTexture(nil, "OVERLAY")
	indicator:SetTexture("Interface\\AddOns\\AutoDelete\\textures\\checkmark.tga")
	indicator:SetPoint("CENTER", box, "CENTER", 0, 0)
	indicator:SetSize(14, 14)
	indicator:SetVertexColor(1, 1, 1, 1)
	indicator:Hide()

	local text = MakeText(row, 10, C_TEXT, "OUTLINE")
	text:SetPoint("LEFT", box, "RIGHT", 8, 0)
	text:SetPoint("RIGHT", row, "RIGHT", -2, 0)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(true)
	text:SetText(label)

	row._checked = false
	local activeColor = color or C_ACCENT

	local function UpdateVisual()
		if row._checked then
			-- Checked: solid accent fill with slightly-brighter border of same hue, white glyph.
			local lighter = {
				math.min(activeColor[1] + 0.10, 1),
				math.min(activeColor[2] + 0.10, 1),
				math.min(activeColor[3] + 0.10, 1),
				1,
			}
			ApplyBackdrop(box, activeColor, lighter)
			indicator:Show()
		else
			-- Unchecked: dark box, medium-gray border, no glyph.
			ApplyBackdrop(box, { 0.04, 0.04, 0.04, 1 }, { 0.33, 0.33, 0.33, 1 })
			indicator:Hide()
		end
	end

	function row:SetChecked(val)
		row._checked = val and true or false
		UpdateVisual()
	end
	function row:GetChecked() return row._checked end

	row:SetScript("OnClick", function()
		row._checked = not row._checked
		UpdateVisual()
	end)

	if tooltip then
		local ttTitle = tooltipTitle or label
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(ttTitle, 1, 1, 1)
			-- The 4th param to AddLine is `wrap`. Without it, long descriptions
			-- render as one ultra-wide line stretching across the screen.
			GameTooltip:AddLine(tooltip, C_DIM[1], C_DIM[2], C_DIM[3], true)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end

	return row
end

-- PEADAR-style custom dropdown
local function MakeDropdown(parent, width, options, onChange)
	local dd = CreateFrame("Frame", nil, parent)
	dd:SetSize(width, 22)

	-- Button: flat near-black bg, thin black border, subtle 1px top gloss
	-- highlight line, teal-tinted border on hover.
	local btn = CreateFrame("Button", nil, dd)
	btn:SetAllPoints()
	btn:SetBackdrop({ bgFile = WHITE8x8, edgeFile = WHITE8x8, edgeSize = 1 })
	btn:SetBackdropColor(0.09, 0.09, 0.09, 1)
	btn:SetBackdropBorderColor(0, 0, 0, 1)
	btn:SetFrameStrata(parent:GetFrameStrata() or "DIALOG")
	btn:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)

	-- Top gloss highlight line
	local gloss = btn:CreateTexture(nil, "OVERLAY")
	gloss:SetTexture(WHITE8x8)
	gloss:SetVertexColor(1, 1, 1, 0.08)
	gloss:SetHeight(1)
	gloss:SetPoint("TOPLEFT", 1, -1)
	gloss:SetPoint("TOPRIGHT", -1, -1)

	local btnText = btn:CreateFontString(nil, "OVERLAY")
	btnText:SetDrawLayer("OVERLAY", 7)
	btnText:SetFont(FONT, 11)
	btnText:SetTextColor(1, 1, 1, 1)
	btnText:SetShadowColor(0, 0, 0, 0)
	btnText:SetPoint("LEFT", 8, 0)
	btnText:SetPoint("RIGHT", -20, 0)
	btnText:SetJustifyH("LEFT")

	-- Arrow - uses pre-rotated arrowdown.tga (no SetRotation needed).
	-- Pre-rotated textures render at exactly the size specified, unlike
	-- rotated textures which WoW 3.3.5 scales slightly inconsistently.
	local arrow = btn:CreateTexture(nil, "OVERLAY", nil, 7)
	arrow:SetTexture("Interface\\AddOns\\AutoDelete\\textures\\arrowdown.tga")
	arrow:SetSize(10, 10)
	arrow:SetPoint("RIGHT", -6, 0)
	arrow:SetVertexColor(1, 1, 1, 1)

	btn:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.14, 0.14, 0.14, 1)
		self:SetBackdropBorderColor(0.25, 0.55, 0.65, 1)
		gloss:SetVertexColor(1, 1, 1, 0.14)
	end)
	btn:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.09, 0.09, 0.09, 1)
		self:SetBackdropBorderColor(0, 0, 0, 1)
		gloss:SetVertexColor(1, 1, 1, 0.08)
	end)

	-- Popup as its own top-level frame so nothing from the panel overlays it
	local popup = CreateFrame("Frame", nil, UIParent)
	popup:SetToplevel(true)
	popup:EnableMouse(true)
	popup:SetClampedToScreen(true)
	popup:SetFrameStrata("FULLSCREEN_DIALOG")
	popup:SetFrameLevel(1000)
	popup:SetWidth(width)
	ApplyBackdrop(popup, { 0, 0, 0, 1 }, { 0.7, 0.7, 0.7, 1 })
	popup:Hide()

	dd._popup = popup

	local popupRows = {}
	for i, opt in ipairs(options) do
		local row = CreateFrame("Button", nil, popup)
		row:SetHeight(20)
		row:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 20)
		row:SetPoint("RIGHT", -1, 0)
		row:SetFrameStrata("FULLSCREEN_DIALOG")
		row:SetFrameLevel(1001)

		local rowBG = row:CreateTexture(nil, "BACKGROUND")
		rowBG:SetTexture(WHITE8x8)
		rowBG:SetAllPoints()
		rowBG:SetVertexColor(0.02, 0.02, 0.02, 1)

		local rowText = row:CreateFontString(nil, "OVERLAY")
		rowText:SetDrawLayer("OVERLAY", 7)
		rowText:SetFont(FONT, 11)
		rowText:SetTextColor(1, 1, 1, 1)
		rowText:SetShadowColor(0, 0, 0, 0)
		rowText:SetJustifyH("LEFT")
		rowText:SetPoint("LEFT", 8, 0)
		rowText:SetPoint("RIGHT", -8, 0)
		rowText:SetText(opt.label)

		row:SetScript("OnEnter", function()
			rowBG:SetVertexColor(0.12, 0.35, 0.40, 1)
		end)
		row:SetScript("OnLeave", function()
			rowBG:SetVertexColor(0.02, 0.02, 0.02, 1)
		end)
		row:SetScript("OnClick", function()
			popup:Hide()
			btnText:SetText(opt.label)
			dd._value = opt.value
			if onChange then onChange(opt.value) end
		end)
		popupRows[i] = row
	end
	popup:SetHeight(2 + #options * 20)

	local clickCatcher = CreateFrame("Button", nil, UIParent)
	clickCatcher:SetAllPoints(UIParent)
	clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
	clickCatcher:SetFrameLevel(999)
	clickCatcher:EnableMouse(true)
	clickCatcher:RegisterForClicks("AnyDown")
	clickCatcher:Hide()
	clickCatcher:SetScript("OnClick", function()
		popup:Hide()
	end)

	local function ShowPopup()
		popup:ClearAllPoints()
		popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)
		clickCatcher:Show()
		popup:Show()
	end

	btn:SetScript("OnClick", function()
		if popup:IsShown() then
			popup:Hide()
		else
			ShowPopup()
		end
	end)

	popup:SetScript("OnShow", function()
		clickCatcher:Show()
	end)

	popup:SetScript("OnHide", function()
		clickCatcher:Hide()
	end)

	parent:HookScript("OnHide", function()
		if popup:IsShown() then popup:Hide() end
	end)

	function dd:SetValue(val)
		dd._value = val
		for _, opt in ipairs(options) do
			if opt.value == val then
				btnText:SetText(opt.label)
				return
			end
		end
		btnText:SetText(tostring(val))
	end
	function dd:GetValue() return dd._value end

	-- Dynamic options rebuild. Used by tabs whose dropdown contents change
	-- at runtime (e.g. Profiles tab - character names may be added/deleted).
	-- Rebuilds the popup row pool, resets selection, preserves size.
	function dd:SetOptions(newOptions)
		-- Hide + remove existing rows.
		for _, row in ipairs(popupRows) do
			row:Hide()
			row:SetParent(nil)
		end
		-- Rebuild the options upvalue so SetValue still finds labels.
		options = newOptions or {}
		popupRows = {}
		for i, opt in ipairs(options) do
			local row = CreateFrame("Button", nil, popup)
			row:SetHeight(20)
			row:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 20)
			row:SetPoint("RIGHT", -1, 0)
			row:SetFrameStrata("FULLSCREEN_DIALOG")
			row:SetFrameLevel(1001)

			local rowBG = row:CreateTexture(nil, "BACKGROUND")
			rowBG:SetTexture(WHITE8x8)
			rowBG:SetAllPoints()
			rowBG:SetVertexColor(0.02, 0.02, 0.02, 1)

			local rowText = row:CreateFontString(nil, "OVERLAY")
			rowText:SetDrawLayer("OVERLAY", 7)
			rowText:SetFont(FONT, 12)
			rowText:SetTextColor(1, 1, 1, 1)
			rowText:SetShadowColor(0, 0, 0, 0)
			rowText:SetJustifyH("LEFT")
			rowText:SetPoint("LEFT", 8, 0)
			rowText:SetPoint("RIGHT", -8, 0)
			rowText:SetText(opt.label)

			row:SetScript("OnEnter", function()
				rowBG:SetVertexColor(0.12, 0.35, 0.40, 1)
			end)
			row:SetScript("OnLeave", function()
				rowBG:SetVertexColor(0.02, 0.02, 0.02, 1)
			end)
			row:SetScript("OnClick", function()
				popup:Hide()
				btnText:SetText(opt.label)
				dd._value = opt.value
				if onChange then onChange(opt.value) end
			end)
			popupRows[i] = row
		end
		popup:SetHeight(2 + #options * 20)
		-- Don't change the displayed label - caller decides what to show via SetValue.
	end

	return dd
end

-- ============================================================================
-- Section Helpers
-- ============================================================================

-- AutoSizeSection: set a section's height based on its lowest child element.
-- Uses GetTop/GetBottom which return absolute screen coords - valid as long as
-- both the section and the element have been SetPoint'd and the frame is shown.
-- Falls back to leaving the section at its current height if coords are nil.
local function AutoSizeSection(section, lastElement, padding, fallback)
	padding = padding or 8
	fallback = fallback or 80
	local top = section:GetTop()
	local bottom = lastElement:GetBottom()
	if top and bottom then
		local h = top - bottom + padding
		if h < 20 then h = 20 end
		section:SetHeight(h)
	else
		-- Layout not resolved yet; use safe fallback
		section:SetHeight(fallback)
	end
	return section:GetHeight()
end

-- MakeSection: titled bordered box.
-- title appears above the box in C_TITLE gold; box has subtle border + dark bg.
-- Returns the content box frame. Caller sets its height and anchors children inside.
-- MakeSpinnerInput: numeric input with up/down arrow spin buttons on the right.
-- Uses Blizzard's stock UIPanelSquareButton textures for reliable arrow rendering.
-- Returns the outer frame (for anchoring) and its .editBox (for value access).
local function MakeSpinnerInput(parent, width, height, minVal, maxVal, onChanged)
	minVal = minVal or 1
	maxVal = maxVal or 9999
	height = height or 22

	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(width, height)
	ApplyBackdrop(frame, C_DROP_BG, C_DROP_BORDER)

	-- The numeric editbox takes most of the width, arrows take the right ~14px
	local ARROW_W = 16
	local editBox = CreateFrame("EditBox", nil, frame)
	editBox:SetFont(FONT, 11)
	editBox:SetTextColor(1, 1, 1)
	editBox:SetAutoFocus(false)
	editBox:SetNumeric(true)
	editBox:SetMaxLetters(4)
	editBox:SetJustifyH("CENTER")
	editBox:SetPoint("TOPLEFT", 5, -2)
	editBox:SetPoint("BOTTOMRIGHT", -ARROW_W - 4, 2)
	editBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
	editBox:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)

	-- Clamp + callback wrapper
	local function CommitValue(val)
		if val < minVal then val = minVal end
		if val > maxVal then val = maxVal end
		editBox:SetText(tostring(val))
		if onChanged then onChanged(val) end
	end

	editBox:SetScript("OnEditFocusLost", function(s)
		local v = tonumber(s:GetText()) or minVal
		CommitValue(v)
	end)

	-- Up arrow: pre-rotated arrowup.tga
	local upBtn = CreateFrame("Button", nil, frame)
	upBtn:SetSize(ARROW_W, math.floor(height / 2))
	upBtn:SetPoint("TOPRIGHT", -1, -1)
	local upGlyph = upBtn:CreateTexture(nil, "OVERLAY")
	upGlyph:SetTexture("Interface\\AddOns\\AutoDelete\\textures\\arrowup.tga")
	upGlyph:SetSize(9, 9)
	upGlyph:SetPoint("CENTER", 0, 0)
	upGlyph:SetVertexColor(1, 1, 1, 1)
	upBtn:SetScript("OnClick", function()
		local cur = tonumber(editBox:GetText()) or minVal
		CommitValue(cur + 1)
	end)
	upBtn:SetScript("OnEnter", function() upGlyph:SetVertexColor(C_HOVER[1], C_HOVER[2], C_HOVER[3], 1) end)
	upBtn:SetScript("OnLeave", function() upGlyph:SetVertexColor(1, 1, 1, 1) end)

	-- Down arrow: pre-rotated arrowdown.tga (no SetRotation needed)
	local downBtn = CreateFrame("Button", nil, frame)
	downBtn:SetSize(ARROW_W, math.floor(height / 2))
	downBtn:SetPoint("BOTTOMRIGHT", -1, 1)
	local downGlyph = downBtn:CreateTexture(nil, "OVERLAY")
	downGlyph:SetTexture("Interface\\AddOns\\AutoDelete\\textures\\arrowdown.tga")
	downGlyph:SetSize(9, 9)
	downGlyph:SetPoint("CENTER", 0, 0)
	downGlyph:SetVertexColor(1, 1, 1, 1)
	downBtn:SetScript("OnClick", function()
		local cur = tonumber(editBox:GetText()) or minVal
		CommitValue(cur - 1)
	end)
	downBtn:SetScript("OnEnter", function() downGlyph:SetVertexColor(C_HOVER[1], C_HOVER[2], C_HOVER[3], 1) end)
	downBtn:SetScript("OnLeave", function() downGlyph:SetVertexColor(1, 1, 1, 1) end)

	-- Thin divider between the editbox and the arrow column
	local divider = frame:CreateTexture(nil, "OVERLAY")
	divider:SetTexture(WHITE8x8)
	divider:SetVertexColor(0.22, 0.22, 0.22, 1)
	divider:SetPoint("TOPRIGHT", -ARROW_W - 1, -1)
	divider:SetPoint("BOTTOMRIGHT", -ARROW_W - 1, 1)
	divider:SetWidth(1)

	frame.editBox = editBox
	frame.upBtn = upBtn
	frame.downBtn = downBtn
	return frame
end

local function MakeSection(parent, title, yOff, height, leftMargin, rightMargin)
	leftMargin = leftMargin or 15
	rightMargin = rightMargin or 15

	local titleFS = parent:CreateFontString(nil, "OVERLAY")
	titleFS:SetFont(FONT, 13, "OUTLINE")
	titleFS:SetTextColor(unpack(C_TITLE))
	titleFS:SetPoint("TOPLEFT", leftMargin, yOff)
	titleFS:SetText(title)

	local box = CreateFrame("Frame", nil, parent)
	box:SetPoint("TOPLEFT", parent, "TOPLEFT", leftMargin, yOff - 16)
	box:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -rightMargin, yOff - 16)
	box:SetHeight(height)
	-- Per CSS: panel bg #0a0a0a, border #1f1f1f
	box:SetBackdrop({ bgFile = WHITE8x8, edgeFile = WHITE8x8, edgeSize = 1 })
	box:SetBackdropColor(0.04, 0.04, 0.04, 1)
	box:SetBackdropBorderColor(0.12, 0.12, 0.12, 1)

	return box, titleFS
end

-- AddToggleDescription: attaches a dim multi-line description below a toggle.
-- Positioned indented under the toggle's text label (not the box).
local function AddToggleDescription(toggle, description, maxWidth)
	local parent = toggle:GetParent()
	local desc = parent:CreateFontString(nil, "OVERLAY")
	desc:SetFont(FONT, 10, "OUTLINE")
	desc:SetTextColor(unpack(C_DIM))
	-- Indent: 26 = 18 box + 8 gap → aligns with toggle label's left edge exactly
	desc:SetPoint("TOPLEFT", toggle, "BOTTOMLEFT", 26, -1)
	desc:SetWidth(maxWidth or 140)
	desc:SetJustifyH("LEFT")
	desc:SetWordWrap(true)
	desc:SetText(description)
	toggle._desc = desc
	return desc
end

-- ============================================================================
-- Database Functions
-- ============================================================================

-- Partial fallback schema used by Options.lua's own EnsureProfileFields call
-- path. The canonical full DEFAULT_PROFILE lives in AutoDelete.lua. This copy
-- only needs the fields the UI itself reads or writes; AutoDelete.lua runs its
-- own EnsureProfileFields too, which fills in everything else (Auto-Invite
-- options, Hide Spam, summon options, etc.). Whichever file's GetDB executes
-- first does the migration and the other becomes a no-op for already-set
-- fields.
local DEFAULT_PROFILE = {
	enabled = false,
	listText = "",
	sellListText = "",
	whitelistText = "",
	autoGray = false,
	scanInterval = 0.5,
	autoDeleteCommon  = false,
	autoSellGreens    = false,
	boeArmorEnabled   = false,
	boeArmorIlvlMin   = 1,
	boeArmorIlvlMax   = 199,
	boeArmorRare      = false,
	boeArmorEpic      = false,
	bopEnabled        = false,
	bopIlvlMin        = 1,
	bopIlvlMax        = 199,
	bopRare           = false,
	bopEpic           = false,
	boeWeaponsEnabled = false,
	boeWeaponsIlvlMin = 1,
	boeWeaponsIlvlMax = 199,
	boeWeaponsRare    = false,
	boeWeaponsEpic    = false,
	summonScavenger   = false,
}

local function GetCharKey()
	local name = UnitName("player")
	local realm = GetRealmName and GetRealmName() or nil
	if not name then return nil end
	if realm and realm ~= "" then return name .. "-" .. realm end
	return name
end

local function EnsureProfileFields(p)
	-- Invert old dontSellBoEWeapons field into sellBoEWeapons.
	if p.dontSellBoEWeapons ~= nil then
		p.sellBoEWeapons = not p.dontSellBoEWeapons
		p.dontSellBoEWeapons = nil
	end
	-- Old profiles stored the weapon iLvl threshold as sellBoEWeaponMinIlvl
	-- acting as a floor. The range model renamed it to sellBoEWeaponMaxIlvl
	-- as the ceiling. Only migrate when the new field is absent so current
	-- range-min values are preserved.
	if p.sellBoEWeaponMinIlvl ~= nil and p.sellBoEWeaponMaxIlvl == nil then
		p.sellBoEWeaponMaxIlvl = p.sellBoEWeaponMinIlvl
		p.sellBoEWeaponMinIlvl = nil
	end

	-- v3.02 schema migration. Mirrors the logic in AutoDelete.lua so it runs
	-- correctly regardless of which file's GetDB executes first.
	local hasOldFields = (p.sellJunk ~= nil) or (p.sellGreen ~= nil)
		or (p.sellBlue ~= nil) or (p.sellEpic ~= nil)
		or (p.sellBoE ~= nil) or (p.sellBoEWeapons ~= nil)
		or (p.sellIlvlEnabled ~= nil)
	if hasOldFields and not p._v302Migrated then
		if p.sellJunk == true then p.autoGray = true end
		p.autoDeleteCommon = false
		p.autoSellGreens   = (p.sellGreen == true)

		local hadIlvlRange = (p.sellIlvlEnabled == true)
		p.boeArmorEnabled = (p.sellBoE == true)
		p.boeArmorRare    = (p.sellBoE == true) and (p.sellBlue == true)
		p.boeArmorEpic    = (p.sellBoE == true) and (p.sellEpic == true)
		if hadIlvlRange and p.sellIlvlMin then p.boeArmorIlvlMin = p.sellIlvlMin end
		if hadIlvlRange and p.sellIlvlMax then p.boeArmorIlvlMax = p.sellIlvlMax end

		p.bopEnabled = false
		p.bopRare    = false
		p.bopEpic    = false

		p.boeWeaponsEnabled = (p.sellBoEWeapons == true)
		p.boeWeaponsRare    = (p.sellBoEWeapons == true) and (p.sellBlue == true)
		p.boeWeaponsEpic    = (p.sellBoEWeapons == true) and (p.sellEpic == true)
		if p.sellBoEWeaponMinIlvl then p.boeWeaponsIlvlMin = p.sellBoEWeaponMinIlvl end
		if p.sellBoEWeaponMaxIlvl then p.boeWeaponsIlvlMax = p.sellBoEWeaponMaxIlvl end

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
		_G._AutoDelete_NeedMigrationNotice = true
	end

	for k, v in pairs(DEFAULT_PROFILE) do
		if p[k] == nil then p[k] = v end
	end
end

local function GetDB()
	_G.AutoDeleteDB = _G.AutoDeleteDB or {}
	local db = _G.AutoDeleteDB
	db.profiles = db.profiles or {}
	db.chars = db.chars or {}
	local charKey = GetCharKey() or "Default"
	local profileKey = db.chars[charKey] or charKey
	if not db.profiles[profileKey] then
		local p = {}
		for k, v in pairs(DEFAULT_PROFILE) do p[k] = v end
		db.profiles[profileKey] = p
	end
	EnsureProfileFields(db.profiles[profileKey])
	if not db.chars[charKey] then db.chars[charKey] = profileKey end
	return db
end

local function GetActiveProfile(db)
	local charKey = GetCharKey() or "Default"
	local profileKey = (db and db.chars and db.chars[charKey]) or charKey
	if not db.profiles[profileKey] then
		local p = {}
		for k, v in pairs(DEFAULT_PROFILE) do p[k] = v end
		db.profiles[profileKey] = p
	end
	EnsureProfileFields(db.profiles[profileKey])
	return db.profiles[profileKey], profileKey, charKey
end

-- ============================================================================
-- Item Utility Functions
-- ============================================================================

local function Trim(s)
	-- Parens truncate gsub's multi-return (string + count) to just the string.
	return (string.gsub(string.gsub(tostring(s or ""), "^%s+", ""), "%s+$", ""))
end
local function Normalize(s) return string.lower(Trim(s)) end
local function GetItemIDFromLink(link)
	if not link then return nil end
	return tonumber(string.match(link, "item:(%d+)"))
end

local function ParseListText(listText)
	local entries = {}
	for line in string.gmatch(listText or "", "[^\r\n]+") do
		local raw = Trim(line)
		raw = string.gsub(raw, "%s*#.*$", "")
		raw = Trim(raw)
		if raw ~= "" then
			local itemId = tonumber(string.match(raw, "^item:(%d+)"))
			if itemId then
				table.insert(entries, { kind = "id", id = itemId, raw = "item:" .. itemId })
			else
				table.insert(entries, { kind = "name", name = raw, raw = raw })
			end
		end
	end
	return entries
end

local function CountListItems(listText)
	local count = 0
	for line in string.gmatch(listText or "", "[^\r\n]+") do
		local raw = Trim(line)
		raw = string.gsub(raw, "%s*#.*$", "")
		if Trim(raw) ~= "" then count = count + 1 end
	end
	return count
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

local function RemoveExactLine(listText, line)
	line = Trim(line)
	if line == "" then return listText or "" end
	local out = {}
	for l in string.gmatch(listText or "", "[^\r\n]+") do
		local tl = Trim(l)
		if tl ~= "" and tl ~= line then table.insert(out, tl) end
	end
	return table.concat(out, "\n") .. (#out > 0 and "\n" or "")
end

local function GetDisplayForEntry(entry)
	if entry.kind == "id" then
		local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(entry.id)
		if name then return name, icon, link, quality end
		GetItemInfo("item:" .. entry.id)
		return "item:" .. entry.id, nil, nil, nil
	end
	return entry.name, nil, nil, nil
end

local function GenerateRawViewText(listText)
	local lines = {}
	for line in string.gmatch(listText or "", "[^\r\n]+") do
		local raw = Trim(line)
		if raw ~= "" then
			local itemId = tonumber(string.match(raw, "^item:(%d+)"))
			if itemId then
				local itemName = GetItemInfo(itemId)
				table.insert(lines, itemName and (raw .. "    # " .. itemName) or raw)
			else
				table.insert(lines, raw)
			end
		end
	end
	return table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")
end

local function ParseRawViewText(text)
	local lines, seen = {}, {}
	for line in string.gmatch(text or "", "[^\r\n]+") do
		local raw = Trim(string.gsub(Trim(line), "%s*#.*$", ""))
		if raw ~= "" and not seen[raw] then
			seen[raw] = true
			table.insert(lines, raw)
		end
	end
	return table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")
end

-- Sort entries by display name. Default is ascending (A->Z); pass true
-- for descending (Z->A). Used by the column header click-to-sort and the
-- regular alphabetic refresh path.
local function SortEntries(entries, descending)
	if descending then
		table.sort(entries, function(a, b)
			return Normalize(GetDisplayForEntry(a)) > Normalize(GetDisplayForEntry(b))
		end)
	else
		table.sort(entries, function(a, b)
			return Normalize(GetDisplayForEntry(a)) < Normalize(GetDisplayForEntry(b))
		end)
	end
end

-- ============================================================================
-- Main Frame
-- ============================================================================

local frame = CreateFrame("Frame", "AutoDeleteFrame", UIParent)
frame:SetSize(580, 840)   -- 540+40 to give cards more breathing room
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetFrameLevel(100)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetClampedToScreen(true)
ApplyBackdrop(frame, C_BG, C_BORDER)
frame:Hide()

-- ESC to close
tinsert(UISpecialFrames, "AutoDeleteFrame")

-- Drag via title bar
local titleBar = CreateFrame("Frame", nil, frame)
titleBar:SetPoint("TOPLEFT"); titleBar:SetPoint("TOPRIGHT")
titleBar:SetHeight(24)
ApplyBackdrop(titleBar, C_TITLEBAR, C_BORDER)
titleBar:EnableMouse(true)
titleBar:SetScript("OnMouseDown", function() frame:StartMoving() end)
titleBar:SetScript("OnMouseUp", function()
	frame:StopMovingOrSizing()
	local db = GetDB()
	local point, _, relPoint, x, y = frame:GetPoint()
	db.framePos = { point = point, relPoint = relPoint, x = x, y = y }
end)

local titleText = MakeText(titleBar, 12, C_TITLE, "OUTLINE")
titleText:SetPoint("LEFT", 10, 0)
local addonVersion = GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version")
if addonVersion and addonVersion ~= "" then
	titleText:SetText("AutoDelete v" .. addonVersion)
else
	titleText:SetText("AutoDelete")
end

-- Close button: text "x" at 14pt
local closeBtn = CreateFrame("Button", nil, titleBar)
closeBtn:SetSize(24, 24)
closeBtn:SetPoint("TOPRIGHT", 0, 0)
local closeBtnText = MakeText(closeBtn, 14, C_DIM, "OUTLINE")
closeBtnText:SetPoint("CENTER")
closeBtnText:SetText("x")
closeBtn:SetScript("OnEnter", function() closeBtnText:SetTextColor(1, 0.3, 0.3) end)
closeBtn:SetScript("OnLeave", function() closeBtnText:SetTextColor(unpack(C_DIM)) end)
closeBtn:SetScript("OnClick", function() frame:Hide() end)

-- Global ref for AutoDelete.lua panel checks
_G.AutoDeleteOptionsPanel = frame

-- ============================================================================
-- Build UI
-- ============================================================================

local function BuildUI(self)
	local db = GetDB()
	local profile, profileKey, charKey = GetActiveProfile(db)
	self._db = db
	self._charKey = charKey
	self._listMode = "delete"

	-- Restore position
	if db.framePos then
		self:ClearAllPoints()
		self:SetPoint(db.framePos.point, UIParent, db.framePos.relPoint,
			db.framePos.x, db.framePos.y)
	end

	-- ========================================================================
	-- Settings frame layout: four titled bordered sections, top to bottom:
	--   1. Tabbed Settings (General / Goblin / AutoInv / Tracking / Profiles)
	--   2. Sell rules - three category cards (BoE Armor / BoP / BoE Weapons)
	--   3. Scan Options - Delete / Sell / Keep list-mode tabs
	--   4. Search & Manage - search row + active list view
	-- The Auto-Delete Junk / Common and Auto-Sell Greens toggles live INSIDE
	-- Section 1's General tab (card 2), not as a standalone section.
	-- ========================================================================
	-- ========================================================================
	-- GRID (everything anchors to these positions)
	-- ========================================================================
	local LEFT_EDGE = 15       -- section title + section box left edge
	local CONTENT_START = 20   -- content inside section boxes
	local LABEL_START = 20     -- label text start (same as content start)
	local INPUT_START = 200    -- right-column value/input start
	local RIGHT_EDGE = 565     -- right margin (580 - 15)

	local LEFT_X = LEFT_EDGE
	local RIGHT_X = RIGHT_EDGE
	local CONTENT_W = RIGHT_X - LEFT_X                                     -- 550 (580 frame - 2*15 margins)
	local INPUT_W = 60                                                     -- numeric input width
	local INPUT_GAP = 8
	local SECTION_GAP = 6                                                  -- vertical space between sections
	local TOP_PAD = 12                                                     -- top padding inside a section
	local BOT_PAD = 6                                                      -- bottom padding inside a section

	local yOff = -36

	-- ========================================================================
	-- SECTION 1: Tabbed Settings (General / Goblin / AutoInv / Tracking / Profiles)
	-- Container panel holds a horizontal tab strip at top + a fixed-height
	-- content area below. The General tab's three cards are:
	--   card 1: Enable (master toggle) + Auto-Delete Junk's parent description
	--   card 2: Auto-Delete Junk + Auto-Delete Common + Auto-Sell Greens (3 rows)
	--   card 3: Scan Speed dropdown
	-- ========================================================================
	local CARD_TOP_PAD = 6
	local CARD_BOT_PAD = 4

	-- Tabbed area geometry:
	-- Tab strip: 26px tall
	-- Content area: 82px tall (fits 4 cards at cardH=74 + 8px buffer)
	-- Inner padding: 6px on each side, 6px gap between strip and content
	local TAB_STRIP_H = 26
	local CONTENT_AREA_H = 100   -- grown from 82 to fit Tracking tab's Reset button below the rows
	local TAB_INNER_PAD = 6
	local TAB_STRIP_GAP = 6
	-- Total tab container height: strip + gap + content + inner padding
	local tabbedSectionH = TAB_STRIP_H + TAB_STRIP_GAP + CONTENT_AREA_H + TAB_INNER_PAD * 2

	-- Section container (same panel style as other sections)
	local tabbedBox = MakeSection(self, "Settings", yOff, tabbedSectionH)
	yOff = yOff - 16 - tabbedSectionH - SECTION_GAP

	-- Tab strip frame (horizontal row at top of tabbedBox)
	local tabStrip = CreateFrame("Frame", nil, tabbedBox)
	tabStrip:SetHeight(TAB_STRIP_H)
	tabStrip:SetPoint("TOPLEFT", TAB_INNER_PAD, -TAB_INNER_PAD)
	tabStrip:SetPoint("TOPRIGHT", -TAB_INNER_PAD, -TAB_INNER_PAD)

	-- Tab content frame (below tab strip, holds the 5 tab pages)
	local tabContent = CreateFrame("Frame", nil, tabbedBox)
	tabContent:SetHeight(CONTENT_AREA_H)
	tabContent:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", 0, -TAB_STRIP_GAP)
	tabContent:SetPoint("TOPRIGHT", tabStrip, "BOTTOMRIGHT", 0, -TAB_STRIP_GAP)

	-- Create 6 tab content pages (frames parented to tabContent, filling it)
	local tabPages = {}
	local TAB_KEYS = { "general", "goblin", "tools", "autoinv", "tracking", "profiles" }
	local TAB_LABELS = { "General", "Goblin", "Tools", "AutoInv", "Tracking", "Profiles" }
	for i, key in ipairs(TAB_KEYS) do
		local page = CreateFrame("Frame", nil, tabContent)
		page:SetAllPoints(tabContent)
		page:Hide()
		tabPages[key] = page
	end

	-- Active tab state (default: General). Stored on self for profile persistence later.
	self._activeSettingsTab = "general"

	-- Build tab buttons - styled same as Delete/Sell/Keep (orange fill when active)
	local TAB_BTN_H = TAB_STRIP_H - 2    -- 24px button height, 1px breathing room top/bottom
	local tabButtons = {}

	local function SetSettingsTabActive(key)
		self._activeSettingsTab = key
		for _, k in ipairs(TAB_KEYS) do
			local btn = tabButtons[k]
			local pg = tabPages[k]
			if k == key then
				-- Active: orange fill, dark text without OUTLINE for clean readability,
				-- bumped to 12pt to add visual weight (fakes bold on a tab strip).
				ApplyBackdrop(btn, { C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 0.9 }, C_ACCENT)
				btn._text:SetFont(FONT, 12, "")
				btn._text:SetTextColor(0.05, 0.05, 0.05, 1)
				pg:Show()
			else
				-- Inactive: dark bg, white outlined text
				ApplyBackdrop(btn, { 0.07, 0.07, 0.07, 1 }, { 0.20, 0.20, 0.20, 1 })
				btn._text:SetFont(FONT, 11, "OUTLINE")
				btn._text:SetTextColor(1, 1, 1, 1)
				pg:Hide()
			end
		end
		-- Refresh stats on tab activation so lifetime values show latest from disk.
		if key == "tracking" and self.RefreshTrackingStats then
			self:RefreshTrackingStats()
		end
		-- Refresh profile list when switching to Profiles tab so new alts
		-- logged-in-since-last-visit appear.
		if key == "profiles" and self.RefreshProfileList then
			self:RefreshProfileList()
		end
	end

	-- Build tab buttons - equal widths chained horizontally
	local TAB_BTN_GAP = 4
	for i, key in ipairs(TAB_KEYS) do
		local btn = CreateFrame("Button", nil, tabStrip)
		btn:SetHeight(TAB_BTN_H)
		local text = MakeText(btn, 11, { 1, 1, 1, 1 }, "OUTLINE")
		text:SetPoint("CENTER")
		text:SetText(TAB_LABELS[i])
		btn._text = text
		btn:SetScript("OnClick", function() SetSettingsTabActive(key) end)
		tabButtons[key] = btn
	end
	-- Anchor first and last tab buttons to strip edges; widths computed once
	-- First button anchors to strip LEFT; every subsequent button chains LEFT→RIGHT
	-- from the previous button with TAB_BTN_GAP. No RIGHT anchor on the last
	-- button (pinning both ends makes the trailing gap absorb the floor() remainder
	-- and look wider than the others).
	tabButtons[TAB_KEYS[1]]:SetPoint("LEFT", tabStrip, "LEFT", 0, 0)
	local function LayoutTabButtons()
		local stripW = tabStrip:GetWidth()
		if not stripW or stripW < 10 then return end
		local btnW = math.floor((stripW - TAB_BTN_GAP * (#TAB_KEYS - 1)) / #TAB_KEYS)
		for _, k in ipairs(TAB_KEYS) do
			tabButtons[k]:SetWidth(btnW)
		end
		-- Chain every button after the first to the previous one's RIGHT edge.
		for i = 2, #TAB_KEYS do
			local btn = tabButtons[TAB_KEYS[i]]
			local prev = tabButtons[TAB_KEYS[i - 1]]
			btn:ClearAllPoints()
			btn:SetPoint("LEFT", prev, "RIGHT", TAB_BTN_GAP, 0)
		end
	end
	tabStrip:SetScript("OnSizeChanged", LayoutTabButtons)
	local tabInitFrame = CreateFrame("Frame")
	tabInitFrame:SetScript("OnUpdate", function(s)
		s:SetScript("OnUpdate", nil)
		LayoutTabButtons()
		SetSettingsTabActive(self._activeSettingsTab)
	end)

	-- ========================================================================
	-- GENERAL TAB: 4 cards horizontally (Enable, Summon, Auto-Delete Junk, Scan Speed)
	-- Content area is 70px tall; cards occupy 62px centered vertically.
	-- ========================================================================
	local generalPage = tabPages.general
	local CARD_GAP = 6
	local CARD_INNER_PAD_X = 10
	local CARD_INNER_PAD_Y = CARD_TOP_PAD
	-- Content width inside tabContent: CONTENT_W - (2 * TAB_INNER_PAD). Account for outer pads.
	local genContentW = CONTENT_W - TAB_INNER_PAD * 2
	local cardW = math.floor((genContentW - CARD_GAP * 2) / 3)  -- 3 cards, 2 gaps
	local cardH = 92   -- fills the 100px tab content area (4px top + 4px bottom margins)

	local function MakeGeneralCard(xOff)
		local card = CreateFrame("Frame", nil, generalPage)
		card:SetSize(cardW, cardH)
		card:SetPoint("TOPLEFT", xOff, -4)
		card:SetBackdrop({ bgFile = WHITE8x8, edgeFile = WHITE8x8, edgeSize = 1 })
		card:SetBackdropColor(0.04, 0.04, 0.04, 1)    -- #0b0b0b per CSS
		card:SetBackdropBorderColor(0.14, 0.14, 0.14, 1)  -- #252525 per CSS
		return card
	end

	local card1 = MakeGeneralCard(0)
	local card2 = MakeGeneralCard(cardW + CARD_GAP)
	local card3 = MakeGeneralCard((cardW + CARD_GAP) * 2)

	local tglEnable = MakeToggle(card1, "Enable", C_ACCENT,
		"Master switch for the item-handling features. When enabled, AutoDelete scans your bags for items on the Delete list, runs Auto-Delete Junk/Common, runs Auto-Sell Greens, performs Auto-Repair at vendors, runs the BoE Armor/BoP/BoE Weapons sell rules, and manages the Greedy Scavenger and Goblin Merchant pets. Auto-Invite and Hide Greedy Spam are independent and run regardless of this switch.")
	tglEnable:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -CARD_INNER_PAD_Y)
	tglEnable:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	AddToggleDescription(tglEnable, "Allow AutoDelete to manage your items.",
		cardW - CARD_INNER_PAD_X * 2 - 26)
	self._tglEnable = tglEnable

	-- Row 3: Auto-Add Equipped. Single toggle that drives both behaviours:
	-- a one-time sync of currently equipped items into Keep on toggle-flip,
	-- and reactive add-to-Keep on every PLAYER_EQUIPMENT_CHANGED. Description
	-- omitted to fit in card1's 92px height under Enable + its description.
	local tglAutoAddEquipped = MakeToggle(card1, "Auto-Add Equipped", C_ACCENT,
		"When ON, every item you equip is added to the Keep list automatically. Toggling this on also syncs your currently equipped items to Keep as a one-time pass. Shirts and tabards are skipped.")
	tglAutoAddEquipped:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 44))
	tglAutoAddEquipped:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglAutoAddEquipped = tglAutoAddEquipped

	-- card2: Auto-Delete Junk, Auto-Delete Common, Auto-Sell Greens
	-- Three rows stacked. No descriptions to keep them compact within cardH=92.
	local tglGray = MakeToggle(card2, "Auto-Delete Junk", C_ACCENT,
		"Automatically destroy poor (gray) quality items. Quest items, shirts, and tabards are protected. Items on the Keep list are also protected.")
	tglGray:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -CARD_INNER_PAD_Y)
	tglGray:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglGray = tglGray

	local tglDelCommon = MakeToggle(card2, "Auto-Delete Common", C_ACCENT,
		"Automatically destroy Common (white) quality equippable gear. Quest items, reagents, consumables, shirts, tabards, and items on the Keep list are protected.")
	tglDelCommon:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 22))
	tglDelCommon:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglDelCommon = tglDelCommon

	local tglSellGreensGen = MakeToggle(card2, "Auto-Sell Greens", C_ACCENT,
		"Automatically sell Uncommon (green) gear at vendors. Equippable gear only. Quest items and items on the Keep list are protected.")
	tglSellGreensGen:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 44))
	tglSellGreensGen:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglSellGreensGen = tglSellGreensGen

	-- Scan Speed card (moved here from the old Scan Options left card)
	local scanSpeedCard = card3
	local speedLabel = MakeText(scanSpeedCard, 10, C_TEXT, "OUTLINE")
	speedLabel:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -CARD_INNER_PAD_Y - 2)
	speedLabel:SetText("Scan Speed")

	local speedOpts = {
		{ value = 0.5, label = "0.5 sec" }, { value = 0.75, label = "0.75 sec" },
		{ value = 1, label = "1 sec" }, { value = 5, label = "5 sec" },
		{ value = 10, label = "10 sec" }, { value = 30, label = "30 sec" },
		{ value = 60, label = "1 min" }, { value = 120, label = "2 min" },
		{ value = 300, label = "5 min" },
	}
	local speedDD = MakeDropdown(scanSpeedCard, cardW - CARD_INNER_PAD_X * 2, speedOpts, function(val)
		local p = GetActiveProfile(db)
		p.scanInterval = val
	end)
	speedDD:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 14))
	self._speedDD = speedDD

	local speedHelp = MakeText(scanSpeedCard, 9, C_DIM, "OUTLINE")
	speedHelp:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 40))
	speedHelp:SetPoint("TOPRIGHT", scanSpeedCard, "TOPRIGHT", -CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 40))
	speedHelp:SetJustifyH("LEFT")
	speedHelp:SetText("How often bags are scanned.")

	-- ========================================================================
	-- GOBLIN TAB: 3 cards (Auto-Repair, Summon Scavenger, Hide Greedy Spam)
	-- Same card dimensions as General tab (3 cards, 2 gaps inside genContentW).
	-- Each card's main toggle sits at top; sub-toggles stack below at reduced size.
	-- ========================================================================
	local goblinPage = tabPages.goblin

	-- Small helper for sub-toggles: smaller box (14x14), 9pt text, no description.
	-- Used for the "Use Guild Bank money" / "After sell" / "After close vendor" rows.
	local function MakeSubToggle(parent, label, color)
		local row = CreateFrame("Button", nil, parent)
		row:SetSize(120, 16)

		local box = CreateFrame("Frame", nil, row)
		box:SetSize(12, 12)
		box:SetPoint("LEFT", 0, 0)
		ApplyBackdrop(box, { 0.04, 0.04, 0.04, 1 }, { 0.33, 0.33, 0.33, 1 })

		local indicator = box:CreateTexture(nil, "OVERLAY")
		indicator:SetTexture("Interface\\AddOns\\AutoDelete\\textures\\checkmark.tga")
		indicator:SetPoint("CENTER", box, "CENTER", 0, 0)
		indicator:SetSize(12, 12)
		indicator:SetVertexColor(1, 1, 1, 1)
		indicator:Hide()

		local text = row:CreateFontString(nil, "OVERLAY")
		text:SetFont(FONT, 9, "OUTLINE")
		text:SetTextColor(unpack(C_DIM))
		text:SetPoint("LEFT", box, "RIGHT", 6, 0)
		text:SetPoint("RIGHT", row, "RIGHT", -2, 0)
		text:SetJustifyH("LEFT")
		text:SetWordWrap(true)
		text:SetText(label)

		row._checked = false
		local activeColor = color or C_ACCENT

		local function UpdateVisual()
			if row._checked then
				local lighter = {
					math.min(activeColor[1] + 0.10, 1),
					math.min(activeColor[2] + 0.10, 1),
					math.min(activeColor[3] + 0.10, 1),
					1,
				}
				ApplyBackdrop(box, activeColor, lighter)
				indicator:Show()
				text:SetTextColor(unpack(C_TEXT))
			else
				ApplyBackdrop(box, { 0.04, 0.04, 0.04, 1 }, { 0.33, 0.33, 0.33, 1 })
				indicator:Hide()
				text:SetTextColor(unpack(C_DIM))
			end
		end

		function row:SetChecked(val)
			row._checked = val and true or false
			UpdateVisual()
		end
		function row:GetChecked() return row._checked end
		row:SetScript("OnClick", function()
			row._checked = not row._checked
			UpdateVisual()
		end)

		return row
	end

	local function MakeGoblinCard(xOff)
		local card = CreateFrame("Frame", nil, goblinPage)
		card:SetSize(cardW, cardH)
		card:SetPoint("TOPLEFT", xOff, -4)
		card:SetBackdrop({ bgFile = WHITE8x8, edgeFile = WHITE8x8, edgeSize = 1 })
		card:SetBackdropColor(0.04, 0.04, 0.04, 1)
		card:SetBackdropBorderColor(0.14, 0.14, 0.14, 1)
		return card
	end

	local gCard1 = MakeGoblinCard(0)
	local gCard2 = MakeGoblinCard(cardW + CARD_GAP)
	local gCard3 = MakeGoblinCard((cardW + CARD_GAP) * 2)

	-- CARD 1: Auto-Repair (main + sub) + Hide Greedy Spam (main)
	local tglRepair = MakeToggle(gCard1, "Auto-Repair", C_ACCENT,
		"Repair your gear automatically when you open a vendor.")
	tglRepair:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -CARD_INNER_PAD_Y)
	tglRepair:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglRepair = tglRepair

	-- Sub-toggles indent to align their box with the parent toggle's TEXT.
	-- Parent anchor = CARD_INNER_PAD_X (10), parent box = 14 wide, gap 8 → text starts at 32.
	local SUBTGL_INDENT = CARD_INNER_PAD_X + 14 + 8   -- 32 (card pad + parent box + gap)
	local tglRepairGuild = MakeSubToggle(gCard1, "Use Guild Bank money", C_DK_RED)
	tglRepairGuild:SetPoint("TOPLEFT", SUBTGL_INDENT, -(CARD_INNER_PAD_Y + 20))
	tglRepairGuild:SetWidth(cardW - SUBTGL_INDENT - CARD_INNER_PAD_X)
	self._tglRepairGuild = tglRepairGuild

	-- Row 3 on Card 1: Hide Greedy Spam (main toggle).
	local tglHideSpam = MakeToggle(gCard1, "Hide Greedy Spam", C_ACCENT,
		"Hides Greedy Scavenger's chat messages and speech bubbles.")
	tglHideSpam:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 44))
	tglHideSpam:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglHideSpam = tglHideSpam

	-- CARD 2: Summon Scavenger (master + 3 sub-toggles)
	local tglScav = MakeToggle(gCard2, "Summon Scavenger", C_ACCENT,
		"Master toggle for Greedy Scavenger pet management. When enabled, the addon dismisses your Scavenger when you mount and re-summons on dismount, and re-summons it if it gets stuck or despawns. The summon itself is triggered by the After sell or After vendor close sub-toggles below. Gated by the AutoDelete master Enable on the General tab.")
	tglScav:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -CARD_INNER_PAD_Y)
	tglScav:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglScav = tglScav

	local tglScavAfterSell = MakeSubToggle(gCard2, "After sell", C_DK_RED)
	tglScavAfterSell:SetPoint("TOPLEFT", SUBTGL_INDENT, -(CARD_INNER_PAD_Y + 20))
	tglScavAfterSell:SetWidth(cardW - SUBTGL_INDENT - CARD_INNER_PAD_X)
	self._tglScavAfterSell = tglScavAfterSell

	local tglScavAfterClose = MakeSubToggle(gCard2, "After vendor close", C_DK_RED)
	tglScavAfterClose:SetPoint("TOPLEFT", SUBTGL_INDENT, -(CARD_INNER_PAD_Y + 36))
	tglScavAfterClose:SetWidth(cardW - SUBTGL_INDENT - CARD_INNER_PAD_X)
	self._tglScavAfterClose = tglScavAfterClose

	local tglScavOnlyInCombat = MakeSubToggle(gCard2, "Only in Combat", C_DK_RED)
	tglScavOnlyInCombat:SetPoint("TOPLEFT", SUBTGL_INDENT, -(CARD_INNER_PAD_Y + 52))
	tglScavOnlyInCombat:SetWidth(cardW - SUBTGL_INDENT - CARD_INNER_PAD_X)
	self._tglScavOnlyInCombat = tglScavOnlyInCombat

	-- CARD 3: Summon Merchant on bags full (main toggle).
	-- Shares the Summon Scavenger master toggle for mount-aware and
	-- stuck-detection behavior.
	local tglSummonMerchant = MakeToggle(gCard3, "Summon Goblin Merchant", C_ACCENT,
		"Automatically summon your Goblin Merchant companion when your bags reach zero free slots and stay full for 3 seconds. The 3-second wait avoids stray summons from transient fills (e.g. stacks that auto-merge a moment later). You still need to target the merchant and press your Interact With Target keybind to open the vendor window. Gated by the Summon Scavenger master toggle and by the AutoDelete master Enable.")
	tglSummonMerchant:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -CARD_INNER_PAD_Y)
	tglSummonMerchant:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	AddToggleDescription(tglSummonMerchant,
		"Summons the Goblin Merchant when bags are full.",
		cardW - CARD_INNER_PAD_X * 2 - 26)
	self._tglSummonMerchant = tglSummonMerchant

	-- ========================================================================
	-- TOOLS TAB: utility features. Currently:
	-- Card 1: Auto-Open Containers (clams, crates, eggs, manna biscuits etc)
	-- Card 2: Sell Threshold (skip selling items worth less than N gold)
	-- Card 3: reserved for future utilities
	-- ========================================================================
	local toolsPage = tabPages.tools

	local function MakeToolsCard(xOff)
		local card = CreateFrame("Frame", nil, toolsPage)
		card:SetSize(cardW, cardH)
		card:SetPoint("TOPLEFT", xOff, -4)
		card:SetBackdrop({ bgFile = WHITE8x8, edgeFile = WHITE8x8, edgeSize = 1 })
		card:SetBackdropColor(0.04, 0.04, 0.04, 1)
		card:SetBackdropBorderColor(0.14, 0.14, 0.14, 1)
		return card
	end

	local tCard1 = MakeToolsCard(0)
	local tCard2 = MakeToolsCard(cardW + CARD_GAP)

	-- Tools Card 1: Auto-Open Containers
	local tglAutoOpen = MakeToggle(tCard1, "Auto-Open Containers", C_ACCENT,
		"Automatically open lootable bag containers (clams, crates, mysterious eggs, enriched manna biscuits, etc). Items inside are added to your bags. Skips lockboxes that need a key unless you toggle the option below.")
	tglAutoOpen:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -CARD_INNER_PAD_Y)
	tglAutoOpen:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglAutoOpen = tglAutoOpen

	local tglAutoOpenLocked = MakeSubToggle(tCard1, "Open locked", C_DK_RED)
	tglAutoOpenLocked:SetPoint("TOPLEFT", SUBTGL_INDENT, -(CARD_INNER_PAD_Y + 22))
	tglAutoOpenLocked:SetWidth(cardW - SUBTGL_INDENT - CARD_INNER_PAD_X)
	self._tglAutoOpenLocked = tglAutoOpenLocked

	local tglAutoOpenInCombat = MakeSubToggle(tCard1, "Skip in combat", C_DK_RED)
	tglAutoOpenInCombat:SetPoint("TOPLEFT", SUBTGL_INDENT, -(CARD_INNER_PAD_Y + 40))
	tglAutoOpenInCombat:SetWidth(cardW - SUBTGL_INDENT - CARD_INNER_PAD_X)
	self._tglAutoOpenInCombat = tglAutoOpenInCombat

	-- Tools Card 2: Sell Threshold (numeric editbox)
	-- Skip selling items worth less than N gold. Defaults to 0 (no threshold).
	-- The check runs against the vendor sell value, not the item rarity, so
	-- expensive crafted whites will be protected automatically when this is set.
	local sellThresholdLabel = MakeText(tCard2, 10, C_TEXT, "OUTLINE")
	sellThresholdLabel:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -CARD_INNER_PAD_Y - 2)
	sellThresholdLabel:SetText("Sell Threshold")

	local sellThresholdHelp = MakeText(tCard2, 9, C_DIM, "OUTLINE")
	sellThresholdHelp:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 18))
	sellThresholdHelp:SetPoint("RIGHT", tCard2, "RIGHT", -CARD_INNER_PAD_X, 0)
	sellThresholdHelp:SetJustifyH("LEFT")
	sellThresholdHelp:SetWordWrap(true)
	sellThresholdHelp:SetText("Skip items worth less than:")

	-- Editbox for the threshold value (in gold). 0 = disabled.
	local thresholdBox = CreateFrame("Frame", nil, tCard2)
	thresholdBox:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	thresholdBox:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 44))
	ApplyBackdrop(thresholdBox, C_DROP_BG, C_DROP_BORDER)

	local thresholdEdit = CreateFrame("EditBox", nil, thresholdBox)
	thresholdEdit:SetFont(FONT, 10, "OUTLINE")
	thresholdEdit:SetTextColor(unpack(C_TEXT))
	thresholdEdit:SetAutoFocus(false)
	thresholdEdit:SetNumeric(true)
	thresholdEdit:SetMaxLetters(8)
	thresholdEdit:SetPoint("TOPLEFT", 4, -1)
	thresholdEdit:SetPoint("BOTTOMRIGHT", -22, 1)
	thresholdEdit:SetJustifyH("LEFT")
	thresholdEdit:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
	thresholdEdit:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
	thresholdEdit:SetScript("OnEditFocusLost", function(s)
		local val = tonumber(s:GetText()) or 0
		if val < 0 then val = 0 end
		s:SetText(tostring(val))
		local p = GetActiveProfile(db)
		p.sellThresholdGold = val
	end)
	self._thresholdEdit = thresholdEdit

	local thresholdSuffix = MakeText(thresholdBox, 10, C_DIM, "OUTLINE")
	thresholdSuffix:SetPoint("RIGHT", thresholdBox, "RIGHT", -4, 0)
	thresholdSuffix:SetText("g")

	-- ========================================================================
	-- AUTOINV TAB: 3 cards (Enable+Keywords, Loot Rules, Party Management)
	-- Same card dimensions as General/Goblin tabs.
	-- ========================================================================
	local autoInvPage = tabPages.autoinv

	local function MakeAutoInvCard(xOff)
		local card = CreateFrame("Frame", nil, autoInvPage)
		card:SetSize(cardW, cardH)
		card:SetPoint("TOPLEFT", xOff, -4)
		card:SetBackdrop({ bgFile = WHITE8x8, edgeFile = WHITE8x8, edgeSize = 1 })
		card:SetBackdropColor(0.04, 0.04, 0.04, 1)
		card:SetBackdropBorderColor(0.14, 0.14, 0.14, 1)
		return card
	end

	local aCard1 = MakeAutoInvCard(0)
	local aCard2 = MakeAutoInvCard(cardW + CARD_GAP)
	local aCard3 = MakeAutoInvCard((cardW + CARD_GAP) * 2)

	-- CARD 1: Auto-Invite master toggle + keyword text input
	local tglAutoInvite = MakeToggle(aCard1, "Auto-Invite", C_ACCENT,
		"Whispers containing any configured keyword trigger auto-invite. Requires you to be group leader or raid assistant.")
	tglAutoInvite:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -CARD_INNER_PAD_Y)
	tglAutoInvite:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglAutoInvite = tglAutoInvite

	-- "!keyword" label (small dim hint)
	local kwLabel = MakeText(aCard1, 9, C_DIM, "OUTLINE")
	kwLabel:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 26))
	kwLabel:SetText("Keywords (comma-separated):")

	-- Keyword input box. Comma-separated. "!" is added automatically at match time.
	local kwFrame = CreateFrame("Frame", nil, aCard1)
	kwFrame:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 40))
	kwFrame:SetPoint("TOPRIGHT", aCard1, "TOPRIGHT", -CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 40))
	kwFrame:SetHeight(20)
	kwFrame:SetBackdrop({ bgFile = WHITE8x8, edgeFile = WHITE8x8, edgeSize = 1 })
	kwFrame:SetBackdropColor(unpack(C_DROP_BG))
	kwFrame:SetBackdropBorderColor(unpack(C_DROP_BORDER))

	local kwBox = CreateFrame("EditBox", nil, kwFrame)
	kwBox:SetFont(FONT, 10, "OUTLINE")
	kwBox:SetTextColor(unpack(C_TEXT))
	kwBox:SetAutoFocus(false)
	kwBox:SetPoint("TOPLEFT", 4, -1)
	-- Pull BOTTOMRIGHT in by 18px to leave room for the clear (x) button.
	kwBox:SetPoint("BOTTOMRIGHT", -22, 1)
	kwBox:SetMaxLetters(120)
	kwBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
	kwBox:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
	kwBox:SetScript("OnEditFocusLost", function(s)
		-- Save on focus loss so the user doesn't have to hit Enter.
		local text = s:GetText() or ""
		text = text:gsub("^%s+", ""):gsub("%s+$", "")
		GetActiveProfile(db).autoInviteKeywords = (text ~= "" and text) or "inv,invite"
		-- Snap the text to the trimmed/normalized value
		s:SetText(GetActiveProfile(db).autoInviteKeywords)
	end)
	self._kwBox = kwBox

	-- Clear (x) button at the right edge of the keyword frame. Click resets
	-- the keywords to the default "inv,invite" (the field is never truly
	-- empty - empty string falls back to the default in OnEditFocusLost).
	local kwClear = CreateFrame("Button", nil, kwFrame)
	kwClear:SetSize(14, 14)
	kwClear:SetPoint("RIGHT", -4, 0)
	local kwClearText = kwClear:CreateFontString(nil, "OVERLAY")
	kwClearText:SetFont(FONT, 11, "OUTLINE")
	kwClearText:SetPoint("CENTER")
	kwClearText:SetTextColor(0.6, 0.6, 0.6, 1)
	kwClearText:SetText("x")
	kwClear:SetScript("OnEnter", function() kwClearText:SetTextColor(1, 0.4, 0.4, 1) end)
	kwClear:SetScript("OnLeave", function() kwClearText:SetTextColor(0.6, 0.6, 0.6, 1) end)
	kwClear:SetScript("OnClick", function()
		kwBox:SetText("")
		kwBox:ClearFocus()
		-- OnEditFocusLost already fired ClearFocus path - explicitly
		-- normalize again here in case the user clicks while not focused.
		GetActiveProfile(db).autoInviteKeywords = "inv,invite"
		kwBox:SetText("inv,invite")
	end)

	-- CARD 2: Apply loot rule (main toggle) + dropdown
	local tglLootRule = MakeToggle(aCard2, "Apply loot rule", C_ACCENT,
		"After auto-inviting, set the party's loot rule to your chosen method.")
	tglLootRule:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -CARD_INNER_PAD_Y)
	tglLootRule:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglLootRule = tglLootRule

	-- Loot rule options - strings match LOOT_METHOD_MAP keys in AutoDelete.lua
	local LOOT_RULE_OPTS = {
		{ value = "freeforall",      label = "Free For All" },
		{ value = "roundrobin",      label = "Round Robin" },
		{ value = "group",           label = "Group Loot" },
		{ value = "needbeforegreed", label = "Need Before Greed" },
		{ value = "master",          label = "Master Loot" },
	}
	local lootDD = MakeDropdown(aCard2, cardW - CARD_INNER_PAD_X * 2, LOOT_RULE_OPTS, function(val)
		GetActiveProfile(db).autoInviteLootRule = val
	end)
	lootDD:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 30))
	self._lootDD = lootDD

	-- CARD 3: Convert to raid (main toggle).
	-- Was previously a "Party Management" header + 2 sub-toggles (Convert + Invite
	-- Requester). Invite Requester was removed in v3.17. Now just a single main
	-- toggle for the Convert behavior.
	local tglConvertRaid = MakeToggle(aCard3, "Convert to raid when full", C_ACCENT,
		"When the 6th player joins your party, automatically convert it to a raid group.")
	tglConvertRaid:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -CARD_INNER_PAD_Y)
	tglConvertRaid:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglConvertRaid = tglConvertRaid

	-- ========================================================================
	-- TRACKING TAB: per-character stats table (SESSION vs LIFETIME columns)
	-- 6 stat rows + header + Reset button. Numbers formatted via the
	-- AutoDelete_Stats.FormatMoney / FormatNumber helpers.
	-- NOTE: locals kept to minimum here - BuildUI() is already near Lua's
	-- 200-local limit.
	-- ========================================================================
	do
		local trackingPage = tabPages.tracking
		local SESSION_X  = math.floor(genContentW * 0.60)
		local LIFETIME_X = math.floor(genContentW * 0.92)

		-- Header row (two column labels, dim gray)
		local hdrS = MakeText(trackingPage, 9, C_DIM, "OUTLINE")
		hdrS:SetPoint("TOPLEFT", SESSION_X - 60, -2)
		hdrS:SetPoint("TOPRIGHT", trackingPage, "TOPLEFT", SESSION_X + 4, -2)
		hdrS:SetJustifyH("RIGHT")
		hdrS:SetText("SESSION")

		local hdrL = MakeText(trackingPage, 9, C_DIM, "OUTLINE")
		hdrL:SetPoint("TOPLEFT", LIFETIME_X - 60, -2)
		hdrL:SetPoint("TOPRIGHT", trackingPage, "TOPLEFT", LIFETIME_X + 4, -2)
		hdrL:SetJustifyH("RIGHT")
		hdrL:SetText("LIFETIME")

		-- Row builder - returns { session, lifetime } fontstrings.
		local function MakeTrackingRow(yOff, labelText)
			local label = MakeText(trackingPage, 9, C_TEXT, "OUTLINE")
			label:SetPoint("TOPLEFT", 4, yOff)
			label:SetJustifyH("LEFT")
			label:SetText(labelText)

			local session = MakeText(trackingPage, 9, C_TEXT, "OUTLINE")
			session:SetPoint("TOPLEFT", SESSION_X - 60, yOff)
			session:SetPoint("TOPRIGHT", trackingPage, "TOPLEFT", SESSION_X + 4, yOff)
			session:SetJustifyH("RIGHT")
			session:SetText("-")

			local lifetime = MakeText(trackingPage, 9, C_TEXT, "OUTLINE")
			lifetime:SetPoint("TOPLEFT", LIFETIME_X - 60, yOff)
			lifetime:SetPoint("TOPRIGHT", trackingPage, "TOPLEFT", LIFETIME_X + 4, yOff)
			lifetime:SetJustifyH("RIGHT")
			lifetime:SetText("-")

			return { session = session, lifetime = lifetime }
		end

		-- Store the 6 rows on self so Refresh can access them without
		-- consuming BuildUI() locals.
		self._trackingRows = {
			gold        = MakeTrackingRow(-14, "Gold Earned"),
			sold        = MakeTrackingRow(-24, "Items Sold"),
			deleted     = MakeTrackingRow(-34, "Items Deleted"),
			repairs     = MakeTrackingRow(-44, "Repairs"),
			repairSpend = MakeTrackingRow(-54, "Repair Spend"),
			invAvg      = MakeTrackingRow(-64, "Inventory Avg"),
		}

		-- Reset button (bottom right).
		local resetBtn = CreateFrame("Button", nil, trackingPage)
		resetBtn:SetSize(76, 16)
		resetBtn:SetPoint("BOTTOMRIGHT", trackingPage, "BOTTOMRIGHT", -4, 2)
		ApplyBackdrop(resetBtn, C_ROW_ODD, C_BORDER)
		local resetText = MakeText(resetBtn, 9, C_DIM, "OUTLINE")
		resetText:SetPoint("CENTER")
		resetText:SetText("Reset Stats")
		resetBtn:SetScript("OnEnter", function()
			ApplyBackdrop(resetBtn, C_ROW_HOVER, C_BORDER)
			resetText:SetTextColor(unpack(C_TEXT))
		end)
		resetBtn:SetScript("OnLeave", function()
			ApplyBackdrop(resetBtn, C_ROW_ODD, C_BORDER)
			resetText:SetTextColor(unpack(C_DIM))
		end)
		resetBtn:SetScript("OnClick", function()
			-- Confirmation popup. Stats reset is destructive and irreversible
			-- so a single click shouldn't fire it. Uses Blizzard's StaticPopup
			-- system, registered once on first click.
			if not StaticPopupDialogs["AUTODELETE_RESET_STATS"] then
				StaticPopupDialogs["AUTODELETE_RESET_STATS"] = {
					text = "Reset all AutoDelete stats?\n\nLifetime and session counters will be cleared. This cannot be undone.",
					button1 = "Reset",
					button2 = "Cancel",
					OnAccept = function()
						if _G.AutoDelete_Stats and _G.AutoDelete_Stats.Reset then
							_G.AutoDelete_Stats.Reset()
							print("|cffff8000[AutoDelete]|r: Stats reset.")
							if self.RefreshTrackingStats then self:RefreshTrackingStats() end
						end
					end,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
					preferredIndex = 3,
				}
			end
			StaticPopup_Show("AUTODELETE_RESET_STATS")
		end)
	end

	-- Refresh function for the Tracking tab. Called on tab show and on reset.
	function self:RefreshTrackingStats()
		if not _G.AutoDelete_Stats then return end
		local L = _G.AutoDelete_Stats.GetLifetime()
		local S = _G.AutoDelete_Stats.GetSession()
		local FM = _G.AutoDelete_Stats.FormatMoney
		local FN = _G.AutoDelete_Stats.FormatNumber
		local rows = self._trackingRows
		if not rows then return end

		rows.gold.session:SetText(FM(S.goldEarned or 0))
		rows.gold.lifetime:SetText(FM(L.goldEarned or 0))
		rows.sold.session:SetText(FN(S.itemsSold or 0))
		rows.sold.lifetime:SetText(FN(L.itemsSold or 0))
		rows.deleted.session:SetText(FN(S.itemsDeleted or 0))
		rows.deleted.lifetime:SetText(FN(L.itemsDeleted or 0))
		rows.repairs.session:SetText(FN(S.repairs or 0))
		rows.repairs.lifetime:SetText(FN(L.repairs or 0))
		rows.repairSpend.session:SetText(FM(S.repairSpend or 0))
		rows.repairSpend.lifetime:SetText(FM(L.repairSpend or 0))

		-- Inventory Avg: session "-" (multi-sample avg doesn't map to session);
		-- lifetime = total / count.
		rows.invAvg.session:SetText("-")
		local invCount = L.inventoryWorthCount or 0
		if invCount > 0 then
			rows.invAvg.lifetime:SetText(FM(math.floor((L.inventoryWorthTotal or 0) / invCount)))
		else
			rows.invAvg.lifetime:SetText("-")
		end
	end

	-- ========================================================================
	-- PROFILES TAB: dropdown of all characters' profiles + Copy/Delete/Reset.
	-- Copy/Delete operate on the dropdown selection. Reset always operates
	-- on the current character. Every destructive action pops a StaticPopup
	-- confirmation. The dropdown includes the current character too.
	-- ========================================================================
	do
		local profilesPage = tabPages.profiles

		-- 4-column layout inside the 498px tab content area.
		--   Col 1 (X=8,   W=113): Row 1 = "Current: <char>" header.
		--   Col 2 (X=131, W=113): Row 1 = empty.
		--   Col 3 (X=254, W=113): Row 1 = Copy;   Row 2 = Import Lists.
		--   Col 4 (X=377, W=113): Row 1 = Delete; Row 2 = Clear List.
		-- Dropdown spans Col 1+2 on Row 2 (width = 2*113 + 10 = 236).
		local PROF_LEFT_PAD = 8
		local PROF_COL_W    = 113
		local PROF_COL_GAP  = 10
		local PROF_COL2_X   = PROF_LEFT_PAD + PROF_COL_W + PROF_COL_GAP           -- 131
		local PROF_COL3_X   = PROF_COL2_X   + PROF_COL_W + PROF_COL_GAP           -- 254
		local PROF_COL4_X   = PROF_COL3_X   + PROF_COL_W + PROF_COL_GAP           -- 377
		local PROF_BTN_H    = 22
		local PROF_BTN_GAP  = 6
		local PROF_ROW1_Y   = -14
		local PROF_ROW2_Y   = PROF_ROW1_Y - PROF_BTN_H - PROF_BTN_GAP             -- -42
		local PROF_DD_W     = PROF_COL_W * 2 + PROF_COL_GAP                       -- 236

		-- Row 1 / Col 1: "Current: <charname>" header. Nudged down a few pixels
		-- so the text baseline sits roughly centered with the button row.
		local curHeader = MakeText(profilesPage, 10, C_TITLE, "OUTLINE")
		curHeader:SetPoint("TOPLEFT", PROF_LEFT_PAD, PROF_ROW1_Y - 4)
		curHeader:SetJustifyH("LEFT")
		curHeader:SetText("Current: " .. (UnitName("player") or "?"))

		-- Selected-character state (tracked on self since the dropdown is built
		-- dynamically in Refresh. We can't capture it as a BuildUI local or
		-- it won't update when characters are added/deleted).
		self._selectedProfile = nil

		-- Row 2 / Col 1+2 spanning: profile dropdown.
		local profileDD = MakeDropdown(profilesPage, PROF_DD_W, {}, function(val)
			self._selectedProfile = val
		end)
		profileDD:SetPoint("TOPLEFT", PROF_LEFT_PAD, PROF_ROW2_Y)
		self._profileDD = profileDD

		-- Action buttons.
		local function MakeActionBtn(label, onClick)
			local btn = CreateFrame("Button", nil, profilesPage)
			btn:SetSize(80, 22)
			ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
			local txt = MakeText(btn, 10, C_DIM, "OUTLINE")
			txt:SetPoint("CENTER")
			txt:SetText(label)
			btn:SetScript("OnEnter", function()
				ApplyBackdrop(btn, C_ROW_HOVER, C_BORDER)
				txt:SetTextColor(unpack(C_TEXT))
			end)
			btn:SetScript("OnLeave", function()
				ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
				txt:SetTextColor(unpack(C_DIM))
			end)
			btn:SetScript("OnClick", onClick)
			return btn
		end

		local copyBtn = MakeActionBtn("Copy", function()
			local sel = self._selectedProfile
			if not sel or sel == "" then
				print("|cffff8000[AutoDelete]|r: Select a profile first.")
				return
			end
			local dlg = StaticPopup_Show("AUTODELETE_PROFILE_COPY", sel,
				_G.AutoDelete_Profiles.GetCurrentCharacter())
			if dlg then dlg.data = sel end
		end)

		local deleteBtn = MakeActionBtn("Delete", function()
			local sel = self._selectedProfile
			if not sel or sel == "" then
				print("|cffff8000[AutoDelete]|r: Select a profile first.")
				return
			end
			local dlg = StaticPopup_Show("AUTODELETE_PROFILE_DELETE", sel)
			if dlg then dlg.data = sel end
		end)

		-- Import button: merges the 3 lists (Delete/Sell/Keep) from the selected
		-- profile into the current character's profile. Never touches other
		-- settings. Duplicates are skipped; cross-list conflicts open a popup.
		local importBtn = MakeActionBtn("Import Lists", function()
			local sel = self._selectedProfile
			if not sel or sel == "" then
				print("|cffff8000[AutoDelete]|r: Select a profile first.")
				return
			end
			if sel == _G.AutoDelete_Profiles.GetCurrentCharacter() then
				print("|cffff8000[AutoDelete]|r: Cannot import from your own profile.")
				return
			end
			if not _G.AutoDelete_Profiles or not _G.AutoDelete_Profiles.PreviewImport then
				return
			end
			local preview, reason = _G.AutoDelete_Profiles.PreviewImport(sel)
			if not preview then
				print("|cffff4444[AutoDelete]|r: Import preview failed (" .. (reason or "unknown") .. ").")
				return
			end
			if #preview.additions == 0 and #preview.conflicts == 0 then
				print("|cffff8000[AutoDelete]|r: Nothing to import. Your lists already match " .. sel .. ".")
				return
			end
			if #preview.conflicts == 0 then
				-- Fast path: just additions, no conflicts. Confirm and apply.
				local msg = string.format("Import %d item(s) from %s into your lists?", #preview.additions, sel)
				StaticPopup_Show("AUTODELETE_PROFILE_IMPORT_SIMPLE", sel, tostring(#preview.additions)).data = sel
				return
			end
			-- Conflicts exist. Open the conflict resolution popup.
			_G.AutoDelete_ShowImportConflicts(sel, preview)
		end)

		-- Clear List button: wipes one list (Delete/Sell/Keep) or all three
		-- on the current character's profile. Opens a small picker popup; the
		-- destructive action is then confirmed via a StaticPopup.
		local clearBtn = MakeActionBtn("Clear List", function()
			if _G.AutoDelete_ShowClearListPicker then
				_G.AutoDelete_ShowClearListPicker()
			end
		end)

		-- Buttons: column 3 is Copy + Import Lists (stacked); column 4 is
		-- Delete + Clear List (stacked). All buttons are identically sized
		-- to match the column width.
		copyBtn:SetSize(PROF_COL_W, PROF_BTN_H)
		copyBtn:SetPoint("TOPLEFT", PROF_COL3_X, PROF_ROW1_Y)

		deleteBtn:SetSize(PROF_COL_W, PROF_BTN_H)
		deleteBtn:SetPoint("TOPLEFT", PROF_COL4_X, PROF_ROW1_Y)

		importBtn:SetSize(PROF_COL_W, PROF_BTN_H)
		importBtn:SetPoint("TOPLEFT", PROF_COL3_X, PROF_ROW2_Y)

		clearBtn:SetSize(PROF_COL_W, PROF_BTN_H)
		clearBtn:SetPoint("TOPLEFT", PROF_COL4_X, PROF_ROW2_Y)

		-- Register StaticPopups (once). Unique names to avoid collisions.
		if not StaticPopupDialogs["AUTODELETE_PROFILE_COPY"] then
			StaticPopupDialogs["AUTODELETE_PROFILE_COPY"] = {
				text = "Copy settings from %s to %s? This will overwrite your current settings (including lists).",
				button1 = "Copy", button2 = "Cancel",
				OnAccept = function(popup)
					local source = popup.data
					if not source or not _G.AutoDelete_Profiles then return end
					local ok, reason = _G.AutoDelete_Profiles.CopyFrom(source)
					if ok then
						print("|cffff8000[AutoDelete]|r: Copied settings from " .. source .. ".")
						if _G.AutoDeleteOptionsPanel and _G.AutoDeleteOptionsPanel.Refresh then
							_G.AutoDeleteOptionsPanel:Refresh()
						end
					else
						print("|cffff4444[AutoDelete]|r: Copy failed (" .. (reason or "unknown") .. ").")
					end
				end,
				timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
			}
		end

		if not StaticPopupDialogs["AUTODELETE_PROFILE_DELETE"] then
			StaticPopupDialogs["AUTODELETE_PROFILE_DELETE"] = {
				text = "Delete profile %s? This cannot be undone.",
				button1 = "Delete", button2 = "Cancel",
				OnAccept = function(popup)
					local target = popup.data
					if not target or not _G.AutoDelete_Profiles then return end
					local ok, reason = _G.AutoDelete_Profiles.DeleteProfile(target)
					if ok then
						print("|cffff8000[AutoDelete]|r: Deleted profile " .. target .. ".")
						if _G.AutoDeleteOptionsPanel and _G.AutoDeleteOptionsPanel.Refresh then
							_G.AutoDeleteOptionsPanel:Refresh()
						end
					else
						print("|cffff4444[AutoDelete]|r: Delete failed (" .. (reason or "unknown") .. ").")
					end
				end,
				timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
			}
		end

		if not StaticPopupDialogs["AUTODELETE_PROFILE_RESET"] then
			StaticPopupDialogs["AUTODELETE_PROFILE_RESET"] = {
				text = "Reset %s's profile to defaults? This will clear all lists and settings for the current character.",
				button1 = "Reset", button2 = "Cancel",
				OnAccept = function(popup)
					if not _G.AutoDelete_Profiles then return end
					local ok = _G.AutoDelete_Profiles.ResetCurrent()
					if ok then
						print("|cffff8000[AutoDelete]|r: Current profile reset to defaults.")
						if _G.AutoDeleteOptionsPanel and _G.AutoDeleteOptionsPanel.Refresh then
							_G.AutoDeleteOptionsPanel:Refresh()
						end
					end
				end,
				timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
			}
		end

		-- Simple import popup: used when there are additions but NO conflicts.
		-- (Conflicts use the custom resolution window, not a StaticPopup.)
		if not StaticPopupDialogs["AUTODELETE_PROFILE_IMPORT_SIMPLE"] then
			StaticPopupDialogs["AUTODELETE_PROFILE_IMPORT_SIMPLE"] = {
				text = "Import %2$s item(s) from %1$s? No conflicts detected. Items will be added to matching lists.",
				button1 = "Import", button2 = "Cancel",
				OnAccept = function(popup)
					local source = popup.data
					if not source or not _G.AutoDelete_Profiles then return end
					local ok, reason = _G.AutoDelete_Profiles.ApplyImport(source, {})
					if not ok then
						print("|cffff4444[AutoDelete]|r: Import failed (" .. (reason or "unknown") .. ").")
					end
				end,
				timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
			}
		end

		-- Clear-list confirmation popup. Data field carries the target name
		-- ("Delete" / "Sell" / "Keep" / "All").
		if not StaticPopupDialogs["AUTODELETE_PROFILE_CLEAR"] then
			StaticPopupDialogs["AUTODELETE_PROFILE_CLEAR"] = {
				text = "Clear the %s list? This cannot be undone.",
				button1 = "Clear", button2 = "Cancel",
				OnAccept = function(popup)
					local target = popup.data
					if not target or not _G.AutoDelete_Profiles then return end
					local ok, count = _G.AutoDelete_Profiles.ClearList(target)
					if ok then
						if target == "All" then
							print(string.format("|cffff8000[AutoDelete]|r: Cleared all lists (%d entries removed).", count))
						else
							print(string.format("|cffff8000[AutoDelete]|r: Cleared %s list (%d entries removed).", target, count))
						end
						if _G.AutoDeleteOptionsPanel and _G.AutoDeleteOptionsPanel.Refresh then
							_G.AutoDeleteOptionsPanel:Refresh()
						end
					else
						print("|cffff4444[AutoDelete]|r: Clear failed (" .. (count or "unknown") .. ").")
					end
				end,
				timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
			}
		end

		-- Separate popup for clearing ALL lists at once (different wording).
		if not StaticPopupDialogs["AUTODELETE_PROFILE_CLEAR_ALL"] then
			StaticPopupDialogs["AUTODELETE_PROFILE_CLEAR_ALL"] = {
				text = "Clear ALL three lists (Delete, Sell, and Keep)? This cannot be undone.",
				button1 = "Clear All", button2 = "Cancel",
				OnAccept = function(popup)
					if not _G.AutoDelete_Profiles then return end
					local ok, count = _G.AutoDelete_Profiles.ClearList("All")
					if ok then
						print(string.format("|cffff8000[AutoDelete]|r: Cleared all lists (%d entries removed).", count))
						if _G.AutoDeleteOptionsPanel and _G.AutoDeleteOptionsPanel.Refresh then
							_G.AutoDeleteOptionsPanel:Refresh()
						end
					else
						print("|cffff4444[AutoDelete]|r: Clear failed (" .. (count or "unknown") .. ").")
					end
				end,
				timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
			}
		end

		-- Remove-junk popup: scans Delete + Sell lists and removes entries
		-- whose item quality is gray (junk). Cache-miss entries are skipped
		-- and reported in the summary so the user knows.
		if not StaticPopupDialogs["AUTODELETE_PROFILE_REMOVE_JUNK"] then
			StaticPopupDialogs["AUTODELETE_PROFILE_REMOVE_JUNK"] = {
				text = "Remove all gray (junk) items from the Delete and Sell lists? This cannot be undone.",
				button1 = "Remove", button2 = "Cancel",
				OnAccept = function(popup)
					if not _G.AutoDelete_Profiles or not _G.AutoDelete_Profiles.RemoveJunk then return end
					local ok, result = _G.AutoDelete_Profiles.RemoveJunk()
					if ok then
						print(string.format(
							"|cffff8000[AutoDelete]|r: Removed junk (Delete: %d, Sell: %d).",
							result.deleteRemoved or 0, result.sellRemoved or 0))
						if (result.uncached or 0) > 0 then
							print(string.format(
								"  |cff999999%d entry(ies) skipped (item data not cached). Open the item or reload to refresh the cache.|r",
								result.uncached))
						end
						if _G.AutoDeleteOptionsPanel and _G.AutoDeleteOptionsPanel.Refresh then
							_G.AutoDeleteOptionsPanel:Refresh()
						end
					else
						print("|cffff4444[AutoDelete]|r: Remove junk failed (" .. (result or "unknown") .. ").")
					end
				end,
				timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
			}
		end

		-- Remove-sellable popup: scans the Delete list only and removes any
		-- entry whose item has a vendor sell price > 0. Helps prune items
		-- that shouldn't be outright deleted because they have value.
		if not StaticPopupDialogs["AUTODELETE_PROFILE_REMOVE_SELLABLE"] then
			StaticPopupDialogs["AUTODELETE_PROFILE_REMOVE_SELLABLE"] = {
				text = "Remove all items from the Delete list that have a vendor sell price? This cannot be undone.",
				button1 = "Remove", button2 = "Cancel",
				OnAccept = function(popup)
					if not _G.AutoDelete_Profiles or not _G.AutoDelete_Profiles.RemoveSellableFromDelete then return end
					local ok, result = _G.AutoDelete_Profiles.RemoveSellableFromDelete()
					if ok then
						print(string.format(
							"|cffff8000[AutoDelete]|r: Removed %d sellable item(s) from the Delete list.",
							result.removed or 0))
						if (result.uncached or 0) > 0 then
							print(string.format(
								"  |cff999999%d entry(ies) skipped (item data not cached). Open the item or reload to refresh the cache.|r",
								result.uncached))
						end
						if _G.AutoDeleteOptionsPanel and _G.AutoDeleteOptionsPanel.Refresh then
							_G.AutoDeleteOptionsPanel:Refresh()
						end
					else
						print("|cffff4444[AutoDelete]|r: Remove sellable failed (" .. (result or "unknown") .. ").")
					end
				end,
				timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
			}
		end
	end

	-- Refresh function for the Profiles tab. Rebuilds the dropdown options
	-- to reflect the current set of saved profiles in the DB.
	function self:RefreshProfileList()
		if not _G.AutoDelete_Profiles then return end
		local dd = self._profileDD
		if not dd then return end

		local names = _G.AutoDelete_Profiles.GetAllCharacters()
		local options = {}
		for _, n in ipairs(names) do
			table.insert(options, { value = n, label = n })
		end

		-- Rebuild dropdown options. MakeDropdown exposes :SetOptions for this.
		if dd.SetOptions then
			dd:SetOptions(options)
		end

		-- Default selection: current character.
		local current = _G.AutoDelete_Profiles.GetCurrentCharacter()
		local selected = self._selectedProfile
		-- Sanitize: if previously-selected char was deleted, fall back to current.
		local found = false
		for _, n in ipairs(names) do
			if n == selected then found = true; break end
		end
		if not found then
			selected = current
			self._selectedProfile = current
		end
		if dd.SetValue then dd:SetValue(selected) end
	end

	-- ========================================================================
	-- SECTION 2: Sell rules - category cards
	--
	-- Three independent category cards (BoE Armor, BoP, BoE Weapons), each
	-- with: enable toggle + Rare/Epic toggles on the header row, iLvl
	-- min/max range on the second row.
	--
	-- The Auto-Delete Junk / Auto-Delete Common / Auto-Sell Greens toggles
	-- live on the General tab (card 2 of the General page), NOT here. They
	-- aren't categories - they're global, quality-based actions that run
	-- independently of the category sections.
	--
	-- Sell decision priority is implemented in AutoDelete.lua's SellItems.
	-- Summary (highest first):
	--   1. Keep list  (always wins)
	--   2. Sell list  (explicit user intent)
	--   3. Auto-Sell Greens (only Greens; Junk and Common are deleted, not sold)
	--   4. BoE Weapons section
	--   5. BoP section
	--   6. BoE Armor section (excludes weapon-slot items, which are step 4)
	-- ========================================================================

	-- Helper: build a category card. Returns a table of widgets so the
	-- enclosing scope can wire OnClick / OnTextChanged handlers.
	local function MakeSellCategoryCard(parent, title, yPos, height, fields)
		local card = MakeSection(parent, title, yPos, 1)
		card:SetHeight(height)

		-- ROW 1: Enable toggle on the LEFT, Rare/Epic toggles on the RIGHT.
		-- Putting the rarity toggles on the same row as the enable cuts
		-- vertical space and groups identity/qualifier visually.
		local tglEnable = MakeToggle(card, title, C_ACCENT, fields.enableTooltip)
		tglEnable:SetPoint("TOPLEFT", 15, -12)
		tglEnable:SetSize(140, 20)

		local tglEpic = MakeToggle(card, "Epic", C_Q_EPIC,
			"Sell Epic (purple) " .. fields.rarityNoun .. ". Requires the section to be enabled and the item's iLvl to fall inside the range below.")
		tglEpic:SetPoint("TOPRIGHT", -15, -12)
		tglEpic:SetSize(60, 20)

		local tglRare = MakeToggle(card, "Rare", C_Q_RARE,
			"Sell Rare (blue) " .. fields.rarityNoun .. ". Requires the section to be enabled and the item's iLvl to fall inside the range below.")
		tglRare:SetPoint("RIGHT", tglEpic, "LEFT", -16, 0)
		tglRare:SetSize(60, 20)

		-- ROW 2: iLvl range. Single row, label + min spinner + "to" + max spinner.
		-- Inputs share the available width so they're visually balanced
		-- instead of being narrow boxes lost in the middle of the card.
		local lblIlvl = MakeText(card, 10, C_DIM, "OUTLINE")
		lblIlvl:SetPoint("TOPLEFT", 15, -42)
		lblIlvl:SetText("iLvl")

		-- Compute spinner width so both spinners + label + "to" fill the row.
		-- Rough: card width ~340, minus 30 (margins), minus 32 (label),
		-- minus 24 (gaps + "to") = ~254. Each spinner = ~120.
		local SPINNER_W = 100

		local minFrame = MakeSpinnerInput(card, SPINNER_W, 22, 1, 9999)
		minFrame:SetPoint("LEFT", lblIlvl, "RIGHT", 8, 0)
		local minBox = minFrame.editBox

		local toLabel = MakeText(card, 9, C_DIM, "OUTLINE")
		toLabel:SetPoint("LEFT", minFrame, "RIGHT", 8, 0)
		toLabel:SetText("to")

		local maxFrame = MakeSpinnerInput(card, SPINNER_W, 22, 1, 9999)
		maxFrame:SetPoint("LEFT", toLabel, "RIGHT", 8, 0)
		local maxBox = maxFrame.editBox

		return {
			card     = card,
			enable   = tglEnable,
			minBox   = minBox,
			maxBox   = maxBox,
			rare     = tglRare,
			epic     = tglEpic,
		}
	end

	-- Card height: row1 (20) + 8 gap + row2 (22) + 14 padding = ~64
	local CARD_H = 64

	-- Info banner above the three category cards. Single row of explanatory
	-- text so users understand at a glance that these are sell filters that
	-- run at vendors (not delete rules, not auto-actions on loot).
	local BANNER_H = 24
	local banner = CreateFrame("Frame", nil, self)
	banner:SetPoint("TOPLEFT", self, "TOPLEFT", 15, yOff)
	banner:SetPoint("TOPRIGHT", self, "TOPRIGHT", -15, yOff)
	banner:SetHeight(BANNER_H)
	banner:SetBackdrop({ bgFile = WHITE8x8, edgeFile = WHITE8x8, edgeSize = 1 })
	banner:SetBackdropColor(unpack(C_BG))                     -- black to match the panel
	banner:SetBackdropBorderColor(unpack(C_HOVER))            -- mage blue accent
	local bannerIcon = banner:CreateFontString(nil, "OVERLAY")
	bannerIcon:SetFont(FONT, 12, "OUTLINE")
	bannerIcon:SetPoint("LEFT", banner, "LEFT", 8, 0)
	bannerIcon:SetTextColor(unpack(C_HOVER))
	bannerIcon:SetText("i")
	local bannerText = banner:CreateFontString(nil, "OVERLAY")
	bannerText:SetFont(FONT, 10, "OUTLINE")
	bannerText:SetPoint("LEFT", bannerIcon, "RIGHT", 8, 0)
	bannerText:SetPoint("RIGHT", banner, "RIGHT", -8, 0)
	bannerText:SetJustifyH("LEFT")
	bannerText:SetWordWrap(false)
	bannerText:SetTextColor(unpack(C_TEXT))
	bannerText:SetText("Sell filters: rules below run at vendors. Items matching are auto-sold for gold.")
	yOff = yOff - BANNER_H - SECTION_GAP

	-- Card 1: BoE Armor
	local boeArmor = MakeSellCategoryCard(self, "BoE Armor", yOff, CARD_H, {
		enableTooltip = "Sell Bind-on-Equip armor and accessories (rings, necks, trinkets, etc.) that match the Rare/Epic toggles and fall inside the iLvl range. Excludes weapons and other Hand Affix Enchant eligible items, which have their own section. Quest items and items on the Keep list are protected.",
		rarityNoun    = "BoE armor (excludes weapons and Hand-Affix targets)",
	})
	self._boeArmor = boeArmor
	yOff = yOff - 16 - CARD_H - SECTION_GAP

	-- Card 2: BoP
	local bop = MakeSellCategoryCard(self, "BoP", yOff, CARD_H, {
		enableTooltip = "Sell Bind-on-Pickup gear (any slot, including weapons) that matches the Rare/Epic toggles and falls inside the iLvl range. Quest items and items on the Keep list are protected.",
		rarityNoun    = "BoP gear",
	})
	self._bop = bop
	yOff = yOff - 16 - CARD_H - SECTION_GAP

	-- Card 3: BoE Weapons
	local boeWeapons = MakeSellCategoryCard(self, "BoE Weapons", yOff, CARD_H, {
		enableTooltip = "Sell Bind-on-Equip weapon-slot items (weapons, shields, holdables, ranged, thrown, relics) that match the Rare/Epic toggles and fall inside the iLvl range. Quest items and items on the Keep list are protected. Takes priority over BoE Armor for items that match both.",
		rarityNoun    = "BoE weapon-slot items",
	})
	self._boeWeapons = boeWeapons
	yOff = yOff - 16 - CARD_H - SECTION_GAP

	-- ========================================================================
	-- SECTION 3: Scan Options - Delete/Sell/Keep list mode tabs
	-- Scan Speed lives on the General settings tab; this section is just
	-- the three list-mode tab buttons that drive the list view below.
	-- ========================================================================
	local scanCardH = 34                                                   -- fits 26-tall buttons + 4px pad top/bot
	local scanBox = MakeSection(self, "Scan Options", yOff, 1)

	-- Full-width inner card: holds Delete/Sell/Keep tab buttons.
	-- Anchored flush to section edges (1px) so the buttons read as edge-aligned
	-- with the section's outer frame margin.
	local scanRightCard = CreateFrame("Frame", nil, scanBox)
	scanRightCard:SetHeight(scanCardH)
	scanRightCard:SetPoint("TOPLEFT", scanBox, "TOPLEFT", 1, -1)
	scanRightCard:SetPoint("TOPRIGHT", scanBox, "TOPRIGHT", -1, -1)
	scanRightCard:SetBackdrop({ bgFile = WHITE8x8, edgeFile = WHITE8x8, edgeSize = 1 })
	scanRightCard:SetBackdropColor(0.03, 0.03, 0.03, 1)  -- #080808
	scanRightCard:SetBackdropBorderColor(0.14, 0.14, 0.14, 1)  -- #232323

	-- Equal-width tabs filling the card horizontally, vertically centered
	local TAB_GAP = 6
	local TAB_INNER_PAD = 8
	local TAB_H = 26                                                       -- fixed button height

	local function MakeTab(parent, name)
		local tab = CreateFrame("Button", nil, parent)
		tab:SetHeight(TAB_H)
		ApplyBackdrop(tab, C_ROW_ODD, { 0.20, 0.20, 0.20, 1 })
		local text = MakeText(tab, 11, { 1, 1, 1, 1 }, "OUTLINE")
		text:SetPoint("CENTER")
		text:SetText(name)
		return tab, text
	end

	local deleteTab, deleteTabText = MakeTab(scanRightCard, "Delete (0)")
	local sellTab, sellTabText = MakeTab(scanRightCard, "Sell (0)")
	local keepTab, keepTabText = MakeTab(scanRightCard, "Keep (0)")

	-- Three equal-width tabs. Outer tabs anchor to card edges; middle tab
	-- anchors to Delete's right edge. LayoutTabs computes the equal width
	-- once scanRightCard has a resolved width.
	deleteTab:SetPoint("LEFT", scanRightCard, "LEFT", TAB_INNER_PAD, 0)
	keepTab:SetPoint("RIGHT", scanRightCard, "RIGHT", -TAB_INNER_PAD, 0)
	local function LayoutTabs()
		local cardW = scanRightCard:GetWidth()
		if not cardW or cardW < 10 then return end
		local totalInner = cardW - (TAB_INNER_PAD * 2) - (TAB_GAP * 2)
		local tabW = math.floor(totalInner / 3)
		deleteTab:SetWidth(tabW)
		sellTab:SetWidth(tabW)
		keepTab:SetWidth(tabW)
		sellTab:ClearAllPoints()
		sellTab:SetPoint("LEFT", deleteTab, "RIGHT", TAB_GAP, 0)
	end
	scanRightCard:SetScript("OnSizeChanged", LayoutTabs)
	-- Initial layout (deferred until the card has a resolved width)
	C_Timer = C_Timer or {}
	-- 3.3.5 has no C_Timer; use a one-shot OnUpdate frame instead
	local initFrame = CreateFrame("Frame")
	initFrame:SetScript("OnUpdate", function(s)
		s:SetScript("OnUpdate", nil)
		LayoutTabs()
	end)
	self._deleteTabText = deleteTabText
	self._sellTabText = sellTabText
	self._keepTabText = keepTabText

	-- AUTO-SIZE: scan card is the lowest element
	local scanActualH = AutoSizeSection(scanBox, scanRightCard, 8, 50)
	yOff = yOff - 16 - scanActualH - SECTION_GAP

	-- ========================================================================
	-- SECTION 4: Search & Manage (search row + item list)
	-- Takes the remaining vertical space inside the panel.
	-- ========================================================================
	local bottomPad = 15
	local frameH = self:GetHeight() or 800
	local manageH = frameH - 28 - math.abs(yOff) - bottomPad
	if manageH < 220 then manageH = 220 end
	local manageBox = MakeSection(self, "Search & Manage", yOff, manageH)
	yOff = yOff - 18

	-- ========================================================================
	-- List mode helpers
	-- ========================================================================
	local function GetActiveListKey()
		if self._listMode == "sell" then return "sellListText"
		elseif self._listMode == "whitelist" then return "whitelistText"
		else return "listText" end
	end

	local emptyText
	local function SetTabActive(tab, text, active)
		if active then
			-- Active: orange fill, dark text without OUTLINE for clean readability,
			-- bumped to 12pt to add visual weight (fakes bold on a tab strip).
			ApplyBackdrop(tab, { C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 0.9 }, C_ACCENT)
			text:SetFont(FONT, 12, "")
			text:SetTextColor(0.05, 0.05, 0.05, 1)
		else
			-- Inactive: dark bg, white outlined text
			ApplyBackdrop(tab, { 0.07, 0.07, 0.07, 1 }, { 0.20, 0.20, 0.20, 1 })
			text:SetFont(FONT, 11, "OUTLINE")
			text:SetTextColor(1, 1, 1, 1)
		end
	end

	local function UpdateTabColors()
		local p = GetActiveProfile(db)
		deleteTabText:SetText("Delete (" .. CountListItems(p.listText) .. ")")
		sellTabText:SetText("Sell (" .. CountListItems(p.sellListText) .. ")")
		keepTabText:SetText("Keep (" .. CountListItems(p.whitelistText) .. ")")
		SetTabActive(deleteTab, deleteTabText, self._listMode == "delete")
		SetTabActive(sellTab, sellTabText, self._listMode == "sell")
		SetTabActive(keepTab, keepTabText, self._listMode == "whitelist")
		if emptyText then
			local hints = { delete = "Drag items here to delete", sell = "Drag items here to sell at vendors", whitelist = "Drag items here to protect" }
			emptyText:SetText(hints[self._listMode] or "")
		end
	end

	-- ========================================================================
	-- Search Row (inside manageBox)
	-- Layout: [🔍 search box .....................] [Raw ☐] [↻ Refresh]
	-- ========================================================================
	local searchFrame = CreateFrame("Frame", nil, manageBox)
	searchFrame:SetSize(280, 22)
	searchFrame:SetPoint("TOPLEFT", 12, -12)
	ApplyBackdrop(searchFrame, C_DROP_BG, C_DROP_BORDER)

	-- Magnifying glass icon on the left (stock Blizzard search icon)
	local searchIcon = searchFrame:CreateTexture(nil, "OVERLAY")
	searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
	searchIcon:SetSize(14, 14)
	searchIcon:SetPoint("LEFT", 6, 0)
	searchIcon:SetVertexColor(0.6, 0.6, 0.6, 1)  -- dim gray to match mockup

	-- Search placeholder text (shown when empty), positioned after icon
	local searchPlaceholder = MakeText(searchFrame, 10, C_DIM, "OUTLINE")
	searchPlaceholder:SetPoint("LEFT", searchIcon, "RIGHT", 6, 0)
	searchPlaceholder:SetText("Search items...")
	self._searchPlaceholder = searchPlaceholder

	local searchBox = CreateFrame("EditBox", nil, searchFrame)
	searchBox:SetFont(FONT, 10, "OUTLINE"); searchBox:SetTextColor(unpack(C_TEXT))
	searchBox:SetAutoFocus(false)
	searchBox:SetPoint("TOPLEFT", searchIcon, "TOPRIGHT", 6, 2)
	-- BOTTOMRIGHT pulled in by 22px to make room for the clear (x) button.
	searchBox:SetPoint("BOTTOMRIGHT", -28, 2)
	searchBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
	-- Enter clears focus too, matching kwBox + numeric editbox behavior.
	searchBox:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
	searchBox:SetScript("OnEditFocusGained", function() searchPlaceholder:Hide() end)
	searchBox:SetScript("OnEditFocusLost", function(s)
		if (s:GetText() or "") == "" then searchPlaceholder:Show() end
	end)
	self._searchBox = searchBox

	-- Clear (x) button at the right edge of the search frame. Visible only
	-- when the search box has text. Click clears the box and refocuses it.
	local searchClear = CreateFrame("Button", nil, searchFrame)
	searchClear:SetSize(16, 16)
	searchClear:SetPoint("RIGHT", -6, 0)
	local searchClearText = searchClear:CreateFontString(nil, "OVERLAY")
	searchClearText:SetFont(FONT, 12, "OUTLINE")
	searchClearText:SetPoint("CENTER")
	searchClearText:SetTextColor(0.6, 0.6, 0.6, 1)
	searchClearText:SetText("x")
	searchClear:SetScript("OnEnter", function() searchClearText:SetTextColor(1, 0.4, 0.4, 1) end)
	searchClear:SetScript("OnLeave", function() searchClearText:SetTextColor(0.6, 0.6, 0.6, 1) end)
	searchClear:SetScript("OnClick", function()
		searchBox:SetText("")
		searchBox:ClearFocus()
	end)
	searchClear:Hide()
	-- Show/hide the clear button as the search box text changes. Hooked
	-- below in OnTextChanged where _filterText is already updated.
	self._searchClear = searchClear

	-- Raw toggle
	local tglRaw = MakeToggle(manageBox, "Raw", C_ACCENT)
	tglRaw:SetSize(55, 20)
	tglRaw:SetPoint("LEFT", searchFrame, "RIGHT", 8, 0)
	self._tglRaw = tglRaw

	-- Refresh button (circular arrow icon + text)
	local refreshBtn = CreateFrame("Button", nil, manageBox)
	refreshBtn:SetSize(86, 22)
	refreshBtn:SetPoint("LEFT", tglRaw, "RIGHT", 8, 0)
	ApplyBackdrop(refreshBtn, C_ROW_ODD, C_BORDER)
	local refreshIcon = refreshBtn:CreateTexture(nil, "OVERLAY")
	refreshIcon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
	refreshIcon:SetSize(12, 12)
	refreshIcon:SetPoint("LEFT", 8, 0)
	refreshIcon:SetVertexColor(0.7, 0.7, 0.7, 1)
	local refreshText = MakeText(refreshBtn, 10, C_DIM, "OUTLINE")
	refreshText:SetPoint("LEFT", refreshIcon, "RIGHT", 5, 0)
	refreshText:SetText("Refresh")
	refreshBtn:SetScript("OnEnter", function()
		ApplyBackdrop(refreshBtn, C_ROW_HOVER, C_BORDER)
		refreshText:SetTextColor(unpack(C_TEXT))
		refreshIcon:SetVertexColor(1, 1, 1, 1)
	end)
	refreshBtn:SetScript("OnLeave", function()
		ApplyBackdrop(refreshBtn, C_ROW_ODD, C_BORDER)
		refreshText:SetTextColor(unpack(C_DIM))
		refreshIcon:SetVertexColor(0.7, 0.7, 0.7, 1)
	end)

	-- "Item Name" column header above the list (CSS: list-header, h=40, bg #101010)
	-- Click to toggle ascending/descending sort. Arrow indicator next to the
	-- label shows current direction.
	local itemNameHeader = CreateFrame("Button", nil, manageBox)
	itemNameHeader:SetPoint("TOPLEFT", 6, -40)
	itemNameHeader:SetPoint("TOPRIGHT", -6, -40)
	itemNameHeader:SetHeight(22)
	itemNameHeader:SetBackdrop({ bgFile = WHITE8x8 })
	itemNameHeader:SetBackdropColor(0.063, 0.063, 0.063, 1)  -- #101010
	local itemNameLabel = MakeText(itemNameHeader, 10, C_TEXT, "OUTLINE")
	itemNameLabel:SetPoint("LEFT", 10, 0)
	itemNameLabel:SetText("Item Name")

	local sortArrow = MakeText(itemNameHeader, 9, C_DIM, "OUTLINE")
	sortArrow:SetPoint("LEFT", itemNameLabel, "RIGHT", 6, 0)
	sortArrow:SetText("v")  -- v = descending visual; we start ascending so default text rotates
	self._sortDescending = false

	itemNameHeader:SetScript("OnEnter", function()
		itemNameHeader:SetBackdropColor(0.10, 0.10, 0.10, 1)
	end)
	itemNameHeader:SetScript("OnLeave", function()
		itemNameHeader:SetBackdropColor(0.063, 0.063, 0.063, 1)
	end)
	itemNameHeader:SetScript("OnClick", function()
		self._sortDescending = not self._sortDescending
		sortArrow:SetText(self._sortDescending and "^" or "v")
		if self.Refresh then self:Refresh() end
	end)
	self._sortArrow = sortArrow


	-- ========================================================================
	-- Item List (inside manageBox, below Item Name header)
	-- ========================================================================
	local listBox = CreateFrame("Frame", nil, manageBox)
	listBox:SetPoint("TOPLEFT", 1, -62)                                    -- below header (40) + header height (22)
	listBox:SetPoint("BOTTOMRIGHT", -1, 36)                                -- reserve 36px at bottom for pagination
	listBox:SetBackdrop({ bgFile = WHITE8x8, edgeFile = WHITE8x8, edgeSize = 1 })
	listBox:SetBackdropColor(0.035, 0.035, 0.035, 1)  -- #090909
	listBox:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)  -- #262626
	self._listBox = listBox

	emptyText = MakeText(listBox, 9, C_DIM, "OUTLINE")
	emptyText:SetPoint("CENTER")
	self._emptyText = emptyText

	local scroll = CreateFrame("ScrollFrame", "AutoDelete_ListScroll", listBox, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 1, -1)
	scroll:SetPoint("BOTTOMRIGHT", -1, 1)
	self._scroll = scroll

	-- Hide the FauxScrollFrame's scrollbar completely - we use pagination only.
	local scrollBar = _G["AutoDelete_ListScrollScrollBar"]
	local scrollUp = _G["AutoDelete_ListScrollScrollBarScrollUpButton"]
	local scrollDown = _G["AutoDelete_ListScrollScrollBarScrollDownButton"]
	if scrollBar then
		scrollBar:Hide()
		scrollBar.Show = function() end  -- prevent FauxScrollFrame_Update from re-showing it
	end
	if scrollUp then scrollUp:Hide() end
	if scrollDown then scrollDown:Hide() end

	local ROW_HEIGHT = 18
	-- listBox sits inside manageBox: 62px at top (search row 34 + header 22 + gap 6),
	-- 36px at bottom (reserved for pagination row). So effective listBox height:
	local listHeight = manageH - 62 - 36 - 4  -- -4 for borders
	local NUM_ROWS = math.floor(listHeight / ROW_HEIGHT)
	if NUM_ROWS < 5 then NUM_ROWS = 5 end
	if NUM_ROWS > 10 then NUM_ROWS = 10 end   -- cap at 10 visible rows per user request

	self._rows = {}
	for i = 1, NUM_ROWS do
		local row = CreateFrame("Button", nil, listBox)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 1, -1 - (i - 1) * ROW_HEIGHT)
		row:SetPoint("RIGHT", -1, 0)

		-- Alternating background
		local rowBG = row:CreateTexture(nil, "BACKGROUND")
		rowBG:SetTexture(WHITE8x8)
		rowBG:SetAllPoints()
		if i % 2 == 1 then
			rowBG:SetVertexColor(unpack(C_ROW_ODD))
		else
			rowBG:SetVertexColor(unpack(C_ROW_EVEN))
		end
		row._bg = rowBG
		row._bgDefault = (i % 2 == 1) and C_ROW_ODD or C_ROW_EVEN

		-- Hover
		row:SetScript("OnEnter", function(self)
			rowBG:SetVertexColor(unpack(C_ROW_HOVER))
			if self.entry and self.entry.kind == "id" then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetHyperlink("item:" .. self.entry.id)
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", function(self)
			rowBG:SetVertexColor(unpack(self._bgDefault))
			GameTooltip:Hide()
		end)

		-- Remove button: text "×" at 12pt (create before text so text can anchor to it)
		row.remove = CreateFrame("Button", nil, row)
		row.remove:SetSize(18, 18)
		row.remove:SetPoint("RIGHT", -2, 0)
		local removeText = MakeText(row.remove, 18, C_RED, "OUTLINE")
		removeText:SetPoint("CENTER", 0, 0)
		removeText:SetText("×")
		row.remove:SetScript("OnEnter", function()
			removeText:SetTextColor(1, 1, 1, 1)
		end)
		row.remove:SetScript("OnLeave", function()
			removeText:SetTextColor(unpack(C_RED))
		end)

		-- Icon texture (left side of row, 18×18, border, trimmed edges)
		row.iconFrame = CreateFrame("Frame", nil, row)
		row.iconFrame:SetSize(20, 20)
		row.iconFrame:SetPoint("LEFT", row, "LEFT", 6, 0)
		ApplyBackdrop(row.iconFrame, { 0, 0, 0, 1 }, C_BORDER)
		row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
		row.icon:SetPoint("TOPLEFT", 1, -1)
		row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trim default Blizzard icon border
		-- Default: use a Blizzard generic question-mark texture; replaced per-item in UpdateListRows
		row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

		-- Name (anchored to the right of the icon)
		row.text = MakeText(row, 10, C_TEXT, "OUTLINE", "LEFT")
		row.text:SetPoint("LEFT", row.iconFrame, "RIGHT", 8, 0)
		row.text:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
		row.text:SetWordWrap(false)

		-- Right-click context menu. Provides quick "move to other list" actions
		-- and remove. Left-click is reserved (not currently used) so the row
		-- registers for both button kinds. The menu is a single shared frame
		-- created lazily on first right-click; see EnsureRowContextMenu.
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, button)
			if button == "RightButton" and self.entry then
				if _G.AutoDelete_ShowRowContextMenu then
					_G.AutoDelete_ShowRowContextMenu(self, self.entry)
				end
			end
		end)

		self._rows[i] = row
	end

	-- Build (lazily) and show the row context menu near a row. Single frame
	-- shared across all rows. Each click rebuilds the items based on the
	-- current list mode so "Move to" only shows the OTHER lists, not the
	-- current one. Items are routed through the same Add/Remove paths the
	-- buttons use, so list-conflict checks and statistics stay consistent.
	local rowMenu
	local function EnsureRowContextMenu()
		if rowMenu then return rowMenu end
		rowMenu = CreateFrame("Frame", "AutoDelete_RowContextMenu", UIParent)
		rowMenu:SetFrameStrata("FULLSCREEN_DIALOG")
		rowMenu:SetFrameLevel(200)
		rowMenu:EnableMouse(true)
		ApplyBackdrop(rowMenu, C_BG, { 0.30, 0.30, 0.30, 1 })
		rowMenu:Hide()
		rowMenu._items = {}
		rowMenu:SetScript("OnHide", function() if rowMenu._closer then rowMenu._closer:Hide() end end)
		-- Click-elsewhere closer (full-screen invisible button, behind the menu)
		local closer = CreateFrame("Button", nil, UIParent)
		closer:SetAllPoints(UIParent)
		closer:SetFrameStrata("FULLSCREEN_DIALOG")
		closer:SetFrameLevel(199)
		closer:RegisterForClicks("AnyDown")
		closer:SetScript("OnClick", function() rowMenu:Hide() end)
		closer:Hide()
		rowMenu._closer = closer
		return rowMenu
	end

	local function ShowRowContextMenu(row, entry)
		local menu = EnsureRowContextMenu()
		menu:ClearAllPoints()
		menu:SetPoint("TOPLEFT", row, "TOPRIGHT", 4, 0)
		-- Build the action list based on current list mode
		local mode = self._listMode or "delete"
		local actions = {}
		if mode ~= "delete"    then table.insert(actions, { label = "Move to Delete", target = "listText" }) end
		if mode ~= "sell"      then table.insert(actions, { label = "Move to Sell",   target = "sellListText" }) end
		if mode ~= "whitelist" then table.insert(actions, { label = "Move to Keep",   target = "whitelistText" }) end
		table.insert(actions, { label = "Remove", target = nil })

		-- Tear down old item buttons
		for _, btn in ipairs(menu._items) do btn:Hide() end
		menu._items = {}

		local rowH = 22
		local W = 140
		menu:SetSize(W, rowH * #actions + 4)
		for i, action in ipairs(actions) do
			local btn = CreateFrame("Button", nil, menu)
			btn:SetSize(W - 4, rowH)
			btn:SetPoint("TOPLEFT", 2, -2 - (i - 1) * rowH)
			ApplyBackdrop(btn, C_ROW_ODD, { 0, 0, 0, 0 })
			local txt = MakeText(btn, 10, C_TEXT, "OUTLINE", "LEFT")
			txt:SetPoint("LEFT", 8, 0)
			txt:SetText(action.label)
			btn:SetScript("OnEnter", function()
				ApplyBackdrop(btn, C_ROW_HOVER, { 0, 0, 0, 0 })
				txt:SetTextColor(1, 1, 1, 1)
			end)
			btn:SetScript("OnLeave", function()
				ApplyBackdrop(btn, C_ROW_ODD, { 0, 0, 0, 0 })
				txt:SetTextColor(unpack(C_TEXT))
			end)
			btn:SetScript("OnClick", function()
				menu:Hide()
				if entry.kind ~= "id" then return end
				local id = entry.id
				if action.target then
					-- Move = remove from current + add to target
					local currentKey = GetActiveListKey()
					if _G.AutoDelete_RemoveItemFromList then
						_G.AutoDelete_RemoveItemFromList(currentKey, id)
					end
					if _G.AutoDelete_AddItemToList then
						_G.AutoDelete_AddItemToList(action.target, id)
					end
				else
					-- Remove only
					local currentKey = GetActiveListKey()
					if _G.AutoDelete_RemoveItemFromList then
						_G.AutoDelete_RemoveItemFromList(currentKey, id)
					end
				end
				if self.Refresh then self:Refresh() end
			end)
			table.insert(menu._items, btn)
		end
		menu:Show()
		menu._closer:Show()
	end
	_G.AutoDelete_ShowRowContextMenu = ShowRowContextMenu

	-- ========================================================================
	-- Pagination UI (below listBox, inside manageBox)
	-- Left: "Showing X-Y of N items"
	-- Right: |< < [page/total] > >|
	-- ========================================================================
	self._currentPage = 1
	-- Page size equals visible rows: exactly 10 items per page, no scrolling.
	-- Use pagination buttons to navigate between pages.
	self._pageSize = NUM_ROWS

	local pagingFrame = CreateFrame("Frame", nil, manageBox)
	pagingFrame:SetPoint("TOPLEFT", listBox, "BOTTOMLEFT", 0, -6)
	pagingFrame:SetPoint("TOPRIGHT", listBox, "BOTTOMRIGHT", 0, -6)
	pagingFrame:SetHeight(24)

	local pagingInfo = MakeText(pagingFrame, 9, C_DIM, "OUTLINE", "LEFT")
	pagingInfo:SetPoint("LEFT", 4, 0)
	pagingInfo:SetText("Showing 0 of 0 items")
	self._pagingInfo = pagingInfo

	-- Single pagination nav button. Flat near-black background, thin black
	-- border, a subtle top-edge gloss highlight, and a hover state that lifts
	-- the background slightly and tints the border.
	-- If `texturePath` is provided, draws a texture (arrow) instead of text.
	local function MakePageBtn(label, w, fontSize, texturePath, texW, texH)
		local btn = CreateFrame("Button", nil, pagingFrame)
		btn:SetSize(w or 28, 22)

		-- Base backdrop: near-black bg, pure-black 1px border
		btn:SetBackdrop({ bgFile = WHITE8x8, edgeFile = WHITE8x8, edgeSize = 1 })
		btn:SetBackdropColor(0.09, 0.09, 0.09, 1)
		btn:SetBackdropBorderColor(0, 0, 0, 1)

		-- Thin top highlight line
		local gloss = btn:CreateTexture(nil, "OVERLAY")
		gloss:SetTexture(WHITE8x8)
		gloss:SetVertexColor(1, 1, 1, 0.08)
		gloss:SetHeight(1)
		gloss:SetPoint("TOPLEFT", 1, -1)
		gloss:SetPoint("TOPRIGHT", -1, -1)
		btn._gloss = gloss

		if texturePath then
			-- Texture-based arrow (pre-rotated, no SetRotation).
			local tex = btn:CreateTexture(nil, "OVERLAY")
			tex:SetTexture(texturePath)
			tex:SetSize(texW or 10, texH or 10)
			tex:SetPoint("CENTER")
			tex:SetVertexColor(1, 1, 1, 1)
			btn._tex = tex
			-- _text stub so SetBtnEnabled can drive all page buttons uniformly.
			btn._text = {
				SetTextColor = function(_, r, g, b, a)
					tex:SetVertexColor(r, g, b, a or 1)
				end,
				SetText = function() end,
			}
		else
			-- Text label (used by the "1 / N" indicator).
			local btnText = btn:CreateFontString(nil, "OVERLAY")
			btnText:SetFont(FONT, fontSize or 13)
			btnText:SetTextColor(1, 1, 1, 1)
			btnText:SetPoint("CENTER")
			btnText:SetText(label)
			btn._text = btnText
		end

		btn:SetScript("OnEnter", function(self)
			-- Hover: lift bg slightly, tint border teal-ish
			self:SetBackdropColor(0.14, 0.14, 0.14, 1)
			self:SetBackdropBorderColor(0.25, 0.55, 0.65, 1)
			gloss:SetVertexColor(1, 1, 1, 0.14)
		end)
		btn:SetScript("OnLeave", function(self)
			self:SetBackdropColor(0.09, 0.09, 0.09, 1)
			self:SetBackdropBorderColor(0, 0, 0, 1)
			gloss:SetVertexColor(1, 1, 1, 0.08)
		end)

		return btn
	end

	-- Pagination arrows: pre-rotated textures for each direction so they all
	-- render at identical visual sizes.
	local TEX_BASE = "Interface\\AddOns\\AutoDelete\\textures\\"
	local firstBtn = MakePageBtn(nil, 28, nil, TEX_BASE .. "doublearrowleft.tga",  12, 12)
	local prevBtn  = MakePageBtn(nil, 28, nil, TEX_BASE .. "arrowleft.tga",        12, 12)
	local nextBtn  = MakePageBtn(nil, 28, nil, TEX_BASE .. "arrowright.tga",       12, 12)
	local lastBtn  = MakePageBtn(nil, 28, nil, TEX_BASE .. "doublearrowright.tga", 12, 12)
	local pageIndicator = MakePageBtn("1 / 1", 52)
	pageIndicator:SetScript("OnEnter", nil)  -- no hover effect for indicator
	pageIndicator:SetScript("OnLeave", nil)
	pageIndicator:EnableMouse(false)

	-- Right-to-left anchoring: >| at right edge, then >, indicator, <, |<
	lastBtn:SetPoint("RIGHT", -4, 0)
	nextBtn:SetPoint("RIGHT", lastBtn, "LEFT", -3, 0)
	pageIndicator:SetPoint("RIGHT", nextBtn, "LEFT", -3, 0)
	prevBtn:SetPoint("RIGHT", pageIndicator, "LEFT", -3, 0)
	firstBtn:SetPoint("RIGHT", prevBtn, "LEFT", -3, 0)

	self._pageIndicator = pageIndicator
	self._pageFirstBtn = firstBtn
	self._pagePrevBtn = prevBtn
	self._pageNextBtn = nextBtn
	self._pageLastBtn = lastBtn

	local function GoToPage(p)
		local totalItems = #(self._filtered or {})
		local totalPages = math.max(1, math.ceil(totalItems / self._pageSize))
		if p < 1 then p = 1 end
		if p > totalPages then p = totalPages end
		self._currentPage = p
		self:UpdateListRows()
	end
	self._GoToPage = GoToPage

	firstBtn:SetScript("OnClick", function() GoToPage(1) end)
	prevBtn:SetScript("OnClick", function() GoToPage((self._currentPage or 1) - 1) end)
	nextBtn:SetScript("OnClick", function() GoToPage((self._currentPage or 1) + 1) end)
	lastBtn:SetScript("OnClick", function()
		local totalItems = #(self._filtered or {})
		local totalPages = math.max(1, math.ceil(totalItems / self._pageSize))
		GoToPage(totalPages)
	end)

	-- ========================================================================
	-- Raw Editor
	-- ========================================================================
	local rawBoxHolder = CreateFrame("Frame", nil, self)
	rawBoxHolder:SetAllPoints(listBox)
	ApplyBackdrop(rawBoxHolder, C_BG, C_BORDER)
	rawBoxHolder:Hide()
	self._rawBoxHolder = rawBoxHolder

	local rawScroll = CreateFrame("ScrollFrame", nil, rawBoxHolder)
	rawScroll:SetPoint("TOPLEFT", 6, -6)
	rawScroll:SetPoint("BOTTOMRIGHT", -6, 6)

	local rawEditBox = CreateFrame("EditBox", nil, rawScroll)
	rawEditBox:SetMultiLine(true); rawEditBox:SetAutoFocus(false)
	rawEditBox:EnableMouse(true); rawEditBox:EnableKeyboard(true)
	rawEditBox:SetFont(FONT, 10, "OUTLINE"); rawEditBox:SetTextColor(unpack(C_TEXT))
	rawEditBox:SetWidth(340)
	rawScroll:SetScrollChild(rawEditBox)
	rawEditBox:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)

	rawBoxHolder:EnableMouse(true)
	rawBoxHolder:SetScript("OnMouseDown", function() rawEditBox:SetFocus() end)
	rawScroll:EnableMouseWheel(true)
	rawScroll:SetScript("OnMouseWheel", function(sf, delta)
		local v = math.max(0, math.min(sf:GetVerticalScrollRange(), sf:GetVerticalScroll() - delta * 40))
		sf:SetVerticalScroll(v)
	end)
	rawEditBox:SetScript("OnCursorChanged", function(eb, x, y, w, h)
		local vs, sh = rawScroll:GetVerticalScroll(), rawScroll:GetHeight()
		local cy = -y
		if cy < vs then rawScroll:SetVerticalScroll(cy)
		elseif cy + h > vs + sh then rawScroll:SetVerticalScroll(cy + h - sh) end
	end)
	self._rawEditBox = rawEditBox

	self._filterText = ""
	self._entries = {}
	self._filtered = {}

	-- ========================================================================
	-- Events
	-- ========================================================================
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	self:SetScript("OnEvent", function(s, event)
		if event == "GET_ITEM_INFO_RECEIVED" and s._built and s:IsVisible() and not rawBoxHolder:IsShown() then
			s:UpdateListRows()
		end
	end)

	-- ========================================================================
	-- Handlers
	-- ========================================================================
	tglEnable:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		local p = GetActiveProfile(db)
		p.enabled = btn._checked
		print("|cffff8000[AutoDelete]|r " .. (p.enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r"))
	end)

	-- Auto-Add Equipped: flipping ON triggers the one-time sync of currently
	-- equipped items. Reactive add-on-equip is handled in AutoDelete.lua's
	-- PLAYER_EQUIPMENT_CHANGED handler, which reads the current cachedProfile.
	-- We refresh cachedProfile after writing here so the event handler sees
	-- the new value without waiting for the next scan.
	tglAutoAddEquipped:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		local p = GetActiveProfile(db)
		local wasOff = (p.autoAddEquipped ~= true)
		p.autoAddEquipped = btn._checked
		if _G.AutoDelete_RefreshCachedProfile then
			_G.AutoDelete_RefreshCachedProfile()
		end
		if btn._checked and wasOff and _G.AutoDelete_SyncEquippedToKeep then
			_G.AutoDelete_SyncEquippedToKeep()
			if self.Refresh then self:Refresh() end
		end
	end)

	tglGray:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).autoGray = btn._checked
	end)

	tglDelCommon:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).autoDeleteCommon = btn._checked
	end)

	tglSellGreensGen:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).autoSellGreens = btn._checked
	end)

	-- =========================================================================
	-- Sell-rule wiring (v3.02 category-based schema)
	-- =========================================================================
	-- Helper: wire a category card's widgets to the matching profile fields.
	local function WireCategoryCard(cardWidgets, fieldEnable, fieldRare, fieldEpic, fieldMin, fieldMax)
		cardWidgets.enable:SetScript("OnClick", function(btn)
			btn._checked = not btn._checked
			btn:SetChecked(btn._checked)
			GetActiveProfile(db)[fieldEnable] = btn._checked
		end)
		cardWidgets.rare:SetScript("OnClick", function(btn)
			btn._checked = not btn._checked
			btn:SetChecked(btn._checked)
			GetActiveProfile(db)[fieldRare] = btn._checked
		end)
		cardWidgets.epic:SetScript("OnClick", function(btn)
			btn._checked = not btn._checked
			btn:SetChecked(btn._checked)
			GetActiveProfile(db)[fieldEpic] = btn._checked
		end)
		cardWidgets.minBox:SetScript("OnTextChanged", function(eb)
			local val = tonumber(eb:GetText())
			if val and val > 0 then GetActiveProfile(db)[fieldMin] = val end
		end)
		cardWidgets.maxBox:SetScript("OnTextChanged", function(eb)
			local val = tonumber(eb:GetText())
			if val and val > 0 then GetActiveProfile(db)[fieldMax] = val end
		end)
	end

	WireCategoryCard(boeArmor,
		"boeArmorEnabled", "boeArmorRare", "boeArmorEpic",
		"boeArmorIlvlMin", "boeArmorIlvlMax")

	WireCategoryCard(bop,
		"bopEnabled", "bopRare", "bopEpic",
		"bopIlvlMin", "bopIlvlMax")

	WireCategoryCard(boeWeapons,
		"boeWeaponsEnabled", "boeWeaponsRare", "boeWeaponsEpic",
		"boeWeaponsIlvlMin", "boeWeaponsIlvlMax")

	tglScav:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).summonScavenger = btn._checked
	end)

	-- Goblin tab: Auto-Repair main + Guild Bank sub
	tglRepair:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).autoRepair = btn._checked
	end)
	tglRepairGuild:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).autoRepairUseGuildBank = btn._checked
	end)

	-- Goblin tab: Summon Scavenger sub-toggles
	tglScavAfterSell:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).summonAfterSell = btn._checked
	end)
	tglScavAfterClose:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).summonAfterClose = btn._checked
	end)
	tglScavOnlyInCombat:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).summonOnlyInCombat = btn._checked
	end)
	tglSummonMerchant:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).summonMerchantWhenBagsFull = btn._checked
	end)

	-- Goblin tab: Hide Greedy Scavenger spam
	tglHideSpam:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).hideGreedySpam = btn._checked
	end)

	-- AutoInv tab: master toggle
	tglAutoInvite:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).autoInviteEnabled = btn._checked
	end)

	-- AutoInv tab: loot rule apply toggle
	tglLootRule:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).autoInviteApplyLootRule = btn._checked
	end)

	-- AutoInv tab: convert to raid
	tglConvertRaid:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).autoInviteConvertToRaid = btn._checked
	end)

	-- Tools tab: Auto-Open Containers toggles. Refresh cached profile after
	-- writing so the LOOT-event handler in AutoDelete.lua sees the new value
	-- without waiting for the next scan tick.
	tglAutoOpen:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).autoOpenContainers = btn._checked
		if _G.AutoDelete_RefreshCachedProfile then
			_G.AutoDelete_RefreshCachedProfile()
		end
	end)

	tglAutoOpenLocked:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).autoOpenLocked = btn._checked
		if _G.AutoDelete_RefreshCachedProfile then
			_G.AutoDelete_RefreshCachedProfile()
		end
	end)

	tglAutoOpenInCombat:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).autoOpenSkipCombat = btn._checked
		if _G.AutoDelete_RefreshCachedProfile then
			_G.AutoDelete_RefreshCachedProfile()
		end
	end)

	-- Returns the display-friendly name of a list key for chat output.
	local function ListLabelForKey(key)
		if key == "listText" then return "Delete" end
		if key == "sellListText" then return "Sell" end
		if key == "whitelistText" then return "Keep" end
		return key
	end

	-- Check if adding `line` to `targetKey` would conflict with either other list.
	-- Returns (conflictFound, conflictingListKey) - or (false, nil) if safe.
	local function FindListConflict(profile, targetKey, line)
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

	-- Drag-drop into panel list
	local function PanelAddItem()
		local cursorType, itemID, itemLink = GetCursorInfo()
		if cursorType ~= "item" then ClearCursor() return end
		local id = (type(itemID) == "number") and itemID or GetItemIDFromLink(itemLink)
		ClearCursor()
		if not id then return end
		local line = "item:" .. tostring(id)
		local p = GetActiveProfile(db)
		local key = GetActiveListKey()
		local displayName = GetItemInfo(id) or ("item:" .. id)

		-- Already on THIS list → benign info message.
		if HasExactLine(p[key], line) then
			print("|cffff8000[AutoDelete]|r " .. displayName .. " already in list")
			return
		end

		-- Conflicts with another list → refuse and warn. User must remove from
		-- the other list first. Prevents the Keep/Delete/Sell ambiguity.
		local hasConflict, conflictKey = FindListConflict(p, key, line)
		if hasConflict then
			print("|cffff4444[AutoDelete]|r Cannot add " .. displayName
				.. " to " .. ListLabelForKey(key)
				.. ". Already on the " .. ListLabelForKey(conflictKey)
				.. " list. Remove it from there first.")
			return
		end

		p[key] = AddLineIfMissing(p[key] or "", line)
		GetItemInfo("item:" .. id)
		local labels = { delete = "delete", sell = "sell", whitelist = "keep" }
		print("|cffff8000[AutoDelete]|r Added " .. displayName .. " to " .. (labels[self._listMode] or "delete") .. " list")
		self:Refresh()
	end

	-- Save raw text
	local function SaveRawText()
		if rawBoxHolder:IsShown() then
			local p = GetActiveProfile(db)
			local key = GetActiveListKey()
			local parsed = ParseRawViewText(rawEditBox:GetText() or "")

			-- Scan each line; drop any that conflict with the other two lists.
			-- Report the dropped count so the user knows something was filtered.
			local kept, droppedCount, firstConflict = {}, 0, nil
			for line in string.gmatch(parsed, "[^\r\n]+") do
				-- Temporarily pretend the current list is empty when checking conflicts
				-- so we compare only against the OTHER lists.
				local savedTarget = p[key]
				p[key] = ""
				local hasConflict, conflictKey = FindListConflict(p, key, line)
				p[key] = savedTarget

				if hasConflict then
					droppedCount = droppedCount + 1
					firstConflict = firstConflict or conflictKey
				else
					table.insert(kept, line)
				end
			end

			p[key] = table.concat(kept, "\n") .. (#kept > 0 and "\n" or "")

			-- Tell the backend to refresh its cached profile so the scanner and
			-- other systems see the new list immediately (not just after /reload).
			if _G.AutoDelete_RefreshCachedProfile then
				_G.AutoDelete_RefreshCachedProfile()
			end

			if droppedCount > 0 then
				print("|cffff4444[AutoDelete]|r Dropped " .. droppedCount
					.. " entr" .. (droppedCount == 1 and "y" or "ies")
					.. " from " .. ListLabelForKey(key)
					.. ". Already on the " .. ListLabelForKey(firstConflict) .. " list.")
			end
		end
	end
	self._saveRawText = SaveRawText

	-- Tab handlers
	local function SwitchTab(mode)
		-- If raw view is open with an active filter, restore the unfiltered
		-- text BEFORE saving. Otherwise SaveRawText would persist the
		-- filtered view and silently delete the hidden non-matching lines.
		if self._rawUnfilteredText then
			rawEditBox:SetText(self._rawUnfilteredText)
			self._rawUnfilteredText = nil
		end
		rawEditBox:EnableKeyboard(true)
		rawEditBox:EnableMouse(true)
		rawEditBox:SetTextColor(unpack(C_TEXT))
		SaveRawText()
		self._listMode = mode
		tglRaw:SetChecked(false)
		rawBoxHolder:Hide()
		listBox:Show()
		self:Refresh()
	end
	deleteTab:SetScript("OnClick", function() SwitchTab("delete") end)
	sellTab:SetScript("OnClick", function() SwitchTab("sell") end)
	keepTab:SetScript("OnClick", function() SwitchTab("whitelist") end)

	-- Public method for external callers (ElvUI bag buttons) to jump to
	-- a specific list tab when opening the panel.
	function self:SwitchListMode(mode)
		if mode == "delete" or mode == "sell" or mode == "whitelist" then
			SwitchTab(mode)
		end
	end

	-- List box drag-drop
	listBox:EnableMouse(true); listBox:RegisterForDrag("LeftButton")
	listBox:SetScript("OnReceiveDrag", PanelAddItem)
	listBox:SetScript("OnMouseUp", function() if CursorHasItem() then PanelAddItem() end end)
	for i = 1, #self._rows do
		local row = self._rows[i]
		row:RegisterForDrag("LeftButton")
		row:SetScript("OnReceiveDrag", PanelAddItem)
	end

	-- Search
	searchBox:SetScript("OnTextChanged", function(eb)
		local text = eb:GetText() or ""
		self._filterText = text
		-- Show/hide the clear (x) button based on whether there's text.
		if self._searchClear then
			if text ~= "" then self._searchClear:Show() else self._searchClear:Hide() end
		end
		self:Refresh()
	end)

	-- Raw toggle
	tglRaw:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		if btn._checked then
			-- Entering raw mode: drop any stale stash, unlock editing, load
			-- text from the profile.
			self._rawUnfilteredText = nil
			rawEditBox:EnableKeyboard(true)
			rawEditBox:EnableMouse(true)
			rawEditBox:SetTextColor(unpack(C_TEXT))
			listBox:Hide(); rawBoxHolder:Show()
			rawEditBox:SetText(GenerateRawViewText(GetActiveProfile(db)[GetActiveListKey()]))
			rawEditBox:SetCursorPosition(0)
			-- If the search box already has text, apply the filter immediately.
			if (self._filterText or "") ~= "" then self:Refresh() end
		else
			-- Leaving raw mode: if a filter stash exists, restore the
			-- unfiltered text BEFORE saving so we don't write the filtered
			-- view (which would silently delete hidden non-matching lines).
			if self._rawUnfilteredText then
				rawEditBox:SetText(self._rawUnfilteredText)
				self._rawUnfilteredText = nil
			end
			rawEditBox:EnableKeyboard(true)
			rawEditBox:EnableMouse(true)
			rawEditBox:SetTextColor(unpack(C_TEXT))
			SaveRawText(); rawBoxHolder:Hide(); listBox:Show()
			self:Refresh()
		end
	end)

	-- Refresh button
	refreshBtn:SetScript("OnClick", function()
		local tip = _G.AutoDelete_CacheTip
		if not tip then
			tip = CreateFrame("GameTooltip", "AutoDelete_CacheTip", UIParent, "GameTooltipTemplate")
			tip:SetOwner(UIParent, "ANCHOR_NONE")
		end
		local count = 0
		for _, entry in ipairs(self._entries or {}) do
			if entry.kind == "id" and not GetItemInfo(entry.id) then
				tip:SetHyperlink("item:" .. entry.id)
				count = count + 1
			end
		end
		tip:Hide()
		if count > 0 then print("|cffff8000[AutoDelete]|r Requesting " .. count .. " item(s)...") end
		local d = CreateFrame("Frame"); local e = 0
		d:SetScript("OnUpdate", function(df, dt)
			e = e + dt
			if e >= 1.5 then df:SetScript("OnUpdate", nil); if self._built and self:IsVisible() then self:Refresh() end end
		end)
	end)

	-- Row remove handlers
	for i = 1, #self._rows do
		local row = self._rows[i]
		row.remove:SetScript("OnClick", function()
			if row.entry then
				local p = GetActiveProfile(db)
				local key = GetActiveListKey()
				p[key] = RemoveExactLine(p[key] or "", row.entry.raw)
				local labels = { delete = "delete", sell = "sell", whitelist = "keep" }
				print("|cffff8000[AutoDelete]|r Removed " .. GetDisplayForEntry(row.entry) .. " from " .. (labels[self._listMode] or "delete") .. " list")
				self:Refresh()
			end
		end)
	end

	-- Scroll handler
	scroll:SetScript("OnVerticalScroll", function(s, offset)
		FauxScrollFrame_OnVerticalScroll(s, offset, ROW_HEIGHT, function() self:UpdateListRows() end)
	end)

	-- Periodic cache retry
	local cacheElapsed = 0
	self:SetScript("OnUpdate", function(s, dt)
		cacheElapsed = cacheElapsed + dt
		if cacheElapsed < 3 then return end
		cacheElapsed = 0
		if not s._built or not s:IsVisible() or rawBoxHolder:IsShown() then return end
		local tip = _G.AutoDelete_CacheTip
		if not tip then
			tip = CreateFrame("GameTooltip", "AutoDelete_CacheTip", UIParent, "GameTooltipTemplate")
			tip:SetOwner(UIParent, "ANCHOR_NONE")
		end
		local hasUncached = false
		for _, entry in ipairs(s._entries or {}) do
			if entry.kind == "id" and not GetItemInfo(entry.id) then
				tip:SetHyperlink("item:" .. entry.id); hasUncached = true
			end
		end
		tip:Hide()
		if hasUncached then s:UpdateListRows() end
	end)

	-- ========================================================================
	-- Refresh
	-- ========================================================================
	function self:Refresh()
		local p = GetActiveProfile(db)
		tglEnable:SetChecked(p.enabled)
		tglAutoAddEquipped:SetChecked(p.autoAddEquipped)

		-- Tools tab: Auto-Open Containers + sub-toggles, Sell Threshold
		tglAutoOpen:SetChecked(p.autoOpenContainers)
		tglAutoOpenLocked:SetChecked(p.autoOpenLocked)
		tglAutoOpenInCombat:SetChecked(p.autoOpenSkipCombat)
		thresholdEdit:SetText(tostring(p.sellThresholdGold or 0))

		-- BoE Armor card
		boeArmor.enable:SetChecked(p.boeArmorEnabled)
		boeArmor.rare:SetChecked(p.boeArmorRare)
		boeArmor.epic:SetChecked(p.boeArmorEpic)
		boeArmor.minBox:SetText(tostring(p.boeArmorIlvlMin or 1))
		boeArmor.maxBox:SetText(tostring(p.boeArmorIlvlMax or 199))

		-- BoP card
		bop.enable:SetChecked(p.bopEnabled)
		bop.rare:SetChecked(p.bopRare)
		bop.epic:SetChecked(p.bopEpic)
		bop.minBox:SetText(tostring(p.bopIlvlMin or 1))
		bop.maxBox:SetText(tostring(p.bopIlvlMax or 199))

		-- BoE Weapons card
		boeWeapons.enable:SetChecked(p.boeWeaponsEnabled)
		boeWeapons.rare:SetChecked(p.boeWeaponsRare)
		boeWeapons.epic:SetChecked(p.boeWeaponsEpic)
		boeWeapons.minBox:SetText(tostring(p.boeWeaponsIlvlMin or 1))
		boeWeapons.maxBox:SetText(tostring(p.boeWeaponsIlvlMax or 199))

		-- General tab: Auto-Delete Junk + Auto-Delete Common + Auto-Sell Greens
		tglGray:SetChecked(p.autoGray)
		tglDelCommon:SetChecked(p.autoDeleteCommon)
		tglSellGreensGen:SetChecked(p.autoSellGreens)

		tglScav:SetChecked(p.summonScavenger)
		-- Goblin tab toggles
		tglRepair:SetChecked(p.autoRepair)
		tglRepairGuild:SetChecked(p.autoRepairUseGuildBank)
		tglScavAfterSell:SetChecked(p.summonAfterSell)
		tglScavAfterClose:SetChecked(p.summonAfterClose)
		tglScavOnlyInCombat:SetChecked(p.summonOnlyInCombat)
		tglSummonMerchant:SetChecked(p.summonMerchantWhenBagsFull)
		tglHideSpam:SetChecked(p.hideGreedySpam)
		-- AutoInv tab toggles
		tglAutoInvite:SetChecked(p.autoInviteEnabled)
		kwBox:SetText(p.autoInviteKeywords or "inv,invite")
		tglLootRule:SetChecked(p.autoInviteApplyLootRule)
		lootDD:SetValue(p.autoInviteLootRule or "freeforall")
		tglConvertRaid:SetChecked(p.autoInviteConvertToRaid)
		speedDD:SetValue((p.scanInterval and p.scanInterval >= 0.5) and p.scanInterval or 0.5)
		UpdateTabColors()

		-- Also refresh tracking stats if the Tracking tab is currently shown.
		if self._activeSettingsTab == "tracking" and self.RefreshTrackingStats then
			self:RefreshTrackingStats()
		end
		-- Also refresh profile list if Profiles tab is currently shown.
		if self._activeSettingsTab == "profiles" and self.RefreshProfileList then
			self:RefreshProfileList()
		end

		if not rawBoxHolder:IsShown() then
			self._entries = ParseListText(p[GetActiveListKey()] or "")
			for _, entry in ipairs(self._entries) do
				if entry.kind == "id" then GetItemInfo("item:" .. entry.id) end
			end
			SortEntries(self._entries, self._sortDescending)
			self._filtered = {}
			local f = Normalize(self._filterText or "")
			for _, e in ipairs(self._entries) do
				local name = GetDisplayForEntry(e)
				if f == "" or string.find(Normalize(name), f, 1, true) then
					table.insert(self._filtered, e)
				end
			end
			-- Reset to page 1 when filter/text changes
			self._currentPage = 1
			-- Tell FauxScrollFrame about the items in the current page so scrollbar
			-- appears and can scroll through the items within the page.
			local pageItemCount = math.min(self._pageSize, #self._filtered)
			FauxScrollFrame_Update(scroll, pageItemCount, NUM_ROWS, ROW_HEIGHT)
			self:UpdateListRows()
		else
			-- Raw view filter handling.
			--
			-- When the user types in the search box while raw view is open we
			-- show only matching lines and lock the editor to read-only so
			-- typing in a filtered view (which would silently discard the
			-- hidden non-matching lines) is impossible. When the filter is
			-- cleared, we restore the original full text and unlock editing.
			--
			-- self._rawUnfilteredText is a stash of the editor's text from
			-- BEFORE filtering started, so user edits made while editing the
			-- raw text are preserved even if they hit search and clear it.
			local f = Normalize(self._filterText or "")
			if f == "" then
				if self._rawUnfilteredText then
					-- Restore from stash, drop the stash, unlock editing.
					rawEditBox:SetText(self._rawUnfilteredText)
					rawEditBox:SetCursorPosition(0)
					self._rawUnfilteredText = nil
					rawEditBox:EnableKeyboard(true)
					rawEditBox:EnableMouse(true)
					rawEditBox:SetTextColor(unpack(C_TEXT))
				end
			else
				-- Stash unfiltered text on the FIRST filtered keystroke so we
				-- can restore later. Subsequent filter changes don't re-stash.
				if not self._rawUnfilteredText then
					self._rawUnfilteredText = rawEditBox:GetText() or ""
				end
				-- Build filtered text: walk the stashed unfiltered content,
				-- keep lines whose item-id-resolved-name (or raw line if no
				-- id) matches the filter.
				local filteredLines = {}
				for line in string.gmatch(self._rawUnfilteredText, "[^\r\n]+") do
					local trimmed = Trim(string.gsub(Trim(line), "%s*#.*$", ""))
					local match = false
					if trimmed ~= "" then
						local itemId = tonumber(string.match(trimmed, "^item:(%d+)"))
						local displayName = trimmed
						if itemId then
							local n = GetItemInfo(itemId)
							if n and n ~= "" then displayName = n end
						end
						if string.find(Normalize(displayName), f, 1, true) then
							match = true
						end
					end
					if match then table.insert(filteredLines, line) end
				end
				rawEditBox:SetText(table.concat(filteredLines, "\n"))
				rawEditBox:SetCursorPosition(0)
				-- Read-only while filtered: disable keyboard input + dim text
				-- so the user can see at a glance that they can't type here.
				rawEditBox:EnableKeyboard(false)
				rawEditBox:SetTextColor(0.55, 0.55, 0.55, 1)
			end
		end
	end

	function self:UpdateListRows()
		local totalItems = #self._filtered
		local pageSize = self._pageSize or #self._rows
		local totalPages = math.max(1, math.ceil(totalItems / pageSize))

		-- Clamp currentPage if totalPages shrunk (e.g. search filter narrowed list)
		if (self._currentPage or 1) > totalPages then
			self._currentPage = totalPages
		end
		if not self._currentPage or self._currentPage < 1 then
			self._currentPage = 1
		end

		local pageStart = (self._currentPage - 1) * pageSize  -- 0-indexed offset
		local pageEnd = math.min(pageStart + pageSize, totalItems)

		if totalItems > 0 then emptyText:Hide() else emptyText:Show() end

		for i = 1, #self._rows do
			local idx = pageStart + i            -- 1-indexed entry index within page
			local row = self._rows[i]
			local entry = (idx <= pageEnd) and self._filtered[idx] or nil
			row.entry = entry
			if entry then
				local dispName, icon, _, quality = GetDisplayForEntry(entry)
				row.text:SetText(dispName)
				if quality and GetItemQualityColor then
					row.text:SetTextColor(GetItemQualityColor(quality))
				else
					row.text:SetTextColor(unpack(C_TEXT))
				end
				if icon then
					row.icon:SetTexture(icon)
				else
					row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
				end
				row:Show()
			else
				row:Hide()
			end
		end

		-- Update pagination UI
		if self._pagingInfo then
			if totalItems == 0 then
				self._pagingInfo:SetText("Showing 0 of 0 items")
			else
				self._pagingInfo:SetText(string.format("Showing %d-%d of %d items",
					pageStart + 1, pageEnd, totalItems))
			end
		end
		if self._pageIndicator then
			self._pageIndicator._text:SetText(string.format("%d / %d",
				self._currentPage, totalPages))
		end

		-- Dim first/prev when on page 1, dim next/last when on last page.
		-- Enabled stays white; disabled drops to a medium gray so the state
		-- difference reads clearly against the dark button bg.
		local function SetBtnEnabled(btn, enabled)
			if not btn then return end
			if enabled then
				btn:EnableMouse(true)
				btn._text:SetTextColor(1, 1, 1, 1)
			else
				btn:EnableMouse(false)
				btn._text:SetTextColor(0.4, 0.4, 0.4, 1)
			end
		end
		SetBtnEnabled(self._pageFirstBtn, self._currentPage > 1)
		SetBtnEnabled(self._pagePrevBtn, self._currentPage > 1)
		SetBtnEnabled(self._pageNextBtn, self._currentPage < totalPages)
		SetBtnEnabled(self._pageLastBtn, self._currentPage < totalPages)

		-- Tell FauxScrollFrame about current page's item count so scrollbar resizes
		local pageItemCount = pageEnd - pageStart
		FauxScrollFrame_Update(scroll, pageItemCount, NUM_ROWS, ROW_HEIGHT)
	end

	self._built = true
	self:Refresh()
end

frame:SetScript("OnShow", function(s)
	if not s._built then BuildUI(s) else s:Refresh() end
end)
frame:SetScript("OnHide", function(s)
	if s._saveRawText then s._saveRawText() end
end)

-- ============================================================================
-- Shared popup builder (matches main window style)
-- ============================================================================
-- All AutoDelete custom popup windows share this skeleton: outer frame with
-- the main-window dark card style, a title bar (same height and color as the
-- main window's title bar), a close X button, and a draggable title. Returns
-- the frame plus a "body" frame (the content area below the title bar) for
-- callers to fill in.

local function BuildPopupSkeleton(globalName, title, W, H)
	if _G[globalName] then return _G[globalName], _G[globalName]._body end

	local f = CreateFrame("Frame", globalName, UIParent)
	f:SetSize(W, H)
	f:SetPoint("CENTER")
	f:SetFrameStrata("FULLSCREEN_DIALOG")   -- above the main options panel (DIALOG)
	f:SetFrameLevel(10)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	ApplyBackdrop(f, C_BG, C_BORDER)
	f:Hide()
	tinsert(UISpecialFrames, globalName)

	-- Title bar (same style as main window). Explicit frame level so it
	-- renders above the outer backdrop.
	local titleBar = CreateFrame("Frame", nil, f)
	titleBar:SetSize(W, 24)
	titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	titleBar:SetFrameLevel(f:GetFrameLevel() + 2)
	ApplyBackdrop(titleBar, C_TITLEBAR, C_BORDER)
	titleBar:EnableMouse(true)
	titleBar:SetScript("OnMouseDown", function() f:StartMoving() end)
	titleBar:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

	local titleText = MakeText(titleBar, 12, C_TITLE, "OUTLINE")
	titleText:SetPoint("LEFT", 10, 0)
	titleText:SetText(title)

	-- Close X (same style as main window close button)
	local closeBtn = CreateFrame("Button", nil, titleBar)
	closeBtn:SetSize(24, 24)
	closeBtn:SetPoint("TOPRIGHT", 0, 0)
	closeBtn:SetFrameLevel(titleBar:GetFrameLevel() + 1)
	local closeTxt = MakeText(closeBtn, 14, C_DIM, "OUTLINE")
	closeTxt:SetPoint("CENTER")
	closeTxt:SetText("x")
	closeBtn:SetScript("OnEnter", function() closeTxt:SetTextColor(1, 0.3, 0.3) end)
	closeBtn:SetScript("OnLeave", function() closeTxt:SetTextColor(unpack(C_DIM)) end)
	closeBtn:SetScript("OnClick", function() f:Hide() end)

	-- Body: everything under the title bar. Explicit SetSize (not dual-anchor)
	-- so child frames that inspect parent dimensions at creation time see a
	-- resolved width. Also explicit frame level so body content renders
	-- between the outer backdrop and the title bar.
	local body = CreateFrame("Frame", nil, f)
	body:SetSize(W, H - 24)
	body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -24)
	body:SetFrameLevel(f:GetFrameLevel() + 1)

	f._body = body
	return f, body
end

-- Shared "dialog button" builder (Apply/Cancel style).
local function MakeDialogButton(parent, label, onClick)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(90, 24)
	ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
	local txt = MakeText(btn, 11, C_TEXT, "OUTLINE")
	txt:SetPoint("CENTER")
	txt:SetText(label)
	btn._text = txt
	btn:SetScript("OnEnter", function(b)
		ApplyBackdrop(b, C_ROW_HOVER, C_BORDER)
		txt:SetTextColor(1, 1, 1)
	end)
	btn:SetScript("OnLeave", function(b)
		ApplyBackdrop(b, C_ROW_ODD, C_BORDER)
		txt:SetTextColor(unpack(C_TEXT))
	end)
	btn:SetScript("OnClick", onClick)
	return btn
end

-- ============================================================================
-- Import Conflicts Window
-- ============================================================================
-- Shows cross-list conflicts in a scrollable card. Each row: item name on
-- left, three segmented Delete/Sell/Keep buttons on right. Pre-selected to
-- source's list. Apply commits; Cancel aborts.

local importFrame       -- outer window
local importContent     -- inner scroll child (the conflict rows live here)
local importScroll      -- the ScrollFrame
local importSubText     -- instruction/count line above the card
local importRows = {}   -- pool of row frames (reused across shows)
local importSourceName  -- current import source character

local function BuildImportConflictsWindow()
	if importFrame then return end

	local W, H = 540, 500
	local f, body = BuildPopupSkeleton("AutoDeleteImportConflictsFrame",
		"Import Conflicts", W, H)
	importFrame = f

	-- Subtitle text at the top of the body
	local sub = MakeText(body, 10, C_TEXT, "OUTLINE", "LEFT")
	sub:SetPoint("TOPLEFT", 15, -10)
	sub:SetPoint("TOPRIGHT", -15, -10)
	sub:SetHeight(30)
	sub:SetJustifyV("TOP")
	sub:SetText("Loading conflicts...")
	importSubText = sub

	-- Content card (scrollable area). Fills body between subtitle and footer.
	local card = CreateFrame("Frame", nil, body)
	card:SetPoint("TOPLEFT", 15, -48)
	card:SetPoint("BOTTOMRIGHT", -15, 50)
	ApplyBackdrop(card, { 14/255, 14/255, 14/255, 1 }, C_BORDER)

	local scroll = CreateFrame("ScrollFrame", nil, card)
	scroll:SetPoint("TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", -4, 4)
	scroll:EnableMouseWheel(true)
	importScroll = scroll

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(W - 46, 1)  -- width matches card inner width; height grown on populate
	scroll:SetScrollChild(content)
	importContent = content

	scroll:SetScript("OnMouseWheel", function(s, delta)
		local cur = s:GetVerticalScroll()
		local max = content:GetHeight() - s:GetHeight()
		if max < 0 then max = 0 end
		local new = cur - (delta * 30)
		if new < 0 then new = 0 end
		if new > max then new = max end
		s:SetVerticalScroll(new)
	end)

	-- Footer buttons (Apply/Cancel)
	local applyBtn = MakeDialogButton(body, "Apply", function()
		if not importSourceName then importFrame:Hide(); return end
		-- Collect per-row choices.
		local resolutions = {}
		for _, row in ipairs(importRows) do
			if row:IsShown() and row._key and row._chosen then
				resolutions[row._key] = row._chosen
			end
		end
		local ok, reason = _G.AutoDelete_Profiles.ApplyImport(importSourceName, resolutions)
		if not ok then
			print("|cffff4444[AutoDelete]|r: Import failed (" .. (reason or "unknown") .. ").")
		end
		importFrame:Hide()
	end)
	applyBtn:SetPoint("BOTTOMRIGHT", -15, 15)

	local cancelBtn = MakeDialogButton(body, "Cancel", function() importFrame:Hide() end)
	cancelBtn:SetPoint("RIGHT", applyBtn, "LEFT", -10, 0)
end

-- Build or reuse a conflict row inside importContent.
-- Layout per row (52 tall):
--   Line 1: item display name (11pt text, LEFT)
--   Line 2: "Source: Delete  .  Current: Sell" (9pt dim, LEFT)
--   Right side: three 56x22 buttons "Delete" | "Sell" | "Keep"
local function BuildImportRow(index)
	local ROW_H = 52
	local parent = importContent
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(parent:GetWidth() - 6, ROW_H)
	row:SetPoint("TOPLEFT", 3, -((index - 1) * (ROW_H + 2)) - 2)

	-- Alternating background
	local bg = (index % 2 == 1) and C_ROW_ODD or C_ROW_EVEN
	ApplyBackdrop(row, bg, C_BORDER)

	-- Item name
	local nameText = MakeText(row, 11, C_TEXT, "OUTLINE", "LEFT")
	nameText:SetPoint("TOPLEFT", 10, -8)
	nameText:SetPoint("TOPRIGHT", -200, -8)
	nameText:SetHeight(14)
	row._nameText = nameText

	-- Sub-line (source vs current)
	local subText = MakeText(row, 9, C_DIM, "OUTLINE", "LEFT")
	subText:SetPoint("TOPLEFT", 10, -26)
	subText:SetPoint("TOPRIGHT", -200, -26)
	subText:SetHeight(12)
	row._subText = subText

	-- Segmented Delete/Sell/Keep buttons
	local segConfigs = {
		{ label = "Delete", color = C_RED },
		{ label = "Sell",   color = C_ACCENT },   -- orange
		{ label = "Keep",   color = C_GREEN },
	}

	row._segBtns = {}
	local BTN_W, BTN_H = 56, 22
	local GAP = 4
	-- Anchor all three from the right side; rightmost is "Keep".
	for i, cfg in ipairs(segConfigs) do
		local b = CreateFrame("Button", nil, row)
		b:SetSize(BTN_W, BTN_H)
		-- i=1 (Delete): rightmost-2 = offset by 2*(BTN_W+GAP) from right edge
		-- i=2 (Sell):   rightmost-1 = offset by 1*(BTN_W+GAP)
		-- i=3 (Keep):   rightmost = offset by 0
		local xOff = -10 - (3 - i) * (BTN_W + GAP)
		b:SetPoint("RIGHT", row, "RIGHT", xOff, 0)
		ApplyBackdrop(b, C_ROW_ODD, C_BORDER)
		local txt = MakeText(b, 10, C_DIM, "OUTLINE")
		txt:SetPoint("CENTER")
		txt:SetText(cfg.label)
		b._text = txt
		b._cfg = cfg
		b:SetScript("OnClick", function()
			row._chosen = cfg.label
			for _, sb in ipairs(row._segBtns) do
				if sb._cfg.label == cfg.label then
					local c = sb._cfg.color
					sb:SetBackdropColor(c[1], c[2], c[3], 0.5)
					sb:SetBackdropBorderColor(c[1], c[2], c[3], 1)
					sb._text:SetTextColor(1, 1, 1)
				else
					sb:SetBackdropColor(unpack(C_ROW_ODD))
					sb:SetBackdropBorderColor(unpack(C_BORDER))
					sb._text:SetTextColor(unpack(C_DIM))
				end
			end
		end)
		tinsert(row._segBtns, b)
	end

	return row
end

local function SelectRowChoice(row, label)
	for _, sb in ipairs(row._segBtns) do
		if sb._cfg.label == label then
			sb:GetScript("OnClick")(sb)
			return
		end
	end
end

_G.AutoDelete_ShowImportConflicts = function(sourceName, preview)
	BuildImportConflictsWindow()
	importSourceName = sourceName

	-- Subtitle line
	local noteAdds = ""
	if preview.additions and #preview.additions > 0 then
		noteAdds = string.format("  (%d non-conflict item(s) will also be added.)", #preview.additions)
	end
	importSubText:SetText(string.format(
		"Importing from %s. %d conflict(s) below. Pick which list should win for each, then click Apply.%s",
		sourceName, #preview.conflicts, noteAdds))

	-- Hide pooled rows before reuse
	for _, r in ipairs(importRows) do r:Hide() end

	local ROW_H = 52
	local ROW_GAP = 2
	for i, c in ipairs(preview.conflicts) do
		local row = importRows[i]
		if not row then
			row = BuildImportRow(i)
			importRows[i] = row
		end
		row:Show()
		row._key = c.key
		row._nameText:SetText(c.display or "(unknown)")
		row._subText:SetText(string.format(
			"Source: |cff%s%s|r   Current: |cff%s%s|r",
			"FFD100", c.sourceListDisplay,
			"FFD100", c.currentListDisplay))
		-- Pre-select source's list
		SelectRowChoice(row, c.sourceListDisplay)
	end

	-- Size content height
	local totalH = #preview.conflicts * (ROW_H + ROW_GAP) + 4
	importContent:SetHeight(math.max(totalH, 1))
	importScroll:SetVerticalScroll(0)
	importFrame:Show()
end

-- ============================================================================
-- Clear List Picker Window
-- ============================================================================
-- Small window with four list-buttons: Delete / Sell / Keep / All. Clicking
-- one fires the destructive confirmation StaticPopup (Clear / Cancel).

local clearFrame

local function BuildClearListWindow()
	if clearFrame then return end

	-- Frame height math: body is (H - 24) tall.
	--   Subtitle area: y=-10 to y=-26 (16px tall at -10 top offset)
	--   Card:          y=-32 to y=-(body_H - 50)
	--   Footer:        50px (Cancel at BOTTOMRIGHT -15, 15 = 24 tall + 15 bottom pad + 11 top pad)
	--
	-- Card needs to fit 6 buttons (26 tall) with 4px gaps, plus 8px top pad
	-- and some bottom pad. Required card height = 8 + 6*26 + 5*4 + bottom_pad.
	-- With bottom_pad=10 that's 194. Working backwards:
	--   card_H = body_H - 32 - 50  →  body_H = card_H + 82 = 276
	--   frame_H = body_H + 24     →  300
	local W, H = 340, 300
	local f, body = BuildPopupSkeleton("AutoDeleteClearListPickerFrame",
		"Clear List", W, H)
	clearFrame = f

	-- Instruction
	local sub = MakeText(body, 10, C_TEXT, "OUTLINE", "LEFT")
	sub:SetPoint("TOPLEFT", 15, -10)
	sub:SetPoint("TOPRIGHT", -15, -10)
	sub:SetHeight(16)
	sub:SetText("Select which list to clear on the current character:")

	-- Six option buttons, vertically stacked inside a card
	local card = CreateFrame("Frame", nil, body)
	card:SetPoint("TOPLEFT", 15, -32)
	card:SetPoint("BOTTOMRIGHT", -15, 50)
	ApplyBackdrop(card, { 14/255, 14/255, 14/255, 1 }, C_BORDER)

	local BTN_W, BTN_H = 290, 26
	local BTN_GAP = 4
	local options = {
		{ value = "Delete",   label = "Delete list",                     color = C_RED },
		{ value = "Sell",     label = "Sell list",                       color = C_ACCENT },
		{ value = "Keep",     label = "Keep list",                       color = C_GREEN },
		{ value = "All",      label = "All three lists",                 color = { 0.85, 0.25, 0.85, 1 } },
		-- Remove Junk: scans Delete + Sell only, removes gray-quality items.
		{ value = "Junk",     label = "Remove junk items",               color = { 0.55, 0.55, 0.55, 1 } },
		-- Remove Sellable: scans Delete only, removes items with vendor value.
		{ value = "Sellable", label = "Remove items with vendor value",  color = { 0.95, 0.80, 0.20, 1 } },
	}

	for i, opt in ipairs(options) do
		local b = CreateFrame("Button", nil, card)
		b:SetSize(BTN_W, BTN_H)
		b:SetPoint("TOP", 0, -8 - ((i - 1) * (BTN_H + BTN_GAP)))
		ApplyBackdrop(b, C_ROW_ODD, C_BORDER)
		local txt = MakeText(b, 11, C_TEXT, "OUTLINE")
		txt:SetPoint("CENTER")
		txt:SetText(opt.label)
		b:SetScript("OnEnter", function(btn)
			local c = opt.color
			btn:SetBackdropColor(c[1], c[2], c[3], 0.3)
			btn:SetBackdropBorderColor(c[1], c[2], c[3], 1)
			txt:SetTextColor(1, 1, 1)
		end)
		b:SetScript("OnLeave", function(btn)
			ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
			txt:SetTextColor(unpack(C_TEXT))
		end)
		b:SetScript("OnClick", function()
			clearFrame:Hide()
			local dlg
			if opt.value == "All" then
				dlg = StaticPopup_Show("AUTODELETE_PROFILE_CLEAR_ALL")
			elseif opt.value == "Junk" then
				dlg = StaticPopup_Show("AUTODELETE_PROFILE_REMOVE_JUNK")
			elseif opt.value == "Sellable" then
				dlg = StaticPopup_Show("AUTODELETE_PROFILE_REMOVE_SELLABLE")
			else
				dlg = StaticPopup_Show("AUTODELETE_PROFILE_CLEAR", opt.value)
			end
			if dlg then dlg.data = opt.value end
		end)
	end

	-- Cancel button in footer
	local cancelBtn = MakeDialogButton(body, "Cancel", function() clearFrame:Hide() end)
	cancelBtn:SetPoint("BOTTOMRIGHT", -15, 15)
end

_G.AutoDelete_ShowClearListPicker = function()
	BuildClearListWindow()
	clearFrame:Show()
end
