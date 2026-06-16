local function reloadRules()
	_G.AutoDelete_RecipeClassNames = nil
	_G.AutoDelete_RecipeSubtypeNames = nil
	_G.AutoDelete_IsRecipeLikeItem = nil
	_G.AutoDelete_IsKnownRecipeQualityEnabled = nil
	_G.AutoDelete_GetRecipeQualityLabel = nil
	_G.AutoDelete_GetKnownRecipeSellDecision = nil
	_G.AutoDelete_IsRecipeDeleteProtected = nil
	dofile("RecipeRules.lua")
end

local function profile(overrides)
	local p = {
		knownRecipeSellEnabled = true,
		knownRecipeSellCommon = true,
		knownRecipeSellUncommon = true,
		knownRecipeSellRare = false,
		knownRecipeSellEpic = false,
	}
	for key, value in pairs(overrides or {}) do
		p[key] = value
	end
	return p
end

describe("Sell Known Recipes rules", function()
	before_each(function()
		reloadRules()
		_G.AutoDelete_GetRecipeKnowledgeState = function()
			return "known"
		end
	end)

	it("identifies recipe-like items by class or profession subtype", function()
		assert.is_true(_G.AutoDelete_IsRecipeLikeItem("Recipe", nil))
		assert.is_true(_G.AutoDelete_IsRecipeLikeItem("Trade Goods", "Pattern"))
		assert.is_true(_G.AutoDelete_IsRecipeLikeItem("Trade Goods", "First Aid"))
		assert.is_false(_G.AutoDelete_IsRecipeLikeItem("Armor", "Plate"))
	end)

	it("maps recipe quality toggles to white, green, blue, and purple", function()
		local p = profile({ knownRecipeSellRare = true })
		assert.is_true(_G.AutoDelete_IsKnownRecipeQualityEnabled(p, 1))
		assert.is_true(_G.AutoDelete_IsKnownRecipeQualityEnabled(p, 2))
		assert.is_true(_G.AutoDelete_IsKnownRecipeQualityEnabled(p, 3))
		assert.is_false(_G.AutoDelete_IsKnownRecipeQualityEnabled(p, 4))
		assert.are.equal("White", _G.AutoDelete_GetRecipeQualityLabel(1))
		assert.are.equal("Green", _G.AutoDelete_GetRecipeQualityLabel(2))
		assert.are.equal("Blue", _G.AutoDelete_GetRecipeQualityLabel(3))
		assert.are.equal("Purple", _G.AutoDelete_GetRecipeQualityLabel(4))
	end)

	it("detects recipe knowledge from tooltip lines", function()
		assert.are.equal("known", _G.AutoDelete_DetectRecipeKnowledgeFromTooltipLines({
			"Use: Teaches you how to cook.",
			"Already known",
		}))
		assert.are.equal("known", _G.AutoDelete_DetectRecipeKnowledgeFromTooltipLines({
			"Use: Teaches you how to cook.",
			"ITEM_SPELL_KNOWN",
		}, "ITEM_SPELL_KNOWN"))
		assert.are.equal("unknown", _G.AutoDelete_DetectRecipeKnowledgeFromTooltipLines({
			"Use: Teaches you how to cook.",
			"Requires Cooking (300)",
		}))
		assert.are.equal("uncertain", _G.AutoDelete_DetectRecipeKnowledgeFromTooltipLines({}))
	end)

	it("sells a known recipe only when the quality toggle allows it", function()
		local action, reason, rule, state, qualityEnabled =
			_G.AutoDelete_GetKnownRecipeSellDecision(profile(), 0, 1, "item:1", "Recipe", nil, 2, false, false)

		assert.are.equal("sell", action)
		assert.are.equal("knownRecipe", reason)
		assert.are.equal("Sell Filters: Sell Known Recipes", rule)
		assert.are.equal("known", state)
		assert.is_true(qualityEnabled)
	end)

	it("protects known recipes when the quality toggle is off", function()
		local action, reason, rule, state, qualityEnabled =
			_G.AutoDelete_GetKnownRecipeSellDecision(profile(), 0, 1, "item:1", "Recipe", nil, 3, false, false)

		assert.are.equal("protect", action)
		assert.are.equal("Known recipe quality not enabled", reason)
		assert.are.equal("Known Recipe Protection", rule)
		assert.are.equal("known", state)
		assert.is_false(qualityEnabled)
	end)

	it("protects quest recipes with a clear reason", function()
		local action, reason, rule, state, qualityEnabled =
			_G.AutoDelete_GetKnownRecipeSellDecision(profile(), 0, 1, "item:1", "Recipe", nil, 2, true, false)

		assert.are.equal("protect", action)
		assert.are.equal("Quest recipe protected", reason)
		assert.are.equal("Known Recipe Protection", rule)
		assert.are.equal("known", state)
		assert.is_true(qualityEnabled)
	end)

	it("protects unknown and uncertain recipe knowledge states", function()
		_G.AutoDelete_GetRecipeKnowledgeState = function()
			return "unknown"
		end
		local action, reason, rule =
			_G.AutoDelete_GetKnownRecipeSellDecision(profile(), 0, 1, "item:1", "Recipe", nil, 2, false, false)

		assert.are.equal("protect", action)
		assert.are.equal("Unknown recipe protected", reason)
		assert.are.equal("Unknown Recipe Protection", rule)

		_G.AutoDelete_GetRecipeKnowledgeState = function()
			return "uncertain"
		end
		action, reason, rule =
			_G.AutoDelete_GetKnownRecipeSellDecision(profile(), 0, 1, "item:1", "Recipe", nil, 2, false, false)

		assert.are.equal("protect", action)
		assert.are.equal("Recipe knowledge unknown; kept safe", reason)
		assert.are.equal("Unknown Recipe Protection", rule)
	end)

	it("lets the explicit Sell list win before recipe protection", function()
		local action, reason, rule, state, qualityEnabled =
			_G.AutoDelete_GetKnownRecipeSellDecision(profile(), 0, 1, "item:1", "Recipe", nil, 4, true, true)

		assert.are.equal("sell", action)
		assert.are.equal("list", reason)
		assert.are.equal("Sell list", rule)
		assert.are.equal("explicit-sell", state)
		assert.is_nil(qualityEnabled)
	end)

	it("keeps auto-delete rules away from recipes but respects explicit list intent", function()
		local p = profile()
		assert.is_true(_G.AutoDelete_IsRecipeDeleteProtected(p, "Recipe", nil, "Junk"))
		assert.is_false(_G.AutoDelete_IsRecipeDeleteProtected(p, "Recipe", nil, "Delete list"))
		assert.is_false(_G.AutoDelete_IsRecipeDeleteProtected(p, "Recipe", nil, "KeepOne"))
		assert.is_false(_G.AutoDelete_IsRecipeDeleteProtected(p, "Recipe", nil, "KeepStack"))
		assert.is_false(_G.AutoDelete_IsRecipeDeleteProtected(p, "Armor", "Plate", "Junk"))
		assert.is_false(_G.AutoDelete_IsRecipeDeleteProtected(profile({ knownRecipeSellEnabled = false }), "Recipe", nil, "Junk"))
	end)
end)
