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
local C_HOVER     = { 0.122, 0.435, 0.659, 1 }   -- mage blue #1F6FA8 (alias: C_BLUE)
-- =========================================================================
-- Semantic action palette (HARD RULE: only THREE colors for button hover)
-- =========================================================================
--   C_GREEN  -> additive / approve / go / positive   (Add, Copy, Import, Apply, Save, Confirm)
--   C_RED    -> destructive / decline / remove       (Delete, Remove, Clear, Cancel)
--   C_BLUE   -> change / update / reward / transform (Open Panel, Edit, Refresh, Audit, Toggle filters)
-- C_ACCENT (legendary orange) is for window CHROME only (title bars, frame
-- titles, accent borders). Never use it for a button hover.
local C_RED       = { 0.75, 0.22, 0.22, 1 }   -- destructive
local C_GREEN     = { 0.20, 0.75, 0.20, 1 }   -- additive
local C_BLUE      = C_HOVER                   -- transformational; alias to keep one source
local C_ACCENT    = { 1.00, 0.50, 0.00, 1 }   -- #ff8000 WoW legendary orange (CHROME ONLY)
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
-- v3.21 SetBackdrop consolidation (wiki §6.3): inner-card pattern shared by
-- five section cards (Affix Display, Affix Protection, Auto Actions, Disenchant
-- card, Manage Ignored launcher card). Slightly darker than the outer frame
-- so cards visually recede from the surrounding panel.
local C_CARD_BG   = { 0.04, 0.04, 0.04, 1 }   -- #0a0a0a inner card bg
local C_CARD_BORDER = { 0.14, 0.14, 0.14, 1 } -- #242424 inner card border
-- Dark button base used by the custom dropdown trigger and the spinner-input
-- arrow buttons. Pure-black 1px border + near-black fill on hover-out.
local C_BTN_BASE_BG = { 0.09, 0.09, 0.09, 1 }
local C_BTN_BASE_BORDER = { 0, 0, 0, 1 }

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

-- Small helper for sub-toggles: smaller box (12x12), 9pt text, no description.
-- Promoted to file scope so the Disenchant Filters popup (built at file load
-- time, before BuildUI runs) can call it. BuildUI's own callers resolve to
-- this same upvalue.
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

-- Segmented control: N pills laid out side-by-side, one active at a time,
-- or none active (idle/off). Used for the Auto Actions card but generic.
--
-- States table format (each entry):
--   { value="delete", label="Del", tooltip="...",
--     bg={r,g,b,a}, border={r,g,b,a}, fg={r,g,b,a} }
-- bg/border/fg describe the ACTIVE appearance. Inactive segments share a
-- single neutral-gray paint -- "all gray until you click one" -- so the
-- active pill is the only thing competing for attention.
--
-- Click semantics:
--   - Click an inactive segment   -> SetValue(segment.value)  (light it up)
--   - Click the active segment    -> SetValue(offValue)       (dim it out)
--     (only if offValue was supplied; otherwise it's a no-op repaint.)
--
-- offValue may be ANY string -- including one that doesn't match any segment.
-- A value that doesn't match any segment renders as "no segment active",
-- which is exactly what we want for an implicit-off state.
--
-- API surface:
--   ctrl:GetValue()       -> current value string
--   ctrl:SetValue(value)  -> set value (any string allowed); fires onChange
--                            iff value actually changed
--   onChange(newValue, oldValue) -> caller-supplied callback
--
-- segWidth is the PER-SEGMENT width. Total control width is
-- N * segWidth + (N - 1) GAP. This lets two different controls share the
-- same pill width but have different total widths -- e.g. a 2-segment row
-- and a 1-segment row whose right edges line up because of where they're
-- anchored, with the single pill lining up with the rightmost pill of the
-- 2-segment row.
local function MakeSegmentedControl(parent, segWidth, height, states, offValue, onChange)
	local n = #states
	local GAP = 1
	local totalWidth = n * segWidth + math.max(0, n - 1) * GAP

	local ctrl = CreateFrame("Frame", nil, parent)
	ctrl:SetSize(totalWidth, height)

	ctrl._states = states
	ctrl._value = offValue   -- start in the implicit-off state; caller SetValue overrides
	ctrl._segments = {}

	-- Neutral inactive paint: dark bg, subtle gray border, dimmed text.
	-- Same for every state when inactive so the visual reads "all gray".
	local INACTIVE_BG     = { 0.07, 0.07, 0.07, 1 }
	local INACTIVE_BORDER = { 0.22, 0.22, 0.22, 1 }
	local INACTIVE_FG     = C_DIM

	local function PaintSegment(seg, isActive)
		local s = seg._state
		if isActive then
			ApplyBackdrop(seg, s.bg, s.border)
			seg._text:SetTextColor(unpack(s.fg))
		else
			ApplyBackdrop(seg, INACTIVE_BG, INACTIVE_BORDER)
			seg._text:SetTextColor(unpack(INACTIVE_FG))
		end
	end

	local function Repaint()
		for _, seg in ipairs(ctrl._segments) do
			PaintSegment(seg, seg._state.value == ctrl._value)
		end
	end

	for i, s in ipairs(states) do
		local seg = CreateFrame("Button", nil, ctrl)
		seg:SetSize(segWidth, height)
		seg:SetPoint("LEFT", ctrl, "LEFT", (i - 1) * (segWidth + GAP), 0)
		seg._state = s

		local text = seg:CreateFontString(nil, "OVERLAY")
		text:SetFont(FONT, 10, "OUTLINE")
		text:SetPoint("CENTER", 0, 0)
		text:SetJustifyH("CENTER")
		text:SetText(s.label)
		seg._text = text

		-- Click an inactive segment -> activate it.
		-- Click the active segment -> deselect (set to offValue).
		seg:SetScript("OnClick", function()
			if ctrl._value == s.value then
				ctrl:SetValue(offValue)
			else
				ctrl:SetValue(s.value)
			end
		end)

		-- Hover: brighten the border on this segment and show its tooltip.
		-- Active segments brighten from their state border; inactive segments
		-- brighten from INACTIVE_BORDER so the hover hint is visible without
		-- pre-disclosing the state color.
		seg:SetScript("OnEnter", function(self)
			local b = (ctrl._value == self._state.value) and self._state.border or INACTIVE_BORDER
			self:SetBackdropBorderColor(
				math.min(b[1] + 0.25, 1),
				math.min(b[2] + 0.25, 1),
				math.min(b[3] + 0.25, 1),
				1)
			if self._state.tooltip then
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(self._state.label, 1, 1, 1)
				GameTooltip:AddLine(self._state.tooltip, C_DIM[1], C_DIM[2], C_DIM[3], true)
				GameTooltip:Show()
			end
		end)
		seg:SetScript("OnLeave", function()
			Repaint()
			GameTooltip:Hide()
		end)

		ctrl._segments[i] = seg
	end

	function ctrl:GetValue() return self._value end

	function ctrl:SetValue(value)
		local oldValue = self._value
		if oldValue == value then
			Repaint()  -- idempotent paint so stale visuals (e.g. post profile-switch) line up
			return
		end
		self._value = value
		Repaint()
		if onChange then onChange(value, oldValue) end
	end

	Repaint()
	return ctrl
end

-- PEADAR-style custom dropdown
local function MakeDropdown(parent, width, options, onChange)
	local dd = CreateFrame("Frame", nil, parent)
	dd:SetSize(width, 22)

	-- Button: flat near-black bg, thin black border, subtle 1px top gloss
	-- highlight line, teal-tinted border on hover.
	local btn = CreateFrame("Button", nil, dd)
	btn:SetAllPoints()
	-- v3.21 §6.3: canonical ApplyBackdrop helper. Was three raw SetBackdrop /
	-- SetBackdropColor / SetBackdropBorderColor calls; same visual result.
	ApplyBackdrop(btn, C_BTN_BASE_BG, C_BTN_BASE_BORDER)
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

-- ============================================================================
-- Canonical button helpers (HARD RULE: every button must go through one
-- of these two helpers; see Addon_UI_StyleGuide.md §4 "Buttons: the two
-- canonical helpers"). Defined here BEFORE BuildUI so BuildUI's tab
-- builders can capture them as upvalues. Other top-level builders below
-- (BuildClearListWindow, etc.) also capture from this same scope.
-- ============================================================================

-- MakeDialogButton: neutral footer button. Apply / Cancel / OK / Close.
-- Default 90x24, blue hover (C_ROW_HOVER), white text on hover. Use this
-- when the action has no semantic weight, or when it is one of a small
-- group of equivalent footer choices.
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

-- MakeActionButton: semantic action button. Variable width, 26 tall by
-- default. On hover the backdrop fills with the semantic color at 0.3
-- alpha and the border switches to the full semantic color. Text becomes
-- pure white on hover. The Clear List window is the canonical reference.
--
-- HARD RULE: only THREE semantic colors. Pick by the action class:
--   C_GREEN  -> additive / approve / go / positive
--              (Add, Copy, Import, Apply, Save, Confirm)
--   C_RED    -> destructive / decline / remove
--              (Delete, Remove, Clear, Cancel)
--   C_BLUE   -> change / update / reward / transform
--              (Open Panel, Edit, Refresh, Audit, Toggle filters)
--
-- Do NOT use C_ACCENT (legendary orange) for button hovers. That color
-- is reserved for window CHROME (title bars, frame titles, accent borders).
-- The hover color itself is a clarity cue for non-technical users: green
-- means "this adds something," red means "this removes something," blue
-- means "this changes or opens something."
local function MakeActionButton(parent, label, semanticColor, onClick, width, height)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(width or 290, height or 26)
	ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
	local txt = MakeText(btn, 11, C_TEXT, "OUTLINE")
	txt:SetPoint("CENTER")
	txt:SetText(label)
	btn._text = txt
	local color = semanticColor or C_ACCENT
	btn:SetScript("OnEnter", function(b)
		b:SetBackdropColor(color[1], color[2], color[3], 0.3)
		b:SetBackdropBorderColor(color[1], color[2], color[3], 1)
		txt:SetTextColor(1, 1, 1)
	end)
	btn:SetScript("OnLeave", function(b)
		ApplyBackdrop(b, C_ROW_ODD, C_BORDER)
		txt:SetTextColor(unpack(C_TEXT))
	end)
	if onClick then btn:SetScript("OnClick", onClick) end
	return btn
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
	-- 3-state quality filters: "off" | "delete" | "sell"
	-- Migration: old boolean true → "delete" (user requested default)
	autoGray = "delete",
	scanInterval = 0.5,
	autoDeleteCommon = "delete",
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
local function Normalize(s)
	if _G.AutoDelete_NormalizeTextKey then
		return _G.AutoDelete_NormalizeTextKey(s)
	end
	return string.lower(Trim(s))
end
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
-- Process Bags Panel
-- ============================================================================
-- Standalone draggable window listing every item in the player's bags that
-- one of the four secure-action features (Open, Disenchant, Mill, Prospect)
-- could target right now. Clicking a row arms that item as the next target
-- for its action; pressing the corresponding bound key fires it.
--
-- Built as a sibling frame to the main AutoDeleteFrame -- not a child.
-- That keeps it openable when the settings panel is closed and lets the
-- two windows be positioned independently. Position is saved per-character
-- in AutoDeleteStatsDB.processPanel.
--
-- Wrapped in a `do ... end` block so its locals stay out of the main
-- chunk's 200-cap. Public entry points are _G.AutoDelete_ToggleProcessPanel
-- and _G.AutoDelete_ProcessPanel set at the bottom.

do

local PROCESS_PANEL_W = 360
local PROCESS_PANEL_H = 480
local PROCESS_ROW_H   = 22
local PROCESS_FILTER_H = 50
local PROCESS_HEADER_H = 22
local PROCESS_FOOTER_H = 28
-- Scroll area height = total - title - header - footer - vertical pads.
local PROCESS_SCROLL_H = PROCESS_PANEL_H - 24 - PROCESS_FILTER_H - PROCESS_HEADER_H - PROCESS_FOOTER_H - 10
local PROCESS_VISIBLE_ROWS = math.floor(PROCESS_SCROLL_H / PROCESS_ROW_H)

-- The panel itself. Strata MEDIUM so it floats above bag frames but
-- below DIALOG (so the settings panel stays on top when both are open
-- and the user clicks the settings panel). Frame name is globally
-- exposed so /framestack and other diagnostic tools find it.
local panel = CreateFrame("Frame", "AutoDeleteProcessPanel", UIParent)
panel:SetSize(PROCESS_PANEL_W, PROCESS_PANEL_H)
-- FULLSCREEN_DIALOG so the panel floats ABOVE the main settings panel
-- (which lives on DIALOG). Previously this was MEDIUM, which put the
-- panel BEHIND the settings panel when both were open -- user clicked
-- the Process Bags launcher and saw nothing happen because the window
-- opened underneath the settings frame.
panel:SetFrameStrata("FULLSCREEN_DIALOG")
panel:SetFrameLevel(50)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:SetClampedToScreen(true)
panel:Hide()

-- Visual style matches the main settings panel (dark body, dark gray
-- border, dark title bar with orange text). Previously this used raw
-- SetBackdrop calls with an orange-filled title bar + orange border,
-- which read as a different window family than the rest of the addon.
ApplyBackdrop(panel, C_BG, C_BORDER)

-- Title bar: clickable drag handle, same dark-with-accent-border look
-- as the main panel's title bar.
local titleBar = CreateFrame("Frame", nil, panel)
titleBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
titleBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
titleBar:SetHeight(24)
ApplyBackdrop(titleBar, C_TITLEBAR, C_BORDER)
titleBar:EnableMouse(true)
titleBar:RegisterForDrag("LeftButton")
titleBar:SetScript("OnDragStart", function() panel:StartMoving() end)
titleBar:SetScript("OnDragStop", function()
	panel:StopMovingOrSizing()
	-- Save position to per-character stats DB so the panel re-opens
	-- in the same place across /reload and logout.
	local point, _, relPoint, x, y = panel:GetPoint(1)
	_G.AutoDeleteStatsDB = _G.AutoDeleteStatsDB or {}
	_G.AutoDeleteStatsDB.processPanel = {
		point = point, relPoint = relPoint, x = x, y = y,
	}
end)

local titleText = MakeText(titleBar, 12, C_TITLE, "OUTLINE")
titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
titleText:SetText("Process Bags")

-- Close X in the title bar's right corner. Dim by default, red on
-- hover -- matches the main settings panel's close button exactly.
local closeX = CreateFrame("Button", nil, titleBar)
closeX:SetSize(24, 24)
closeX:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", 0, 0)
local closeXText = MakeText(closeX, 14, C_DIM, "OUTLINE")
closeXText:SetText("x")
closeXText:SetPoint("CENTER")
closeX:SetScript("OnEnter", function() closeXText:SetTextColor(1, 0.3, 0.3) end)
closeX:SetScript("OnLeave", function() closeXText:SetTextColor(unpack(C_DIM)) end)
closeX:SetScript("OnClick", function() panel:Hide() end)

local currentFilter = "all"
local filterButtons = {}
local filterDefs = {
	{ key = "all", label = "All" },
	{ key = "sell", label = "Sell" },
	{ key = "delete", label = "Delete" },
	{ key = "disenchant", label = "DE" },
	{ key = "mill", label = "Mill" },
	{ key = "prospect", label = "Prospect" },
	{ key = "open", label = "Open" },
	{ key = "kept", label = "Kept" },
}

local filterRow = CreateFrame("Frame", nil, panel)
filterRow:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -2)
filterRow:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -2)
filterRow:SetHeight(PROCESS_FILTER_H)
filterRow:SetBackdrop({ bgFile = WHITE8x8 })
filterRow:SetBackdropColor(0.055, 0.055, 0.055, 1)

local function RefreshFilterButtons()
	for _, def in ipairs(filterDefs) do
		local btn = filterButtons[def.key]
		if btn then
			if currentFilter == def.key then
				ApplyBackdrop(btn, { C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 0.9 }, C_ACCENT)
				btn._text:SetTextColor(0.05, 0.05, 0.05, 1)
			else
				ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
				btn._text:SetTextColor(unpack(C_TEXT))
			end
		end
	end
end

local FILTER_PAD = 6
local FILTER_GAP = 4
local FILTER_BTN_H = 20
local FILTER_BTN_W = math.floor((PROCESS_PANEL_W - FILTER_PAD * 2 - FILTER_GAP * 3) / 4)
for i, def in ipairs(filterDefs) do
	local btn = CreateFrame("Button", nil, filterRow)
	btn:SetSize(FILTER_BTN_W, FILTER_BTN_H)
	local col = (i - 1) % 4
	local row = math.floor((i - 1) / 4)
	btn:SetPoint("TOPLEFT", filterRow, "TOPLEFT",
		FILTER_PAD + col * (FILTER_BTN_W + FILTER_GAP),
		-4 - row * (FILTER_BTN_H + 4))
	ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
	local txt = MakeText(btn, 10, C_TEXT, "OUTLINE")
	txt:SetPoint("CENTER")
	txt:SetWidth(FILTER_BTN_W - 8)
	txt:SetJustifyH("CENTER")
	txt:SetWordWrap(false)
	txt:SetText(def.label)
	btn._text = txt
	btn:SetScript("OnClick", function()
		currentFilter = def.key
		RefreshFilterButtons()
		if _G.AutoDelete_RefreshProcessPanel then _G.AutoDelete_RefreshProcessPanel() end
	end)
	btn:SetScript("OnEnter", function(self)
		if currentFilter ~= def.key then
			ApplyBackdrop(self, C_ROW_HOVER, C_BORDER)
			self._text:SetTextColor(1, 1, 1, 1)
		end
	end)
	btn:SetScript("OnLeave", RefreshFilterButtons)
	filterButtons[def.key] = btn
end
RefreshFilterButtons()

-- Column header row directly under the title bar.
local headerRow = CreateFrame("Frame", nil, panel)
headerRow:SetPoint("TOPLEFT", filterRow, "BOTTOMLEFT", 0, -2)
headerRow:SetPoint("TOPRIGHT", filterRow, "BOTTOMRIGHT", 0, -2)
headerRow:SetHeight(PROCESS_HEADER_H)
-- v3.21 §6.3: kept as raw SetBackdrop intentionally. ApplyBackdrop always sets
-- a 1px edge file; this Process Bags header band is fill-only (no border) and
-- abuts the title bar visually. Adding a 1px border would create a visible
-- seam right under the title bar.
headerRow:SetBackdrop({ bgFile = WHITE8x8 })
headerRow:SetBackdropColor(0.10, 0.10, 0.10, 1)

local headerItemText = headerRow:CreateFontString(nil, "OVERLAY")
headerItemText:SetFont(FONT, 10, "OUTLINE")
headerItemText:SetTextColor(unpack(C_DIM))
headerItemText:SetPoint("LEFT", headerRow, "LEFT", 10 + 18 + 6, 0)  -- after icon column
headerItemText:SetText("Item")

local headerActionText = headerRow:CreateFontString(nil, "OVERLAY")
headerActionText:SetFont(FONT, 10, "OUTLINE")
headerActionText:SetTextColor(unpack(C_DIM))
headerActionText:SetPoint("RIGHT", headerRow, "RIGHT", -10, 0)
headerActionText:SetText("Action")

-- FauxScrollFrame for the row list. 3.3.5a-correct (HybridScrollFrame is
-- later). Rows themselves get created lazily in B.3 via a row pool.
local scrollContainer = CreateFrame("Frame", nil, panel)
scrollContainer:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 4, -2)
scrollContainer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -22, PROCESS_FOOTER_H + 4)

local scrollFrame = CreateFrame("ScrollFrame", "AutoDeleteProcessScroll",
	scrollContainer, "FauxScrollFrameTemplate")
scrollFrame:SetAllPoints(scrollContainer)
-- The OnVerticalScroll callback is wired in B.3 once the row-update
-- function exists. Standard FauxScroll idiom.
scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
	FauxScrollFrame_OnVerticalScroll(self, offset, PROCESS_ROW_H,
		function()
			if _G.AutoDelete_RenderProcessPanelRows then
				_G.AutoDelete_RenderProcessPanelRows()
			elseif _G.AutoDelete_RefreshProcessPanel then
				_G.AutoDelete_RefreshProcessPanel()
			end
		end)
end)

-- Footer: row count on the left, "Clear Ignored" button on the right.
local footer = CreateFrame("Frame", nil, panel)
footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
footer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
footer:SetHeight(PROCESS_FOOTER_H)
-- v3.21 §6.3: kept as raw SetBackdrop intentionally. Fill-only (no border) to
-- match the headerRow band; together they bracket the scroll area without a
-- visible 1px seam.
footer:SetBackdrop({ bgFile = WHITE8x8 })
footer:SetBackdropColor(0.07, 0.07, 0.07, 1)

local footerCount = footer:CreateFontString(nil, "OVERLAY")
footerCount:SetFont(FONT, 10, "OUTLINE")
footerCount:SetTextColor(unpack(C_DIM))
footerCount:SetPoint("LEFT", footer, "LEFT", 10, 0)
footerCount:SetText("")  -- populated by RefreshProcessPanel in B.3

-- Clear Ignored: canonical MakeActionButton (semantic destructive red).
-- Resets the per-character ignore list, undoing prior right-click-off
-- decisions. Treated as destructive because it loses user choices.
-- Same width and height as the Filters-tab card buttons so footers
-- read uniformly across the addon.
local clearBtn = MakeActionButton(footer, "Clear Ignored", C_RED, function()
	if _G.AutoDelete_ClearProcessIgnored then _G.AutoDelete_ClearProcessIgnored() end
	if _G.AutoDelete_RefreshProcessPanel then _G.AutoDelete_RefreshProcessPanel() end
end, 110, 22)
clearBtn:SetPoint("RIGHT", footer, "RIGHT", -8, 0)
footerCount:SetPoint("RIGHT", clearBtn, "LEFT", -8, 0)
footerCount:SetJustifyH("LEFT")
-- Tooltip on hover (the MakeActionButton hover styling stays; we just
-- layer the tooltip on top so the user sees the explanation).
clearBtn:SetScript("OnEnter", function(btn)
	btn:SetBackdropColor(C_RED[1], C_RED[2], C_RED[3], 0.3)
	btn:SetBackdropBorderColor(C_RED[1], C_RED[2], C_RED[3], 1)
	btn._text:SetTextColor(1, 1, 1)
	GameTooltip:SetOwner(btn, "ANCHOR_TOP")
	GameTooltip:SetText("Clear Ignored", 1, 1, 1)
	GameTooltip:AddLine("Resets the ignore list. Items you right-clicked to hide will come back if they're still in your bags.",
		C_DIM[1], C_DIM[2], C_DIM[3], true)
	GameTooltip:Show()
end)
clearBtn:SetScript("OnLeave", function(btn)
	ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
	btn._text:SetTextColor(unpack(C_TEXT))
	GameTooltip:Hide()
end)

-- Position restoration on first Show. Reads saved per-character coords;
-- falls back to centered on first run.
panel:SetScript("OnShow", function(self)
	local saved = _G.AutoDeleteStatsDB and _G.AutoDeleteStatsDB.processPanel
	if saved and saved.point then
		self:ClearAllPoints()
		self:SetPoint(saved.point, UIParent, saved.relPoint or saved.point,
			saved.x or 0, saved.y or 0)
	else
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
	-- Refresh content. The actual list-population happens in B.3; for now
	-- this is a no-op gated check.
	if _G.AutoDelete_RefreshProcessPanel then _G.AutoDelete_RefreshProcessPanel() end
end)

-- Toggle entry point. Called from the /del process slash command and the
-- Tools Card 1 launcher button. Idempotent.
local function ToggleProcessPanel()
	if panel:IsShown() then panel:Hide() else panel:Show() end
end

_G.AutoDelete_ProcessPanel       = panel
_G.AutoDelete_ProcessPanelScroll = scrollFrame
_G.AutoDelete_ProcessPanelCount  = footerCount
_G.AutoDelete_ProcessVisibleRows = PROCESS_VISIBLE_ROWS
_G.AutoDelete_ProcessRowHeight   = PROCESS_ROW_H
_G.AutoDelete_ToggleProcessPanel = ToggleProcessPanel

-- ------------------------------------------------------------------
-- Row pool + RefreshProcessPanel
-- ------------------------------------------------------------------
-- Row pool: rows are created on demand and never
-- destroyed. Anchor chain is "row N below row N-1"; row 1 anchors to
-- the scroll container's TOPLEFT. The pool persists between Refresh
-- calls -- only the visible window's row.data fields are rewritten.
--
-- Selected row (per action) is tracked in `armed[action]` so that the
-- yellow tint persists across Refresh redraws.

local rowPool = {}          -- [i] = row frame
local armed = {}            -- ["disenchant"] = {bag, slot, itemId} or nil
local lastResults = {}      -- cached ProcessScan result, used by row OnClick
local lastAllTotal = 0      -- total rows before filter, for footer text

-- Lazy row factory. The first call creates the row; subsequent calls
-- return the cached frame.
local function GetOrCreateRow(i)
	if rowPool[i] then return rowPool[i] end
	local rowName = "AutoDeleteProcessRow" .. i
	local row = CreateFrame("Button", rowName, scrollContainer)
	row:SetSize(PROCESS_PANEL_W - 24, PROCESS_ROW_H)
	if i == 1 then
		row:SetPoint("TOPLEFT", scrollContainer, "TOPLEFT", 0, 0)
	else
		row:SetPoint("TOPLEFT", rowPool[i - 1], "BOTTOMLEFT", 0, 0)
	end
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	-- Backdrop is the armed-row highlight. Hidden by default; toggled
	-- via row.armedTexture:SetShown() on Refresh. Yellow tint is the
	-- Yellow tint marks the selected/staged target.
	local armedTexture = row:CreateTexture(nil, "BACKGROUND")
	armedTexture:SetAllPoints(row)
	armedTexture:SetTexture(WHITE8x8)
	armedTexture:SetVertexColor(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 0.18)
	armedTexture:Hide()
	row.armedTexture = armedTexture

	-- Hover highlight is a separate, dimmer texture so the armed-row
	-- color reads correctly even when also hovered.
	local hoverTexture = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	hoverTexture:SetAllPoints(row)
	hoverTexture:SetTexture(WHITE8x8)
	hoverTexture:SetVertexColor(1, 1, 1, 0.06)
	hoverTexture:Hide()
	row.hoverTexture = hoverTexture

	-- Icon column: 18x18 texture left-anchored, 4px inset.
	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.icon = icon

	-- Item-name FontString. Positioned after the icon; truncates with
	-- ellipsis if the link is too long for the column width.
	local nameText = row:CreateFontString(nil, "OVERLAY")
	nameText:SetFont(FONT, 10, "OUTLINE")
	nameText:SetTextColor(unpack(C_TEXT))
	nameText:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	nameText:SetPoint("RIGHT", row, "RIGHT", -80, 0)  -- leave room for action tag
	nameText:SetJustifyH("LEFT")
	nameText:SetWordWrap(false)
	row.nameText = nameText

	-- Action tag (Delete / Sell / DE / Mill / Prospect / Open / Kept). Right-aligned, color
	-- pulled from PROCESS_ACTIONS in AutoDelete.lua.
	local actionTag = row:CreateFontString(nil, "OVERLAY")
	actionTag:SetFont(FONT, 10, "OUTLINE")
	actionTag:SetPoint("RIGHT", row, "RIGHT", -10, 0)
	actionTag:SetJustifyH("RIGHT")
	row.actionTag = actionTag

	-- Hover handlers: show tooltip with the item link details + the
	-- secondary "click to arm / right-click to ignore" hint.
	row:SetScript("OnEnter", function(self)
		self.hoverTexture:Show()
		if self._entry and self._entry.link then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetHyperlink(self._entry.link)
			GameTooltip:AddLine(" ", 1, 1, 1)
			if (self._entry.count or 1) > 1 then
				GameTooltip:AddLine("|cffffd200" .. tostring(self._entry.count) .. " matching copies|r share this item ID.",
					C_DIM[1], C_DIM[2], C_DIM[3], true)
				if self._entry.variantNames then
					GameTooltip:AddLine("Affix names may differ, but Process Bags groups them by item ID to limit spam.",
						C_DIM[1], C_DIM[2], C_DIM[3], true)
				end
			end
			if self._entry.processAction then
				GameTooltip:AddLine("|cff00ff00Left-click|r to arm this item for the action's keybind.",
					C_DIM[1], C_DIM[2], C_DIM[3], true)
			else
				GameTooltip:AddLine("|cff00ff00Left-click|r to open a Why report.",
					C_DIM[1], C_DIM[2], C_DIM[3], true)
			end
			GameTooltip:AddLine("|cffff8000Right-click|r for Keep, Sell, Delete, or Why.",
				C_DIM[1], C_DIM[2], C_DIM[3], true)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.hoverTexture:Hide()
		GameTooltip:Hide()
	end)

	-- Click dispatch. Left arms, right opens the item quick action menu. The
	-- button-arg form receives "LeftButton" / "RightButton" from WoW.
	row:SetScript("OnClick", function(self, mouseButton)
		local entry = self._entry
		if not entry then return end
		if mouseButton == "RightButton" then
			if _G.AutoDelete_ShowItemQuickMenu then
				_G.AutoDelete_ShowItemQuickMenu(entry, self)
			end
			return
		end
		if not entry.processAction then
			if _G.AutoDelete_BuildWhyReport and _G.AutoDelete_ShowReportWindow then
				_G.AutoDelete_ShowReportWindow(
					_G.AutoDelete_BuildWhyReport(entry.itemId, entry.link, entry.name, entry.bag, entry.slot),
					"Why?"
				)
			end
			return
		end
		-- Left-click: arm the secure-button macrotext for this action.
		if InCombatLockdown and InCombatLockdown() then
			print("|cffff8000[AutoDelete]|r Can't arm a target in combat.")
			return
		end
		if _G.AutoDelete_ProcessArm then
			local ok = _G.AutoDelete_ProcessArm(entry.action, entry.bag, entry.slot)
			if ok then
				armed[entry.action] = {
					bag = entry.bag, slot = entry.slot, itemId = entry.itemId
				}
				if _G.AutoDelete_RefreshProcessPanel then
					_G.AutoDelete_RefreshProcessPanel()
				end
			end
		end
	end)

	rowPool[i] = row
	return row
