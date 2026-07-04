local function readFile(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

describe("Goblin Merchant full-bag defer gate", function()
	it("does not fake a completed bag walk when no delete rules are active", function()
		local autoDelete = readFile("AutoDelete.lua")
		local noDeleteRulesBranch = "if not hasWanted and not hasKeepOne and not hasKeepStack "
			.. "and not doGray and not doCommon and not doGreens and not doRares then"
		local branchStart = assert(autoDelete:find(
			noDeleteRulesBranch,
			1,
			true
		))
		local branchEnd = assert(autoDelete:find("_G%._AutoDelete_DebugDelEmptyLogged%s*=%s*false", branchStart))
		local branch = autoDelete:sub(branchStart, branchEnd)

		assert.is_nil(branch:find("_G%.AutoDelete_LastDeleteWalkAt%s*="))
		assert.is_nil(branch:find("_G%.AutoDelete_LastDeleteWalkEnqueued%s*="))
	end)

	it("lets the Merchant gate proceed when no delete rules can clear bags", function()
		local autoDelete = readFile("AutoDelete.lua")
		local marker = assert(autoDelete:find("local noDeleteRulesActive = not ProfileHasDeleteRules%(p%)"))
		local gate = assert(autoDelete:find("elseif noDeleteRulesActive or foundNothingLastWalk then", marker, true))
		local noWalk = assert(autoDelete:find("elseif not walkSinceBelow then", marker, true))

		assert.is_true(gate < noWalk)
		assert.is_not_nil(autoDelete:find('local fireReason = noDeleteRulesActive and "no%-delete%-rules"', gate))
		assert.is_not_nil(autoDelete:find('local waitReason = noDeleteRulesActive and "no%-delete%-rules%-waiting"', gate))
	end)
end)
