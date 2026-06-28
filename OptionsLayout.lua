-- Pure layout math for Options.lua. Kept free of WoW APIs so Busted can guard
-- frame-fit regressions before the addon is loaded in-client.

local Layout = {}

Layout.FRAME_H = 906
Layout.FRAME_W = 580
Layout.FRAME_BOTTOM_CHROME = 28
Layout.SECTION_GAP = 6
Layout.SECTION_TITLE_H = 16
Layout.SETTINGS_Y = -36

Layout.TAB_STRIP_H = 26
Layout.TAB_STRIP_GAP = 6
Layout.TAB_CONTENT_H = 100
Layout.TAB_INNER_PAD = 6

Layout.SELL_BANNER_H = 24
Layout.SELL_OPTION_W = 60
Layout.SELL_OPTION_H = 20
Layout.SELL_CARD_TOP_Y = 3
Layout.SELL_CARD_ROW_Y = 24
Layout.SELL_CARD_BOTTOM_PAD = 6
Layout.SELL_CARD_H = Layout.SELL_CARD_ROW_Y + Layout.SELL_OPTION_H + Layout.SELL_CARD_BOTTOM_PAD
Layout.SELL_CARD_LABEL_Y = 28
Layout.SELL_OPTION_GAP = 16
Layout.GEAR_ENABLE_X = 15
Layout.GEAR_ENABLE_W = 140
Layout.GEAR_RARE_X = 399
Layout.GEAR_EPIC_X = 475
Layout.GEAR_ILVL_ROW_X = 15
Layout.GEAR_SPINNER_X = 70
Layout.GEAR_SPINNER_W = 100
Layout.GEAR_TO_LABEL_GAP = 8
Layout.GEAR_TO_LABEL_W = 16
Layout.GEAR_ILVL_ROW_W = (Layout.GEAR_SPINNER_X - Layout.GEAR_ILVL_ROW_X)
	+ Layout.GEAR_SPINNER_W + Layout.GEAR_TO_LABEL_GAP
	+ Layout.GEAR_TO_LABEL_W + Layout.GEAR_TO_LABEL_GAP + Layout.GEAR_SPINNER_W
Layout.RECIPE_ENABLE_X = 15
Layout.RECIPE_ENABLE_W = 150
Layout.RECIPE_BOE_X = Layout.RECIPE_ENABLE_X
Layout.RECIPE_BOP_X = Layout.RECIPE_BOE_X + Layout.SELL_OPTION_W + Layout.SELL_OPTION_GAP
Layout.RECIPE_BLUE_X = Layout.GEAR_RARE_X
Layout.RECIPE_PURPLE_X = Layout.GEAR_EPIC_X
Layout.RECIPE_GREEN_X = Layout.RECIPE_BLUE_X - Layout.SELL_OPTION_W - Layout.SELL_OPTION_GAP
Layout.RECIPE_WHITE_X = Layout.RECIPE_GREEN_X - Layout.SELL_OPTION_W - Layout.SELL_OPTION_GAP
Layout.LIST_MODE_CARD_H = 34
Layout.LIST_MODE_AUTOSIZE_PAD = 8
Layout.LIST_MODE_H = Layout.LIST_MODE_CARD_H + 1 + Layout.LIST_MODE_AUTOSIZE_PAD
Layout.MANAGE_BOTTOM_PAD = 8
Layout.MANAGE_SEARCH_Y = 12
Layout.MANAGE_SEARCH_H = 22
Layout.MANAGE_HEADER_Y = 40
Layout.MANAGE_HEADER_H = 22
Layout.MANAGE_LIST_Y = Layout.MANAGE_HEADER_Y + Layout.MANAGE_HEADER_H
Layout.MANAGE_INSET = 1
Layout.MANAGE_PAGING_GAP = 6
Layout.MANAGE_PAGING_H = 24
Layout.MANAGE_TOP_RESERVED = Layout.MANAGE_LIST_Y
Layout.MANAGE_BOTTOM_RESERVED = Layout.MANAGE_PAGING_GAP + Layout.MANAGE_PAGING_H + Layout.MANAGE_PAGING_GAP
Layout.MANAGE_BORDER_RESERVED = 4
Layout.LIST_ROW_H = 18
Layout.LIST_MAX_ROWS = 10
Layout.CONTENT_W = 550
Layout.TAB_CARD_GAP = 6
Layout.SETTINGS_CARD_H = 92

function Layout.TabbedSectionHeight()
	return Layout.TAB_STRIP_H + Layout.TAB_STRIP_GAP + Layout.TAB_CONTENT_H + Layout.TAB_INNER_PAD * 2
end

local function consumeSection(yOff, height)
	return yOff - Layout.SECTION_TITLE_H - height - Layout.SECTION_GAP
end

function Layout.SellFiltersYAfterListMode()
	local yOff = Layout.SETTINGS_Y
	yOff = consumeSection(yOff, Layout.TabbedSectionHeight())
	yOff = yOff - Layout.SELL_BANNER_H - Layout.SECTION_GAP
	for _ = 1, 4 do
		yOff = consumeSection(yOff, Layout.SELL_CARD_H)
	end
	yOff = consumeSection(yOff, Layout.LIST_MODE_H)
	return yOff