end

-- Returns true if this entry is the currently-armed target for its
-- action. Compared by itemId+bag+slot rather than table identity since
-- armed[] is rewritten on every arm and ProcessScan returns fresh tables.
local function IsArmed(entry)
	local a = armed[entry.action]
	if not a then return false end
	return a.bag == entry.bag and a.slot == entry.slot and a.itemId == entry.itemId
end

-- The actual list refresh. Called from OnShow, from BAG_UPDATE hook in
-- B.4, and after Clear Ignored / Arm / Ignore actions. Scroll events now
-- redraw from cached results instead of forcing a full bag re-scan.
-- Cheap when the panel is hidden (early-returns).
local function RenderProcessPanelRows()
	local results = lastResults or {}
	local actionsTable = _G.AutoDelete_PROCESS_ACTIONS or {}
	local visible = PROCESS_VISIBLE_ROWS
	local total = #results
	local allTotal = lastAllTotal or total

	FauxScrollFrame_Update(scrollFrame, total, visible, PROCESS_ROW_H)
	local offset = FauxScrollFrame_GetOffset(scrollFrame)

	for i = 1, visible do
		local row = GetOrCreateRow(i)
		local entry = results[i + offset]
		if entry then
			local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(entry.link)
			row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
			if (entry.count or 1) > 1 then
				row.nameText:SetText(entry.link .. " |cff737373x" .. tostring(entry.count) .. "|r")
			else
				row.nameText:SetText(entry.link)
			end
			local meta = actionsTable[entry.action]
			if meta then
				row.actionTag:SetText(meta.label)
				row.actionTag:SetTextColor(unpack(meta.color))
			else
				row.actionTag:SetText("?")
				row.actionTag:SetTextColor(0.55, 0.55, 0.55, 1)
			end
			row._entry = entry
			if IsArmed(entry) then
				row.armedTexture:Show()
			else
				row.armedTexture:Hide()
			end
			row:Show()
		else
			row._entry = nil
			row:Hide()
		end
	end

	local ignoredCount = 0
	if _G.AutoDeleteStatsDB and _G.AutoDeleteStatsDB.processIgnored then
		for _ in pairs(_G.AutoDeleteStatsDB.processIgnored) do
			ignoredCount = ignoredCount + 1
		end
	end

	local copies = 0
	for _, entry in ipairs(results) do copies = copies + (entry.count or 1) end
	if ignoredCount > 0 then
		if copies > total then
			footerCount:SetText(total .. "/" .. allTotal .. " rows (" .. copies .. " copies), " .. ignoredCount .. " ignored")
		else
			footerCount:SetText(total .. "/" .. allTotal .. " rows, " .. ignoredCount .. " ignored")
		end
	else
		if copies > total then
			footerCount:SetText(total .. "/" .. allTotal .. " rows (" .. copies .. " copies)")
		else
			footerCount:SetText(total .. "/" .. allTotal .. " rows")
		end
	end
end

local function RefreshProcessPanel()
	if not panel:IsShown() then return end
	local profile = nil
	if _G.AutoDelete_GetCachedProfile then
		profile = _G.AutoDelete_GetCachedProfile()
	end
	local scan = _G.AutoDelete_ProcessScan
	local allResults = (scan and profile) and scan(profile) or {}
	local results = {}
	for _, entry in ipairs(allResults) do
		if currentFilter == "all" or entry.action == currentFilter then
			table.insert(results, entry)
		end
	end
	lastResults = results
	lastAllTotal = #allResults
	RenderProcessPanelRows()
end

_G.AutoDelete_RenderProcessPanelRows = RenderProcessPanelRows
_G.AutoDelete_RefreshProcessPanel = RefreshProcessPanel

end  -- end of Process Bags Panel `do` block

-- ============================================================================
-- Disenchant Filters Popup
-- ============================================================================
-- Tiny standalone popup that holds the Disenchant scope filters that don't
-- fit on the Keybinds-tab single-row layout. Opened by clicking the gear
-- button on the One-Key Disenchant row. Same draggable-frame pattern as
-- the Process Bags panel, just smaller (no scrollable list, just a stack
-- of compact controls).

do

local POPUP_W = 240
-- v3.21: bumped from 170 -> 190 to absorb the Quality-label Y shift that
-- fixed the BoP/BoE overlap (was off-by-10 against the toggle row height).
local POPUP_H = 190

-- Visual style mirrors the Process Bags panel and the main settings
-- panel: dark body, dark gray border, dark title bar with orange text,
-- dim close X that turns red on hover. Previously this popup used an
-- orange-filled title bar and an orange border, which read as a
-- different window family from the rest of the addon (same regression
-- the Process Bags panel had pre-2026-04). Audit fix 2026-05-20.
local popup = CreateFrame("Frame", "AutoDeleteDisenchantFiltersPopup", UIParent)
popup:SetSize(POPUP_W, POPUP_H)
popup:SetFrameStrata("DIALOG")
popup:SetFrameLevel(120)
popup:SetMovable(true)
popup:EnableMouse(true)
popup:SetClampedToScreen(true)
popup:Hide()
ApplyBackdrop(popup, C_BG, C_BORDER)

-- Title bar: drag handle + window title. Same canonical look as
-- Process Bags and the main settings panel.
local titleBar = CreateFrame("Frame", nil, popup)
titleBar:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, 0)
titleBar:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, 0)
titleBar:SetHeight(24)
ApplyBackdrop(titleBar, C_TITLEBAR, C_BORDER)
titleBar:EnableMouse(true)
titleBar:RegisterForDrag("LeftButton")
titleBar:SetScript("OnDragStart", function() popup:StartMoving() end)
titleBar:SetScript("OnDragStop", function() popup:StopMovingOrSizing() end)

local titleText = MakeText(titleBar, 12, C_TITLE, "OUTLINE")
titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
titleText:SetText("Disenchant Filters")

-- Close X in the title bar's right corner. Dim by default, red on
-- hover -- matches the main settings panel and Process Bags exactly.
local closeX = CreateFrame("Button", nil, titleBar)
closeX:SetSize(24, 24)
closeX:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", 0, 0)
local closeXText = MakeText(closeX, 14, C_DIM, "OUTLINE")
closeXText:SetText("x")
closeXText:SetPoint("CENTER")
closeX:SetScript("OnEnter", function() closeXText:SetTextColor(1, 0.3, 0.3) end)
closeX:SetScript("OnLeave", function() closeXText:SetTextColor(unpack(C_DIM)) end)
closeX:SetScript("OnClick", function() popup:Hide() end)

-- Body: section labels + 5 inline sub-toggles (BoP / BoE / Unc / Rare /
-- Epic) on two rows + an iLvl row with min/max inputs. All controls
-- mirror the Keybinds-tab inline controls we used to render before this
-- popup existed; the OnClick handlers below dispatch the same way.
--
-- v3.21: section Y values pushed down to eliminate label/toggle overlap.
-- The original layout had QUAL_Y = -56 (label) and TGL_Y_BIND = -46
-- (toggles, height 16, extending to -62), so the Quality label collided
-- with the BoP/BoE row from y=-56 to y=-62. New values give each
-- section a clean 6px gap below the toggles of the section above.
--   Section A (Bind state): label at -30, toggles at -46 (row -46..-62)
--   Section B (Quality):    label at -68, toggles at -84 (row -84..-100)
--   Section C (iLvl range): label at -106, inputs at -124 (row -124..-142)
local BIND_Y    = -30
local QUAL_Y    = -68
local ILVL_Y    = -106
local LABEL_X   = 12

local function MakeSectionLabel(parent, text, y)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, 10, "OUTLINE")
	fs:SetTextColor(unpack(C_ACCENT))
	fs:SetPoint("TOPLEFT", LABEL_X, y)
	fs:SetText(text)
	return fs
end

local bindLabel = MakeSectionLabel(popup, "Bind state:", BIND_Y)
local qualLabel = MakeSectionLabel(popup, "Quality:",    QUAL_Y)
local ilvlLabel = MakeSectionLabel(popup, "iLvl range:", ILVL_Y)

-- Sub-toggles: positioned with a per-toggle width, anchored to the
-- popup at fixed x offsets. Color follows the main-panel convention:
-- binary toggles (BoP/BoE) use C_ACCENT (the standard active-state
-- orange); rarity toggles (Unc/Rare/Epic) use the WoW quality colors
-- (green/blue/purple). Audit fix 2026-05-20 -- the previous build
-- used C_DK_RED (Death Knight class color, only intended for the
-- Auto-Repair "Use Guild Bank money" sub-toggle) for everything,
-- which read as off-design and didn't communicate rarity.
local TGL_Y_BIND = BIND_Y - 16
local TGL_Y_QUAL = QUAL_Y - 16
local TGL_W      = 52

local function MakeFilterToggle(label, color, x, y)
	local tgl = MakeSubToggle(popup, label, color)
	tgl:SetPoint("TOPLEFT", x, y)
	tgl:SetWidth(TGL_W)
	return tgl
end

-- Binary bind-state toggles use the standard accent (orange).
local tglBoP  = MakeFilterToggle("BoP",  C_ACCENT, LABEL_X,             TGL_Y_BIND)
local tglBoE  = MakeFilterToggle("BoE",  C_ACCENT, LABEL_X + TGL_W,     TGL_Y_BIND)

-- Rarity toggles use WoW quality colors so the checked-state fill
-- communicates which rarity each control governs at a glance.
local tglUnc  = MakeFilterToggle("Unc",  C_Q_UNCOMMON, LABEL_X,             TGL_Y_QUAL)
local tglRare = MakeFilterToggle("Rare", C_Q_RARE,     LABEL_X + TGL_W,     TGL_Y_QUAL)
local tglEpic = MakeFilterToggle("Epic", C_Q_EPIC,     LABEL_X + TGL_W * 2, TGL_Y_QUAL)

-- iLvl min/max: two small numeric input boxes joined by a dash. Width
-- and offset match the Process Bags panel's iLvl controls for visual
-- consistency.
local function MakeIlvlEdit(x, y)
	local box = CreateFrame("Frame", nil, popup)
	box:SetSize(36, 18)
	box:SetPoint("TOPLEFT", x, y)
	ApplyBackdrop(box, C_DROP_BG, C_DROP_BORDER)
	local edit = CreateFrame("EditBox", nil, box)
	edit:SetFont(FONT, 10, "OUTLINE")
	edit:SetTextColor(unpack(C_TEXT))
	edit:SetAutoFocus(false)
	edit:SetNumeric(true)
	edit:SetMaxLetters(4)
	edit:SetPoint("TOPLEFT", 3, -1)
	edit:SetPoint("BOTTOMRIGHT", -3, 1)
	edit:SetJustifyH("CENTER")
	edit:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
	edit:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
	return edit
end

local ilvlMinEdit = MakeIlvlEdit(LABEL_X,      ILVL_Y - 18)
local ilvlMaxEdit = MakeIlvlEdit(LABEL_X + 48, ILVL_Y - 18)

local ilvlDash = popup:CreateFontString(nil, "OVERLAY")
ilvlDash:SetFont(FONT, 10, "OUTLINE")
ilvlDash:SetTextColor(unpack(C_DIM))
ilvlDash:SetPoint("TOPLEFT", LABEL_X + 38, ILVL_Y - 21)
ilvlDash:SetText("-")

-- Hint text under the iLvl row explaining the 0 = use-default semantics.
local ilvlHint = popup:CreateFontString(nil, "OVERLAY")
ilvlHint:SetFont(FONT, 8, "OUTLINE")
ilvlHint:SetTextColor(unpack(C_DIM))
ilvlHint:SetPoint("TOPLEFT", LABEL_X + 92, ILVL_Y - 18)
ilvlHint:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -10, ILVL_Y - 18)
ilvlHint:SetJustifyH("LEFT")
ilvlHint:SetWordWrap(true)
ilvlHint:SetText("0 = use default")

-- OnClick handlers. Each writes the profile field, refreshes the cache,
-- and re-arms the disenchant button. Mirrors the per-toggle handler the
-- main panel sets up for other features.
--
-- IMPORTANT: this popup is constructed at FILE LOAD time, outside the
-- BuildUI() closure where `db` is a local. Use GetDB() explicitly here
-- so the handlers don't resolve `db` to a nil global. (Latent bug fixed
-- 2026-05-20: any toggle click previously errored with "attempt to
-- index local 'db' (a nil value)" at GetActiveProfile.)
local function MakeFilterHandler(field)
	return function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(GetDB())[field] = btn._checked
		if _G.AutoDelete_RefreshCachedProfile then _G.AutoDelete_RefreshCachedProfile() end
		if _G.AutoDelete_UpdateDisenchantButton then _G.AutoDelete_UpdateDisenchantButton() end
		local panel = _G.AutoDeleteOptionsPanel
		if panel and panel._refreshDisenchantStatus then panel:_refreshDisenchantStatus() end
	end
end
tglBoP:SetScript("OnClick",  MakeFilterHandler("disenchantBoP"))
tglBoE:SetScript("OnClick",  MakeFilterHandler("disenchantBoE"))
tglUnc:SetScript("OnClick",  MakeFilterHandler("disenchantUncommon"))
tglRare:SetScript("OnClick", MakeFilterHandler("disenchantRare"))
tglEpic:SetScript("OnClick", MakeFilterHandler("disenchantEpic"))

local function MakeIlvlHandler(field)
	return function(s)
		local val = tonumber(s:GetText()) or 0
		if val < 0 then val = 0 end
		s:SetText(tostring(val))
		GetActiveProfile(GetDB())[field] = val
		if _G.AutoDelete_RefreshCachedProfile then _G.AutoDelete_RefreshCachedProfile() end
		if _G.AutoDelete_UpdateDisenchantButton then _G.AutoDelete_UpdateDisenchantButton() end
	end
end
ilvlMinEdit:SetScript("OnEditFocusLost", MakeIlvlHandler("disenchantIlvlMin"))
ilvlMaxEdit:SetScript("OnEditFocusLost", MakeIlvlHandler("disenchantIlvlMax"))

-- Refresh: reads current profile values into the popup widgets. Called
-- on popup show so the controls always reflect saved state.
local function RefreshPopup()
	local profile = _G.AutoDelete_GetCachedProfile and _G.AutoDelete_GetCachedProfile()
	if not profile then return end
	tglBoP:SetChecked(profile.disenchantBoP)
	tglBoE:SetChecked(profile.disenchantBoE)
	tglUnc:SetChecked(profile.disenchantUncommon)
	tglRare:SetChecked(profile.disenchantRare)
	tglEpic:SetChecked(profile.disenchantEpic)
	ilvlMinEdit:SetText(tostring(profile.disenchantIlvlMin or 0))
	ilvlMaxEdit:SetText(tostring(profile.disenchantIlvlMax or 0))
end

popup:SetScript("OnShow", function(self)
	-- Anchor centered on first show; user can drag it after.
	if not self._everShown then
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		self._everShown = true
	end
	RefreshPopup()
end)

local function ToggleDisenchantFiltersPopup()
	if popup:IsShown() then popup:Hide() else popup:Show() end
end

_G.AutoDelete_DisenchantFiltersPopup       = popup
_G.AutoDelete_ToggleDisenchantFiltersPopup = ToggleDisenchantFiltersPopup
_G.AutoDelete_RefreshDisenchantFilters     = RefreshPopup

end  -- end of Disenchant Filters Popup `do` block

-- ============================================================================
-- Learned Affixes Popup
-- ============================================================================
-- Scrollable read-only window that displays the player's learned and unlearned affixes,
-- populated by the Scan Learned Affixes button on the Affix Display card.
-- Same draggable-frame pattern as the Disenchant Filters popup and the
-- Process Bags panel: dark body, dark gray border, dark title bar with
-- orange text, dim close X that turns red on hover.
--
-- Body is a ScrollFrame with pooled rows so affix names can be clicked.
-- Clicking an affix opens a selected copy field because WoW addons cannot
-- silently write to the OS clipboard.

do

local POPUP_W = 320
local POPUP_H = 390
local TITLE_H = 24
local TAB_H = 30
local BODY_PAD_X = 10
local BODY_PAD_TOP = 4
local BODY_PAD_BOT = 8
-- Scrollbar built into UIPanelScrollFrameTemplate reserves ~22px on the
-- right edge of the scroll frame; pad accordingly so text doesn't slide
-- under the bar.
local SCROLLBAR_W = 22

local popup = CreateFrame("Frame", "AutoDeleteLearnedAffixesPopup", UIParent)
popup:SetSize(POPUP_W, POPUP_H)
popup:SetFrameStrata("DIALOG")
popup:SetFrameLevel(120)
popup:SetMovable(true)
popup:EnableMouse(true)
popup:SetClampedToScreen(true)
popup:Hide()
ApplyBackdrop(popup, C_BG, C_BORDER)

-- Title bar: drag handle + window title + close X. Mirrors the canonical
-- look used by the Disenchant Filters popup and Process Bags panel.
local titleBar = CreateFrame("Frame", nil, popup)
titleBar:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, 0)
titleBar:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, 0)
titleBar:SetHeight(TITLE_H)
ApplyBackdrop(titleBar, C_TITLEBAR, C_BORDER)
titleBar:EnableMouse(true)
titleBar:RegisterForDrag("LeftButton")
titleBar:SetScript("OnDragStart", function() popup:StartMoving() end)
titleBar:SetScript("OnDragStop", function() popup:StopMovingOrSizing() end)

local titleText = MakeText(titleBar, 12, C_TITLE, "OUTLINE")
titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
titleText:SetText("Learned Affixes")

local refreshBtn = CreateFrame("Button", nil, titleBar)
refreshBtn:SetSize(62, 18)
refreshBtn:SetPoint("RIGHT", titleBar, "RIGHT", -28, 0)
ApplyBackdrop(refreshBtn, C_ROW_ODD, C_BORDER)
local refreshText = MakeText(refreshBtn, 10, C_TEXT, "OUTLINE")
refreshText:SetPoint("CENTER")
refreshText:SetText("Refresh")
refreshBtn:SetScript("OnClick", function()
	if _G.AutoDelete_ScanLearnedAffixes then
		_G.AutoDelete_ScanLearnedAffixes()
	end
end)
refreshBtn:SetScript("OnEnter", function(btn)
	ApplyBackdrop(btn, C_ROW_HOVER, C_BORDER)
	refreshText:SetTextColor(1, 1, 1, 1)
	GameTooltip:SetOwner(btn, "ANCHOR_TOP")
	GameTooltip:SetText("Refresh", 1, 1, 1)
	GameTooltip:AddLine("Scans Project Ebonhold's current affix data again.",
		C_DIM[1], C_DIM[2], C_DIM[3], true)
	GameTooltip:Show()
end)
refreshBtn:SetScript("OnLeave", function(btn)
	ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
	refreshText:SetTextColor(unpack(C_TEXT))
	GameTooltip:Hide()
end)

local closeX = CreateFrame("Button", nil, titleBar)
closeX:SetSize(24, 24)
closeX:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", 0, 0)
local closeXText = MakeText(closeX, 14, C_DIM, "OUTLINE")
closeXText:SetText("x")
closeXText:SetPoint("CENTER")
closeX:SetScript("OnEnter", function() closeXText:SetTextColor(1, 0.3, 0.3) end)
closeX:SetScript("OnLeave", function() closeXText:SetTextColor(unpack(C_DIM)) end)
closeX:SetScript("OnClick", function() popup:Hide() end)

local currentTab = "learned"
local tabData = {
	learned = "",
	unlearned = "",
}
local tabRows = {}
local tabCounts = {}
local tabButtons = {}
local RefreshLearnedAffixesTabs

local function FormatAffixTabLabel(label, count)
	if count ~= nil then
		return string.format("%s (%d)", label, count)
	end
	return label
end

local tabRow = CreateFrame("Frame", nil, popup)
tabRow:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -2)
tabRow:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -2)
tabRow:SetHeight(TAB_H)

local function RefreshAffixTabButtons()
	for key, btn in pairs(tabButtons) do
		if key == currentTab then
			ApplyBackdrop(btn, { C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 0.9 }, C_ACCENT)
			btn._text:SetFont(FONT, 12, "")
			btn._text:SetTextColor(0.05, 0.05, 0.05, 1)
		else
			ApplyBackdrop(btn, { 0.07, 0.07, 0.07, 1 }, { 0.20, 0.20, 0.20, 1 })
			btn._text:SetFont(FONT, 11, "OUTLINE")
			btn._text:SetTextColor(1, 1, 1, 1)
		end
	end
end

local TAB_PAD_X = 8
local TAB_GAP = 6
local TAB_BTN_W = math.floor((POPUP_W - TAB_PAD_X * 2 - TAB_GAP) / 2)
local TAB_BTN_H = 22

local function CreateAffixTabButton(key, label, x)
	local btn = CreateFrame("Button", nil, tabRow)
	btn:SetSize(TAB_BTN_W, TAB_BTN_H)
	btn:SetPoint("TOPLEFT", tabRow, "TOPLEFT", x, -4)
	ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
	local txt = MakeText(btn, 11, C_TEXT, "OUTLINE")
	txt:SetPoint("CENTER")
	txt:SetWidth(TAB_BTN_W - 8)
	txt:SetJustifyH("CENTER")
	txt:SetWordWrap(false)
	txt:SetNonSpaceWrap(false)
	txt:SetText(label)
	btn._text = txt
	btn._baseLabel = label
	btn:SetScript("OnClick", function()
		currentTab = key
		if RefreshLearnedAffixesTabs then RefreshLearnedAffixesTabs(true) end
	end)
	btn:SetScript("OnEnter", function(self)
		if currentTab ~= key then
			ApplyBackdrop(self, C_ROW_HOVER, C_BORDER)
			self._text:SetTextColor(1, 1, 1, 1)
		end
	end)
	btn:SetScript("OnLeave", RefreshAffixTabButtons)
	tabButtons[key] = btn
end

CreateAffixTabButton("learned", "Learned", TAB_PAD_X)
CreateAffixTabButton("unlearned", "Unlearned", TAB_PAD_X + TAB_BTN_W + TAB_GAP)
RefreshAffixTabButtons()

-- Scroll frame fills the body below the title bar. Use Blizzard's stock
-- UIPanelScrollFrameTemplate so we get a usable scrollbar with up/down
-- arrows that match the rest of the WoW UI on 3.3.5a.
local scroll = CreateFrame("ScrollFrame", "AutoDeleteLearnedAffixesScroll", popup,
	"UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", BODY_PAD_X, -(TITLE_H + TAB_H + BODY_PAD_TOP))
scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -SCROLLBAR_W, BODY_PAD_BOT)

-- Scroll child: a Frame holding the body FontString. UIPanelScrollFrameTemplate
-- needs an explicit child whose height drives how much can be scrolled. After
-- setting text we measure GetStringHeight() and resize the child to match.
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(POPUP_W - BODY_PAD_X - SCROLLBAR_W, 1) -- height set dynamically on Show
scroll:SetScrollChild(content)

local bodyFS = content:CreateFontString(nil, "OVERLAY")
bodyFS:SetFont(FONT, 11, "OUTLINE")
bodyFS:SetTextColor(unpack(C_TEXT))
bodyFS:SetJustifyH("LEFT")
bodyFS:SetJustifyV("TOP")
bodyFS:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
-- Fixed width so the FontString wraps cleanly within the scroll child.
-- Per AGENTS.md FontString rule §10.9: width MUST come from SetWidth(N),
-- never from a RIGHT-anchor SetPoint. SetWordWrap + SetNonSpaceWrap
-- explicit per the same rule.
local CONTENT_FS_W = POPUP_W - BODY_PAD_X - SCROLLBAR_W
bodyFS:SetWidth(CONTENT_FS_W)
bodyFS:SetWordWrap(true)
bodyFS:SetNonSpaceWrap(false)

local copyFrame = CreateFrame("Frame", nil, popup)
copyFrame:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", BODY_PAD_X, 8)
copyFrame:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -BODY_PAD_X, 8)
copyFrame:SetHeight(28)
copyFrame:SetFrameLevel(popup:GetFrameLevel() + 4)
copyFrame:Hide()
ApplyBackdrop(copyFrame, C_DROP_BG, C_DROP_BORDER)

local copyHint = MakeText(copyFrame, 9, C_DIM, "OUTLINE")
copyHint:SetPoint("LEFT", copyFrame, "LEFT", 6, 0)
copyHint:SetText("Ctrl+C")

local copyEdit = CreateFrame("EditBox", nil, copyFrame)
copyEdit:SetFont(FONT, 11, "OUTLINE")
copyEdit:SetTextColor(unpack(C_TEXT))
copyEdit:SetAutoFocus(false)
copyEdit:EnableKeyboard(true)
copyEdit:SetPoint("LEFT", copyHint, "RIGHT", 8, 0)
copyEdit:SetPoint("RIGHT", copyFrame, "RIGHT", -6, 0)
copyEdit:SetHeight(20)
copyEdit._copyText = ""
copyEdit._settingText = false
copyEdit:SetScript("OnEscapePressed", function(s)
	s:ClearFocus()
	copyFrame:Hide()
end)
copyEdit:SetScript("OnEnterPressed", function(s)
	s:ClearFocus()
	copyFrame:Hide()
end)
copyEdit:SetScript("OnTextChanged", function(s)
	if s._settingText then return end
	if s:GetText() ~= (s._copyText or "") then
		s._settingText = true
		s:SetText(s._copyText or "")
		s._settingText = false
		s:HighlightText()
	end
end)

local copyDefocusFrame = CreateFrame("Frame")
copyDefocusFrame:Hide()
copyDefocusFrame:SetScript("OnUpdate", function(self)
	self:Hide()
	copyEdit:ClearFocus()
	copyFrame:Hide()
end)
copyEdit:SetScript("OnKeyDown", function(s, key)
	if (key == "C" or key == "c") and IsControlKeyDown and IsControlKeyDown() then
		copyDefocusFrame:Show()
	else
		s:HighlightText()
	end
end)

local function ShowAffixCopyBox(text)
	copyEdit._copyText = text or ""
	copyEdit._settingText = true
	copyEdit:SetText(copyEdit._copyText)
	copyEdit._settingText = false
	copyFrame:Show()
	copyEdit:SetFocus()
	copyEdit:HighlightText()
end

local ROW_H = 17
local BLANK_ROW_H = 8
local rowPool = {}

local function HideAffixRows()
	for _, row in ipairs(rowPool) do
		row:Hide()
	end
end

local function GetAffixRow(index)
	local row = rowPool[index]
	if row then return row end
	row = CreateFrame("Button", nil, content)
	row:SetHeight(ROW_H)
	row:SetWidth(CONTENT_FS_W)
	row:EnableMouse(true)

	local hover = row:CreateTexture(nil, "BACKGROUND")
	hover:SetAllPoints(row)
	hover:SetTexture(WHITE8x8)
	hover:SetVertexColor(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 0.16)
	hover:Hide()
	row._hover = hover

	local text = MakeText(row, 11, C_TEXT, "OUTLINE")
	text:SetPoint("LEFT", row, "LEFT", 0, 0)
	text:SetWidth(CONTENT_FS_W)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	text:SetNonSpaceWrap(false)
	row._text = text

	row:SetScript("OnClick", function(self)
		if self._copyText then
			ShowAffixCopyBox(self._copyText)
		end
	end)
	row:SetScript("OnEnter", function(self)
		if self._copyText then
			self._hover:Show()
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Copy Affix Name", 1, 1, 1)
			GameTooltip:AddLine("Click to select this affix name for Ctrl+C.",
				C_DIM[1], C_DIM[2], C_DIM[3], true)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		self._hover:Hide()
		GameTooltip:Hide()
	end)

	rowPool[index] = row
	return row
