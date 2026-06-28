local function reloadLayout()
	_G.AutoDelete_OptionsLayout = nil
	return dofile("OptionsLayout.lua")
end

local function readFile(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

local function countMatches(text, pattern)
	local count = 0
	for _ in text:gmatch(pattern) do
		count = count + 1
	end
	return count
end

describe("Options UI layout math", function()
	local function byName(rects)
		local out = {}
		for _, rect in ipairs(rects) do
			out[rect.name] = rect
		end
		return out
	end

	local function bottom(rect)
		return rect.y + rect.h
	end

	local function right(rect)
		return rect.x + rect.w
	end

	local function bottomPadding(child, parent)
		return bottom(parent) - bottom(child)
	end

	local function assertWithin(child, parent)
		assert.is_true(child.x >= parent.x, child.name .. " x underflows " .. parent.name)
		assert.is_true(child.y >= parent.y, child.name .. " y underflows " .. parent.name)
		assert.is_true(right(child) <= right(parent), child.name .. " x overflows " .. parent.name)
		assert.is_true(bottom(child) <= bottom(parent), child.name .. " y overflows " .. parent.name)
	end

	it("keeps Search & Manage inside the options frame after Sell Filters", function()
		local layout = reloadLayout()
		local yOff = layout.SellFiltersYAfterListMode()
		local manageH = layout.ClampManageHeight(layout.FRAME_H, yOff, layout.MANAGE_BOTTOM_PAD)
		local manageBottom = math.abs(yOff) + layout.SECTION_TITLE_H + manageH

		assert.are.equal(906, layout.FRAME_H)
		assert.are.equal(-585, yOff)
		assert.are.equal(285, manageH)
		assert.is_true(manageBottom <= layout.FRAME_H)
	end)

	it("does not use the old fixed 220px Search & Manage minimum when it cannot fit", function()
		local layout = reloadLayout()
		local smallFrameH = 760
		local remaining = layout.RemainingManageHeight(smallFrameH)

		assert.is_true(remaining < 220)
		assert.are.equal(remaining, layout.ClampManageHeight(smallFrameH))
	end)

	it("keeps every declared Sell Filters section inside the options frame", function()
		local layout = reloadLayout()
		local rects = layout.BuildSellFiltersRects(layout.FRAME_H)
		local map = byName(rects)

		for _, rect in ipairs(rects) do
			if rect.parent then
				assertWithin(rect, map[rect.parent])
			end
		end
	end)

	it("keeps settings cards and their rows inside the Settings tab content", function()
		local layout = reloadLayout()
		local rects = byName(layout.BuildSellFiltersRects(layout.FRAME_H))

		for i = 1, 3 do
			assertWithin(rects["settings.card" .. tostring(i)], rects["settings.tabContent"])
			for row = 1, 3 do
				assertWithin(rects["settings.card" .. tostring(i) .. ".row" .. tostring(row)],
					rects["settings.card" .. tostring(i)])
			end
		end
	end)

	it("keeps the Pets merchant card controls inside the settings card", function()
		local layout = reloadLayout()
		local rects = byName(layout.BuildSellFiltersRects(layout.FRAME_H))

		assertWithin(rects["settings.pets.merchant.section"], rects["settings.tabContent"])
		assertWithin(rects["settings.pets.merchant.enable"], rects["settings.pets.merchant.section"])
		assertWithin(rects["settings.pets.merchant.autoClose"], rects["settings.pets.merchant.section"])
		assert.is_true(bottomPadding(rects["settings.pets.merchant.autoClose"],
			rects["settings.pets.merchant.section"]) >= 30)
	end)

	it("keeps all Sell Filters cards on one height", function()
		local layout = reloadLayout()
		local rects = byName(layout.BuildSellFiltersRects(layout.FRAME_H))
		local h = layout.SELL_CARD_H

		assert.are.equal(h, rects["sell.recipe.section"].h)
		assert.are.equal(h, rects["sell.boeArmor.section"].h)
		assert.are.equal(h, rects["sell.bop.section"].h)
		assert.are.equal(h, rects["sell.boeWeapons.section"].h)
		assert.are.equal(50, h)
		assert.are.equal(6, layout.SELL_CARD_BOTTOM_PAD)
	end)

	it("keeps gear-card horizontal math derived from shared constants", function()
		local layout = reloadLayout()

		assert.are.equal(layout.SELL_OPTION_GAP,
			layout.GEAR_EPIC_X - layout.GEAR_RARE_X - layout.SELL_OPTION_W)
		assert.are.equal((layout.GEAR_SPINNER_X - layout.GEAR_ILVL_ROW_X)
			+ layout.GEAR_SPINNER_W + layout.GEAR_TO_LABEL_GAP
			+ layout.GEAR_TO_LABEL_W + layout.GEAR_TO_LABEL_GAP + layout.GEAR_SPINNER_W,
			layout.GEAR_ILVL_ROW_W)
	end)

	it("does not render more list rows than the list box can hold", function()
		local layout = reloadLayout()
		local manageH = layout.ClampManageHeight(layout.FRAME_H)
		local rows, listHeight = layout.ListRowsForManageHeight(manageH)
		local used = rows * layout.LIST_ROW_H

		assert.is_true(used <= listHeight)
		assert.are.equal(10, rows)
		assert.are.equal(183, listHeight)
	end)

	it("keeps every declared list row inside the list box", function()
		local layout = reloadLayout()
		local rects = byName(layout.BuildSellFiltersRects(layout.FRAME_H))
		local rows = layout.ListRowsForManageHeight(rects["manage.section"].h)

		for i = 1, rows do
			assertWithin(rects["manage.row" .. tostring(i)], rects["manage.listBox"])
		end
	end)

	it("keeps Search & Manage child bands inside the Search & Manage card", function()
		local layout = reloadLayout()
		local rects = byName(layout.BuildSellFiltersRects(layout.FRAME_H))

		assert.are.equal(layout.MANAGE_HEADER_Y + layout.MANAGE_HEADER_H, layout.MANAGE_LIST_Y)
		assert.are.equal(layout.MANAGE_PAGING_GAP + layout.MANAGE_PAGING_H + layout.MANAGE_PAGING_GAP,
			layout.MANAGE_BOTTOM_RESERVED)
		assertWithin(rects["manage.searchRow"], rects["manage.section"])
		assertWithin(rects["manage.header"], rects["manage.section"])
		assertWithin(rects["manage.listBox"], rects["manage.section"])
		assertWithin(rects["manage.pagination"], rects["manage.section"])
		assert.is_true(bottom(rects["manage.listBox"]) <= rects["manage.pagination"].y)
	end)

	it("keeps list mode tabs inside the List Mode card", function()
		local layout = reloadLayout()
		local rects = byName(layout.BuildSellFiltersRects(layout.FRAME_H))

		for i = 1, 5 do
			assertWithin(rects["listMode.tab" .. tostring(i)], rects["listMode.section"])
		end
	end)

	it("keeps Sell Known Recipes rows inside the recipe card", function()
		local layout = reloadLayout()
		local rects = byName(layout.BuildSellFiltersRects(layout.FRAME_H))
		local names = {
			"enable",
			"boe",
			"bop",
			"white",
			"green",
			"blue",
			"purple",
		}

		for _, name in ipairs(names) do
			assertWithin(rects["sell.recipe." .. name], rects["sell.recipe.section"])
		end
		assert.is_nil(rects["sell.recipe.rarityLabel"])
		assert.are.equal(layout.SELL_CARD_BOTTOM_PAD, bottomPadding(rects["sell.recipe.white"], rects["sell.recipe.section"]))
		assert.are.equal(layout.SELL_CARD_BOTTOM_PAD, bottomPadding(rects["sell.recipe.green"], rects["sell.recipe.section"]))
		assert.are.equal(layout.SELL_CARD_BOTTOM_PAD, bottomPadding(rects["sell.recipe.blue"], rects["sell.recipe.section"]))
		assert.are.equal(layout.SELL_CARD_BOTTOM_PAD, bottomPadding(rects["sell.recipe.purple"], rects["sell.recipe.section"]))
	end)

	it("keeps Sell Known Recipes compact rows aligned", function()
		local layout = reloadLayout()
		local rects = byName(layout.BuildSellFiltersRects(layout.FRAME_H))
		local rowNames = { "boe", "bop", "white", "green", "blue", "purple" }

		assert.are_not.equal(rects["sell.recipe.enable"].y, rects["sell.recipe.boe"].y)
		assert.are.equal(rects["sell.recipe.boe"].y, rects["sell.recipe.bop"].y)
		assert.are.equal(rects["sell.recipe.white"].y, rects["sell.recipe.green"].y)
		assert.are.equal(rects["sell.recipe.green"].y, rects["sell.recipe.blue"].y)
		assert.are.equal(rects["sell.recipe.blue"].y, rects["sell.recipe.purple"].y)
		assert.is_nil(rects["sell.recipe.rarityLabel"])
		assert.are.equal(rects["sell.recipe.enable"].x, rects["sell.recipe.boe"].x)
		assert.are.equal(layout.RECIPE_ENABLE_X, layout.RECIPE_BOE_X)
		assert.are.equal(rects["sell.boeArmor.rare"].x, rects["sell.recipe.blue"].x)
		assert.are.equal(rects["sell.boeArmor.epic"].x, rects["sell.recipe.purple"].x)
		assert.are.equal(16, rects["sell.recipe.bop"].x - right(rects["sell.recipe.boe"]))
		assert.are.equal(16, rects["sell.recipe.green"].x - right(rects["sell.recipe.white"]))
		assert.are.equal(16, rects["sell.recipe.blue"].x - right(rects["sell.recipe.green"]))
		assert.are.equal(16, rects["sell.recipe.purple"].x - right(rects["sell.recipe.blue"]))
		assert.is_true(rects["sell.recipe.white"].x - right(rects["sell.recipe.bop"]) > 16)
		for _, name in ipairs(rowNames) do
			local rect = rects["sell.recipe." .. name]
			assert.are.equal(rects["sell.recipe.boe"].y, rect.y)
			assert.are.equal(rects["sell.recipe.boe"].w, rect.w)
			assert.are.equal(rects["sell.recipe.boe"].h, rect.h)
		end
	end)

	it("keeps gear sell card controls inside each gear card", function()
		local layout = reloadLayout()
		local rects = byName(layout.BuildSellFiltersRects(layout.FRAME_H))
		local cards = { "sell.boeArmor", "sell.bop", "sell.boeWeapons" }
		local controls = { "enable", "rare", "epic", "ilvlRow" }

		for _, card in ipairs(cards) do
			for _, control in ipairs(controls) do
				assertWithin(rects[card .. "." .. control], rects[card .. ".section"])
			end
			assert.are.equal(layout.SELL_CARD_BOTTOM_PAD, bottomPadding(rects[card .. ".ilvlRow"], rects[card .. ".section"]))
		end
	end)

	it("keeps the Sell Known Recipes controls on one checkbox size", function()
		local options = readFile("Options.lua")
		local toggles = { "boe", "bop", "common", "uncommon", "rare", "epic" }

		assert.is_nil(options:match("self%._knownRecipes%.[%w_]+%s*=%s*MakeSubToggle"))
		assert.is_not_nil(options:match("box:SetSize%(%s*14,%s*14%s*%)"))
		assert.is_not_nil(options:match("indicator:SetSize%(%s*14,%s*14%s*%)"))
		for _, name in ipairs(toggles) do
			assert.is_not_nil(options:match("self%._knownRecipes%." .. name .. "%s*=%s*MakeToggle"))
			assert.is_not_nil(options:match("self%._knownRecipes%." .. name ..
				":SetSize%(%s*%(SELL_LAYOUT and SELL_LAYOUT%.SELL_OPTION_W%) or 60,%s*" ..
				"%(SELL_LAYOUT and SELL_LAYOUT%.SELL_OPTION_H%) or 20%s*%)"))
		end
	end)

	it("keeps gear card spinner row tied to the shared layout constants", function()
		local options = readFile("Options.lua")

		assert.is_nil(options:match("MakeSpinnerInput%(%s*card,%s*SPINNER_W"))
		assert.is_nil(options:match("MakeSpinnerInput%(%s*ilvlRow,%s*SPINNER_W,%s*20"))
		assert.are.equal(2, countMatches(options,
			"MakeSpinnerInput%(%s*ilvlRow,%s*SPINNER_W,%s*%(SELL_LAYOUT and SELL_LAYOUT%.SELL_OPTION_H%) or 20"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.GEAR_ILVL_ROW_W"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.GEAR_SPINNER_W"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.GEAR_TO_LABEL_GAP"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.GEAR_TO_LABEL_W"))
	end)

	it("loads OptionsLayout before Options in the addon TOC", function()
		local toc = readFile("AutoDelete.toc")
		local layoutAt = toc:find("OptionsLayout%.lua")
		local optionsAt = toc:find("Options%.lua")

		assert.is_not_nil(layoutAt)
		assert.is_not_nil(optionsAt)
		assert.is_true(layoutAt < optionsAt)
	end)

	it("keeps frame size and Sell Filters heights owned by OptionsLayout", function()
		local options = readFile("Options.lua")

		assert.is_not_nil(options:match("AutoDelete_OptionsLayout%.FRAME_W"))
		assert.is_not_nil(options:match("AutoDelete_OptionsLayout%.FRAME_H"))
		assert.is_not_nil(options:match("AutoDelete_OptionsLayout%.SELL_CARD_H"))
		assert.is_not_nil(options:match("AutoDelete_OptionsLayout%.SELL_BANNER_H"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.SELL_CARD_TOP_Y"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.SELL_CARD_LABEL_Y"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.SELL_OPTION_W"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.SELL_OPTION_H"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.SELL_OPTION_GAP"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.GEAR_ENABLE_X"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.GEAR_ENABLE_W"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.GEAR_RARE_X"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.GEAR_EPIC_X"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.GEAR_ILVL_ROW_X"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.GEAR_ILVL_ROW_W"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.GEAR_SPINNER_X"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.GEAR_SPINNER_W"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.GEAR_TO_LABEL_GAP"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.GEAR_TO_LABEL_W"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.RECIPE_ENABLE_X"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.RECIPE_ENABLE_W"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.RECIPE_BOE_X"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.RECIPE_BOP_X"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.RECIPE_WHITE_X"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.RECIPE_GREEN_X"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.RECIPE_BLUE_X"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.RECIPE_PURPLE_X"))
		assert.is_not_nil(options:match("SELL_LAYOUT%.SELL_CARD_ROW_Y"))
		assert.is_not_nil(options:match("AutoDelete_OptionsLayout%.LIST_MODE_CARD_H"))
		assert.is_not_nil(options:match("AutoDelete_OptionsLayout%.LIST_MODE_H"))
		assert.is_not_nil(options:match("MANAGE_LAYOUT%.MANAGE_LIST_Y"))
		assert.is_not_nil(options:match("MANAGE_LAYOUT%.MANAGE_BOTTOM_RESERVED"))
	end)

	it("keeps Search & Manage height and list rows bound by layout math", function()
		local options = readFile("Options.lua")

		assert.is_not_nil(options:match("AutoDelete_OptionsLayout%.ClampManageHeight"))
		assert.is_not_nil(options:match("AutoDelete_OptionsLayout%.ListRowsForManageHeight"))
		assert.is_not_nil(options:match("for%s+i%s*=%s*1,%s*NUM_ROWS%s+do"))
		assert.is_not_nil(options:match("self%._pageSize%s*=%s*NUM_ROWS"))
		assert.is_not_nil(options:match("FauxScrollFrame_Update%(%s*scroll,%s*pageItemCount,%s*NUM_ROWS,%s*ROW_HEIGHT%s*%)"))
		assert.is_nil(options:match('SetPoint%("TOPLEFT",%s*1,%s*%-40%)'))
		assert.is_nil(options:match('SetPoint%("TOPLEFT",%s*1,%s*%-62%)'))
		assert.is_nil(options:match('SetPoint%("BOTTOMRIGHT",%s*%-1,%s*36%)'))
		assert.is_nil(options:match("if%s+manageH%s*<%s*220%s+then%s+manageH%s*=%s*220%s+end"))
		assert.is_nil(options:match("if%s+NUM_ROWS%s*<%s*5%s+then%s+NUM_ROWS%s*=%s*5%s+end"))
		assert.is_not_nil(options:match("if%s+NUM_ROWS%s*<%s*1%s+then%s+NUM_ROWS%s*=%s*1%s+end"))
	end)
end)