end

function Layout.RemainingManageHeight(frameHeight, yOff, bottomPad)
	frameHeight = frameHeight or Layout.FRAME_H
	yOff = yOff or Layout.SellFiltersYAfterListMode()
	bottomPad = bottomPad or Layout.MANAGE_BOTTOM_PAD
	return frameHeight - Layout.FRAME_BOTTOM_CHROME - math.abs(yOff) - bottomPad
end

function Layout.ClampManageHeight(frameHeight, yOff, bottomPad)
	local h = Layout.RemainingManageHeight(frameHeight, yOff, bottomPad)
	if h < 1 then h = 1 end
	return h
end

function Layout.ListBoxHeight(manageHeight)
	return manageHeight - Layout.MANAGE_TOP_RESERVED - Layout.MANAGE_BOTTOM_RESERVED
end

function Layout.ListRowsForManageHeight(manageHeight)
	local listHeight = manageHeight - Layout.MANAGE_TOP_RESERVED
		- Layout.MANAGE_BOTTOM_RESERVED - Layout.MANAGE_BORDER_RESERVED
	local rows = math.floor(listHeight / Layout.LIST_ROW_H)
	if rows < 1 then rows = 1 end
	if rows > Layout.LIST_MAX_ROWS then rows = Layout.LIST_MAX_ROWS end
	return rows, listHeight
end