end

local function ResizeLearnedAffixesContent()
	-- Measure rendered height and size the scroll child to match so the
	-- scrollbar's range is correct. Add a small bottom pad so the last line
	-- isn't flush against the frame edge.
	local h = bodyFS:GetStringHeight() + 8
	if h < 1 then h = 1 end
	content:SetHeight(h)
end

local function RenderAffixRows(rows)
	bodyFS:Hide()
	HideAffixRows()
	local y = 0
	for i, data in ipairs(rows or {}) do
		local row = GetAffixRow(i)
		local isBlank = data.kind == "blank"
		local h = isBlank and BLANK_ROW_H or ROW_H
		row:SetHeight(h)
		row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
		row._copyText = data.copyText
		row._hover:Hide()
		row._text:SetText(data.text or "")
		if isBlank then row._text:Hide() else row._text:Show() end
		if data.kind == "header" then
			row._text:SetFont(FONT, 11, "OUTLINE")
			row._text:SetTextColor(unpack(C_TITLE))
		elseif data.kind == "affix" then
			row._text:SetFont(FONT, 11, "OUTLINE")
			row._text:SetTextColor(unpack(C_TEXT))
		else
			row._text:SetFont(FONT, 11, "OUTLINE")
			row._text:SetTextColor(unpack(C_DIM))
		end
		row:EnableMouse(data.copyText ~= nil)
		row:Show()
		y = y + h
	end
	content:SetHeight(math.max(1, y + 8))
end

RefreshLearnedAffixesTabs = function(resetScroll)
	for key, btn in pairs(tabButtons) do
		btn._text:SetText(FormatAffixTabLabel(btn._baseLabel, tabCounts[key]))
	end
	RefreshAffixTabButtons()
	copyFrame:Hide()
	if tabRows[currentTab] then
		RenderAffixRows(tabRows[currentTab])
	else
		HideAffixRows()
		bodyFS:Show()
		bodyFS:SetText(tabData[currentTab] or "")
		ResizeLearnedAffixesContent()
	end
	if resetScroll then
		scroll:SetVerticalScroll(0)
	end
end

-- Show the popup with the given body text. Resizes the scroll child so the
-- scrollbar reflects the actual content height. Text may include WoW color
-- escapes (|cffRRGGBB...|r) which FontString renders natively.
local function ShowLearnedAffixesWindow(bodyTextOrData)
	if type(bodyTextOrData) == "table" then
		tabData.learned = bodyTextOrData.learned or ""
		tabData.unlearned = bodyTextOrData.unlearned or ""
		tabRows.learned = bodyTextOrData.learnedRows
		tabRows.unlearned = bodyTextOrData.unlearnedRows
		tabCounts.learned = bodyTextOrData.learnedCount
		tabCounts.unlearned = bodyTextOrData.unlearnedCount
		if bodyTextOrData.defaultTab == "learned" or bodyTextOrData.defaultTab == "unlearned" then
			currentTab = bodyTextOrData.defaultTab
		end
	else
		tabData.learned = bodyTextOrData or ""
		tabData.unlearned = "|cffff8000No unlearned-affix list available.|r"
		tabRows.learned = nil
		tabRows.unlearned = nil
		tabCounts.learned = nil
		tabCounts.unlearned = nil
		currentTab = "learned"
	end
	RefreshLearnedAffixesTabs(true)
	-- Anchor centered on first show; user can drag it after.
	if not popup._everShown then
		popup:ClearAllPoints()
		popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		popup._everShown = true
	end
	popup:Show()
end

_G.AutoDelete_LearnedAffixesPopup      = popup
_G.AutoDelete_ShowLearnedAffixesWindow = ShowLearnedAffixesWindow

-- Escape-to-close: WoW's stock UISpecialFrames mechanism scans this table on
-- ESC and Hides any matching named frame. Our popup has a global name set
-- via CreateFrame's second arg, so just append it once.
tinsert(UISpecialFrames, "AutoDeleteLearnedAffixesPopup")

end  -- end of Learned Affixes Popup `do` block

-- ============================================================================
-- Manage Ignored Items Popup
-- ============================================================================
-- v3.20: surfaces the per-character "Skip this item" choices the user made
-- via the Keep-list override popup (AutoDelete_MarkKeepSkipped writes them
-- into AutoDeleteStatsDB.keepSkip[action][itemId]). Each row shows the
-- action tag + item link + a one-click Unignore button.
--
-- Same chrome pattern as Learned Affixes (themed title bar, dim close X,
-- UIPanelScrollFrameTemplate body, ESC-closes via UISpecialFrames).
-- Refreshes the row list every time it's shown so new ignores appear and
-- removed ones disappear without requiring a reload.

do

local POPUP_W = 360
local POPUP_H = 420
local TITLE_H = 24
local BODY_PAD_X = 10
local BODY_PAD_TOP = 4
local BODY_PAD_BOT = 8
local SCROLLBAR_W = 22
local ROW_H = 22

local popup = CreateFrame("Frame", "AutoDeleteIgnoredItemsPopup", UIParent)
popup:SetSize(POPUP_W, POPUP_H)
popup:SetFrameStrata("DIALOG")
popup:SetFrameLevel(120)
popup:SetMovable(true)
popup:EnableMouse(true)
popup:SetClampedToScreen(true)
popup:Hide()
ApplyBackdrop(popup, C_BG, C_BORDER)

local titleBar = CreateFrame("Frame", nil, popup)
titleBar:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, 0)
titleBar:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, 0)
titleBar:SetHeight(TITLE_H)
ApplyBackdrop(titleBar, C_TITLEBAR, C_BORDER)
titleBar:EnableMouse(true)
titleBar:RegisterForDrag("LeftButton")
titleBar:SetScript("OnDragStart", function() popup:StartMoving() end)
titleBar:SetScript("OnDragStop", function() popup:StopMovingOrSizing() end)

local titleText = MakeText(titleBar, 12, C_TITLE, "OUTLINE")
titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
titleText:SetText("Ignored Items")

local closeX = CreateFrame("Button", nil, titleBar)
closeX:SetSize(24, 24)
closeX:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", 0, 0)
local closeXText = MakeText(closeX, 14, C_DIM, "OUTLINE")
closeXText:SetText("x")
closeXText:SetPoint("CENTER")
closeX:SetScript("OnEnter", function() closeXText:SetTextColor(1, 0.3, 0.3) end)
closeX:SetScript("OnLeave", function() closeXText:SetTextColor(unpack(C_DIM)) end)
closeX:SetScript("OnClick", function() popup:Hide() end)

-- Scroll frame fills the body below the title bar.
local scroll = CreateFrame("ScrollFrame", "AutoDeleteIgnoredItemsScroll", popup,
	"UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", BODY_PAD_X, -(TITLE_H + BODY_PAD_TOP))
scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -SCROLLBAR_W, BODY_PAD_BOT)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(POPUP_W - BODY_PAD_X - SCROLLBAR_W, 1)
scroll:SetScrollChild(content)

-- Row pool: lazy-create on demand, reuse across refreshes. Each row has an
-- action tag FontString, an item link FontString, and an "X" unignore
-- button on the right. Rows hide when unused (refresh pass shows only as
-- many rows as needed, hides the rest).
local rowPool = {}

local function MakeIgnoreRow(idx)
	local row = CreateFrame("Frame", nil, content)
	row:SetSize(POPUP_W - BODY_PAD_X - SCROLLBAR_W, ROW_H)
	row:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_H)

	-- Subtle alternating row bg so a long list reads as a list.
	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(WHITE8x8)
	bg:SetAllPoints()
	bg:SetVertexColor(0.06, 0.06, 0.06, 1)
	row._bg = bg

	-- Action tag on the left ("DE" / "Mill" / "Prospect" / "Open").
	local tag = MakeText(row, 9, C_DIM, "OUTLINE")
	tag:SetPoint("LEFT", row, "LEFT", 6, 0)
	tag:SetWidth(52)
	tag:SetJustifyH("LEFT")
	tag:SetWordWrap(false)
	tag:SetNonSpaceWrap(false)
	row._tag = tag

	-- Item link in the middle.
	local link = MakeText(row, 10, C_TEXT, "OUTLINE")
	link:SetPoint("LEFT", tag, "RIGHT", 6, 0)
	link:SetPoint("RIGHT", row, "RIGHT", -30, 0)
	link:SetJustifyH("LEFT")
	link:SetWordWrap(false)
	link:SetNonSpaceWrap(false)
	row._link = link

	-- Unignore button on the right -- small X.
	local unignore = CreateFrame("Button", nil, row)
	unignore:SetSize(18, 18)
	unignore:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	ApplyBackdrop(unignore, { 0.07, 0.07, 0.07, 1 }, { 0.30, 0.30, 0.30, 1 })
	local uTxt = MakeText(unignore, 12, C_DIM, "OUTLINE")
	uTxt:SetText("x")
	uTxt:SetPoint("CENTER")
	unignore:SetScript("OnEnter", function(self)
		ApplyBackdrop(self, { C_RED[1], C_RED[2], C_RED[3], 0.4 }, C_RED)
		uTxt:SetTextColor(1, 1, 1, 1)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Unignore", 1, 1, 1)
		GameTooltip:AddLine("Stop ignoring this item. AutoDelete will ask about it again next time.",
			C_DIM[1], C_DIM[2], C_DIM[3], true)
		GameTooltip:Show()
	end)
	unignore:SetScript("OnLeave", function(self)
		ApplyBackdrop(self, { 0.07, 0.07, 0.07, 1 }, { 0.30, 0.30, 0.30, 1 })
		uTxt:SetTextColor(unpack(C_DIM))
		GameTooltip:Hide()
	end)
	row._unignore = unignore

	return row
end

-- Empty-state message (shown when no items are ignored).
local emptyText = MakeText(content, 11, C_DIM, "OUTLINE")
emptyText:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -8)
emptyText:SetWidth(POPUP_W - BODY_PAD_X - SCROLLBAR_W - 12)
emptyText:SetJustifyH("LEFT")
emptyText:SetWordWrap(true)
emptyText:SetNonSpaceWrap(false)
emptyText:SetText("No ignored items. When the Keep-list popup appears, clicking Ignore on an item adds it here.")
emptyText:Hide()

-- Action label lookup. Uses the same verbs as the override popup.
local ACTION_TAGS = {
	disenchant = "DE",
	mill       = "Mill",
	prospect   = "Prospect",
	open       = "Open",
}

local function RefreshIgnoredItems()
	local sv = _G.AutoDeleteStatsDB
	if not sv or not sv.keepSkip then
		-- SV not initialized yet (PLAYER_LOGIN hasn't fired); show empty.
		for _, r in ipairs(rowPool) do r:Hide() end
		emptyText:Show()
		content:SetHeight(40)
		return
	end
	-- Collect (action, itemId) pairs.
	local entries = {}
	for _, action in ipairs({ "disenchant", "mill", "prospect", "open" }) do
		local bucket = sv.keepSkip[action]
		if bucket then
			for id in pairs(bucket) do
				if bucket[id] then
					table.insert(entries, { action = action, id = id })
				end
			end
		end
	end
	-- Sort: by action first (DE / Mill / Prospect / Open) then by id.
	local actionOrder = { disenchant = 1, mill = 2, prospect = 3, open = 4 }
	table.sort(entries, function(a, b)
		if a.action == b.action then return a.id < b.id end
		return (actionOrder[a.action] or 99) < (actionOrder[b.action] or 99)
	end)

	if #entries == 0 then
		for _, r in ipairs(rowPool) do r:Hide() end
		emptyText:Show()
		content:SetHeight(40)
		return
	end
	emptyText:Hide()

	-- Populate rows; grow the pool as needed.
	for i, entry in ipairs(entries) do
		local row = rowPool[i]
		if not row then
			row = MakeIgnoreRow(i)
			rowPool[i] = row
		end
		row:Show()
		row._tag:SetText(ACTION_TAGS[entry.action] or entry.action)
		-- Item link if cached; otherwise itemId text.
		local _, link = GetItemInfo("item:" .. entry.id)
		row._link:SetText(link or ("item:" .. entry.id))
		-- Per-row unignore wires its action+id at refresh time so the
		-- closure captures the right values.
		row._unignore:SetScript("OnClick", function()
			if _G.AutoDelete_ClearKeepSkip then
				_G.AutoDelete_ClearKeepSkip(entry.action, entry.id)
			end
			RefreshIgnoredItems()
		end)
		-- Alternating row tint for legibility.
		if i % 2 == 0 then
			row._bg:SetVertexColor(0.04, 0.04, 0.04, 1)
		else
			row._bg:SetVertexColor(0.07, 0.07, 0.07, 1)
		end
	end
	-- Hide unused rows from the pool.
	for i = #entries + 1, #rowPool do
		rowPool[i]:Hide()
	end
	content:SetHeight(#entries * ROW_H + 8)
end

popup:SetScript("OnShow", function(self)
	if not self._everShown then
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		self._everShown = true
	end
	scroll:SetVerticalScroll(0)
	RefreshIgnoredItems()
end)

local function ShowIgnoredItemsWindow()
	popup:Show()
end

local function ToggleIgnoredItemsWindow()
	if popup:IsShown() then popup:Hide() else popup:Show() end
end

_G.AutoDelete_IgnoredItemsPopup        = popup
_G.AutoDelete_ShowIgnoredItemsWindow   = ShowIgnoredItemsWindow
_G.AutoDelete_ToggleIgnoredItemsWindow = ToggleIgnoredItemsWindow
_G.AutoDelete_RefreshIgnoredItemsWindow = RefreshIgnoredItems

tinsert(UISpecialFrames, "AutoDeleteIgnoredItemsPopup")

end  -- end of Ignored Items Popup `do` block

-- ============================================================================
-- Raw Lists Import / Export (v3.20)
-- ============================================================================
-- Three popups + the execute helper that wires them together:
--
--   1. Import Raw popup       (paste area + Import to Delete/Sell/Keep buttons)
--   2. Import Results popup   (summary: imported / duplicates / unresolved)
--   3. Export Raw popup       (list-picker dropdown + read-only auto-selected text)
--
-- Flow:
--   * User pastes item names (one per line) into Import Raw, clicks a
--     destination button -> AutoDelete_ExecuteRawImport(listKey, rawText)
--     resolves names via GetItemInfo, dedupes against the target list,
--     appends item:<id> lines to profile.<listText|sellListText|whitelistText>,
--     opens the Results popup with counts + unresolved names.
--   * User opens Export Raw, picks Delete / Sell / Keep -> the read-only
--     EditBox fills with the target list's items as plain names (one per
--     line). User Ctrl+A / Ctrl+C to copy.
--
-- All popups follow the canonical chrome (dark body, dark gray border,
-- dark title bar + orange title, dim close X that turns red on hover) and
-- close on Escape via UISpecialFrames. Helpers all live on _G to keep
-- the main chunk under Lua 5.1's 200-local cap.

-- ---------------------------------------------------------------------------
-- Parser + import-execute helpers (file-local; called by the popups below).
-- ---------------------------------------------------------------------------

-- The list-key -> profile-field map used by both Import and Export.
local RAW_LIST_FIELDS = {
	delete = "listText",
	sell   = "sellListText",
	keep   = "whitelistText",
}
local RAW_LIST_LABELS = {
	delete = "Delete",
	sell   = "Sell",
	keep   = "Keep",
}

-- Build a set of itemIds already on a list (newline-separated `item:<id>`
-- format). Cheap; used for dedupe and conflict checks during import.
local function ParseListItemIds(listText)
	local ids = {}
	for line in string.gmatch(listText or "", "[^\r\n]+") do
		local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
		local id = tonumber(trimmed:match("item:(%d+)"))
		if id then ids[id] = true end
	end
	return ids
end

local function CleanRawImportLine(line)
	local cleaned = tostring(line or "")
	cleaned = cleaned:gsub("%s*#.*$", "")
	cleaned = cleaned:gsub("^%s+", ""):gsub("%s+$", "")
	cleaned = cleaned:gsub("^%s*[%-%*]+%s*", "")
	cleaned = cleaned:gsub("^%s*%d+[%.)]%s*", "")
	cleaned = cleaned:gsub("^%[(.+)%]$", "%1")
	cleaned = cleaned:gsub("^\"(.+)\"$", "%1")
	return cleaned:gsub("^%s+", ""):gsub("%s+$", "")
end

local function AddKnownItemName(lookup, name, id, source)
	if not lookup or not name or not id then return end
	local key = Normalize(name)
	if key == "" then return end
	local bucket = lookup[key]
	if not bucket then
		bucket = { order = {}, ids = {} }
		lookup[key] = bucket
	end
	if not bucket.ids[id] then
		bucket.ids[id] = { name = name, source = source }
		table.insert(bucket.order, id)
	end
end

local function AddKnownItemId(lookup, id, source)
	if not id then return end
	local name = GetItemInfo(id)
	if name then
		AddKnownItemName(lookup, name, id, source)
	else
		GetItemInfo("item:" .. id)
	end
end

local function BuildRawImportNameLookup(profile)
	local lookup = {}
	if profile then
		for _, field in pairs(RAW_LIST_FIELDS) do
			for id in pairs(ParseListItemIds(profile[field])) do
				AddKnownItemId(lookup, id, "list")
			end
		end
	end
	for bag = 0, 4 do
		local slots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local link = GetContainerItemLink and GetContainerItemLink(bag, slot) or nil
			local id = link and GetItemIDFromLink(link)
			if id then
				local name = GetItemInfo(link)
				if name then
					AddKnownItemName(lookup, name, id, "bags")
				else
					AddKnownItemId(lookup, id, "bags")
				end
			end
		end
	end
	return lookup
end

local function FormatCandidateIds(candidate)
	if not candidate or not candidate.order then return "" end
	local out = {}
	for _, id in ipairs(candidate.order) do
		table.insert(out, "item:" .. id)
	end
	return table.concat(out, ", ")
end

-- Try to resolve one pasted line into exactly one item id by accepting full item
-- links, item:<id>, plain numeric ids, and cached/current-bag plain names.
-- Returns:
--   "ok", id, displayName
--   "ambiguous", nil, displayName, "item:1, item:2"
--   "unresolved", nil, displayName
local function ResolveRawLine(line, nameLookup)
	if not line or line == "" then return nil, nil end
	local cleanName = CleanRawImportLine(line)
	if cleanName == "" then return nil, nil end
	-- Form A: full link or item:<id> reference.
	local id = tonumber(cleanName:match("Hitem:(%d+)") or cleanName:match("item:(%d+)") or cleanName:match("^(%d+)$"))
	if id then
		local name = GetItemInfo(id)
		if name then return "ok", id, name end
		-- We have an id we can format, but the player's cache has not
		-- seen it. Still usable for the import (we have the id) but the
		-- summary popup won't have a pretty name; show the id.
		GetItemInfo("item:" .. id)
		return "ok", id, "item:" .. id
	end
	-- Form B: plain name. First ask the client cache, then use names we can
	-- prove from current bags and existing list entries. There is no 3.3.5 API
	-- for a full item-database name search, so unresolved names stay unresolved.
	local resolved, link = GetItemInfo(cleanName)
	if resolved and link then
		local linkId = tonumber(link:match("item:(%d+)"))
		if linkId then return "ok", linkId, resolved end
	end
	local candidate = nameLookup and nameLookup[Normalize(cleanName)] or nil
	if candidate and #candidate.order == 1 then
		local foundId = candidate.order[1]
		local info = candidate.ids[foundId] or {}
		return "ok", foundId, info.name or cleanName
	elseif candidate and #candidate.order > 1 then
		return "ambiguous", nil, cleanName, FormatCandidateIds(candidate)
	end
	return "unresolved", nil, cleanName
end

local function BuildRawImportConflictIds(profile, targetField)
	local conflicts = {}
	if not profile then return conflicts end
	for listKey, field in pairs(RAW_LIST_FIELDS) do
		if field ~= targetField then
			for id in pairs(ParseListItemIds(profile[field])) do
				conflicts[id] = RAW_LIST_LABELS[listKey] or field
			end
		end
	end
	return conflicts
end

-- Append a batch of item ids to profile[listKey field]. Caller has already
-- deduped. Adds a trailing newline if the existing list doesn't already
-- end with one so the appended block stays on its own lines.
local function AppendIdsToList(profile, listKey, ids)
	local field = RAW_LIST_FIELDS[listKey]
	if not field or not profile or #ids == 0 then return end
	local current = profile[field] or ""
	if current ~= "" and not current:match("\n$") then
		current = current .. "\n"
	end
	local lines = {}
	for _, id in ipairs(ids) do
		table.insert(lines, "item:" .. id)
	end
	profile[field] = current .. table.concat(lines, "\n") .. "\n"
end

-- Execute Raw import. Called by the Import Raw popup's destination buttons.
-- Walks the paste text line-by-line, resolves each, dedupes against the
-- target list, appends survivors, then opens the Results popup with a
-- summary breakdown.
function _G.AutoDelete_ExecuteRawImport(listKey, rawText)
	if not RAW_LIST_FIELDS[listKey] then return end
	local profile = _G.AutoDelete_GetCachedProfile and _G.AutoDelete_GetCachedProfile()
	if not profile then return end
	local field = RAW_LIST_FIELDS[listKey]
	local existing = ParseListItemIds(profile[field])
	local conflictsById = BuildRawImportConflictIds(profile, field)
	local nameLookup = BuildRawImportNameLookup(profile)
	local imported, duplicates, unresolved, ambiguous, conflicts = {}, {}, {}, {}, {}
	local toAppend = {}
	for line in string.gmatch(rawText or "", "[^\r\n]+") do
		local trimmed = CleanRawImportLine(line)
		if trimmed ~= "" then
			local status, id, name, note = ResolveRawLine(trimmed, nameLookup)
			if status == "unresolved" then
				table.insert(unresolved, name or trimmed)
			elseif status == "ambiguous" then
				table.insert(ambiguous, { name = name or trimmed, candidates = note or "" })
			elseif existing[id] then
				table.insert(duplicates, name or ("item:" .. id))
			elseif conflictsById[id] then
				table.insert(conflicts, {
					name = name or ("item:" .. id),
					list = conflictsById[id],
				})
			else
				table.insert(imported, name or ("item:" .. id))
				table.insert(toAppend, id)
				existing[id] = true
			end
		end
	end
	AppendIdsToList(profile, listKey, toAppend)
	if _G.AutoDelete_RefreshCachedProfile then
		_G.AutoDelete_RefreshCachedProfile()
	end
	-- Refresh the visible Lists view (Delete/Sell/Keep) if open.
	local panel = _G.AutoDeleteOptionsPanel
	if panel and panel.Refresh then panel:Refresh() end
	-- Show the Results popup with counts + unresolved names.
	if _G.AutoDelete_ShowImportResultsWindow then
		_G.AutoDelete_ShowImportResultsWindow(listKey, #imported, #duplicates, unresolved, {
			ambiguous = ambiguous,
			conflicts = conflicts,
		})
	end
end

-- Render a list as raw names for export. Walks profile[<listKey>Text],
-- resolves each item:<id> entry via GetItemInfo, returns a newline-joined
-- string of names. Uncached items fall back to their item:<id> form.
function _G.AutoDelete_BuildRawExport(listKey)
	if not RAW_LIST_FIELDS[listKey] then return "" end
	local profile = _G.AutoDelete_GetCachedProfile and _G.AutoDelete_GetCachedProfile()
	if not profile then return "" end
	local text = profile[RAW_LIST_FIELDS[listKey]] or ""
	local names = {}
	for line in string.gmatch(text, "[^\r\n]+") do
		local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
		local id = tonumber(trimmed:match("item:(%d+)"))
		if id then
			local name = GetItemInfo(id)
			table.insert(names, name or ("item:" .. id))
		end
	end
	return table.concat(names, "\n")
end

-- ---------------------------------------------------------------------------
-- Shared chrome helper for the three Raw popups. Returns the popup frame
-- with title bar + close X already attached. Caller fills the body area
-- (everything below TITLE_H pixels from the top).
-- ---------------------------------------------------------------------------
local function MakeRawPopup(globalName, titleText, w, h)
	local p = CreateFrame("Frame", globalName, UIParent)
	p:SetSize(w, h)
	p:SetFrameStrata("DIALOG")
	p:SetFrameLevel(120)
	p:SetMovable(true)
	p:EnableMouse(true)
	p:SetClampedToScreen(true)
	p:Hide()
	ApplyBackdrop(p, C_BG, C_BORDER)
	local tb = CreateFrame("Frame", nil, p)
	tb:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
	tb:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
	tb:SetHeight(24)
	ApplyBackdrop(tb, C_TITLEBAR, C_BORDER)
	tb:EnableMouse(true)
	tb:RegisterForDrag("LeftButton")
	tb:SetScript("OnDragStart", function() p:StartMoving() end)
	tb:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
	local title = MakeText(tb, 12, C_TITLE, "OUTLINE")
	title:SetPoint("LEFT", tb, "LEFT", 10, 0)
	title:SetText(titleText)
	p._titleText = title
	local x = CreateFrame("Button", nil, tb)
	x:SetSize(24, 24)
	x:SetPoint("TOPRIGHT", tb, "TOPRIGHT", 0, 0)
	local xt = MakeText(x, 14, C_DIM, "OUTLINE")
	xt:SetText("x")
	xt:SetPoint("CENTER")
	x:SetScript("OnEnter", function() xt:SetTextColor(1, 0.3, 0.3) end)
	x:SetScript("OnLeave", function() xt:SetTextColor(unpack(C_DIM)) end)
	x:SetScript("OnClick", function() p:Hide() end)
	tinsert(UISpecialFrames, globalName)
	return p
end

-- ---------------------------------------------------------------------------
-- Import Raw popup
-- ---------------------------------------------------------------------------

do

local POPUP_W = 380
local POPUP_H = 360
local TITLE_H = 24
local PAD_X = 10

local popup = MakeRawPopup("AutoDeleteImportRawPopup", "Import Raw", POPUP_W, POPUP_H)

-- Hint text above the paste area.
local hint = MakeText(popup, 10, C_DIM, "OUTLINE")
hint:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X, -(TITLE_H + 8))
hint:SetWidth(POPUP_W - PAD_X * 2)
hint:SetJustifyH("LEFT")
hint:SetWordWrap(true)
hint:SetNonSpaceWrap(false)
hint:SetText("Paste item names below, one per line. Item links also work. Then pick a list:")

-- Paste area: multi-line EditBox inside a ScrollFrame, dark bg.
local pasteHolder = CreateFrame("Frame", nil, popup)
pasteHolder:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X, -(TITLE_H + 8 + 24))
pasteHolder:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD_X, -(TITLE_H + 8 + 24))
pasteHolder:SetHeight(POPUP_H - TITLE_H - 8 - 24 - 38 - 12)
ApplyBackdrop(pasteHolder, C_DROP_BG, C_DROP_BORDER)

local pasteScroll = CreateFrame("ScrollFrame", nil, pasteHolder)
pasteScroll:SetPoint("TOPLEFT", 4, -4)
pasteScroll:SetPoint("BOTTOMRIGHT", -4, 4)

local pasteEdit = CreateFrame("EditBox", nil, pasteScroll)
pasteEdit:SetMultiLine(true)
pasteEdit:SetAutoFocus(false)
pasteEdit:EnableMouse(true)
pasteEdit:EnableKeyboard(true)
pasteEdit:SetFont(FONT, 11, "OUTLINE")
pasteEdit:SetTextColor(unpack(C_TEXT))
pasteEdit:SetWidth(POPUP_W - PAD_X * 2 - 8)
pasteScroll:SetScrollChild(pasteEdit)
pasteEdit:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)

pasteHolder:EnableMouse(true)
pasteHolder:SetScript("OnMouseDown", function() pasteEdit:SetFocus() end)
pasteScroll:EnableMouseWheel(true)
pasteScroll:SetScript("OnMouseWheel", function(sf, delta)
	local v = math.max(0, math.min(sf:GetVerticalScrollRange(),
		sf:GetVerticalScroll() - delta * 30))
	sf:SetVerticalScroll(v)
end)

-- Three destination buttons below the paste area, equal widths.
local BTN_H = 24
local function MakeDestButton(label, listKey, color, xOff, btnW)
	local b = MakeActionButton(popup, label, color, function()
		local txt = pasteEdit:GetText() or ""
		if txt == "" then return end
		if _G.AutoDelete_ExecuteRawImport then
			_G.AutoDelete_ExecuteRawImport(listKey, txt)
		end
		pasteEdit:SetText("")
		popup:Hide()
	end, btnW, BTN_H)
	b:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", xOff, 12)
	return b
