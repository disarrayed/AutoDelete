-- Pure Sell Known Recipes rule helpers.
-- Kept separate so Busted can exercise the decision rules without loading WoW UI.

_G.AutoDelete_RecipeClassNames = {
	Recipe = true,
}

_G.AutoDelete_RecipeSubtypeNames = {
	Alchemy = true,
	Blacksmithing = true,
	Cooking = true,
	Design = true,
	Enchanting = true,
	Engineering = true,
	FirstAid = true,
	["First Aid"] = true,
	Formula = true,
	Inscription = true,
	Jewelcrafting = true,
	Leatherworking = true,
	Manual = true,
	Pattern = true,
	Plans = true,
	Recipe = true,
	Schematic = true,
	Tailoring = true,
	Technique = true,
}

_G.AutoDelete_RecipeExcludedNamePrefixes = {
	["tome of echo"] = true,
	["echo tome"] = true,
	["echo tomb"] = true,
}

function _G.AutoDelete_IsRecipeExcludedItem(itemName)
	if type(itemName) ~= "string" then return false end
	local linkedName = string.match(itemName, "%|h%[(.-)%]%|h")
	local normalizedName = string.lower(linkedName or itemName)
	for prefix in pairs(_G.AutoDelete_RecipeExcludedNamePrefixes) do
		if string.sub(normalizedName, 1, string.len(prefix)) == prefix then
			return true
		end
	end
	return false
end

function _G.AutoDelete_IsRecipeLikeItem(itemClass, itemSubType, itemName)
	if _G.AutoDelete_IsRecipeExcludedItem(itemName) then return false end
	if itemClass and _G.AutoDelete_RecipeClassNames[itemClass] then return true end
	if itemSubType and _G.AutoDelete_RecipeSubtypeNames[itemSubType] then return true end
	return false
end

function _G.AutoDelete_IsKnownRecipeQualityEnabled(profile, itemQuality)
	if not profile then return false end
	if itemQuality == 1 then return profile.knownRecipeSellCommon == true end
	if itemQuality == 2 then return profile.knownRecipeSellUncommon == true end
	if itemQuality == 3 then return profile.knownRecipeSellRare == true end
	if itemQuality == 4 then return profile.knownRecipeSellEpic == true end
	return false
end

function _G.AutoDelete_GetRecipeQualityLabel(itemQuality)
	if itemQuality == 1 then return "White" end
	if itemQuality == 2 then return "Green" end
	if itemQuality == 3 then return "Blue" end
	if itemQuality == 4 then return "Purple" end
	return tostring(itemQuality or "unknown")
end

function _G.AutoDelete_IsKnownRecipeBindEnabled(profile, bindState)
	if not profile then return false end
	if bindState == nil or bindState == "unknown" then return false end
	if bindState == "bop" or bindState == "soulbound" then
		return profile.knownRecipeSellBoP ~= false
	end
	return profile.knownRecipeSellBoE ~= false
end

function _G.AutoDelete_GetRecipeBindLabel(bindState)
	if bindState == "bop" or bindState == "soulbound" then return "BoP" end
	if bindState == nil or bindState == "unknown" then return "unknown" end
	return "BoE"
end

function _G.AutoDelete_DetectRecipeKnowledgeFromTooltipLines(lines, knownToken)
	if type(knownToken) ~= "string" or knownToken == "" then
		knownToken = "Already known"
	end
	if type(lines) ~= "table" or #lines == 0 then return "uncertain" end
	for _, text in ipairs(lines) do
		if type(text) == "string" and string.find(text, knownToken, 1, true) then
			return "known"
		end
	end
	return "unknown"
end

function _G.AutoDelete_GetRecipeKnowledgeCacheHit(cache, link)
	if not cache or not link then return nil end
	if cache[link] == "known" then return "known" end
	return nil
end

function _G.AutoDelete_RememberRecipeKnowledgeState(cache, link, state)
	if not cache or not link then return end
	if state == "known" then
		cache[link] = "known"
	else
		cache[link] = nil
	end
end

function _G.AutoDelete_GetKnownRecipeSellDecision(profile, bag, slot, link, itemClass, itemSubType, itemQuality, isQuestItem, onExplicitSell, itemName, bindState)
	if not profile or profile.knownRecipeSellEnabled ~= true then return nil end
	if not itemName and link and type(GetItemInfo) == "function" then
		itemName = GetItemInfo(link)
	end
	if not _G.AutoDelete_IsRecipeLikeItem(itemClass, itemSubType, itemName) then return nil end

	if onExplicitSell then
		return "sell", "list", "Sell list", "explicit-sell", nil
	end

	local state = _G.AutoDelete_GetRecipeKnowledgeState(bag, slot, link)
	local qualityEnabled = _G.AutoDelete_IsKnownRecipeQualityEnabled(profile, itemQuality)
	local bindEnabled = _G.AutoDelete_IsKnownRecipeBindEnabled(profile, bindState)
	if state == "known" then
		if isQuestItem then
			return "protect", "Quest recipe protected", "Known Recipe Protection", state, qualityEnabled, bindEnabled
		end
		if not qualityEnabled then
			return "protect", "Known recipe quality not enabled", "Known Recipe Protection", state, qualityEnabled, bindEnabled
		end
		if not bindEnabled then
			return "protect", "Known recipe bind type not enabled", "Known Recipe Protection", state, qualityEnabled, bindEnabled
		end
		return "sell", "knownRecipe", "Sell Filters: Sell Known Recipes", state, qualityEnabled, bindEnabled
	end

	if state == "uncertain" then
		return "protect", "Recipe knowledge unknown; kept safe", "Unknown Recipe Protection", state, qualityEnabled, bindEnabled
	end
	return "protect", "Unknown recipe protected", "Unknown Recipe Protection", state, qualityEnabled, bindEnabled
end

function _G.AutoDelete_IsRecipeDeleteProtected(profile, itemClass, itemSubType, sourceRule, itemName)
	return profile
		and profile.knownRecipeSellEnabled == true
		and _G.AutoDelete_IsRecipeLikeItem(itemClass, itemSubType, itemName)
		and sourceRule ~= "Delete list"
		and sourceRule ~= "KeepOne"
		and sourceRule ~= "KeepStack"
end