function Layout.BuildSellFiltersRects(frameHeight)
	frameHeight = frameHeight or Layout.FRAME_H
	local rects = {}
	local yOff = Layout.SETTINGS_Y

	local function addRect(name, parent, x, y, w, h)
		rects[#rects + 1] = { name = name, parent = parent, x = x, y = y, w = w, h = h }
		return rects[#rects]
	end

	addRect("frame", nil, 0, 0, Layout.FRAME_W, frameHeight)
	local settingsH = Layout.TabbedSectionHeight()
	local settings = addRect("settings.section", "frame", 15, math.abs(yOff) + Layout.SECTION_TITLE_H,
		Layout.CONTENT_W, settingsH)
	addRect("settings.tabStrip", "settings.section", settings.x + Layout.TAB_INNER_PAD,
		settings.y + Layout.TAB_INNER_PAD, Layout.CONTENT_W - Layout.TAB_INNER_PAD * 2, Layout.TAB_STRIP_H)
	local tabContent = addRect("settings.tabContent", "settings.section", settings.x + Layout.TAB_INNER_PAD,
		settings.y + Layout.TAB_INNER_PAD + Layout.TAB_STRIP_H + Layout.TAB_STRIP_GAP,
		Layout.CONTENT_W - Layout.TAB_INNER_PAD * 2, Layout.TAB_CONTENT_H)
	local cardW = math.floor((tabContent.w - Layout.TAB_CARD_GAP * 2) / 3)
	for i = 0, 2 do
		local card = addRect("settings.card" .. tostring(i + 1), "settings.tabContent",
			tabContent.x + i * (cardW + Layout.TAB_CARD_GAP), tabContent.y + 4, cardW, Layout.SETTINGS_CARD_H)
		addRect("settings.card" .. tostring(i + 1) .. ".row1", card.name, card.x + 10, card.y + 6,
			card.w - 20, 20)
		addRect("settings.card" .. tostring(i + 1) .. ".row2", card.name, card.x + 10, card.y + 28,
			card.w - 20, 20)
		addRect("settings.card" .. tostring(i + 1) .. ".row3", card.name, card.x + 10, card.y + 50,
			card.w - 20, 20)
	end
	local petMerchantCard = addRect("settings.pets.merchant.section", "settings.tabContent",
		tabContent.x + cardW + Layout.TAB_CARD_GAP, tabContent.y + 4, cardW, Layout.SETTINGS_CARD_H)
	addRect("settings.pets.merchant.enable", petMerchantCard.name, petMerchantCard.x + 10,
		petMerchantCard.y + 6, petMerchantCard.w - 20, 20)
	addRect("settings.pets.merchant.autoClose", petMerchantCard.name, petMerchantCard.x + 32,
		petMerchantCard.y + 30, petMerchantCard.w - 42, 16)
	yOff = consumeSection(yOff, settingsH)

	addRect("sell.banner", "frame", 15, math.abs(yOff), 550, Layout.SELL_BANNER_H)
	yOff = yOff - Layout.SELL_BANNER_H - Layout.SECTION_GAP

	local sellNames = {
		"sell.recipe",
		"sell.boeArmor",
		"sell.bop",
		"sell.boeWeapons",
	}
	local recipeRect = nil
	for _, name in ipairs(sellNames) do
		local card = addRect(name .. ".section", "frame", 15, math.abs(yOff) + Layout.SECTION_TITLE_H,
			550, Layout.SELL_CARD_H)
		if name == "sell.recipe" then
			recipeRect = card
		else
			addRect(name .. ".enable", card.name, card.x + Layout.GEAR_ENABLE_X,
				card.y + Layout.SELL_CARD_TOP_Y, Layout.GEAR_ENABLE_W, Layout.SELL_OPTION_H)
			addRect(name .. ".rare", card.name, card.x + Layout.GEAR_RARE_X,
				card.y + Layout.SELL_CARD_TOP_Y, Layout.SELL_OPTION_W, Layout.SELL_OPTION_H)
			addRect(name .. ".epic", card.name, card.x + Layout.GEAR_EPIC_X,
				card.y + Layout.SELL_CARD_TOP_Y, Layout.SELL_OPTION_W, Layout.SELL_OPTION_H)
			addRect(name .. ".ilvlRow", card.name, card.x + Layout.GEAR_ILVL_ROW_X,
				card.y + Layout.SELL_CARD_ROW_Y, Layout.GEAR_ILVL_ROW_W, Layout.SELL_OPTION_H)
		end
		yOff = consumeSection(yOff, Layout.SELL_CARD_H)
	end
	if recipeRect then
		addRect("sell.recipe.enable", recipeRect.name, recipeRect.x + Layout.RECIPE_ENABLE_X,
			recipeRect.y + Layout.SELL_CARD_TOP_Y, Layout.RECIPE_ENABLE_W, Layout.SELL_OPTION_H)
		addRect("sell.recipe.boe", recipeRect.name, recipeRect.x + Layout.RECIPE_BOE_X,
			recipeRect.y + Layout.SELL_CARD_ROW_Y, Layout.SELL_OPTION_W, Layout.SELL_OPTION_H)
		addRect("sell.recipe.bop", recipeRect.name, recipeRect.x + Layout.RECIPE_BOP_X,
			recipeRect.y + Layout.SELL_CARD_ROW_Y, Layout.SELL_OPTION_W, Layout.SELL_OPTION_H)
		addRect("sell.recipe.white", recipeRect.name, recipeRect.x + Layout.RECIPE_WHITE_X,
			recipeRect.y + Layout.SELL_CARD_ROW_Y, Layout.SELL_OPTION_W, Layout.SELL_OPTION_H)
		addRect("sell.recipe.green", recipeRect.name, recipeRect.x + Layout.RECIPE_GREEN_X,
			recipeRect.y + Layout.SELL_CARD_ROW_Y, Layout.SELL_OPTION_W, Layout.SELL_OPTION_H)
		addRect("sell.recipe.blue", recipeRect.name, recipeRect.x + Layout.RECIPE_BLUE_X,
			recipeRect.y + Layout.SELL_CARD_ROW_Y, Layout.SELL_OPTION_W, Layout.SELL_OPTION_H)
		addRect("sell.recipe.purple", recipeRect.name, recipeRect.x + Layout.RECIPE_PURPLE_X,
			recipeRect.y + Layout.SELL_CARD_ROW_Y, Layout.SELL_OPTION_W, Layout.SELL_OPTION_H)
	end

	local listMode = addRect("listMode.section", "frame", 15, math.abs(yOff) + Layout.SECTION_TITLE_H,
		550, Layout.LIST_MODE_H)
	local tabW = math.floor((548 - 16 - 24) / 5)
	for i = 0, 4 do
		addRect("listMode.tab" .. tostring(i + 1), listMode.name, listMode.x + 9 + i * (tabW + 6),
			listMode.y + 4, tabW, 26)
	end
	yOff = consumeSection(yOff, Layout.LIST_MODE_H)

	local manageH = Layout.ClampManageHeight(frameHeight, yOff, Layout.MANAGE_BOTTOM_PAD)
	local manage = addRect("manage.section", "frame", 15, math.abs(yOff) + Layout.SECTION_TITLE_H,
		550, manageH)
	addRect("manage.searchRow", "manage.section", manage.x + 12, manage.y + Layout.MANAGE_SEARCH_Y, 510,
		Layout.MANAGE_SEARCH_H)
	addRect("manage.header", "manage.section", manage.x + Layout.MANAGE_INSET,
		manage.y + Layout.MANAGE_HEADER_Y, 548, Layout.MANAGE_HEADER_H)
	local listBox = addRect("manage.listBox", "manage.section", manage.x + Layout.MANAGE_INSET,
		manage.y + Layout.MANAGE_LIST_Y, 548,
		Layout.ListBoxHeight(manageH))
	addRect("manage.pagination", "manage.section", manage.x + Layout.MANAGE_INSET,
		manage.y + manageH - Layout.MANAGE_BOTTOM_RESERVED, 548, Layout.MANAGE_BOTTOM_RESERVED)
	local rows = Layout.ListRowsForManageHeight(manageH)
	for i = 1, rows do
		addRect("manage.row" .. tostring(i), "manage.listBox", listBox.x + 1,
			listBox.y + 1 + (i - 1) * Layout.LIST_ROW_H, listBox.w - 2, Layout.LIST_ROW_H)
	end

	return rects
end

_G.AutoDelete_OptionsLayout = Layout

return Layout