end
local BTN_GAP = 6
local TOTAL_BTN_W = POPUP_W - PAD_X * 2 - BTN_GAP * 2
local BTN_W = math.floor(TOTAL_BTN_W / 3)
MakeDestButton("Import to Delete", "delete", C_RED,   PAD_X,                                BTN_W)
MakeDestButton("Import to Sell",   "sell",   C_BLUE,  PAD_X + BTN_W + BTN_GAP,              BTN_W)
MakeDestButton("Import to Keep",   "keep",   C_GREEN, PAD_X + (BTN_W + BTN_GAP) * 2,        BTN_W)

popup:SetScript("OnShow", function(self)
	if not self._everShown then
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		self._everShown = true
	end
	pasteEdit:SetText("")
	pasteEdit:SetFocus()
end)

function _G.AutoDelete_ShowImportRawWindow()
	popup:Show()
end

end  -- end of Import Raw Popup `do` block

-- ---------------------------------------------------------------------------
-- Import Results popup (summary: imported / duplicates / unresolved)
-- ---------------------------------------------------------------------------

do

local POPUP_W = 380
local POPUP_H = 320
local TITLE_H = 24
local PAD_X = 10
local SCROLLBAR_W = 22

local popup = MakeRawPopup("AutoDeleteImportResultsPopup", "Import Results", POPUP_W, POPUP_H)

-- Scrollable body so a long list of unresolved names doesn't overflow.
local scroll = CreateFrame("ScrollFrame", "AutoDeleteImportResultsScroll", popup,
	"UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X, -(TITLE_H + 4))
scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -SCROLLBAR_W, 40)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(POPUP_W - PAD_X - SCROLLBAR_W, 1)
scroll:SetScrollChild(content)

local body = content:CreateFontString(nil, "OVERLAY")
body:SetFont(FONT, 11, "OUTLINE")
body:SetTextColor(unpack(C_TEXT))
body:SetJustifyH("LEFT")
body:SetJustifyV("TOP")
body:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
body:SetWidth(POPUP_W - PAD_X - SCROLLBAR_W)
body:SetWordWrap(true)
body:SetNonSpaceWrap(false)

-- OK button anchored at the bottom of the popup.
local okBtn = MakeActionButton(popup, "OK", C_BLUE, function() popup:Hide() end,
	POPUP_W - PAD_X * 2, 24)
okBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", PAD_X, 8)

function _G.AutoDelete_ShowImportResultsWindow(listKey, importedCount, duplicateCount, unresolved, details)
	local listLabel = RAW_LIST_LABELS[listKey] or listKey or "?"
	details = details or {}
	local lines = {}
	table.insert(lines, string.format(
		"|cffff8000Imported %d item(s) to the %s list.|r", importedCount, listLabel))
	if duplicateCount and duplicateCount > 0 then
		table.insert(lines, "")
		table.insert(lines, string.format(
			"|cff8a8a8aSkipped %d duplicate(s) already on the %s list.|r",
			duplicateCount, listLabel))
	end
	if details.conflicts and #details.conflicts > 0 then
		table.insert(lines, "")
		table.insert(lines, string.format(
			"|cffffaa00Skipped %d item(s) already on another list:|r",
			#details.conflicts))
		for _, entry in ipairs(details.conflicts) do
			table.insert(lines, string.format("  %s  (%s list)",
				entry.name or "Unknown item", entry.list or "other"))
		end
		table.insert(lines, "")
		table.insert(lines, "|cff8a8a8aRemove the item from the other list first if you want to move it.|r")
	end
	if details.ambiguous and #details.ambiguous > 0 then
		table.insert(lines, "")
		table.insert(lines, string.format(
			"|cffffaa00Skipped %d ambiguous name(s):|r", #details.ambiguous))
		for _, entry in ipairs(details.ambiguous) do
			table.insert(lines, "  " .. (entry.name or "Unknown item"))
			if entry.candidates and entry.candidates ~= "" then
				table.insert(lines, "    candidates: " .. entry.candidates)
			end
		end
		table.insert(lines, "")
		table.insert(lines, "|cff8a8a8aPaste the exact item:id for ambiguous names so AutoDelete does not guess wrong.|r")
	end
	if unresolved and #unresolved > 0 then
		table.insert(lines, "")
		table.insert(lines, string.format(
			"|cffff5555Could not find %d name(s):|r", #unresolved))
		for _, name in ipairs(unresolved) do
			table.insert(lines, "  " .. name)
		end
		table.insert(lines, "")
		table.insert(lines, "|cff8a8a8aTip: AutoDelete can resolve item links, item:id, plain numeric IDs, cached names, current bag items, and known list entries. Mouse over missing items or paste item:id when a name is not cached.|r")
	end
	body:SetText(table.concat(lines, "\n"))
	local h = body:GetStringHeight() + 8
	if h < 1 then h = 1 end
	content:SetHeight(h)
	if not popup._everShown then
		popup:ClearAllPoints()
		popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		popup._everShown = true
	end
	scroll:SetVerticalScroll(0)
	popup:Show()
end

end  -- end of Import Results Popup `do` block

-- ---------------------------------------------------------------------------
-- Export Raw popup (dropdown + read-only auto-selected text area)
-- ---------------------------------------------------------------------------

do

local POPUP_W = 380
local POPUP_H = 360
local TITLE_H = 24
local PAD_X = 10

local popup = MakeRawPopup("AutoDeleteExportRawPopup", "Export Raw", POPUP_W, POPUP_H)

-- Hint + dropdown row at top.
local hint = MakeText(popup, 10, C_DIM, "OUTLINE")
hint:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X, -(TITLE_H + 8))
hint:SetWidth(POPUP_W - PAD_X * 2)
hint:SetJustifyH("LEFT")
hint:SetWordWrap(true)
hint:SetNonSpaceWrap(false)
hint:SetText("Pick a list. The names below are pre-selected -- press Ctrl+C to copy.")

-- Read-only text area (multi-line EditBox inside a ScrollFrame).
local exportHolder = CreateFrame("Frame", nil, popup)
exportHolder:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X, -(TITLE_H + 8 + 24 + 28))
exportHolder:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD_X, -(TITLE_H + 8 + 24 + 28))
exportHolder:SetHeight(POPUP_H - TITLE_H - 8 - 24 - 28 - 12 - 8)
ApplyBackdrop(exportHolder, C_DROP_BG, C_DROP_BORDER)

local exportScroll = CreateFrame("ScrollFrame", nil, exportHolder)
exportScroll:SetPoint("TOPLEFT", 4, -4)
exportScroll:SetPoint("BOTTOMRIGHT", -4, 4)

local exportEdit = CreateFrame("EditBox", nil, exportScroll)
exportEdit:SetMultiLine(true)
exportEdit:SetAutoFocus(false)
exportEdit:EnableMouse(true)
exportEdit:EnableKeyboard(true)
exportEdit:SetFont(FONT, 11, "OUTLINE")
exportEdit:SetTextColor(unpack(C_TEXT))
exportEdit:SetWidth(POPUP_W - PAD_X * 2 - 8)
exportScroll:SetScrollChild(exportEdit)
exportEdit:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
-- Read-only: any edit attempts revert. The user can still highlight + copy.
exportEdit:SetScript("OnTextChanged", function(eb)
	if eb._suppress then return end
	eb._suppress = true
	eb:SetText(eb._stash or "")
	eb._suppress = false
end)

exportHolder:EnableMouse(true)
exportHolder:SetScript("OnMouseDown", function() exportEdit:SetFocus() end)
exportScroll:EnableMouseWheel(true)
exportScroll:SetScript("OnMouseWheel", function(sf, delta)
	local v = math.max(0, math.min(sf:GetVerticalScrollRange(),
		sf:GetVerticalScroll() - delta * 30))
	sf:SetVerticalScroll(v)
end)

local function FillFor(listKey)
	local txt = (_G.AutoDelete_BuildRawExport and _G.AutoDelete_BuildRawExport(listKey)) or ""
	exportEdit._suppress = true
	exportEdit._stash = txt
	exportEdit:SetText(txt)
	exportEdit._suppress = false
	-- Auto-select all so Ctrl+C copies the whole list immediately.
	exportEdit:SetFocus()
	exportEdit:HighlightText()
end

-- Three buttons act as the "picker": clicking one fills the text area.
-- (Simpler than a dropdown for three options and consistent with the
-- Import popup's three-destination row.)
local pickRow = CreateFrame("Frame", nil, popup)
pickRow:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X, -(TITLE_H + 8 + 22))
pickRow:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD_X, -(TITLE_H + 8 + 22))
pickRow:SetHeight(22)

local BTN_GAP = 6
local TOTAL_PICK_W = POPUP_W - PAD_X * 2 - BTN_GAP * 2
local PICK_BTN_W = math.floor(TOTAL_PICK_W / 3)
local function MakePickButton(label, listKey, color, xOff)
	local b = MakeActionButton(pickRow, label, color, function()
		FillFor(listKey)
	end, PICK_BTN_W, 22)
	b:SetPoint("LEFT", pickRow, "LEFT", xOff, 0)
	return b
end
MakePickButton("Delete", "delete", C_RED,   0)
MakePickButton("Sell",   "sell",   C_BLUE,  PICK_BTN_W + BTN_GAP)
MakePickButton("Keep",   "keep",   C_GREEN, (PICK_BTN_W + BTN_GAP) * 2)

popup:SetScript("OnShow", function(self)
	if not self._everShown then
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		self._everShown = true
	end
	-- Default to Delete list on open.
	FillFor("delete")
end)

function _G.AutoDelete_ShowExportRawWindow()
	popup:Show()
end

end  -- end of Export Raw Popup `do` block

-- ============================================================================
-- Spike Report popup (v3.20)
-- ============================================================================
-- Read-only multi-line dump of the spike-debug ring buffer. Mirrors the
-- Export Raw popup pattern: pre-selects text on show so Ctrl+C copies the
-- whole report immediately. Built so users without ElvUI (which provides
-- chat copying) can still grab spike data after a test pass.
--
-- Called from AutoDelete.lua via _G.AutoDelete_ShowSpikeReportWindow(text).
-- The text-building lives there; this file only owns the popup geometry.

do

local POPUP_W = 720         -- wider than Export Raw so one spike row fits per line
local POPUP_H = 460
local TITLE_H = 24
local PAD_X   = 10

local popup = MakeRawPopup("AutoDeleteSpikeReportPopup", "Spike Report", POPUP_W, POPUP_H)

local hint = MakeText(popup, 10, C_DIM, "OUTLINE")
hint:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X, -(TITLE_H + 8))
hint:SetWidth(POPUP_W - PAD_X * 2)
hint:SetJustifyH("LEFT")
hint:SetWordWrap(true)
hint:SetNonSpaceWrap(false)
hint:SetText("Spike ring buffer (oldest first). Pre-selected -- press Ctrl+C to copy.")

local txtHolder = CreateFrame("Frame", nil, popup)
txtHolder:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X, -(TITLE_H + 8 + 18))
txtHolder:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD_X, -(TITLE_H + 8 + 18))
txtHolder:SetHeight(POPUP_H - TITLE_H - 8 - 18 - 12)
ApplyBackdrop(txtHolder, C_DROP_BG, C_DROP_BORDER)

local txtScroll = CreateFrame("ScrollFrame", nil, txtHolder)
txtScroll:SetPoint("TOPLEFT", 4, -4)
txtScroll:SetPoint("BOTTOMRIGHT", -4, 4)

local txtEdit = CreateFrame("EditBox", nil, txtScroll)
txtEdit:SetMultiLine(true)
txtEdit:SetAutoFocus(false)
txtEdit:EnableMouse(true)
txtEdit:EnableKeyboard(true)
txtEdit:SetFont(FONT, 10, "OUTLINE")  -- 10pt fits one spike row at POPUP_W=720
txtEdit:SetTextColor(unpack(C_TEXT))
txtEdit:SetWidth(POPUP_W - PAD_X * 2 - 8)
txtScroll:SetScrollChild(txtEdit)
txtEdit:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
-- Read-only: any edit attempts revert to the stash. Highlight + copy still work.
txtEdit:SetScript("OnTextChanged", function(eb)
	if eb._suppress then return end
	eb._suppress = true
	eb:SetText(eb._stash or "")
	eb._suppress = false
end)

txtHolder:EnableMouse(true)
txtHolder:SetScript("OnMouseDown", function() txtEdit:SetFocus() end)
txtScroll:EnableMouseWheel(true)
txtScroll:SetScript("OnMouseWheel", function(sf, delta)
	local v = math.max(0, math.min(sf:GetVerticalScrollRange(),
		sf:GetVerticalScroll() - delta * 30))
	sf:SetVerticalScroll(v)
end)

local function FillWith(text)
	txtEdit._suppress = true
	txtEdit._stash = text or ""
	txtEdit:SetText(text or "")
	txtEdit._suppress = false
	-- Auto-select all so Ctrl+C copies the whole report immediately.
	txtEdit:SetFocus()
	txtEdit:HighlightText()
end

popup:SetScript("OnShow", function(self)
	if not self._everShown then
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		self._everShown = true
	end
end)

function _G.AutoDelete_ShowSpikeReportWindow(text)
	FillWith(text)
	popup:Show()
end

end  -- end of Spike Report Popup `do` block

-- ============================================================================
-- General Report popup
-- ============================================================================
-- Copyable report surface for /del report and item Why? reports. Mirrors the Spike
-- Report popup: plain text, pre-selected, no local paths or process docs.

do

local POPUP_W = 640
local POPUP_H = 430
local TITLE_H = 24
local PAD_X   = 10

local popup = MakeRawPopup("AutoDeleteReportPopup", "AutoDelete Report", POPUP_W, POPUP_H)

local hint = MakeText(popup, 10, C_DIM, "OUTLINE")
hint:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X, -(TITLE_H + 8))
hint:SetWidth(POPUP_W - PAD_X * 2)
hint:SetJustifyH("LEFT")
hint:SetWordWrap(true)
hint:SetNonSpaceWrap(false)
hint:SetText("Report text is pre-selected. Press Ctrl+C to copy.")

local txtHolder = CreateFrame("Frame", nil, popup)
txtHolder:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X, -(TITLE_H + 8 + 18))
txtHolder:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD_X, -(TITLE_H + 8 + 18))
txtHolder:SetHeight(POPUP_H - TITLE_H - 8 - 18 - 12)
ApplyBackdrop(txtHolder, C_DROP_BG, C_DROP_BORDER)

local txtScroll = CreateFrame("ScrollFrame", nil, txtHolder)
txtScroll:SetPoint("TOPLEFT", 4, -4)
txtScroll:SetPoint("BOTTOMRIGHT", -4, 4)

local txtEdit = CreateFrame("EditBox", nil, txtScroll)
txtEdit:SetMultiLine(true)
txtEdit:SetAutoFocus(false)
txtEdit:EnableMouse(true)
txtEdit:EnableKeyboard(true)
txtEdit:SetFont(FONT, 10, "OUTLINE")
txtEdit:SetTextColor(unpack(C_TEXT))
txtEdit:SetWidth(POPUP_W - PAD_X * 2 - 8)
txtScroll:SetScrollChild(txtEdit)
txtEdit:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
txtEdit:SetScript("OnTextChanged", function(eb)
	if eb._suppress then return end
	eb._suppress = true
	eb:SetText(eb._stash or "")
	eb._suppress = false
end)

txtHolder:EnableMouse(true)
txtHolder:SetScript("OnMouseDown", function() txtEdit:SetFocus() end)
txtScroll:EnableMouseWheel(true)
txtScroll:SetScript("OnMouseWheel", function(sf, delta)
	local v = math.max(0, math.min(sf:GetVerticalScrollRange(),
		sf:GetVerticalScroll() - delta * 30))
	sf:SetVerticalScroll(v)
end)

local function FillWith(text)
	txtEdit._suppress = true
	txtEdit._stash = text or ""
	txtEdit:SetText(text or "")
	txtEdit._suppress = false
	txtEdit:SetFocus()
	txtEdit:HighlightText()
end

popup:SetScript("OnShow", function(self)
	if not self._everShown then
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		self._everShown = true
	end
end)

function _G.AutoDelete_ShowReportWindow(text, title)
	if popup._titleText then
		popup._titleText:SetText(title or "AutoDelete Report")
	end
	FillWith(text)
	popup:Show()
end

end  -- end of General Report Popup `do` block

-- ============================================================================
-- Help Topic popup
-- ============================================================================
-- Dedicated readable help surface that mirrors the addon's card style: every
-- section renders as an icon (left) + bold title + muted description, using the
-- same role colors as the tabs (accent title, bright option title, dim copy,
-- warning red for destructive options). Section data carries its own icon path
-- and an optional `destructive` flag; for safe options that still hide a
-- destructive action, the clause is marked inline with |cffbf3838...|r. No
-- per-kind rainbow, no auto-detected tags.

function _G.AutoDelete_ShowHelpTopicWindow(titleText, sections)
	if not _G.AutoDeleteHelpTopicPopup then
		local POPUP_W = 470
		local POPUP_H = 390
		local TITLE_H = 24
		local PAD_X   = 12
		local popup = MakeRawPopup("AutoDeleteHelpTopicPopup", "AutoDelete Help", POPUP_W, POPUP_H)

		local topicTitle = MakeText(popup, 14, C_ACCENT, "OUTLINE")
		topicTitle:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X, -(TITLE_H + 10))
		topicTitle:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD_X, -(TITLE_H + 10))
		topicTitle:SetJustifyH("LEFT")
		topicTitle:SetText("Help")
		popup._helpTopicTitle = topicTitle

		local introRule = popup:CreateTexture(nil, "ARTWORK")
		introRule:SetTexture(WHITE8x8)
		introRule:SetHeight(1)
		introRule:SetPoint("TOPLEFT", topicTitle, "BOTTOMLEFT", 0, -8)
		introRule:SetPoint("TOPRIGHT", topicTitle, "BOTTOMRIGHT", 0, -8)
		introRule:SetVertexColor(C_ACCENT[1], C_ACCENT[2], C_ACCENT[3], 0.55)

		local holder = CreateFrame("Frame", nil, popup)
		holder:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD_X, -(TITLE_H + 42))
		holder:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -PAD_X, 12)
		ApplyBackdrop(holder, C_DROP_BG, C_DROP_BORDER)

		local scroll = CreateFrame("ScrollFrame", "AutoDeleteHelpTopicScroll", holder, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", holder, "TOPLEFT", 8, -8)
		scroll:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -26, 8)

		local content = CreateFrame("Frame", nil, scroll)
		content:SetWidth(POPUP_W - PAD_X * 2 - 42)
		content:SetHeight(1)
		scroll:SetScrollChild(content)

		popup._helpScroll = scroll
		popup._helpContent = content
		popup._helpRows = {}
		_G.AutoDeleteHelpTopicPopup = popup
	end

	local popup = _G.AutoDeleteHelpTopicPopup
	if popup._titleText then popup._titleText:SetText("AutoDelete Help") end
	popup._helpTopicTitle:SetText(titleText or "Help")

	local rows = popup._helpRows
	for _, row in ipairs(rows) do
		row.icon:Hide()
		row.title:Hide()
		row.body:Hide()
		row.sep:Hide()
	end

	local content = popup._helpContent
	local width = content:GetWidth() or 420
	local ICON = 18                 -- matches the Process Bags item-row icon size
	local TEXT_X = 2 + ICON + 8     -- icon (left) + gap; title/body start here
	local y = -2

	for i, section in ipairs(sections or {}) do
		local row = rows[i]
		if not row then
			row = {}
			row.icon = content:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(ICON, ICON)
			-- Trim the stock icon border so it reads as a clean glyph.
			row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			row.title = MakeText(content, 11, C_TEXT, "OUTLINE")
			row.title:SetJustifyH("LEFT")
			row.body = MakeText(content, 10, C_DIM)
			row.body:SetJustifyH("LEFT")
			row.body:SetWordWrap(true)
			row.body:SetNonSpaceWrap(false)
			row.sep = content:CreateTexture(nil, "ARTWORK")
			row.sep:SetTexture(WHITE8x8)
			row.sep:SetHeight(1)
			row.sep:SetVertexColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)
			rows[i] = row
		end

		-- Icon on the left. Bad paths fall back to the stock question mark.
		row.icon:ClearAllPoints()
		row.icon:SetPoint("TOPLEFT", content, "TOPLEFT", 2, y - 1)
		row.icon:SetTexture(section.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		row.icon:Show()

		-- Bold option title: bright by default, warning red for destructive ones.
		row.title:ClearAllPoints()
		row.title:SetPoint("TOPLEFT", content, "TOPLEFT", TEXT_X, y)
		row.title:SetWidth(width - TEXT_X - 2)
		if section.destructive then
			row.title:SetTextColor(C_RED[1], C_RED[2], C_RED[3], 1)
		else
			row.title:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3], 1)
		end
		row.title:SetText(section.title or "")
		row.title:Show()
		local titleH = row.title:GetStringHeight() or 12

		-- Muted description below the title. Inline |cffbf3838...|r marks any
		-- destructive clause inside an otherwise-safe option.
		row.body:ClearAllPoints()
		row.body:SetPoint("TOPLEFT", content, "TOPLEFT", TEXT_X, y - titleH - 4)
		row.body:SetWidth(width - TEXT_X - 2)
		row.body:SetText(section.body or "")
		row.body:Show()
		local bodyH = row.body:GetStringHeight() or 14

		-- Advance by the taller of (title + gap + body) or the icon, so short
		-- descriptions never overlap the icon.
		local rowH = math.max(titleH + 4 + bodyH, ICON)
		y = y - rowH - 10

		row.sep:ClearAllPoints()
		row.sep:SetPoint("TOPLEFT", content, "TOPLEFT", TEXT_X, y)
		row.sep:SetPoint("RIGHT", content, "RIGHT", -2, 0)
		row.sep:SetVertexColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 0.5)
		row.sep:Show()
		y = y - 10
	end

	content:SetHeight(math.max(1, -y + 6))
	popup._helpScroll:SetVerticalScroll(0)
	if not popup._everShown then
		popup:ClearAllPoints()
		popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		popup._everShown = true
	end
	popup:Show()
end

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
	-- SECTION 1: Tabbed Settings (General / Pets / Filters / Keybinds /
	-- Invites / Tracking / Profiles). Container panel holds a horizontal
	-- tab strip at top + a fixed-height content area below. See each tab's
	-- own header comment further down for the card-by-card breakdown of
	-- that tab's layout.
	-- ========================================================================
	local CARD_TOP_PAD = 6
	local CARD_BOT_PAD = 4

	-- Tabbed area geometry:
	-- Tab strip: 26px tall
	-- Content area: 82px tall (fits 4 cards at cardH=74 + 8px buffer)
	-- Inner padding: 6px on each side, 6px gap between strip and content
	local TAB_STRIP_H = 26
	-- Tab content area height. All tabs share this single height; the
	-- previous 196 experiment (to fit a 2x2 Keybinds grid) put visible
	-- dead space below every other tab and was reverted. Keybinds now
	-- uses a compact 4-row layout that fits in 100.
	local CONTENT_AREA_H = 100   -- 92px card area + 4px top + 4px bottom margins
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

	-- Create tab content pages (frames parented to tabContent, filling it).
	local tabPages = {}
	-- Tab keys are stable internal identifiers (referenced in tabPages[<key>]
	-- across the file); tab labels are user-facing and renamed without
	-- migrating the keys. Goblin -> Pets, Tools -> Filters, AutoInv -> Invites
	-- reflect what the tabs actually contain after the Option B reorg.
	-- v3.20: added "affix" key/Affix label to house the Project Ebonhold
	-- affix tooling that previously lived on Filters. Filters now hosts
	-- DE Filters + Manage Ignored Items.
	--
	-- Order (2026-05-27 spec): General > Pets > Affix > Invites > Filters >
	-- Keybinds > Tracking > Profiles > Help. Internal keys stay STABLE (the SV
	-- has `tools` for Filters and `goblin` for Pets from earlier renames)
	-- so the visual reorder is just rearranging these two arrays.
	local TAB_KEYS = { "general", "goblin", "affix", "autoinv", "tools", "keybinds", "tracking", "profiles", "help" }
	local TAB_LABELS = { "General", "Pets", "Affix", "Invites", "Filters", "Keybinds", "Tracking", "Profiles", "Help" }
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
	-- GENERAL TAB: 3 cards horizontally:
	--   Card 1: Enable Addon + Auto-Add Equipped + Auto-Repair (+ guild bank
	--           sub-toggle indented under Auto-Repair)
	--   Card 2: Process Bags     (title + live count + Open Panel button)
	--   Card 3: Scan Speed       (dropdown + help text + detailed tooltip)
	-- Content area is 100px tall; cards occupy 92px with 4px top/bottom margins.
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
		-- v3.21 §6.3: shared inner-card pattern via ApplyBackdrop + constants.
		ApplyBackdrop(card, C_CARD_BG, C_CARD_BORDER)
		return card
	end

	local card1 = MakeGeneralCard(0)
	local card2 = MakeGeneralCard(cardW + CARD_GAP)
	local card3 = MakeGeneralCard((cardW + CARD_GAP) * 2)

	-- Card 1 (Option B reorg per user request 2026-05-20):
	--   Row 1: Enable Addon  (master toggle; description dropped from the
	--          card to make room for Auto-Repair below -- the hover tooltip
	--          still carries the full explanation)
	--   Row 2: Auto-Add Equipped
	--   Row 3: Auto-Repair      (master)
	--   Row 3-sub: Use Guild Bank money (16px sub-toggle, indented)
	-- 3 main rows + 1 sub-row fit in cardH=92 with 4px slack.
	-- Sub-toggle indent matches MakeSubToggle convention (parent box+gap=32).
	local SUBTGL_INDENT_GEN = CARD_INNER_PAD_X + 14 + 8

	local tglEnable = MakeToggle(card1, "Enable Addon", C_ACCENT,
		"Turns AutoDelete on or off. When off, nothing is auto-deleted or sold. Auto-Invite and Hide Greedy Spam still work no matter what.")
	tglEnable:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -CARD_INNER_PAD_Y)
	tglEnable:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglEnable = tglEnable

	local tglAutoAddEquipped = MakeToggle(card1, "Auto-Add Equipped", C_ACCENT,
		"Adds gear you equip to your Keep list so it won't be sold or deleted by mistake. Shirts and tabards are skipped.")
	tglAutoAddEquipped:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 22))
	tglAutoAddEquipped:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglAutoAddEquipped = tglAutoAddEquipped

	local tglRepair = MakeToggle(card1, "Auto-Repair", C_ACCENT,
		"Fixes your gear when you talk to a vendor. Turn on the sub-toggle below to pay from your guild bank first.")
	tglRepair:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 44))
	tglRepair:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglRepair = tglRepair

	local tglRepairGuild = MakeSubToggle(card1, "Use Guild Bank money", C_DK_RED)
	tglRepairGuild:SetPoint("TOPLEFT", SUBTGL_INDENT_GEN, -(CARD_INNER_PAD_Y + 66))
	tglRepairGuild:SetWidth(cardW - SUBTGL_INDENT_GEN - CARD_INNER_PAD_X)
	self._tglRepairGuild = tglRepairGuild

	-- Card 2: Process Bags launcher (moved from Filters -> Card 3 per the
	-- Option B reorg). General tab now carries the "I want to actively run
	-- something" feature; the Filters tab is purely about which auto-rules
	-- apply. Same layout as the old Process Bags card -- title, live count
	-- summary that refreshes on BAG_UPDATE + panel Refresh, and an Open
	-- Panel action button.
	--
	-- Wrapped in `do ... end` so the title/count/button locals don't bump
	-- BuildUI past Lua 5.1's 200-local cap. The count FontString is
	-- exported on `self._processCount` (read by self:_refreshProcessCount
	-- below), so the wrapper's locals can vanish on block exit.
	do
		local card2Title = MakeText(card2, 11, C_ACCENT, "OUTLINE")
		card2Title:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -6)
		card2Title:SetText("Process Bags")

		local processCount = MakeText(card2, 9, C_DIM)
		processCount:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -24)
		processCount:SetPoint("TOPRIGHT", -CARD_INNER_PAD_X, -24)
		processCount:SetJustifyH("LEFT")
		processCount:SetWordWrap(true)
		processCount:SetText("...")
		self._processCount = processCount

		-- Open Panel: launches the standalone Process Bags window. C_BLUE
		-- (change/transform class). Sits at y=-68 to match the Audit Lists
		-- button on Filters Card 2 (uniform row geometry across tabs).
		local launchBtn = MakeActionButton(card2, "Open Panel", C_BLUE, function()
			if _G.AutoDelete_ToggleProcessPanel then _G.AutoDelete_ToggleProcessPanel() end
		end, cardW - CARD_INNER_PAD_X * 2, 20)
		launchBtn:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -68)
		launchBtn:SetScript("OnEnter", function(btn)
			-- Override MakeActionButton's hover so we can layer the tooltip
			-- on top, same pattern Audit Lists + Scan Learned Affixes use.
			btn:SetBackdropColor(C_BLUE[1], C_BLUE[2], C_BLUE[3], 0.3)
			btn:SetBackdropBorderColor(C_BLUE[1], C_BLUE[2], C_BLUE[3], 1)
			btn._text:SetTextColor(1, 1, 1)
			GameTooltip:SetOwner(btn, "ANCHOR_TOP")
			GameTooltip:SetText("Open Panel", 1, 1, 1)
			GameTooltip:AddLine("Opens the Process Bags window. Use the filters to review All, Sell, Delete, DE, Mill, Prospect, Open, or Kept rows before acting.",
				C_DIM[1], C_DIM[2], C_DIM[3], true)
			GameTooltip:Show()
		end)
		launchBtn:SetScript("OnLeave", function(btn)
			ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
			btn._text:SetTextColor(unpack(C_TEXT))
			GameTooltip:Hide()
		end)
	end

	function self:_refreshProcessCount()
		if not self._processCount then return end
		local getter = _G.AutoDelete_ProcessScanCounts
		if not getter then return end
		local profile = _G.AutoDelete_GetCachedProfile and _G.AutoDelete_GetCachedProfile()
		local c = getter(profile)
		if not c or c.total == 0 then
			self._processCount:SetText("No bag items found")
			return
		end
		local parts = {}
		if c.delete     > 0 then table.insert(parts, c.delete     .. " Del") end
		if c.sell       > 0 then table.insert(parts, c.sell       .. " Sell") end
		if c.disenchant > 0 then table.insert(parts, c.disenchant .. " DE") end
		if c.mill       > 0 then table.insert(parts, c.mill       .. " Mill") end
		if c.prospect   > 0 then table.insert(parts, c.prospect   .. " Pros") end
		if c.open       > 0 then table.insert(parts, c.open       .. " Open") end
		if c.kept       > 0 then table.insert(parts, c.kept       .. " Kept") end
		if (c.copies or c.total) > c.total then
			self._processCount:SetText(c.total .. " rows, " .. c.copies .. " copies: " .. table.concat(parts, ", "))
		else
			self._processCount:SetText(c.total .. " rows: " .. table.concat(parts, ", "))
		end
	end

	-- Card 3: Scan Speed (dot toggles moved to Filters -> Affix Display per
	-- the Option B reorg). Card now has just the dropdown + a couple of
	-- help lines + a detailed hover tooltip explaining the trade-off.
	-- "Nobody knows what it does" was the original feedback that triggered
	-- this rewrite -- the in-card description spells out concretely what
	-- the scan does and the hover tooltip spells out the trade-off.
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

	-- Hover tooltip on the dropdown explaining the trade-off in detail.
	-- The dropdown's main button is the OnEnter/OnLeave target -- the
	-- arrow texture and bg both live under it so hovering anywhere on
	-- the dropdown surfaces the tip. Mirrors the affixFloorRow pattern
	-- used elsewhere in this file.
	local SCAN_TIP_TITLE = "Scan Speed"
	local SCAN_TIP_BODY  = "How often AutoDelete checks your bags for items on the Delete and Sell lists.\n\n|cffffd200Fast (0.5-1 sec):|r items disappear almost instantly. Tiny CPU cost.\n\n|cffffd200Slow (5-30 sec):|r quieter in the background. Short delay before items go.\n\n|cffffd200Very slow (1-5 min):|r runs once in a while. Good if you only want vendor cleanup.\n\nVendor selling always fires right when you open a merchant, no matter this setting."
	speedDD:EnableMouse(true)
	speedDD:SetScript("OnEnter", function(s)
		GameTooltip:SetOwner(s, "ANCHOR_TOP")
		GameTooltip:SetText(SCAN_TIP_TITLE, 1, 1, 1)
		GameTooltip:AddLine(SCAN_TIP_BODY, C_DIM[1], C_DIM[2], C_DIM[3], true)
		GameTooltip:Show()
	end)
	speedDD:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- In-card description (2 lines, dim, wrapped) summarizing what the
	-- option controls. Sits below the dropdown so the card visually
	-- balances and the user has a hint without needing to hover.
	local speedHelp = MakeText(scanSpeedCard, 9, C_DIM, "OUTLINE")
	speedHelp:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 42))
	speedHelp:SetPoint("TOPRIGHT", scanSpeedCard, "TOPRIGHT", -CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 42))
	speedHelp:SetJustifyH("LEFT")
	speedHelp:SetWordWrap(true)
	speedHelp:SetText("How often bags are checked against your Delete and Sell lists. Hover for the full trade-off.")

	-- ========================================================================
	-- HELP TAB: topic buttons, each opening a formatted help popup.
	-- ========================================================================
	do
		local helpPage = tabPages.help
		local helpBox = CreateFrame("Frame", nil, helpPage)
		helpBox:SetPoint("TOPLEFT", 0, -4)
		helpBox:SetPoint("BOTTOMRIGHT", 0, 4)
		ApplyBackdrop(helpBox, C_CARD_BG, C_CARD_BORDER)

		local topics = {
			{
				label = "General",
				title = "General",
				sections = {
					{ icon = "Interface\\Icons\\INV_Misc_Gear_01", title = "Enable Addon", body = "The master switch on the General tab. While it is off, nothing is auto-deleted or auto-sold. Auto-Invite and Hide Greedy Spam keep working either way." },
					{ icon = "Interface\\Icons\\Ability_Defend", title = "Auto-Add Equipped", body = "Adds gear you equip to your Keep list so it is never sold or deleted by mistake. Shirts and tabards are skipped. Click it again after you change gear or copy a profile." },
					{ icon = "Interface\\Icons\\Ability_Repair", title = "Auto-Repair", body = "Repairs your gear whenever you talk to a vendor. Turn on Use Guild Bank money below it to pay from the guild bank first when you can." },
					{ icon = "Interface\\Icons\\INV_Misc_Bag_10_Black", title = "Process Bags", body = "Open Panel opens the Process Bags window, a separate list of every bag item ready for One-Key Disenchant, Mill, Prospect, or Open. The card also shows a live count." },
					{ icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", title = "Scan Speed", body = "How often your bags are checked against the Delete and Sell lists. Fast clears matches almost instantly, slow is quieter in the background. Vendor selling always runs when a merchant opens." },
				}
			},
			{
				label = "Pets",
				title = "Pets",
				sections = {
					{ icon = "Interface\\Icons\\Ability_Hunter_BeastCall", title = "Summon Scavenger", body = "Manages your Greedy Scavenger pet and brings it back when it gets stuck or after you mount. The sub-toggles pick when to resummon: After sell, After vendor close, and Only in Combat." },
					{ icon = "Interface\\Icons\\INV_Misc_Coin_16", title = "Summon Merchant", body = "Summons your Goblin Merchant once your bags stay full for two seconds. Target the merchant and press your Interact key to open the shop." },
					{ icon = "Interface\\Icons\\INV_Misc_Bell_01", title = "Bag warning", body = "Warns you in chat when free bag slots drop to the number in Free slots. It warns once, then stays quiet until your bags fill up again." },
					{ icon = "Interface\\Icons\\Ability_Vanish", title = "Hide Greedy Spam", body = "Hides the Greedy Scavenger chat messages and speech bubbles. It only quiets the noise, it does not change any cleanup rules." },
				}
			},
			{
				label = "Affix",
				title = "Affix",
				sections = {
					{ icon = "Interface\\Icons\\Spell_Holy_DivineProtection", title = "Affix Protection", body = "No Auto-Sell stops Auto-Sell from selling items that carry a Project Ebonhold affix. Min iLvl sets the floor: affix items at that item level or higher are protected, lower ones can still be sold." },
					{ icon = "Interface\\Icons\\Spell_Nature_WispSplode", title = "Affix Display", body = "Show affix dot marks affix items in your bags, colored by tier, with gold meaning an affix you have not learned. Only missing affixes narrows the dot to unlearned affixes and protects them." },
					{ icon = "Interface\\Icons\\INV_Misc_Spyglass_02", title = "Affix Tools", body = "Audit Lists checks your Delete and Sell lists for affix items and prints what it finds without changing anything. Scan Learned Affixes refreshes and lists every affix you own by tier." },
				}
			},
			{
				label = "Invites",
				title = "Invites",
				sections = {
					{ icon = "Interface\\Icons\\INV_Misc_GroupLooking", title = "Auto-Invite", body = "When someone whispers one of your Keywords, you invite them to your group. You must be the leader or a raid assistant. Set the Keywords first, then turn the toggle on." },
					{ icon = "Interface\\Icons\\INV_Misc_Dice_01", title = "Apply loot rule", body = "After an auto-invite, sets the party loot rule to the one you pick in the dropdown. Leave it off when a raid lead or another addon controls loot." },
					{ icon = "Interface\\Icons\\Ability_Warrior_BattleShout", title = "Convert to raid when full", body = "When the sixth player joins, the party becomes a raid automatically. Leave it off for normal five-person parties." },
				}
			},
			{
				label = "Filters",
				title = "Filters",
				sections = {
					{ icon = "Interface\\Icons\\INV_Broom_01", title = "Auto Actions", body = "Sets Junk, Common, and Greens each to Del or Sell, or leaves them off. |cffbf3838Del deletes matching items on bag scans|r, Sell vendors them. Keep-list and quest items are always safe." },
					{ icon = "Interface\\Icons\\INV_Enchant_ShardGlimmering", title = "DE Filters", body = "Controls which items One-Key Disenchant will target, by bind state (BoP, BoE), quality (Unc, Rare, Epic), and the iLvl range. It does not touch your Delete, Sell, or Keep lists." },
					{ icon = "Interface\\Icons\\Spell_Shadow_DetectInvisibility", title = "Ignored Items", body = "Manage Ignored opens the list of items you marked Ignore on the Keep-list popup. Ignore only hides an item from Process Bags, it is not protection from cleanup." },
				}
			},
			{
				label = "Keybinds",
				title = "Keybinds",
				sections = {
					{ icon = "Interface\\Icons\\INV_Box_01", title = "One-Key Open", body = "Binds one key to open the next clam, coin purse, or egg in your bags. Locked boxes are skipped until you can pick the lock." },
					{ icon = "Interface\\Icons\\INV_Enchant_Disenchant", title = "One-Key Disenchant", body = "Binds one key to disenchant your next eligible item. Needs the Enchanting profession. Pick which items count under DE Filters on the Filters tab." },
					{ icon = "Interface\\Icons\\INV_Inscription_Tradeskill01", title = "One-Key Mill", body = "Binds one key to mill the next stack of at least five herbs. Needs the Inscription profession." },
					{ icon = "Interface\\Icons\\INV_Misc_Gem_01", title = "One-Key Prospect", body = "Binds one key to prospect the next stack of at least five ore. Needs the Jewelcrafting profession." },
				}
			},
			{
				label = "Tracking",
				title = "Tracking",
				sections = {
					{ icon = "Interface\\Icons\\INV_Misc_Coin_01", title = "Gold Earned", body = "Total gold from auto-selling, shown in two columns: SESSION since your last login and LIFETIME for this character overall." },
					{ icon = "Interface\\Icons\\INV_Misc_Coin_06", title = "Items Sold", body = "How many items AutoDelete has vendored for you, counted for the session and for this character lifetime." },
					{ icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", title = "Items Deleted", body = "How many items AutoDelete has destroyed on bag scans, for the session and lifetime." },
					{ icon = "Interface\\Icons\\INV_Hammer_20", title = "Repairs", body = "How many times Auto-Repair has fixed your gear at a vendor." },
					{ icon = "Interface\\Icons\\Trade_BlackSmithing", title = "Repair Spend", body = "Total gold Auto-Repair has spent keeping your gear repaired." },
					{ icon = "Interface\\Icons\\INV_Misc_Bag_08", title = "Inventory Avg", body = "The average gold value of your bags over time, a rough sense of how much you are carrying." },
					{ icon = "Interface\\Icons\\Spell_ChargeNegative", title = "Reset Stats", destructive = true, body = "Clears every counter above for this character. This cannot be undone, so note any totals you want to keep before you confirm." },
				}
			},
			{
				label = "Profiles",
				title = "Profiles",
				sections = {
					{ icon = "Interface\\Icons\\INV_Misc_Book_09", title = "Current profile", body = "The dropdown lists every character profile, including the one you are on now, and the Current line shows the active character. Copy, Delete, and Import Lists all act on the profile picked here." },
					{ icon = "Interface\\Icons\\INV_Misc_Note_05", title = "Copy", body = "Copies the selected profile full AutoDelete setup onto this character. |cffbf3838It overwrites your current settings and lists|r, so review Sell, Delete, and Affix rules afterward." },
					{ icon = "Interface\\Icons\\Ability_Creature_Cursed_05", title = "Delete", destructive = true, body = "Deletes the profile selected in the dropdown. This cannot be undone. It does not touch the character you are currently playing." },
					{ icon = "Interface\\Icons\\INV_Misc_Note_06", title = "Import Lists", body = "Merges only the Delete, Sell, and Keep lists from the selected profile into this one. Toggles, scan speed, and filters are left alone. Conflicts open a review window." },
					{ icon = "Interface\\Icons\\Spell_Holy_Purify", title = "Clear List", destructive = true, body = "Opens a picker to wipe one list, or all three, on the current character. Clearing a list cannot be undone." },
					{ icon = "Interface\\Icons\\INV_Scroll_03", title = "Import Raw", body = "Paste plain item names and AutoDelete looks each one up and adds it to the Delete, Sell, or Keep list you choose. Check the names first, a large paste changes many entries at once." },
					{ icon = "Interface\\Icons\\INV_Scroll_08", title = "Export Raw", body = "Copies your Delete, Sell, or Keep list out as plain item names so you can share them or paste them elsewhere. It only reads your lists, it changes nothing." },
				}
			},
			{
				label = "Sell Filters",
				title = "Sell Filters",
				sections = {
					{ icon = "Interface\\Icons\\INV_Chest_Chain", title = "BoE Armor", body = "Sells Bind-on-Equip armor and accessories that match the Rare and Epic toggles and the iLvl range on the card. Weapons belong to BoE Weapons. Keep-list and quest items stay safe." },
					{ icon = "Interface\\Icons\\INV_Helmet_06", title = "BoP", body = "Sells Bind-on-Pickup gear in any slot, including weapons, that matches the Rare and Epic toggles and the iLvl range. Keep-list and quest items stay safe." },
					{ icon = "Interface\\Icons\\INV_Sword_27", title = "BoE Weapons", body = "Sells Bind-on-Equip weapons, shields, ranged, thrown, and relics in range. It wins over BoE Armor when an item could fit both. Use Why? if a sale surprises you." },
				}
			},
			{
				label = "Lists",
				title = "Lists",
				sections = {
					{ icon = "Interface\\Icons\\Spell_Shadow_DeathCoil", title = "Delete", destructive = true, body = "The Delete list. Items whose ID matches are destroyed on the next bag scan, so add with care and test one safe item first. Entries match by item ID, so heroic and normal versions stay separate." },
					{ icon = "Interface\\Icons\\INV_Misc_Coin_02", title = "Sell", body = "The Sell list. Matching items are vendored when a merchant is open, not during normal bag use. Good for known vendor trash and surplus." },
					{ icon = "Interface\\Icons\\INV_Misc_Key_03", title = "Keep", body = "The Keep list, your protection list. Anything here wins over every automatic rule, so add important items before turning on broad delete or sell actions." },
					{ icon = "Interface\\Icons\\INV_Misc_Spyglass_03", title = "Search & Manage", body = "Below the tabs, Search items filters the current list, Raw shows the plain stored text, and Refresh rebuilds the view. Drag a bag item onto the Delete, Sell, or Keep tab to add it." },
				}
			},
			{
				label = "Bag Features",
				title = "Bag Features",
				sections = {
					{ icon = "Interface\\Icons\\INV_Misc_Bag_09", title = "Drag to Delete, Sell, or Keep", body = "Drag a real bag item onto the Delete, Sell, or Keep tab to add it to that list. An empty list also shows a Drag items here hint." },
					{ icon = "Interface\\Icons\\INV_Misc_Gear_02", title = "Alt+Right-click menu", body = "Alt+Right-click a real bag item to open the AutoDelete quick menu, with Keep, Sell, |cffbf3838Delete|r, and Why?. Picking Delete adds the item to the Delete list." },
					{ icon = "Interface\\Icons\\INV_Misc_Food_15", title = "Normal right-click", body = "Plain right-click still belongs to WoW and your bag addon for eating, drinking, equipping, and using items. AutoDelete only acts on Alt+Right-click. |cffbf3838If a plain right-click ever stops working, that is a bug, not intended.|r" },
				}
			},
			{
				label = "Process Bags",
				title = "Process Bags",
				sections = {
					{ icon = "Interface\\Icons\\INV_Misc_Bag_07", title = "Process Bags window", body = "A separate panel listing every bag item ready for One-Key Disenchant, Mill, Prospect, or Open, with an Item column and an Action column. An empty list means nothing matched right now." },
					{ icon = "Interface\\Icons\\Ability_Hunter_MasterMarksman", title = "Left-click a row", body = "Left-click a row to arm that item as the next target for its matching keybind. Read the row once more before you press the key." },
					{ icon = "Interface\\Icons\\Trade_Engineering", title = "Right-click a row", body = "Right-click a row to open Keep, Sell, |cffbf3838Delete|r, Ignore for Process, and Why?. This menu only appears inside the Process Bags list." },
					{ icon = "Interface\\Icons\\INV_Misc_Blindfold_01", title = "Ignore for Process", body = "Stops an item from showing in Process Bags on this character. It is not protection: use Keep if the item needs to be safe from cleanup rules." },
					{ icon = "Interface\\Icons\\INV_Misc_QuestionMark", title = "Why?", body = "Explains why an item is kept, sold, deleted, dotted, or skipped. The report shows list membership, item facts, affix protection, and any matched process action." },
				}
			},
		}

		-- Centered 3x4 grid of topic buttons inside helpBox (the tab content
		-- area, 538 wide, minus its 4px top/bottom inset = 92 tall). Uniform
		-- gaps and even margins, with the block centered so it no longer hugs
		-- the top edge.
		local helpContentW = CONTENT_W - TAB_INNER_PAD * 2
		local helpContentH = CONTENT_AREA_H - 8
		local gap = 6
		local btnH = 16
		local btnW = math.floor((helpContentW - gap * 2 - 12) / 3)
		local blockW = btnW * 3 + gap * 2
		local blockH = btnH * 4 + gap * 3
		local startX = math.floor((helpContentW - blockW) / 2)
		local startY = math.floor((helpContentH - blockH) / 2)
		for i, topic in ipairs(topics) do
			local col = (i - 1) % 3
			local row = math.floor((i - 1) / 3)
			local btn = MakeActionButton(helpBox, topic.label, C_BLUE, function()
				if _G.AutoDelete_ShowHelpTopicWindow then
					_G.AutoDelete_ShowHelpTopicWindow(topic.title, topic.sections)
				end
			end, btnW, btnH)
			btn:SetPoint("TOPLEFT", startX + col * (btnW + gap), -startY - row * (btnH + gap))
		end
	end

	-- ========================================================================
	-- GOBLIN TAB: 3 cards (Auto-Repair, Summon Scavenger, Hide Greedy Spam)
	-- Same card dimensions as General tab (3 cards, 2 gaps inside genContentW).
	-- Each card's main toggle sits at top; sub-toggles stack below at reduced size.
	-- ========================================================================
	local goblinPage = tabPages.goblin

	-- MakeSubToggle was promoted to file scope (see top of file). BuildUI's
	-- callers below resolve to that upvalue.

	local function MakeGoblinCard(xOff)
		local card = CreateFrame("Frame", nil, goblinPage)
		card:SetSize(cardW, cardH)
		card:SetPoint("TOPLEFT", xOff, -4)
		-- v3.21 §6.3: shared inner-card pattern via ApplyBackdrop + constants.
		ApplyBackdrop(card, C_CARD_BG, C_CARD_BORDER)
		return card
	end

	local gCard1 = MakeGoblinCard(0)
	local gCard2 = MakeGoblinCard(cardW + CARD_GAP)
	local gCard3 = MakeGoblinCard((cardW + CARD_GAP) * 2)

	-- Sub-toggle indent shared by Scavenger and Bag Warning rows below.
	-- Lines up the sub-toggle's checkbox with the parent toggle's label text:
	-- parent x=10, parent box=14, gap=8 -> text starts at 32.
	local SUBTGL_INDENT = CARD_INNER_PAD_X + 14 + 8   -- 32

	-- CARD 1 (Pets, was Goblin's Scavenger card): master Summon Scavenger
	-- toggle + 3 sub-toggles. Moved here from the old Goblin Card 2 so the
	-- Scavenger pet feature lives in the leftmost slot of the Pets tab.
	local tglScav = MakeToggle(gCard1, "Summon Scavenger", C_ACCENT,
		"Manages your Greedy Scavenger pet. Brings it back when it gets stuck or after you mount up. Use the sub-toggles below to pick when to summon.")
	tglScav:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -CARD_INNER_PAD_Y)
	tglScav:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglScav = tglScav

	local tglScavAfterSell = MakeSubToggle(gCard1, "After sell", C_DK_RED)
	tglScavAfterSell:SetPoint("TOPLEFT", SUBTGL_INDENT, -(CARD_INNER_PAD_Y + 20))
	tglScavAfterSell:SetWidth(cardW - SUBTGL_INDENT - CARD_INNER_PAD_X)
	self._tglScavAfterSell = tglScavAfterSell

	local tglScavAfterClose = MakeSubToggle(gCard1, "After vendor close", C_DK_RED)
	tglScavAfterClose:SetPoint("TOPLEFT", SUBTGL_INDENT, -(CARD_INNER_PAD_Y + 36))
	tglScavAfterClose:SetWidth(cardW - SUBTGL_INDENT - CARD_INNER_PAD_X)
	self._tglScavAfterClose = tglScavAfterClose

	local tglScavOnlyInCombat = MakeSubToggle(gCard1, "Only in Combat", C_DK_RED)
	tglScavOnlyInCombat:SetPoint("TOPLEFT", SUBTGL_INDENT, -(CARD_INNER_PAD_Y + 52))
	tglScavOnlyInCombat:SetWidth(cardW - SUBTGL_INDENT - CARD_INNER_PAD_X)
	self._tglScavOnlyInCombat = tglScavOnlyInCombat

	-- CARD 2 (Pets): Summon Goblin Merchant. Moved here from the old Card 3
	-- so Scavenger and Merchant sit adjacent. Gated by the Summon Scavenger
	-- master + the AutoDelete master Enable.
	-- Label is "Summon Merchant" (not "Summon Goblin Merchant"): the full
	-- name truncated on the ~175px card width. Tooltip still names the
	-- Goblin Merchant explicitly.
	local tglSummonMerchant = MakeToggle(gCard2, "Summon Merchant", C_ACCENT,
		"Summons your Goblin Merchant when your bags stay full for 2 seconds. Target the merchant and press your Interact key to open the shop.")
	tglSummonMerchant:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -CARD_INNER_PAD_Y)
	tglSummonMerchant:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	AddToggleDescription(tglSummonMerchant,
		"Summons the Goblin Merchant when bags are full.",
		cardW - CARD_INNER_PAD_X * 2 - 26)
	self._tglSummonMerchant = tglSummonMerchant

	-- CARD 3 (Pets): Bag Warning + Hide Greedy Spam. Two notification-style
	-- toggles. Bag Warning fires a chat line when free slots fall below the
	-- threshold (one-shot per low cycle). Hide Greedy Spam suppresses the
	-- Scavenger's chat / speech-bubble strings. Threshold here also gates
	-- the chat notification only; Goblin Merchant summon triggers at zero
	-- free slots independently.
	local tglBagSpaceWarn = MakeToggle(gCard3, "Bag warning", C_ACCENT,
		"Tells you in chat when your free bag slots drop to the number below. Only warns once until your bags fill up again.")
	tglBagSpaceWarn:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -CARD_INNER_PAD_Y)
	tglBagSpaceWarn:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglBagSpaceWarn = tglBagSpaceWarn

	-- Threshold row beneath the Bag warning toggle. Small EditBox + label.
	local thresholdRow = CreateFrame("Frame", nil, gCard3)
	thresholdRow:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	thresholdRow:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 22))

	local thresholdLabel = thresholdRow:CreateFontString(nil, "OVERLAY")
	thresholdLabel:SetFont(FONT, 10, "OUTLINE")
	thresholdLabel:SetTextColor(unpack(C_DIM))
	thresholdLabel:SetPoint("LEFT", thresholdRow, "LEFT", 0, 0)
	thresholdLabel:SetText("Free slots:")

	local thresholdBox = CreateFrame("Frame", nil, thresholdRow)
	thresholdBox:SetSize(44, 20)
	thresholdBox:SetPoint("RIGHT", thresholdRow, "RIGHT", 0, 0)
	ApplyBackdrop(thresholdBox, C_DROP_BG, C_DROP_BORDER)
	local thresholdEdit = CreateFrame("EditBox", nil, thresholdBox)
	thresholdEdit:SetFont(FONT, 10, "OUTLINE")
	thresholdEdit:SetTextColor(unpack(C_TEXT))
	thresholdEdit:SetAutoFocus(false)
	thresholdEdit:SetNumeric(true)
	thresholdEdit:SetMaxLetters(3)
	thresholdEdit:SetPoint("TOPLEFT", 4, -1)
	thresholdEdit:SetPoint("BOTTOMRIGHT", -4, 1)
	thresholdEdit:SetJustifyH("CENTER")
	thresholdEdit:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
	thresholdEdit:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
	thresholdEdit:SetScript("OnEditFocusLost", function(s)
		local val = tonumber(s:GetText()) or 5
		if val < 0 then val = 0 end
		if val > 100 then val = 100 end
		s:SetText(tostring(val))
		local p = GetActiveProfile(db)
		p.bagSpaceWarnThreshold = val
		if _G.AutoDelete_RefreshCachedProfile then _G.AutoDelete_RefreshCachedProfile() end
	end)
	self._bagSpaceWarnEdit = thresholdEdit

	-- Hide Greedy Spam at the bottom of card 3. Compact toggle, no
	-- sub-description.
	local tglHideSpam = MakeToggle(gCard3, "Hide Greedy Spam", C_ACCENT,
		"Hides Greedy Scavenger's chat messages and speech bubbles.")
	tglHideSpam:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -(CARD_INNER_PAD_Y + 48))
	tglHideSpam:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglHideSpam = tglHideSpam

	-- ========================================================================
	-- FILTERS TAB (internal key "tools" -- kept stable for SV migration):
	--   Card 1: Auto Actions        (Del/Sell per quality)
	--   Card 2: (DE Filters -- ported from popup, v3.20 work-in-progress)
	--   Card 3: (Manage Ignored Items button -- v3.20 work-in-progress)
	--
	-- Affix Protection + Affix Display moved out to the AFFIX TAB below
	-- (v3.20). The Filters tab still owns Auto Actions and will host the
	-- DE Filters card + the Manage Ignored Items entrypoint once those
	-- land in the same release. For now Cards 2 and 3 are placeholders
	-- so the tab content area isn't visually empty after the move.
	-- ========================================================================
	local toolsPage = tabPages.tools

	local function MakeToolsCard(xOff)
		local card = CreateFrame("Frame", nil, toolsPage)
		card:SetSize(cardW, cardH)
		card:SetPoint("TOPLEFT", xOff, -4)
		-- v3.21 §6.3: shared inner-card pattern via ApplyBackdrop + constants.
		ApplyBackdrop(card, C_CARD_BG, C_CARD_BORDER)
		return card
	end

	local tCard1 = MakeToolsCard(0)
	local tCard2 = MakeToolsCard(cardW + CARD_GAP)
	local tCard3 = MakeToolsCard((cardW + CARD_GAP) * 2)
	-- tCard1: Auto Actions, tCard2: DE Filters, tCard3: Ignored Items
	-- (button opens the scrollable Manage Ignored Items popup). All three
	-- populated in the blocks below.

	-- ========================================================================
	-- Filters Card 2: DE Filters (v3.20).
	-- Ported inline from the standalone Disenchant Filters popup (which used
	-- to be opened by a gear button on the Keybinds tab -- both the gear
	-- button and the popup are gone in v3.20). Same controls, same profile
	-- fields, same handlers: BoP / BoE bind-state toggles, Unc / Rare / Epic
	-- quality toggles, iLvl min/max boxes. Wrapped in `do ... end` so the
	-- card-internal locals don't bump BuildUI past Lua 5.1's 200-local cap
	-- (the toggles + edit boxes are stored on self._tglDisenchant* and
	-- self._editDisenchantIlvl* for Refresh()'s state restore).
	-- ========================================================================
	do
		local card2Title = MakeText(tCard2, 11, C_ACCENT, "OUTLINE")
		card2Title:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -6)
		card2Title:SetText("DE Filters")

		-- Row 1 (y=-24): BoP + BoE bind-state toggles, side by side.
		-- C_ACCENT (orange) matches the popup's prior convention for these.
		local BIND_TGL_W = 60
		local tglDeBoP = MakeSubToggle(tCard2, "BoP", C_ACCENT)
		tglDeBoP:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -24)
		tglDeBoP:SetWidth(BIND_TGL_W)

		local tglDeBoE = MakeSubToggle(tCard2, "BoE", C_ACCENT)
		tglDeBoE:SetPoint("TOPLEFT", CARD_INNER_PAD_X + BIND_TGL_W + 8, -24)
		tglDeBoE:SetWidth(BIND_TGL_W)

		-- Row 2 (y=-46): Unc / Rare / Epic quality toggles, three across.
		-- WoW item-quality colors so the checked fill communicates the
		-- rarity tier at a glance (matches the popup's prior convention).
		local QUAL_TGL_W = 48
		local tglDeUnc = MakeSubToggle(tCard2, "Unc", C_Q_UNCOMMON)
		tglDeUnc:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -46)
		tglDeUnc:SetWidth(QUAL_TGL_W)

		local tglDeRare = MakeSubToggle(tCard2, "Rare", C_Q_RARE)
		tglDeRare:SetPoint("TOPLEFT", CARD_INNER_PAD_X + QUAL_TGL_W + 4, -46)
		tglDeRare:SetWidth(QUAL_TGL_W)

		local tglDeEpic = MakeSubToggle(tCard2, "Epic", C_Q_EPIC)
		tglDeEpic:SetPoint("TOPLEFT", CARD_INNER_PAD_X + (QUAL_TGL_W + 4) * 2, -46)
		tglDeEpic:SetWidth(QUAL_TGL_W)

		-- Row 3 (y=-70): iLvl label + min box + dash + max box. Compact
		-- horizontal layout fits inside the 155px content width.
		local ilvlLabel = MakeText(tCard2, 10, C_DIM, "OUTLINE")
		ilvlLabel:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -70)
		ilvlLabel:SetText("iLvl:")

		local function MakeIlvlBox(xOff)
			local frame = CreateFrame("Frame", nil, tCard2)
			frame:SetSize(38, 18)
			frame:SetPoint("TOPLEFT", xOff, -68)
			ApplyBackdrop(frame, C_DROP_BG, C_DROP_BORDER)
			local edit = CreateFrame("EditBox", nil, frame)
			edit:SetFont(FONT, 10, "OUTLINE")
			edit:SetTextColor(unpack(C_TEXT))
			edit:SetAutoFocus(false)
			edit:SetNumeric(true)
			edit:SetMaxLetters(4)
			edit:SetPoint("TOPLEFT", 3, -1)
			edit:SetPoint("BOTTOMRIGHT", -3, 1)
			edit:SetJustifyH("CENTER")
			edit:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
			edit:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
			return edit
		end
		local ilvlMinEdit = MakeIlvlBox(CARD_INNER_PAD_X + 28)
		local ilvlDash = MakeText(tCard2, 10, C_DIM, "OUTLINE")
		ilvlDash:SetPoint("TOPLEFT", CARD_INNER_PAD_X + 28 + 40, -71)
		ilvlDash:SetText("-")
		local ilvlMaxEdit = MakeIlvlBox(CARD_INNER_PAD_X + 28 + 48)

		-- Toggle handler: writes the profile boolean, refreshes the cached
		-- profile, re-arms the secure button. Same logic the prior popup
		-- handler used (see MakeFilterHandler in the Disenchant Filters
		-- Popup block at file scope -- now orphaned but kept for one
		-- release cycle as a safety net).
		local function MakeDeToggleHandler(field)
			return function(btn)
				btn._checked = not btn._checked
				btn:SetChecked(btn._checked)
				GetActiveProfile(db)[field] = btn._checked
				if _G.AutoDelete_RefreshCachedProfile then _G.AutoDelete_RefreshCachedProfile() end
				if _G.AutoDelete_UpdateDisenchantButton then _G.AutoDelete_UpdateDisenchantButton() end
			end
		end
		tglDeBoP:SetScript("OnClick",  MakeDeToggleHandler("disenchantBoP"))
		tglDeBoE:SetScript("OnClick",  MakeDeToggleHandler("disenchantBoE"))
		tglDeUnc:SetScript("OnClick",  MakeDeToggleHandler("disenchantUncommon"))
		tglDeRare:SetScript("OnClick", MakeDeToggleHandler("disenchantRare"))
		tglDeEpic:SetScript("OnClick", MakeDeToggleHandler("disenchantEpic"))

		local function MakeDeIlvlHandler(field)
			return function(s)
				local val = tonumber(s:GetText()) or 0
				if val < 0 then val = 0 end
				s:SetText(tostring(val))
				GetActiveProfile(db)[field] = val
				if _G.AutoDelete_RefreshCachedProfile then _G.AutoDelete_RefreshCachedProfile() end
				if _G.AutoDelete_UpdateDisenchantButton then _G.AutoDelete_UpdateDisenchantButton() end
			end
		end
		ilvlMinEdit:SetScript("OnEditFocusLost", MakeDeIlvlHandler("disenchantIlvlMin"))
		ilvlMaxEdit:SetScript("OnEditFocusLost", MakeDeIlvlHandler("disenchantIlvlMax"))

		-- Store on self for Refresh()'s state-restore pass (added below).
		self._tglDisenchantBoP      = tglDeBoP
		self._tglDisenchantBoE      = tglDeBoE
		self._tglDisenchantUnc      = tglDeUnc
		self._tglDisenchantRare     = tglDeRare
		self._tglDisenchantEpic     = tglDeEpic
		self._editDisenchantIlvlMin = ilvlMinEdit
		self._editDisenchantIlvlMax = ilvlMaxEdit
	end

	-- ========================================================================
	-- Filters Card 3: Ignored Items (v3.20).
	-- Single-button card: opens the Manage Ignored Items popup which lists
	-- every (action, itemId) pair the user clicked Ignore on via the
	-- Keep-list override popup. Per-row Unignore button in that popup lets
	-- them undo the choice. Same y=-68 bottom-of-card slot as the Audit
	-- Lists / Scan Learned Affixes buttons on the Affix tab for visual
	-- alignment.
	-- ========================================================================
	do
		local card3Title = MakeText(tCard3, 11, C_ACCENT, "OUTLINE")
		card3Title:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -6)
		card3Title:SetText("Ignored Items")

		-- Hint text explains what lands in the list and why a player would
		-- want to open the manager. Two short wrapped lines.
		local hint = MakeText(tCard3, 9, C_DIM)
		hint:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -24)
		hint:SetWidth(cardW - CARD_INNER_PAD_X * 2)
		hint:SetJustifyH("LEFT")
		hint:SetWordWrap(true)
		hint:SetNonSpaceWrap(false)
		hint:SetText("Items you marked Ignore on the Keep-list popup land here. Open the list to unignore them.")

		local manageBtn = MakeActionButton(tCard3, "Manage Ignored", C_BLUE, function()
			if _G.AutoDelete_ShowIgnoredItemsWindow then
				_G.AutoDelete_ShowIgnoredItemsWindow()
			end
		end, cardW - CARD_INNER_PAD_X * 2, 20)
		manageBtn:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -68)
		manageBtn:SetScript("OnEnter", function(btn)
			btn:SetBackdropColor(C_BLUE[1], C_BLUE[2], C_BLUE[3], 0.3)
			btn:SetBackdropBorderColor(C_BLUE[1], C_BLUE[2], C_BLUE[3], 1)
			btn._text:SetTextColor(1, 1, 1)
			GameTooltip:SetOwner(btn, "ANCHOR_TOP")
			GameTooltip:SetText("Manage Ignored Items", 1, 1, 1)
			GameTooltip:AddLine("Opens a window listing every item you have set to Ignore. Click the X next to an item to stop ignoring it.",
				C_DIM[1], C_DIM[2], C_DIM[3], true)
			GameTooltip:Show()
		end)
		manageBtn:SetScript("OnLeave", function(btn)
			ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
			btn._text:SetTextColor(unpack(C_TEXT))
			GameTooltip:Hide()
		end)
	end

	-- ========================================================================
	-- AFFIX TAB (internal key "affix", v3.20):
	--   Card 1: Affix Protection    (No Auto-Sell + Min iLvl)
	--   Card 2: Affix Display       (Show affix dot + Only missing affixes)
	--   Card 3: Affix Tools         (Audit Lists + Scan Learned Affixes)
	-- User feedback 2026-05-23: Cards 1 and 2 were too crowded with both
	-- toggles AND their action button each, so the two buttons moved to a
	-- dedicated Card 3.
	-- ========================================================================
	local affixPage = tabPages.affix

	local function MakeAffixCard(xOff)
		local card = CreateFrame("Frame", nil, affixPage)
		card:SetSize(cardW, cardH)
		card:SetPoint("TOPLEFT", xOff, -4)
		-- v3.21 §6.3: shared inner-card pattern via ApplyBackdrop + constants.
		ApplyBackdrop(card, C_CARD_BG, C_CARD_BORDER)
		return card
	end

	local aCard1 = MakeAffixCard(0)
	local aCard2 = MakeAffixCard(cardW + CARD_GAP)
	local aCard3 = MakeAffixCard((cardW + CARD_GAP) * 2)

	-- Filters Card 1: Auto Actions. Each quality (Junk / Common / Greens)
	-- is an independent segmented control showing Del / Sell pills (Greens
	-- shows Sell only -- deleting greens by quality is rarely the intended
	-- outcome; if a user wants that they can put a specific green on the
	-- Delete list explicitly). The default state for every row is "off"
	-- (no pill highlighted). Clicking a pill activates that action;
	-- clicking the active pill again deselects (back to off). Colors
	-- follow the semantic palette: red for delete, blue for sell.
	-- Migration from the old three-checkbox layout (autoGray /
	-- autoDeleteCommon / autoSellGreens booleans) runs at PLAYER_LOGIN
	-- in RunDBMigrations v3. v4 normalizes any legacy
	-- qualityActionGreens=="delete" back to "off" since Greens has no
	-- Delete pill in this UI -- without the migration the stored "delete"
	-- would render as no-pill-active (visually equivalent to off), but
	-- it's cleaner to normalize the data than leave the gotcha lying.
	--
	-- Wrapped in `do ... end` so the per-state tables, helper, and three
	-- pill locals don't bump BuildUI past Lua 5.1's 200-local cap. The
	-- segmented controls themselves survive on self._pillJunk/_pillCommon/
	-- _pillGreens for state restore in Refresh and the OnClick handlers
	-- below.
	do
	local card1Title = MakeText(tCard1, 11, C_ACCENT, "OUTLINE")
	card1Title:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -6)
	card1Title:SetText("Auto Actions")

	-- State definitions. Active appearance only; the segmented control
	-- paints inactive segments with its own neutral-gray treatment so the
	-- "all gray until you click one" visual works automatically. Labels
	-- stay short because segments are narrow. 3-color semantic palette
	-- HARD RULE (conventions §11): C_RED for destructive, C_BLUE for
	-- transformational.
	local QSTATE_DEL = {
		value = "delete",
		label = "Del",
		tooltip = "Auto-deletes items of this quality. Click again to turn off. Keep-list items, quest items, shirts, and tabards are safe.",
		bg     = { C_RED[1], C_RED[2], C_RED[3], 0.85 },
		border = C_RED,
		fg     = { 1, 1, 1, 1 },
	}
	local QSTATE_SELL = {
		value = "sell",
		label = "Sell",
		tooltip = "Auto-sells items of this quality at vendors. Click again to turn off. Keep-list items and quest items are safe.",
		bg     = { C_BLUE[1], C_BLUE[2], C_BLUE[3], 0.85 },
		border = C_BLUE,
		fg     = { 1, 1, 1, 1 },
	}
	local QUALITY_STATES_DEL_SELL  = { QSTATE_DEL, QSTATE_SELL }

	-- Helper that builds one row inside the card: [label LEFT, segments RIGHT].
	-- Returns the segmented control so BuildUI can wire up state restore.
	-- Profile-field arg is captured by the OnChange closure so a single
	-- helper covers all three rows without per-row glue code.
	--
	-- Per-segment width is fixed (SEG_W) -- both 2-segment and 1-segment
	-- rows use the same pill size. The control's total width grows with
	-- segment count, and since each row anchors its RIGHT edge to the same
	-- card boundary, the rightmost pill (Sell) always lines up vertically
	-- across rows.
	local SEG_W = 42
	local SEG_H = 18
	local function MakeQualityRow(label, profileField, states, tooltip, y)
		local txt = MakeText(tCard1, 10, C_TEXT, "OUTLINE")
		txt:SetPoint("LEFT", tCard1, "TOPLEFT", CARD_INNER_PAD_X, y - SEG_H/2)
		txt:SetText(label)
		local seg = MakeSegmentedControl(tCard1, SEG_W, SEG_H, states, "off", function(newValue)
			-- Write the new value to the active profile and refresh the
			-- cached-profile upvalue used by the hot path. No bag refresh
			-- needed -- the next DeleteItems / SellItems tick reads the
			-- new value naturally.
			GetActiveProfile(GetDB())[profileField] = newValue
			if _G.AutoDelete_RefreshCachedProfile then
				_G.AutoDelete_RefreshCachedProfile()
			end
		end)
		seg:SetPoint("RIGHT", tCard1, "TOPRIGHT", -CARD_INNER_PAD_X, y - SEG_H/2)
		-- Tooltip on the label-side area (hover the row label for an
		-- explanation of what the quality covers; segments have their own
		-- per-action tooltips wired inside MakeSegmentedControl).
		local tipFrame = CreateFrame("Frame", nil, tCard1)
		tipFrame:SetPoint("TOPLEFT", txt, "TOPLEFT", 0, 0)
		tipFrame:SetPoint("BOTTOMRIGHT", seg, "BOTTOMLEFT", -4, 0)
		tipFrame:EnableMouse(true)
		tipFrame:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(label, 1, 1, 1)
			GameTooltip:AddLine(tooltip, C_DIM[1], C_DIM[2], C_DIM[3], true)
			GameTooltip:Show()
		end)
		tipFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return seg
	end

	-- Three rows, anchored at the standard CARD_ROW1/2/3 y-positions so
	-- they line up with widgets on Cards 2 and 3 (uniformity rule).
	local pillJunk = MakeQualityRow(
		"Junk",
		"qualityActionJunk",
		QUALITY_STATES_DEL_SELL,
		"Gray-quality (poor) items. Quest items, shirts, tabards, and Keep-list items are always safe.",
		-24)
	self._pillJunk = pillJunk

	local pillCommon = MakeQualityRow(
		"Common",
		"qualityActionCommon",
		QUALITY_STATES_DEL_SELL,
		"White-quality gear only. Reagents, consumables, quest items, and Keep-list items are always safe.",
		-46)
	self._pillCommon = pillCommon

	local pillGreens = MakeQualityRow(
		"Greens",
		"qualityActionGreens",
		QUALITY_STATES_DEL_SELL,
		"Green-quality (uncommon) gear -- armor, weapons, rings, necks, trinkets, all armor slots. Reagents, consumables, bags, quest items, and Keep-list items are safe.",
		-68)
	self._pillGreens = pillGreens
	end  -- /Filters Card 1: Auto Actions

	-- Affix Tab Card 1: Affix Protection (moved from Filters tab in v3.20).
	-- Layout:
	--   y=-6   title
	--   y=-24  No Auto-Sell toggle (only one toggle now -- the No Auto-Delete
	--          one was dropped because Auto-Delete Junk/Common never fire on
	--          Rare/Epic gear, which is the only quality range affixes
	--          appear on; the toggle protected nothing in practice)
	--   y=-46  Min iLvl row (label + input)
	--   y=-70  Audit Lists button (scans Delete + Sell lists for affixed
	--          items and prints a chat report)
	local card2Title = MakeText(aCard1, 11, C_ACCENT, "OUTLINE")
	card2Title:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -6)
	card2Title:SetText("Affix Protection")

	local tglProtectAffixFromSell = MakeToggle(aCard1, "No Auto-Sell", C_ACCENT,
		"Stops Auto-Sell from selling items with a Project Ebonhold affix. Low-iLvl affix items below the number on the next row can still be sold.")
	tglProtectAffixFromSell:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -24)
	tglProtectAffixFromSell:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	self._tglProtectAffixFromSell = tglProtectAffixFromSell

	-- Min iLvl row: label LEFT, small input RIGHT, same row.
	local affixFloorRow = CreateFrame("Frame", nil, aCard1)
	affixFloorRow:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
	affixFloorRow:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -46)

	local affixFloorLabel = affixFloorRow:CreateFontString(nil, "OVERLAY")
	affixFloorLabel:SetFont(FONT, 10, "OUTLINE")
	affixFloorLabel:SetTextColor(unpack(C_DIM))
	affixFloorLabel:SetPoint("LEFT", affixFloorRow, "LEFT", 0, 0)
	affixFloorLabel:SetText("Min iLvl:")

	-- Tooltip hook on the row so hovering either the label or empty area
	-- explains what the value does. Same text mirrored on the input box
	-- below so hovering the editbox surface also shows the tip.
	local AFFIX_FLOOR_TOOLTIP_TITLE = "Min iLvl"
	local AFFIX_FLOOR_TOOLTIP_BODY  = "Affix items at this iLvl or higher are protected. Lower iLvl affix items can still be sold or deleted normally. Set to 0 to protect every affix item."
	affixFloorRow:EnableMouse(true)
	affixFloorRow:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(AFFIX_FLOOR_TOOLTIP_TITLE, 1, 1, 1)
		GameTooltip:AddLine(AFFIX_FLOOR_TOOLTIP_BODY, C_DIM[1], C_DIM[2], C_DIM[3], true)
		GameTooltip:Show()
	end)
	affixFloorRow:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local affixFloorBox = CreateFrame("Frame", nil, affixFloorRow)
	affixFloorBox:SetSize(44, 20)
	affixFloorBox:SetPoint("RIGHT", affixFloorRow, "RIGHT", 0, 0)
	ApplyBackdrop(affixFloorBox, C_DROP_BG, C_DROP_BORDER)
	affixFloorBox:EnableMouse(true)
	affixFloorBox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(AFFIX_FLOOR_TOOLTIP_TITLE, 1, 1, 1)
		GameTooltip:AddLine(AFFIX_FLOOR_TOOLTIP_BODY, C_DIM[1], C_DIM[2], C_DIM[3], true)
		GameTooltip:Show()
	end)
	affixFloorBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local affixFloorEdit = CreateFrame("EditBox", nil, affixFloorBox)
	affixFloorEdit:SetFont(FONT, 10, "OUTLINE")
	affixFloorEdit:SetTextColor(unpack(C_TEXT))
	affixFloorEdit:SetAutoFocus(false)
	affixFloorEdit:SetNumeric(true)
	affixFloorEdit:SetMaxLetters(4)
	affixFloorEdit:SetPoint("TOPLEFT", 4, -1)
	affixFloorEdit:SetPoint("BOTTOMRIGHT", -4, 1)
	affixFloorEdit:SetJustifyH("CENTER")
	affixFloorEdit:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
	affixFloorEdit:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
	affixFloorEdit:SetScript("OnEditFocusLost", function(s)
		local val = tonumber(s:GetText()) or 0
		if val < 0 then val = 0 end
		s:SetText(tostring(val))
		local p = GetActiveProfile(db)
		p.affixIlvlMin = val
		if _G.AutoDelete_RefreshCachedProfile then _G.AutoDelete_RefreshCachedProfile() end
	end)
	self._affixIlvlEdit = affixFloorEdit

	-- Plain-language description spanning the bottom of the card (where the
	-- Audit Lists button used to live). Tells the player what Affix
	-- Protection IS so they aren't guessing from the toggle/input alone.
	--
	-- Sizing math (UI Visual Audit, conventions §10.5):
	--   Card height            = 92
	--   Min iLvl row bottom    = -46 (top) - 20 (row height) = -66
	--   Card bottom            = -92
	--   Available vertical     = 92 - 66 = 22 px (y=-70 anchor to y=-92)
	--   8pt OUTLINE line height ~= 10 px so safe budget = 2 lines.
	--   At width = 155 px, ~30 chars per line -> text must be ~<= 60 chars
	--   to stay within 2 lines.
	-- Prior text overflowed (118 chars, ~5 lines, ~55 px) -- regression
	-- caught by user 2026-05-23.
	local affixProtHint = MakeText(aCard1, 8, C_DIM)
	affixProtHint:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -70)
	affixProtHint:SetWidth(cardW - CARD_INNER_PAD_X * 2)
	affixProtHint:SetJustifyH("LEFT")
	affixProtHint:SetWordWrap(true)
	affixProtHint:SetNonSpaceWrap(false)
	affixProtHint:SetText("Keeps Project Ebonhold items safe from auto-sell.")

	-- (Audit Lists button moved to Card 3 in v3.20 -- user feedback said
	-- Card 1 was too crowded with the No Auto-Sell toggle, the Min iLvl
	-- row, AND the audit button all stacked. Card 3 hosts both diagnostic
	-- buttons now.)

	-- Affix Tab Card 2: Affix Display (moved from Filters tab in v3.20
	-- alongside Affix Protection so all affix tooling lives together).
	-- Two tightly-coupled toggles + a diagnostic button:
	--   Row 1: Show affix dot              (master gate for any dot display)
	--   Row 2: Only missing affixes        (collection mode, gated by Row 1)
	--   Row 3: Scan Learned Affixes        (refresh PE mirror + print roster)
	--
	-- The Scan button shares the bottom-of-card slot with the Audit Lists
	-- button on Card 1 (y=-68) so the two diagnostic actions line up
	-- visually across the Affix tab.
	--
	-- Wrapped in `do ... end` so the card-internal locals (title FS,
	-- toggle frames, scan button) don't bump BuildUI past Lua 5.1's
	-- 200-local cap. The toggles are exported on self._tglShowAffixDot /
	-- self._tglAffixCollection -- OnClick handlers and state restoration
	-- below reach them through `self` so the bare locals can vanish.
	do
		local card3Title = MakeText(aCard2, 11, C_ACCENT, "OUTLINE")
		card3Title:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -6)
		card3Title:SetText("Affix Display")

		local tglShowAffixDot = MakeToggle(aCard2, "Show affix dot", C_ACCENT,
			"Puts a small dot on bag items that have a Project Ebonhold affix. Dot color shows the tier (I white, II green, III blue, IV purple, V orange). Gold dot means an affix you haven't learned yet. Works on default bags and ElvUI bags.")
		tglShowAffixDot:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -24)
		tglShowAffixDot:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
		self._tglShowAffixDot = tglShowAffixDot

		local tglAffixCollection = MakeToggle(aCard2, "Only missing affixes", C_ACCENT,
			"Only puts a gold dot on items with affixes you haven't learned yet. Items with affixes you already have stay clean. Also protects unknown affixes from being sold or deleted. Needs Show affix dot turned on.")
		tglAffixCollection:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -46)
		tglAffixCollection:SetSize(cardW - CARD_INNER_PAD_X * 2, 20)
		self._tglAffixCollection = tglAffixCollection

		-- (Scan Learned Affixes button moved to Card 3 in v3.20 -- see the
		-- Affix Tools card construction below.)
	end

	-- ========================================================================
	-- Affix Tab Card 3: Affix Tools (v3.20).
	-- Hosts the two diagnostic buttons that used to live one-per-card on
	-- Cards 1 and 2 (Audit Lists, Scan Learned Affixes). Stacking them on
	-- their own card lets Cards 1 and 2 breathe (the toggles + Min iLvl
	-- row were sharing a card with a button, which felt cramped).
	-- C_BLUE for both (transform/report class -- they surface info, don't
	-- add or remove anything).
	-- Wrapped in do...end so the two button locals don't bump BuildUI past
	-- Lua 5.1's 200-local cap.
	-- ========================================================================
	do
		local card3Title = MakeText(aCard3, 11, C_ACCENT, "OUTLINE")
		card3Title:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -6)
		card3Title:SetText("Affix Tools")

		-- Refresh List button (was Audit Lists on Card 1). Scans the user's Delete + Sell
		-- lists for items carrying PE's @affix@ tooltip marker; prints a
		-- chat summary. Doesn't modify the lists.
		local auditBtn = MakeActionButton(aCard3, "Refresh List", C_BLUE, function()
			if _G.AutoDelete_AuditAffixOnLists then
				_G.AutoDelete_AuditAffixOnLists(GetActiveProfile(db))
			end
		end, cardW - CARD_INNER_PAD_X * 2, 20)
		auditBtn:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -24)
		auditBtn:SetScript("OnEnter", function(btn)
			btn:SetBackdropColor(C_BLUE[1], C_BLUE[2], C_BLUE[3], 0.3)
			btn:SetBackdropBorderColor(C_BLUE[1], C_BLUE[2], C_BLUE[3], 1)
			btn._text:SetTextColor(1, 1, 1)
			GameTooltip:SetOwner(btn, "ANCHOR_TOP")
			GameTooltip:SetText("Refresh List", 1, 1, 1)
			GameTooltip:AddLine("Checks your Delete and Sell lists for items with a Project Ebonhold affix. Prints what it finds in chat. Doesn't change your lists.",
				C_DIM[1], C_DIM[2], C_DIM[3], true)
			GameTooltip:Show()
		end)
		auditBtn:SetScript("OnLeave", function(btn)
			ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
			btn._text:SetTextColor(unpack(C_TEXT))
			GameTooltip:Hide()
		end)

		-- Update Affix List button (was Scan Learned Affixes on Card 2). Refreshes the
		-- addon's owned-affix mirror from PE and opens the scrollable
		-- Learned Affixes window with Learned and Unlearned tabs.
		local scanBtn = MakeActionButton(aCard3, "Update Affix List", C_BLUE, function()
			if _G.AutoDelete_ScanLearnedAffixes then
				_G.AutoDelete_ScanLearnedAffixes()
			end
		end, cardW - CARD_INNER_PAD_X * 2, 20)
		scanBtn:SetPoint("TOPLEFT", CARD_INNER_PAD_X, -46)
		scanBtn:SetScript("OnEnter", function(btn)
			btn:SetBackdropColor(C_BLUE[1], C_BLUE[2], C_BLUE[3], 0.3)
			btn:SetBackdropBorderColor(C_BLUE[1], C_BLUE[2], C_BLUE[3], 1)
			btn._text:SetTextColor(1, 1, 1)
			GameTooltip:SetOwner(btn, "ANCHOR_TOP")
			GameTooltip:SetText("Update Affix List", 1, 1, 1)
			GameTooltip:AddLine("Opens a window with Learned and Unlearned tabs, grouped by tier.",
				C_DIM[1], C_DIM[2], C_DIM[3], true)
			GameTooltip:Show()
		end)
		scanBtn:SetScript("OnLeave", function(btn)
			ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
			btn._text:SetTextColor(unpack(C_TEXT))
			GameTooltip:Hide()
		end)
	end

	-- ========================================================================
	-- KEYBINDS TAB: holds the secure-button features (One-Key Open, future
	-- One-Key Disenchant migration). On WoW 3.3.5a the only path that can
	-- fire a protected function (UseContainerItem, CastSpell on a bag item)
	-- from addon code is a user-pressed key on a SecureActionButton. Each
	-- card on this tab is one such feature. The key-capture row in each
	-- card writes the binding via SetBinding + SaveBindings, so the addon
	-- stays in two files (no Bindings.xml required).
	--
	-- Wrapped in a `do ... end` block so its locals stay out of the panel-
	-- builder function's local-count (Lua 5.1 has a 200-local cap per
	-- function and we'd otherwise bump against it). Widgets that need to
	-- survive across scopes (OnClick handlers, Refresh path) are stored
	-- on `self` and accessed via self._tglOpenEnabled etc. later.
	-- ========================================================================
	do
	local keybindsPage = tabPages.keybinds

	-- Reusable key-capture row. Renders a labelled button that displays the
	-- currently bound key for `bindingCmd` (the BINDING name, e.g. "CLICK
	-- AutoDeleteOpenButton:LeftButton"). Click to enter capture mode; the
	-- next non-modifier key (with current modifiers) becomes the binding.
	-- Right-click clears the binding. Returns the row Frame so the caller
	-- can :SetPoint() it.
	--
	-- Combat-safe: SetBinding/SetBindingClick is taint-locked while combat
	-- is active. We refuse to enter capture mode in combat and show a one-
	-- shot chat note instead.
	local function MakeKeyCaptureRow(parent, bindingCmd, width)
		local row = CreateFrame("Frame", nil, parent)
		row:SetSize(width or 200, 22)

		local btn = CreateFrame("Button", nil, row)
		btn:SetAllPoints(row)
		ApplyBackdrop(btn, C_DROP_BG, C_DROP_BORDER)

		local label = MakeText(btn, 10, C_TEXT, "OUTLINE")
		label:SetPoint("CENTER", btn, "CENTER", 0, 0)

		-- RefreshLabel reads the current binding and renders either the key
		-- combo or a "click to bind" placeholder. Called after every state
		-- change and on panel Refresh.
		local capturing = false
		local function RefreshLabel()
			if capturing then
				label:SetText("Press a key...")
				label:SetTextColor(unpack(C_ACCENT))
				return
			end
			local key1 = GetBindingKey(bindingCmd)
			if key1 then
				label:SetText(key1)
				label:SetTextColor(unpack(C_TEXT))
			else
				label:SetText("Click to bind")
				label:SetTextColor(unpack(C_DIM))
			end
			-- Optional hook the panel sets so it can refresh the row's
			-- status text the moment a key is bound or cleared (without
			-- waiting for the next BAG_UPDATE to do it).
			if row._onBindingChanged then row._onBindingChanged() end
		end
		row._refresh = RefreshLabel
		RefreshLabel()

		-- Enter / exit capture mode. EnableKeyboard captures every key
		-- press globally (game input also runs, but our handler grabs the
		-- key first). We use a propagation block (return true semantics
		-- by setting PropagateKeyboardInput on later clients; 3.3.5a does
		-- not have it, so we just live with the side effect that the key
		-- ALSO fires its normal binding once during capture -- this is a
		-- one-frame inconvenience and matches how Blizzard's own
		-- KeyBindingFrame handles it on this client).
		local function StartCapture()
			if InCombatLockdown and InCombatLockdown() then
				print("|cffff8000[AutoDelete]|r Can't change keybinds in combat.")
				return
			end
			capturing = true
			btn:EnableKeyboard(true)
			RefreshLabel()
		end
		local function StopCapture()
			capturing = false
			btn:EnableKeyboard(false)
			RefreshLabel()
		end

		btn:SetScript("OnKeyDown", function(self, key)
			-- Skip modifier-only presses so a combo like SHIFT-A waits for
			-- the actual letter rather than binding to SHIFT alone.
			if key == "LSHIFT" or key == "RSHIFT"
				or key == "LCTRL"  or key == "RCTRL"
				or key == "LALT"   or key == "RALT" then
				return
			end
			-- Escape cancels.
			if key == "ESCAPE" then StopCapture(); return end
			-- Build the combo string. Order matches Blizzard convention
			-- so SetBinding's lookup matches what the binding UI shows.
			local combo = ""
			if IsAltKeyDown()     then combo = combo .. "ALT-"   end
			if IsControlKeyDown() then combo = combo .. "CTRL-"  end
			if IsShiftKeyDown()   then combo = combo .. "SHIFT-" end
			combo = combo .. key
			-- Clear any prior binding of this combo first so two features
			-- never collide on the same key. SetBinding(key, nil) unbinds.
			SetBinding(combo, bindingCmd)
			SaveBindings(GetCurrentBindingSet())
			StopCapture()
		end)

		btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		btn:SetScript("OnClick", function(self, mouseButton)
			if mouseButton == "RightButton" then
				if InCombatLockdown and InCombatLockdown() then
					print("|cffff8000[AutoDelete]|r Can't change keybinds in combat.")
					return
				end
				local existing = GetBindingKey(bindingCmd)
				if existing then SetBinding(existing) end
				SaveBindings(GetCurrentBindingSet())
				RefreshLabel()
				return
			end
			if capturing then StopCapture() else StartCapture() end
		end)

		-- Tooltip explains the click semantics.
		btn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText("Keybind", 1, 1, 1)
			GameTooltip:AddLine("Left-click and press a key (with modifiers) to bind.", C_DIM[1], C_DIM[2], C_DIM[3], true)
			GameTooltip:AddLine("Right-click to clear.", C_DIM[1], C_DIM[2], C_DIM[3], true)
			GameTooltip:AddLine("Cannot bind in combat.", 1, 0.4, 0.4, true)
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

		row._button = btn
		return row
	end

	-- Keybinds tab layout: four vertical rows, one per feature. Each row
	-- is ~22px tall and renders inline as:
	--   [x] Feature Name  [Key Button]  Status text  [⚙]
	-- The gear button on the right opens a feature-specific filter popup
	-- when the feature has filterable options (Disenchant, Open). Mill
	-- and Prospect have no per-item filters, so their gear button is
	-- omitted. Total content: 4 rows * 22px + small top pad = ~92px,
	-- fits inside the standard 100px tab content area.
	local KEYBIND_ROW_H   = 22
	local KEYBIND_ROW_GAP = 2
	local KEYBIND_PAD_X   = 8
	local KEYBIND_TGL_W   = 16              -- the small checkbox-only width
	local KEYBIND_NAME_W  = 140
	local KEYBIND_KEY_W   = 110
	-- Widened from 22 (gear-glyph era) to 56 to fit "Filters" text label.
	-- The glyph (`*`) was confusing -- it read like a footnote marker. The
	-- explicit text button is unambiguous and tells the user what the
	-- button does without needing a hover tooltip.
	local KEYBIND_GEAR_W  = 56
	local CONTENT_W_KEYBINDS = genContentW - KEYBIND_PAD_X * 2

	-- Reusable row factory. Each row has the slots described above; the
	-- caller passes a config table with the feature's labels, binding
	-- command, and an optional `openFilters` function to wire the gear
	-- button. Returns { toggle, keyRow, status, gear } so OnClick handlers
	-- and the panel Refresh path can address each piece.
	local function MakeKeybindRow(opts, yOffset)
		local row = CreateFrame("Frame", nil, keybindsPage)
		row:SetSize(CONTENT_W_KEYBINDS, KEYBIND_ROW_H)
		row:SetPoint("TOPLEFT", KEYBIND_PAD_X, yOffset)

		-- Master toggle on the far left. Compact icon-only width; the
		-- feature name label sits next to it as the "real" label.
		-- Pass opts.label as the explicit tooltipTitle so the GameTooltip
		-- header still reads the feature name ("One-Key Open" etc.) even
		-- though the checkbox itself has no inline label (the name lives in
		-- a sibling FontString in the row).
		local tgl = MakeToggle(row, "", C_ACCENT, opts.tooltip, opts.label)
		tgl:SetPoint("LEFT", row, "LEFT", 0, 0)
		tgl:SetSize(KEYBIND_TGL_W, KEYBIND_TGL_W)

		local nameText = row:CreateFontString(nil, "OVERLAY")
		nameText:SetFont(FONT, 11, "OUTLINE")
		nameText:SetTextColor(unpack(C_TEXT))
		nameText:SetPoint("LEFT", tgl, "RIGHT", 6, 0)
		nameText:SetWidth(KEYBIND_NAME_W)
		nameText:SetJustifyH("LEFT")
		nameText:SetText(opts.label)

		local keyRow = MakeKeyCaptureRow(row, opts.bindingCmd, KEYBIND_KEY_W)
		keyRow:SetPoint("LEFT", nameText, "RIGHT", 4, 0)

		local statusText = row:CreateFontString(nil, "OVERLAY")
		statusText:SetFont(FONT, 9, "OUTLINE")
		statusText:SetTextColor(unpack(C_DIM))
		statusText:SetPoint("LEFT", keyRow, "RIGHT", 6, 0)
		statusText:SetPoint("RIGHT", row, "RIGHT", -(KEYBIND_GEAR_W + 4), 0)
		statusText:SetJustifyH("LEFT")
		statusText:SetWordWrap(false)
		statusText:SetText("")

		-- Stash the binding command on the row so the panel's status
		-- composer can call GetBindingKey() to check whether the user has
		-- actually bound a key. The composer uses this to switch between
		-- "Bind a key" (no key) and "[KEY] [Item]" (key + target) status.
		row._bindingCmd = opts.bindingCmd

		-- Filters button on the far right; opens the filter popup for this
		-- v3.20: removed the per-row Filters button. DE Filters now live as
		-- a card on the Filters tab (and the other three one-key actions
		-- never had filters), so the Keybinds tab is just keybinding now.
		-- The unused `openFilters` opts field is silently ignored.

		return tgl, keyRow, statusText
	end

	-- Row 1: One-Key Open (y=-6). No gear / filter popup -- the only
	-- option (autoOpenIncludeLocked) defaults to true and the cost of a
	-- popup for one toggle exceeds the value. If we add more Open options
	-- later, restore the openFilters callback.
	local tglOpenEnabled, openKeyRow, openStatus = MakeKeybindRow({
		label      = "One-Key Open",
		bindingCmd = "CLICK AutoDeleteOpenButton:LeftButton",
		tooltip    = "Press one button to open the next clam, coin purse, or egg in your bags. Locked boxes are skipped until you can pick the lock.",
	}, -6)
	self._tglOpenEnabled  = tglOpenEnabled
	self._openKeyRow      = openKeyRow
	self._openStatus      = openStatus
	self._openBindingCmd  = "CLICK AutoDeleteOpenButton:LeftButton"

	-- Row 2: One-Key Disenchant (y=-30).
	local tglDisenchant, disenchantKeyRow, disenchantStatus = MakeKeybindRow({
		label      = "One-Key Disenchant",
		bindingCmd = "CLICK AutoDeleteDisenchantButton:LeftButton",
		tooltip    = "Press one button to disenchant your next green or higher item. You need the Enchanting profession. Pick which items count on the Filters tab.",
	}, -(6 + (KEYBIND_ROW_H + KEYBIND_ROW_GAP)))
	self._tglDisenchant         = tglDisenchant
	self._disenchantKeyRow      = disenchantKeyRow
	self._disenchantStatus      = disenchantStatus
	self._disenchantBindingCmd  = "CLICK AutoDeleteDisenchantButton:LeftButton"

	-- Row 3: One-Key Mill (y=-54).
	local tglMill, millKeyRow, millStatus = MakeKeybindRow({
		label      = "One-Key Mill",
		bindingCmd = "CLICK AutoDeleteMillButton:LeftButton",
		tooltip    = "Press one button to mill the next stack of herbs in your bags. The stack needs at least 5 herbs. You need the Inscription profession.",
	}, -(6 + (KEYBIND_ROW_H + KEYBIND_ROW_GAP) * 2))
	self._tglMill        = tglMill
	self._millKeyRow     = millKeyRow
	self._millStatus     = millStatus
	self._millBindingCmd = "CLICK AutoDeleteMillButton:LeftButton"

	-- Row 4: One-Key Prospect (y=-78).
	local tglProspect, prospectKeyRow, prospectStatus = MakeKeybindRow({
		label      = "One-Key Prospect",
		bindingCmd = "CLICK AutoDeleteProspectButton:LeftButton",
		tooltip    = "Press one button to prospect the next stack of ore in your bags. The stack needs at least 5 ore. You need the Jewelcrafting profession.",
	}, -(6 + (KEYBIND_ROW_H + KEYBIND_ROW_GAP) * 3))
	self._tglProspect        = tglProspect
	self._prospectKeyRow     = prospectKeyRow
	self._prospectStatus     = prospectStatus
	self._prospectBindingCmd = "CLICK AutoDeleteProspectButton:LeftButton"

	-- Wire the key-row's _onBindingChanged callbacks so the row's status
	-- text refreshes the moment a key is bound or cleared. Without these,
	-- the row would say "Bind a key" until the next BAG_UPDATE fired.
	openKeyRow._onBindingChanged       = function()
		if self._refreshOpenStatus       then self:_refreshOpenStatus()       end
	end
	disenchantKeyRow._onBindingChanged = function()
		if self._refreshDisenchantStatus then self:_refreshDisenchantStatus() end
	end
	millKeyRow._onBindingChanged       = function()
		if self._refreshMillStatus       then self:_refreshMillStatus()       end
	end
	prospectKeyRow._onBindingChanged   = function()
		if self._refreshProspectStatus   then self:_refreshProspectStatus()   end
	end
	end  -- end of Keybinds-tab `do` block

	-- ========================================================================
	-- AUTOINV TAB: 3 cards (Enable+Keywords, Loot Rules, Party Management)
	-- Same card dimensions as General/Goblin tabs.
	-- ========================================================================
	local autoInvPage = tabPages.autoinv

	local function MakeAutoInvCard(xOff)
		local card = CreateFrame("Frame", nil, autoInvPage)
		card:SetSize(cardW, cardH)
		card:SetPoint("TOPLEFT", xOff, -4)
		-- v3.21 §6.3: shared inner-card pattern via ApplyBackdrop + constants.
		ApplyBackdrop(card, C_CARD_BG, C_CARD_BORDER)
		return card
	end

	local aCard1 = MakeAutoInvCard(0)
	local aCard2 = MakeAutoInvCard(cardW + CARD_GAP)
	local aCard3 = MakeAutoInvCard((cardW + CARD_GAP) * 2)

	-- CARD 1: Auto-Invite master toggle + keyword text input
	local tglAutoInvite = MakeToggle(aCard1, "Auto-Invite", C_ACCENT,
		"When someone whispers you one of the keywords below, you invite them to your group. You need to be the leader or a raid assistant.")
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
	-- v3.21 §6.3: ApplyBackdrop helper.
	ApplyBackdrop(kwFrame, C_DROP_BG, C_DROP_BORDER)

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
		"After someone is auto-invited, sets the party's loot rule to the one you pick below.")
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

		-- Left-stack + right 2x2 grid layout inside the tab content area.
		--
		--   LEFT half (x=8, width=236):
		--     "Current: <char>" label at y=-10 (top)
		--     Profile dropdown at  y=-30 (below label, 22 tall)
		--
		--   RIGHT half (cols 3+4):
		--     Row 1: [Copy]         [Delete]
		--     Row 2: [Import Lists] [Clear List]
		--     Row 3: [Import Raw]   [Export Raw]
		--     Row 4: [Audit Lists]  [Fix Safe]
		--     Four rows must fit inside the fixed tab content frame. Keep the
		--     row math tight enough that the last row clears the bottom border.
		--
		-- Semantic colors per Addon_UI_StyleGuide.md:
		--   Copy / Import Lists  -> C_GREEN (additive, copies data in)
		--   Delete / Clear List  -> C_RED   (destructive)
		-- Both sides are independently top-aligned. Each side is read
		-- top-down so the user does not have to scan diagonally.
		local PROF_LEFT_PAD = 8
		local PROF_COL_W    = 113
		local PROF_COL_GAP  = 10
		local PROF_COL3_X   = PROF_LEFT_PAD + PROF_COL_W * 2 + PROF_COL_GAP * 2   -- 254
		local PROF_COL4_X   = PROF_COL3_X   + PROF_COL_W + PROF_COL_GAP           -- 377
		local PROF_BTN_H    = 20
		local PROF_BTN_GAP  = 4
		local PROF_DD_W     = PROF_COL_W * 2 + PROF_COL_GAP                       -- 236
		local PROF_LABEL_Y  = -6
		local PROF_DD_Y     = PROF_LABEL_Y - 20                                   -- -26
		local PROF_ROW1_Y   = -4
		local PROF_ROW2_Y   = PROF_ROW1_Y - PROF_BTN_H - PROF_BTN_GAP             -- -28

		-- LEFT half / row 1: "Current: <charname>" label (small accent text).
		local curHeader = MakeText(profilesPage, 10, C_TITLE, "OUTLINE")
		curHeader:SetPoint("TOPLEFT", PROF_LEFT_PAD, PROF_LABEL_Y)
		curHeader:SetJustifyH("LEFT")
		curHeader:SetText("Current: " .. (UnitName("player") or "?"))

		-- Selected-character state (tracked on self since the dropdown is built
		-- dynamically in Refresh. We cannot capture it as a BuildUI local or
		-- it will not update when characters are added/deleted).
		self._selectedProfile = nil

		-- LEFT half / row 2: profile dropdown (sits directly below the label).
		local profileDD = MakeDropdown(profilesPage, PROF_DD_W, {}, function(val)
			self._selectedProfile = val
		end)
		profileDD:SetPoint("TOPLEFT", PROF_LEFT_PAD, PROF_DD_Y)
		self._profileDD = profileDD

		-- RIGHT half / row 1: Copy (green) and Delete (red).
		local copyBtn = MakeActionButton(profilesPage, "Copy", C_GREEN, function()
			local sel = self._selectedProfile
			if not sel or sel == "" then
				print("|cffff8000[AutoDelete]|r: Select a profile first.")
				return
			end
			local dlg = StaticPopup_Show("AUTODELETE_PROFILE_COPY", sel,
				_G.AutoDelete_Profiles.GetCurrentCharacter())
			if dlg then dlg.data = sel end
		end, PROF_COL_W, PROF_BTN_H)
		copyBtn:SetPoint("TOPLEFT", PROF_COL3_X, PROF_ROW1_Y)

		local deleteBtn = MakeActionButton(profilesPage, "Delete", C_RED, function()
			local sel = self._selectedProfile
			if not sel or sel == "" then
				print("|cffff8000[AutoDelete]|r: Select a profile first.")
				return
			end
			local dlg = StaticPopup_Show("AUTODELETE_PROFILE_DELETE", sel)
			if dlg then dlg.data = sel end
		end, PROF_COL_W, PROF_BTN_H)
		deleteBtn:SetPoint("TOPLEFT", PROF_COL4_X, PROF_ROW1_Y)

		-- RIGHT half / row 2: Import Lists (green) and Clear List (red).
		-- Import merges the 3 lists (Delete/Sell/Keep) from the selected
		-- profile into the current character's profile. Never touches other
		-- settings. Duplicates are skipped; cross-list conflicts open a popup.
		local importBtn = MakeActionButton(profilesPage, "Import Lists", C_GREEN, function()
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
				StaticPopup_Show("AUTODELETE_PROFILE_IMPORT_SIMPLE", sel, tostring(#preview.additions)).data = sel
				return
			end
			-- Conflicts exist. Open the conflict resolution popup.
			_G.AutoDelete_ShowImportConflicts(sel, preview)
		end, PROF_COL_W, PROF_BTN_H)
		importBtn:SetPoint("TOPLEFT", PROF_COL3_X, PROF_ROW2_Y)

		-- Clear List opens a picker that wipes one list (Delete/Sell/Keep)
		-- or all three on the current character. The destructive action is
		-- then confirmed via a StaticPopup inside the picker.
		local clearBtn = MakeActionButton(profilesPage, "Clear List", C_RED, function()
			if _G.AutoDelete_ShowClearListPicker then
				_G.AutoDelete_ShowClearListPicker()
			end
		end, PROF_COL_W, PROF_BTN_H)
		clearBtn:SetPoint("TOPLEFT", PROF_COL4_X, PROF_ROW2_Y)

		-- v3.20 Row 3: Import Raw (left) + Export Raw (right). Same column
		-- positions as rows 1-2 so the 3-row grid stays aligned. C_GREEN
		-- for Import (additive: brings data IN), C_BLUE for Export
		-- (transform: shows existing data, doesn't change it).
		local PROF_ROW3_Y = PROF_ROW2_Y - PROF_BTN_H - PROF_BTN_GAP
		local importRawBtn = MakeActionButton(profilesPage, "Import Raw", C_GREEN, function()
			if _G.AutoDelete_ShowImportRawWindow then
				_G.AutoDelete_ShowImportRawWindow()
			end
		end, PROF_COL_W, PROF_BTN_H)
		importRawBtn:SetPoint("TOPLEFT", PROF_COL3_X, PROF_ROW3_Y)
		importRawBtn:SetScript("OnEnter", function(btn)
			btn:SetBackdropColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 0.3)
			btn:SetBackdropBorderColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
			btn._text:SetTextColor(1, 1, 1)
			GameTooltip:SetOwner(btn, "ANCHOR_TOP")
			GameTooltip:SetText("Import Raw", 1, 1, 1)
			GameTooltip:AddLine("Paste a list of item names and add them to your Delete, Sell, or Keep list. AutoDelete looks each name up and adds it for you.",
				C_DIM[1], C_DIM[2], C_DIM[3], true)
			GameTooltip:Show()
		end)
		importRawBtn:SetScript("OnLeave", function(btn)
			ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
			btn._text:SetTextColor(unpack(C_TEXT))
			GameTooltip:Hide()
		end)

		local exportRawBtn = MakeActionButton(profilesPage, "Export Raw", C_BLUE, function()
			if _G.AutoDelete_ShowExportRawWindow then
				_G.AutoDelete_ShowExportRawWindow()
			end
		end, PROF_COL_W, PROF_BTN_H)
		exportRawBtn:SetPoint("TOPLEFT", PROF_COL4_X, PROF_ROW3_Y)
		exportRawBtn:SetScript("OnEnter", function(btn)
			btn:SetBackdropColor(C_BLUE[1], C_BLUE[2], C_BLUE[3], 0.3)
			btn:SetBackdropBorderColor(C_BLUE[1], C_BLUE[2], C_BLUE[3], 1)
			btn._text:SetTextColor(1, 1, 1)
			GameTooltip:SetOwner(btn, "ANCHOR_TOP")
			GameTooltip:SetText("Export Raw", 1, 1, 1)
			GameTooltip:AddLine("Copy your Delete, Sell, or Keep list as plain item names so you can share or paste them somewhere else.",
				C_DIM[1], C_DIM[2], C_DIM[3], true)
			GameTooltip:Show()
		end)
		exportRawBtn:SetScript("OnLeave", function(btn)
			ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
			btn._text:SetTextColor(unpack(C_TEXT))
			GameTooltip:Hide()
		end)

		-- Row 4: List Audit (report-only) + Fix Safe (mechanical cleanup).
		-- Audit is non-mutating. Fix Safe removes same-list duplicate lines
		-- and normalizes full item links / plain numeric IDs to item:<id>.
		local PROF_ROW4_Y = PROF_ROW3_Y - PROF_BTN_H - PROF_BTN_GAP
		local auditBtn = MakeActionButton(profilesPage, "Audit Lists", C_BLUE, function()
			if _G.AutoDelete_ShowListAudit then
				_G.AutoDelete_ShowListAudit()
			end
		end, PROF_COL_W, PROF_BTN_H)
		auditBtn:SetPoint("TOPLEFT", PROF_COL3_X, PROF_ROW4_Y)
		auditBtn:SetScript("OnEnter", function(btn)
			btn:SetBackdropColor(C_BLUE[1], C_BLUE[2], C_BLUE[3], 0.3)
			btn:SetBackdropBorderColor(C_BLUE[1], C_BLUE[2], C_BLUE[3], 1)
			btn._text:SetTextColor(1, 1, 1)
			GameTooltip:SetOwner(btn, "ANCHOR_TOP")
			GameTooltip:SetText("Audit Lists", 1, 1, 1)
			GameTooltip:AddLine("Open a copyable report for duplicate entries, cross-list conflicts, name-only entries, and same-name item ID traps.",
				C_DIM[1], C_DIM[2], C_DIM[3], true)
			GameTooltip:Show()
		end)
		auditBtn:SetScript("OnLeave", function(btn)
			ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
			btn._text:SetTextColor(unpack(C_TEXT))
			GameTooltip:Hide()
		end)

		local fixAuditBtn = MakeActionButton(profilesPage, "Fix Safe", C_GREEN, function()
			if _G.AutoDelete_RunListAuditSafeFix then
				_G.AutoDelete_RunListAuditSafeFix()
			end
		end, PROF_COL_W, PROF_BTN_H)
		fixAuditBtn:SetPoint("TOPLEFT", PROF_COL4_X, PROF_ROW4_Y)
		fixAuditBtn:SetScript("OnEnter", function(btn)
			btn:SetBackdropColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 0.3)
			btn:SetBackdropBorderColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
			btn._text:SetTextColor(1, 1, 1)
			GameTooltip:SetOwner(btn, "ANCHOR_TOP")
			GameTooltip:SetText("Fix Safe", 1, 1, 1)
			GameTooltip:AddLine("Apply only safe mechanical list cleanup: same-list duplicates and item reference normalization. Cross-list and same-name item ID traps stay for review.",
				C_DIM[1], C_DIM[2], C_DIM[3], true)
			GameTooltip:Show()
		end)
		fixAuditBtn:SetScript("OnLeave", function(btn)
			ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
			btn._text:SetTextColor(unpack(C_TEXT))
			GameTooltip:Hide()
		end)

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

		-- Remove-patterns popup: scans all three lists (Delete + Sell + Keep)
		-- for items whose itemSubType matches the chosen profession token
		-- (passed via popup.data). One popup serves all eight profession
		-- options on the sub-window; popup.data carries the localized
		-- subtype string ("Pattern", "Recipe", "Plans", etc.) and a
		-- display label for the prompt text.
		if not StaticPopupDialogs["AUTODELETE_PROFILE_REMOVE_PATTERNS"] then
			StaticPopupDialogs["AUTODELETE_PROFILE_REMOVE_PATTERNS"] = {
				text = "Remove all %s items from your Delete, Sell, and Keep lists? This cannot be undone.",
				button1 = "Remove", button2 = "Cancel",
				OnAccept = function(popup)
					local payload = popup.data
					if type(payload) ~= "table" or not payload.subtype then return end
					if not _G.AutoDelete_Profiles or not _G.AutoDelete_Profiles.RemovePatternsBySubtype then return end
					local ok, result = _G.AutoDelete_Profiles.RemovePatternsBySubtype(payload.subtype)
					if ok then
						print(string.format(
							"|cffff8000[AutoDelete]|r: Removed %s (Delete: %d, Sell: %d, Keep: %d).",
							payload.label or payload.subtype,
							result.deleteRemoved or 0,
							result.sellRemoved or 0,
							result.keepRemoved or 0))
						if (result.uncached or 0) > 0 then
							print(string.format(
								"  |cff999999%d entry(ies) skipped (item data not cached). Open the item or reload to refresh the cache.|r",
								result.uncached))
						end
						if _G.AutoDeleteOptionsPanel and _G.AutoDeleteOptionsPanel.Refresh then
							_G.AutoDeleteOptionsPanel:Refresh()
						end
					else
						print("|cffff4444[AutoDelete]|r: Remove patterns failed (" .. tostring(result) .. ").")
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
	-- v3.21 §6.3: ApplyBackdrop helper. Black to match the panel + mage blue accent border.
	ApplyBackdrop(banner, C_BG, C_HOVER)
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
		enableTooltip = "Sells Bind-on-Equip armor and accessories (rings, necks, trinkets) that match the Rare/Epic toggles and the iLvl range below. Weapons go in the BoE Weapons section. Keep-list and quest items are safe.",
		rarityNoun    = "BoE armor (no weapons)",
	})
	self._boeArmor = boeArmor
	yOff = yOff - 16 - CARD_H - SECTION_GAP

	-- Card 2: BoP
	local bop = MakeSellCategoryCard(self, "BoP", yOff, CARD_H, {
		enableTooltip = "Sells Bind-on-Pickup gear (any slot, including weapons) that matches the Rare/Epic toggles and the iLvl range below. Keep-list and quest items are safe.",
		rarityNoun    = "BoP gear",
	})
	self._bop = bop
	yOff = yOff - 16 - CARD_H - SECTION_GAP

	-- Card 3: BoE Weapons
	local boeWeapons = MakeSellCategoryCard(self, "BoE Weapons", yOff, CARD_H, {
		enableTooltip = "Sells Bind-on-Equip weapons, shields, ranged, thrown, and relics that match the Rare/Epic toggles and the iLvl range below. Wins over BoE Armor when an item fits both. Keep-list and quest items are safe.",
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
	-- Section renamed from "Scan Options" to "List Mode": the contained
	-- buttons select Delete / Sell / Keep list view, not scan settings.
	-- Scan Speed lives on the General tab.
	local scanBox = MakeSection(self, "List Mode", yOff, 1)
	-- Hide the outer section border so it doesn't double up with the inner
	-- scanRightCard's border below. The inner card is the visible frame.
	scanBox:SetBackdropBorderColor(0, 0, 0, 0)
	scanBox:SetBackdropColor(0, 0, 0, 0)

	-- Full-width inner card: holds Delete/Sell/Keep tab buttons.
	-- Anchored flush to section edges (1px) so the buttons read as edge-aligned
	-- with the section's outer frame margin.
	local scanRightCard = CreateFrame("Frame", nil, scanBox)
	scanRightCard:SetHeight(scanCardH)
	scanRightCard:SetPoint("TOPLEFT", scanBox, "TOPLEFT", 1, -1)
	scanRightCard:SetPoint("TOPRIGHT", scanBox, "TOPRIGHT", -1, -1)
	-- v3.21 §6.3: ApplyBackdrop helper. Slightly darker than C_CARD_BG (#080808 vs
	-- #0a0a0a) so the Scan Speed dropdown reads as a recessed sub-card.
	ApplyBackdrop(scanRightCard, { 0.03, 0.03, 0.03, 1 }, C_CARD_BORDER)

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
	-- Bottom padding from manageBox to frame edge. Tightened so the empty
	-- space below the pagination row reads as similar in size to the side
	-- margins. Account for the ~7px ALREADY consumed inside manageBox
	-- (1px border + 6px gap below pagination); 8 below that lands the
	-- visible bottom gap at ~15, matching the 15px side margin.
	local bottomPad = 8
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
	-- Layout: [search box ...........] [Raw] [Refresh] [short helper]
	-- ========================================================================
	local LIST_SEARCH_W = 240
	local LIST_RAW_W = 55
	local LIST_REFRESH_W = 86
	local LIST_REFRESH_HELP_W = 100

	local searchFrame = CreateFrame("Frame", nil, manageBox)
	searchFrame:SetSize(LIST_SEARCH_W, 22)
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
	tglRaw:SetSize(LIST_RAW_W, 20)
	tglRaw:SetPoint("LEFT", searchFrame, "RIGHT", 8, 0)
	self._tglRaw = tglRaw

	-- Refresh button (circular arrow icon + text)
	local refreshBtn = CreateFrame("Button", nil, manageBox)
	refreshBtn:SetSize(LIST_REFRESH_W, 22)
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
	local refreshHint = MakeText(manageBox, 9, C_DIM, "OUTLINE")
	refreshHint:SetPoint("LEFT", refreshBtn, "RIGHT", 8, 0)
	refreshHint:SetWidth(LIST_REFRESH_HELP_W)
	refreshHint:SetJustifyH("LEFT")
	refreshHint:SetWordWrap(false)
	refreshHint:SetNonSpaceWrap(false)
	refreshHint:SetText("Loads item names.")
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
	-- Anchors match listBox (1px inset) and border style matches listBox so
	-- the header reads as the top section of the same bordered container.
	-- Header keeps a slightly lighter bg than listBox to signal "this is the
	-- column header" without breaking the unified border.
	local itemNameHeader = CreateFrame("Button", nil, manageBox)
	itemNameHeader:SetPoint("TOPLEFT", 1, -40)
	itemNameHeader:SetPoint("TOPRIGHT", -1, -40)
	itemNameHeader:SetHeight(22)
	-- v3.21 §6.3: ApplyBackdrop helper. Slightly lighter than the listBox below
	-- so the column header reads as a header band.
	ApplyBackdrop(itemNameHeader, { 0.063, 0.063, 0.063, 1 }, { 0.15, 0.15, 0.15, 1 })
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
	-- v3.21 §6.3: ApplyBackdrop helper. Matches the column-header border so
	-- the list reads as a single bordered region.
	ApplyBackdrop(listBox, { 0.035, 0.035, 0.035, 1 }, { 0.15, 0.15, 0.15, 1 })
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
		rowMenu:SetClampedToScreen(true)
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
		-- Anchor at the mouse cursor. GetCursorPosition returns screen-pixel
		-- coordinates; divide by UIParent's effective scale so we land at the
		-- correct UI-coordinate position. A small (8, -2) offset keeps the
		-- cursor just inside the top-left of the menu instead of dead on the
		-- border, so the first row isn't hovered the instant the menu opens.
		local mx, my = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (mx / scale) - 8, (my / scale) + 2)
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
		local W = 160
		menu:SetSize(W, rowH * #actions + 4)
		local menuLevel = menu:GetFrameLevel()
		for i, action in ipairs(actions) do
			local btn = CreateFrame("Button", nil, menu)
			btn:SetSize(W - 4, rowH)
			btn:SetPoint("TOPLEFT", 2, -2 - (i - 1) * rowH)
			-- Explicitly raise above the menu's backdrop so the button frame
			-- and its fontstring render on top, not under, the menu chrome.
			btn:SetFrameLevel(menuLevel + 1)
			-- Visible 1px border (dim mid-gray) so each row is clearly delimited
			-- and not invisible against the menu's near-black bg.
			ApplyBackdrop(btn, C_ROW_ODD, { 0.25, 0.25, 0.25, 1 })
			local txt = btn:CreateFontString(nil, "OVERLAY")
			txt:SetFont(FONT, 11, "OUTLINE")
			txt:SetTextColor(unpack(C_TEXT))
			txt:SetJustifyH("LEFT")
			txt:SetPoint("LEFT", 8, 0)
			txt:SetPoint("RIGHT", -8, 0)
			txt:SetText(action.label)
			btn:SetScript("OnEnter", function()
				ApplyBackdrop(btn, C_ROW_HOVER, { 0.40, 0.40, 0.40, 1 })
				txt:SetTextColor(1, 1, 1, 1)
			end)
			btn:SetScript("OnLeave", function()
				ApplyBackdrop(btn, C_ROW_ODD, { 0.25, 0.25, 0.25, 1 })
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

		-- v3.21 §6.3: ApplyBackdrop helper. Near-black bg + pure-black 1px border.
		ApplyBackdrop(btn, C_BTN_BASE_BG, C_BTN_BASE_BORDER)

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

	-- (Old tglGray / tglDelCommon / tglSellGreensGen OnClick wiring
	-- removed -- Filters Card 1 now uses cycle pills. The pill's
	-- onChange closure writes to the profile directly, so no separate
	-- wiring block is needed here. See MakeQualityRow above.)

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

	-- Keybinds tab: One-Key Disenchant. Each toggle writes to the profile,
	-- refreshes the cached profile, re-arms the secure button, and pokes
	-- the status text. Inputs (iLvl min/max) wire their own OnEditFocusLost
	-- handlers at construction time; nothing to do here for them.
	local function MakeDisenchantToggleHandler(field)
		return function(btn)
			btn._checked = not btn._checked
			btn:SetChecked(btn._checked)
			GetActiveProfile(db)[field] = btn._checked
			if _G.AutoDelete_RefreshCachedProfile then _G.AutoDelete_RefreshCachedProfile() end
			if _G.AutoDelete_UpdateDisenchantButton then _G.AutoDelete_UpdateDisenchantButton() end
			if self._refreshDisenchantStatus then self:_refreshDisenchantStatus() end
		end
	end
	-- Only the master Enabled toggle lives on the Keybinds-tab row. The
	-- BoP/BoE/Unc/Rare/Epic/iLvl filters moved into the gear-button popup
	-- (AutoDeleteDisenchantFiltersPopup) which wires its own handlers.
	if self._tglDisenchant then
		self._tglDisenchant:SetScript("OnClick", MakeDisenchantToggleHandler("disenchantEnabled"))
	end

	-- Updates the disenchant status line from the live module. Stored on
	-- self so both the Keybinds-tab card's handlers and the Refresh path
	-- below share one implementation. Safe to call before AutoDelete.lua
	-- exports the accessor (falls back to a dim "..." string).

	-- Status composer for all four Keybinds-tab rows. Takes the raw text
	-- the addon-side getter returns ("Disabled" / "Requires X" / "Next: ..."
	-- / "No ... in bags") and rewrites it in plain English that explains
	-- the next step the user should take. Reads the current keybind via
	-- GetBindingKey() so a feature that's enabled but unbound surfaces
	-- "Bind a key" instead of misleading "Next: <item>" text.
	--
	-- Returns: (text, r, g, b). Always returns a string + a color triple,
	-- even on error paths, so callers can SetText/SetTextColor unconditionally.
	function self:_buildKeybindStatus(rawText, bindingCmd, r, g, b)
		if not rawText or rawText == "" then
			return "...", 0.55, 0.55, 0.55
		end

		-- Checkbox is off. The addon getter returns "Disabled" only in
		-- this case (profession requirements have their own branch).
		if rawText == "Disabled" then
			return "Off -- tick the box to enable", 0.55, 0.55, 0.55
		end

		-- Profession requirement not met. Re-word "Requires Enchanting"
		-- as "Needs Enchanting profession" so it reads as an action
		-- prompt rather than a flat label.
		local profMatch = rawText:match("^Requires (.+)$")
		if profMatch then
			return "Needs " .. profMatch .. " profession", 1.0, 0.4, 0.4
		end

		-- Feature is enabled; check whether the user has actually
		-- bound a key. If not, surface that as the next step regardless
		-- of whether the bags have a valid target.
		local boundKey = bindingCmd and GetBindingKey(bindingCmd)
		if not boundKey then
			return "Bind a key (button to the left)", 1.0, 0.7, 0.0
		end

		-- "Next: <link>" -> "[KEY] <link>". The item link is colored
		-- by WoW so we don't need a special color triple on the whole
		-- string; the leading "[KEY] " inherits the cyan tint from the
		-- addon getter's r/g/b.
		local link = rawText:match("^Next:%s*(.+)$")
		if link then
			return "[" .. boundKey .. "] " .. link, r or 0.7, g or 0.85, b or 1.0
		end

		-- "No ... in bags" -> "Nothing to <feature> right now". Trim
		-- the addon's wordy phrasing to one short line. Bag-empty is a
		-- transient state, not a problem to fix, so use the dim color.
		if rawText:find("^No ") then
			return "Nothing to do right now", 0.55, 0.55, 0.55
		end

		-- Unknown shape; pass through with the original color so we
		-- don't lose information.
		return rawText, r or 0.55, g or 0.55, b or 0.55
	end

	function self:_refreshDisenchantStatus()
		if not self._disenchantStatus then return end
		local getter = _G.AutoDelete_GetDisenchantStatus
		if not getter then
			self._disenchantStatus:SetText("...")
			self._disenchantStatus:SetTextColor(0.55, 0.55, 0.55)
			return
		end
		local rawText, r, g, b = getter()
		local text, nr, ng, nb = self:_buildKeybindStatus(rawText, self._disenchantBindingCmd, r, g, b)
		self._disenchantStatus:SetText(text)
		self._disenchantStatus:SetTextColor(nr, ng, nb)
	end

	-- Keybinds tab: One-Key Open. Toggle + sub-toggle update the profile
	-- and immediately re-arm the secure button so the next-target pointer
	-- reflects the new eligibility set. Self references for both toggles
	-- because they live inside a `do ... end` block above and are out of
	-- this scope's view by lexical reach.
	if self._tglOpenEnabled then
		self._tglOpenEnabled:SetScript("OnClick", function(btn)
			btn._checked = not btn._checked
			btn:SetChecked(btn._checked)
			GetActiveProfile(db).autoOpenEnabled = btn._checked
			if _G.AutoDelete_RefreshCachedProfile then _G.AutoDelete_RefreshCachedProfile() end
			if _G.AutoDelete_UpdateOpenButton then _G.AutoDelete_UpdateOpenButton() end
			if self._refreshOpenStatus then self:_refreshOpenStatus() end
		end)
	end
	-- autoOpenIncludeLocked has no on-tab UI in the row-based Keybinds
	-- layout (the single-toggle popup would be overkill). Profile field
	-- defaults to true via DEFAULT_PROFILE and stays there until a
	-- future filter popup is added for the Open row.

	-- Pulls the current "Next: <item>" / "Disabled" / "No openable items"
	-- string from the One-Key Open module and paints the status text.
	-- Called from the toggle handlers above, from the Refresh path below,
	-- and from AutoDelete.lua's UpdateOpenButton when the panel is open.
	function self:_refreshOpenStatus()
		if not self._openStatus then return end
		local getter = _G.AutoDelete_GetOpenStatus
		if not getter then
			self._openStatus:SetText("...")
			self._openStatus:SetTextColor(0.55, 0.55, 0.55)
			return
		end
		local rawText, r, g, b = getter()
		local text, nr, ng, nb = self:_buildKeybindStatus(rawText, self._openBindingCmd, r, g, b)
		self._openStatus:SetText(text)
		self._openStatus:SetTextColor(nr, ng, nb)
	end

	-- Keybinds tab Row 2: Mill (Inscription) and Prospect (Jewelcrafting).
	-- Both are simple single-toggle features so we factor the handler and
	-- status-refresher pair into a tiny closure-builder. `field` is the
	-- profile key, `updateFn` is the AutoDelete.lua exported updater, and
	-- `statusKey` / `getterKey` plug into the per-feature self fields.
	local function MakeSecureCastWiring(field, updateGlobalName, getterGlobalName, statusFieldKey, refreshSelfKey, bindingCmdKey)
		local function OnClickHandler(btn)
			btn._checked = not btn._checked
			btn:SetChecked(btn._checked)
			GetActiveProfile(db)[field] = btn._checked
			if _G.AutoDelete_RefreshCachedProfile then _G.AutoDelete_RefreshCachedProfile() end
			local up = _G[updateGlobalName]
			if up then up() end
			if self[refreshSelfKey] then self[refreshSelfKey](self) end
		end
		self[refreshSelfKey] = function(s)
			local widget = s[statusFieldKey]
			if not widget then return end
			local getter = _G[getterGlobalName]
			if not getter then
				widget:SetText("...")
				widget:SetTextColor(0.55, 0.55, 0.55)
				return
			end
			local rawText, r, g, b = getter()
			local text, nr, ng, nb = s:_buildKeybindStatus(rawText, s[bindingCmdKey], r, g, b)
			widget:SetText(text)
			widget:SetTextColor(nr, ng, nb)
		end
		return OnClickHandler
	end

	if self._tglMill then
		self._tglMill:SetScript("OnClick", MakeSecureCastWiring(
			"millEnabled",
			"AutoDelete_UpdateMillButton",
			"AutoDelete_GetMillStatus",
			"_millStatus",
			"_refreshMillStatus",
			"_millBindingCmd"))
	end
	if self._tglProspect then
		self._tglProspect:SetScript("OnClick", MakeSecureCastWiring(
			"prospectEnabled",
			"AutoDelete_UpdateProspectButton",
			"AutoDelete_GetProspectStatus",
			"_prospectStatus",
			"_refreshProspectStatus",
			"_prospectBindingCmd"))
	end

	-- Filters tab: Affix Protection toggles. Same RefreshCachedProfile call
	-- so the sell loop sees the new setting on the next tick without
	-- waiting for a profile reload. Only the No Auto-Sell toggle remains;
	-- the No Auto-Delete one was dropped (auto-delete never fires on
	-- Rare/Epic gear where affixes appear).
	tglProtectAffixFromSell:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).protectAffixFromSell = btn._checked
		if _G.AutoDelete_RefreshCachedProfile then
			_G.AutoDelete_RefreshCachedProfile()
		end
	end)

	-- Filters tab -> Affix Display: Show affix dot toggle. Forces an
	-- immediate dot refresh so the visual state matches the toggle
	-- without waiting for a natural bag event. Accessed through `self`
	-- because the toggle's local scope was wrapped in a `do/end` to
	-- relieve BuildUI's 200-local cap.
	self._tglShowAffixDot:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).showAffixDot = btn._checked
		if _G.AutoDelete_RefreshCachedProfile then
			_G.AutoDelete_RefreshCachedProfile()
		end
		if _G.AutoDelete_RefreshAffixDots then
			_G.AutoDelete_RefreshAffixDots()
		end
	end)

	-- Filters tab -> Affix Display: Collection Mode toggle. Mirrors the
	-- Only missing affixes toggle. On toggle-on we re-pull PE's
	-- learned-affix table (it may have grown since the player last
	-- reloaded) and force a dot refresh so existing bag slots reflect
	-- the new owned/missing partition immediately. Accessed through
	-- `self` for the same do/end-scope reason as Show affix dot above.
	self._tglAffixCollection:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		local p = GetActiveProfile(db)
		p.affixCollectionMode = btn._checked
		if _G.AutoDelete_RefreshCachedProfile then
			_G.AutoDelete_RefreshCachedProfile()
		end
		-- Re-mirror PE's learned-affix map so the next dot evaluation
		-- sees current data. Safe no-op if PE isn't loaded.
		if _G.AutoDelete_RefreshOwnedAffixes then
			_G.AutoDelete_RefreshOwnedAffixes()
		end
		if _G.AutoDelete_RefreshAffixDots then
			_G.AutoDelete_RefreshAffixDots()
		end
		-- Chat confirmation matching the slash-command output so the user
		-- gets the same "37 owned affixes mirrored from PE" signal whether
		-- they toggle via UI or slash.
		if btn._checked then
			local count = 0
			for _ in pairs(_G.AutoDelete_OwnedAffixes or {}) do
				count = count + 1
			end
			print("|cffff8000[AutoDelete]|r affix collection mode |cff00ff00ON|r. "
				.. count .. " owned affixes mirrored from PE. Dots will now "
				.. "show ONLY for missing affixes (in gold).")
		else
			print("|cffff8000[AutoDelete]|r affix collection mode |cffff5555OFF|r. "
				.. "Dots show on all affixed items, colored by tier.")
		end
	end)

	-- Tools tab: Bag Space Warning toggle.
	tglBagSpaceWarn:SetScript("OnClick", function(btn)
		btn._checked = not btn._checked
		btn:SetChecked(btn._checked)
		GetActiveProfile(db).bagSpaceWarnEnabled = btn._checked
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
		-- Switching lists -> the previous page index belongs to the OLD list
		-- and means nothing in the new one. Reset before Refresh so the user
		-- lands on page 1 of whatever they switched to.
		self._currentPage = 1
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
		-- Filter changed -> the visible set is now a different identity, so
		-- the user's previous page index is no longer meaningful. Reset to
		-- page 1 so they see results from the top of the filtered list.
		self._currentPage = 1
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

		-- Keybinds tab rows. Only the master toggle and the key-capture
		-- row live on each feature's row; per-feature filters (BoP/BoE/
		-- qualities/iLvl for Disenchant; Include-locked-tier for Open)
		-- live in the gear-button popup, which refreshes itself on Show.
		if self._tglDisenchant     then self._tglDisenchant:SetChecked(p.disenchantEnabled) end
		if self._disenchantKeyRow  and self._disenchantKeyRow._refresh then self._disenchantKeyRow:_refresh() end
		if self._refreshDisenchantStatus then self:_refreshDisenchantStatus() end

		if self._tglOpenEnabled then self._tglOpenEnabled:SetChecked(p.autoOpenEnabled) end
		if self._openKeyRow and self._openKeyRow._refresh then self._openKeyRow:_refresh() end
		if self._refreshOpenStatus then self:_refreshOpenStatus() end

		-- If the Disenchant filters popup is currently open, refresh its
		-- contents from the new profile values.
		if _G.AutoDelete_DisenchantFiltersPopup and
		   _G.AutoDelete_DisenchantFiltersPopup:IsShown() and
		   _G.AutoDelete_RefreshDisenchantFilters then
			_G.AutoDelete_RefreshDisenchantFilters()
		end

		-- Tools Card 1: Process Bags count summary.
		if self._refreshProcessCount then self:_refreshProcessCount() end

		-- Keybinds tab: Mill (Inscription)
		if self._tglMill then self._tglMill:SetChecked(p.millEnabled) end
		if self._millKeyRow and self._millKeyRow._refresh then
			self._millKeyRow:_refresh()
		end
		if self._refreshMillStatus then self:_refreshMillStatus() end

		-- Keybinds tab: Prospect (Jewelcrafting)
		if self._tglProspect then self._tglProspect:SetChecked(p.prospectEnabled) end
		if self._prospectKeyRow and self._prospectKeyRow._refresh then
			self._prospectKeyRow:_refresh()
		end
		if self._refreshProspectStatus then self:_refreshProspectStatus() end

		-- Affix tab: Affix Protection (Card 1). Only the No Auto-Sell
		-- toggle remains; No Auto-Delete was dropped.
		tglProtectAffixFromSell:SetChecked(p.protectAffixFromSell)
		affixFloorEdit:SetText(tostring(p.affixIlvlMin or 0))

		-- Filters tab: DE Filters (Card 2, v3.20 -- ported from the old
		-- Disenchant Filters popup that opened from a gear button on the
		-- Keybinds tab). Same profile fields as the popup version.
		if self._tglDisenchantBoP      then self._tglDisenchantBoP:SetChecked(p.disenchantBoP)          end
		if self._tglDisenchantBoE      then self._tglDisenchantBoE:SetChecked(p.disenchantBoE)          end
		if self._tglDisenchantUnc      then self._tglDisenchantUnc:SetChecked(p.disenchantUncommon)     end
		if self._tglDisenchantRare     then self._tglDisenchantRare:SetChecked(p.disenchantRare)        end
		if self._tglDisenchantEpic     then self._tglDisenchantEpic:SetChecked(p.disenchantEpic)        end
		if self._editDisenchantIlvlMin then self._editDisenchantIlvlMin:SetText(tostring(p.disenchantIlvlMin or 0)) end
		if self._editDisenchantIlvlMax then self._editDisenchantIlvlMax:SetText(tostring(p.disenchantIlvlMax or 0)) end

		-- Pets tab: Bag Warning + threshold (Card 3, moved from Tools tab)
		tglBagSpaceWarn:SetChecked(p.bagSpaceWarnEnabled)
		thresholdEdit:SetText(tostring(p.bagSpaceWarnThreshold or 5))

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

		-- Filters tab: Quality Filters (Card 1, moved from General tab)
		-- Quality Filters card now uses cycle pills, not checkboxes.
		-- Read the tri-state enum field; default to "off" if the migration
		-- somehow hasn't run yet (defensive; shouldn't happen post-v3).
		self._pillJunk:SetValue(p.qualityActionJunk or "off")
		self._pillCommon:SetValue(p.qualityActionCommon or "off")
		self._pillGreens:SetValue(p.qualityActionGreens or "off")

		-- General tab: Auto-Repair (Card 2, moved from Goblin tab)
		tglRepair:SetChecked(p.autoRepair)
		tglRepairGuild:SetChecked(p.autoRepairUseGuildBank)

		-- Pets tab: Scavenger + Goblin Merchant + Hide Greedy Spam
		tglScav:SetChecked(p.summonScavenger)
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
		self._tglShowAffixDot:SetChecked(p.showAffixDot ~= false)  -- default true if nil
		self._tglAffixCollection:SetChecked(p.affixCollectionMode == true)  -- default false if nil
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
			-- DO NOT reset self._currentPage here. Refresh runs on every
			-- list mutation (X-button delete, drag-add, cache poll), and
			-- a blanket reset jumps the user off whatever page they were
			-- viewing -- exactly the bug we hit when deleting from page 2+.
			-- Page-1 resets are triggered explicitly at the two call sites
			-- where the visible set genuinely changes identity: search-box
			-- OnTextChanged (filter applied) and SwitchTab (list switched).
			-- The UpdateListRows clamp below handles the "deleted the last
			-- item on the page" edge case by stepping back one page.
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
	-- Card needs to fit 7 buttons (26 tall) with 4px gaps, plus 8px top pad
	-- and some bottom pad. Required card height = 8 + 7*26 + 6*4 + bottom_pad.
	-- With bottom_pad=10 that's 224. Working backwards:
	--   card_H = body_H - 32 - 50  →  body_H = card_H + 82 = 306
	--   frame_H = body_H + 24     →  330
	local W, H = 340, 330
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
	-- 3-color semantic palette per Addon_UI_StyleGuide.md:
	--   Six options destructive (clear / remove user data) -> C_RED
	--   "Remove recipes & patterns..." opens a sub-picker  -> C_BLUE
	local options = {
		{ value = "Delete",   label = "Delete list",                     color = C_RED  },
		{ value = "Sell",     label = "Sell list",                       color = C_RED  },
		{ value = "Keep",     label = "Keep list",                       color = C_RED  },
		{ value = "All",      label = "All three lists",                 color = C_RED  },
		-- Remove Junk: scans Delete + Sell only, removes gray-quality items.
		{ value = "Junk",     label = "Remove junk items",               color = C_RED  },
		-- Remove Sellable: scans Delete only, removes items with vendor value.
		{ value = "Sellable", label = "Remove items with vendor value",  color = C_RED  },
		-- Remove Patterns: opens a sub-window listing each profession-style
		-- subtype (Pattern / Recipe / Plans / Schematic / Formula / Design /
		-- Technique / Manual). This is navigational, not directly destructive,
		-- so it gets C_BLUE per the change/transform class. Ellipsis on the
		-- label signals "opens another window."
		{ value = "Patterns", label = "Remove recipes & patterns...",    color = C_BLUE },
	}

	for i, opt in ipairs(options) do
		local b = MakeActionButton(card, opt.label, opt.color, nil, BTN_W, BTN_H)
		b:SetPoint("TOP", 0, -8 - ((i - 1) * (BTN_H + BTN_GAP)))
		-- MakeActionButton wires its own OnEnter/OnLeave (hover tint + white
		-- text). Only the click action is bespoke per row.
		b:SetScript("OnClick", function()
			clearFrame:Hide()
			-- "Patterns" routes to a sub-window (sibling, not confirm) so
			-- the user can pick which profession's items to remove. Every
			-- other option fires a confirm StaticPopup directly.
			if opt.value == "Patterns" then
				if _G.AutoDelete_ShowRemovePatternsPicker then
					_G.AutoDelete_ShowRemovePatternsPicker()
				end
				return
			end
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

-- ============================================================================
-- Remove Patterns by Profession Window
-- ============================================================================
-- Sub-window opened from the Clear List window's "Remove recipes & patterns..."
-- option. Lists each profession's craft-item subtype (Pattern / Recipe / Plans
-- / Schematic / Formula / Design / Technique / Manual). Clicking a row fires
-- the shared AUTODELETE_PROFILE_REMOVE_PATTERNS confirm popup with the chosen
-- subtype in popup.data; the OnAccept handler walks all three lists and
-- removes matching entries.

local removePatternsFrame

-- 8 profession buttons + chrome math:
--   card_H = 8 (top pad) + 8 * 26 (buttons) + 7 * 4 (gaps) + 10 (bottom pad) = 254
--   body_H = card_H + 32 (subtitle) + 50 (footer) = 336
--   frame_H = body_H + 24 (title bar) = 360
local PROFESSIONS_LIST = {
	-- Subtype string matches GetItemInfo()'s 7th return on 3.3.5a enUS.
	-- TODO: localize -- subtype strings differ on non-enUS clients.
	{ subtype = "Pattern",   label = "Patterns (Tailoring + Leatherworking)" },
	{ subtype = "Recipe",    label = "Recipes (Cooking + Alchemy)" },
	{ subtype = "Plans",     label = "Plans (Blacksmithing)" },
	{ subtype = "Schematic", label = "Schematics (Engineering)" },
	{ subtype = "Formula",   label = "Formulas (Enchanting)" },
	{ subtype = "Design",    label = "Designs (Jewelcrafting)" },
	{ subtype = "Technique", label = "Techniques (Inscription)" },
	{ subtype = "Manual",    label = "Manuals (First Aid)" },
}

local function BuildRemovePatternsWindow()
	if removePatternsFrame then return end

	local W, H = 360, 360
	local f, body = BuildPopupSkeleton("AutoDeleteRemovePatternsFrame",
		"Remove Patterns by Profession", W, H)
	removePatternsFrame = f

	-- Instruction text
	local sub = MakeText(body, 10, C_TEXT, "OUTLINE", "LEFT")
	sub:SetPoint("TOPLEFT", 15, -10)
	sub:SetPoint("TOPRIGHT", -15, -10)
	sub:SetHeight(16)
	sub:SetText("Pick which crafting items to scrub from your lists:")

	-- Card for the 8 buttons
	local card = CreateFrame("Frame", nil, body)
	card:SetPoint("TOPLEFT", 15, -32)
	card:SetPoint("BOTTOMRIGHT", -15, 50)
	ApplyBackdrop(card, { 14/255, 14/255, 14/255, 1 }, C_BORDER)

	local BTN_W, BTN_H = 310, 26
	local BTN_GAP = 4
	local PROF_COLOR = { 0.45, 0.85, 0.55, 1 }  -- match the launcher option color

	for i, prof in ipairs(PROFESSIONS_LIST) do
		local b = CreateFrame("Button", nil, card)
		b:SetSize(BTN_W, BTN_H)
		b:SetPoint("TOP", 0, -8 - ((i - 1) * (BTN_H + BTN_GAP)))
		ApplyBackdrop(b, C_ROW_ODD, C_BORDER)
		local txt = MakeText(b, 11, C_TEXT, "OUTLINE")
		txt:SetPoint("CENTER")
		txt:SetText(prof.label)
		b:SetScript("OnEnter", function(btn)
			btn:SetBackdropColor(PROF_COLOR[1], PROF_COLOR[2], PROF_COLOR[3], 0.3)
			btn:SetBackdropBorderColor(PROF_COLOR[1], PROF_COLOR[2], PROF_COLOR[3], 1)
			txt:SetTextColor(1, 1, 1)
		end)
		b:SetScript("OnLeave", function(btn)
			ApplyBackdrop(btn, C_ROW_ODD, C_BORDER)
			txt:SetTextColor(unpack(C_TEXT))
		end)
		b:SetScript("OnClick", function()
			removePatternsFrame:Hide()
			-- Confirm popup gets a payload table with both the subtype to
			-- match and a friendlier label for the prompt text. %s in the
			-- popup text expects a single string -- we use the label.
			local dlg = StaticPopup_Show("AUTODELETE_PROFILE_REMOVE_PATTERNS", prof.label)
			if dlg then
				dlg.data = { subtype = prof.subtype, label = prof.label }
			end
		end)
	end

	-- Cancel button in footer
	local cancelBtn = MakeDialogButton(body, "Cancel", function() removePatternsFrame:Hide() end)
	cancelBtn:SetPoint("BOTTOMRIGHT", -15, 15)
end

_G.AutoDelete_ShowRemovePatternsPicker = function()
	BuildRemovePatternsWindow()
	removePatternsFrame:Show()
end
