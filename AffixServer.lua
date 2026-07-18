local Server = {}

Server.PREFIX = "AAM0x9"
Server.REQUEST_LEARNED = 313
Server.SEND_EXTRACTION_RESULT = 510
Server.SEND_LEARNED = 513
Server.REQUEST_THROTTLE_SECONDS = 5

local function normalizeSender(name)
	name = tostring(name or ""):lower()
	name = name:match("^([^-]+)") or name
	return name
end

function Server.ShouldAcceptMessage(prefix, payload, dist, sender, playerName)
	if prefix ~= Server.PREFIX then return false, "prefix" end
	if dist ~= "WHISPER" then return false, "dist" end
	if playerName and sender and normalizeSender(sender) ~= normalizeSender(playerName) then
		return false, "sender"
	end
	if type(payload) ~= "string" or payload == "" then
		return false, "payload"
	end
	local evtStr = payload:match("^(%d+)\t") or payload:match("^(%d+)$")
	local evt = tonumber(evtStr)
	if evt ~= Server.SEND_LEARNED and evt ~= Server.SEND_EXTRACTION_RESULT then
		return false, "event"
	end
	return true
end

function Server.GetLearnedRefreshDelay(now, lastRequestAt, throttleSeconds, minimumDelay)
	now = tonumber(now) or 0
	lastRequestAt = tonumber(lastRequestAt) or 0
	throttleSeconds = tonumber(throttleSeconds) or Server.REQUEST_THROTTLE_SECONDS
	minimumDelay = tonumber(minimumDelay) or 0.75
	if now <= 0 or lastRequestAt <= 0 or now < lastRequestAt then
		return minimumDelay
	end
	local remaining = throttleSeconds - (now - lastRequestAt)
	if remaining > minimumDelay then return remaining end
	return minimumDelay
end

function Server.ExtractionResultNeedsLearnedRefresh(body)
	if body == "OK" then return true end
	if type(body) ~= "string" then return false end
	local _, reason = body:match("^([^,]+),(.+)$")
	if not reason then return false end
	return reason:lower():find("already know this affix", 1, true) ~= nil
end

function Server.ParseEventPayload(payload)
	if type(payload) ~= "string" then return nil, nil end
	local evtStr, rest = payload:match("^(%d+)\t(.*)$")
	if not evtStr then
		evtStr = payload:match("^(%d+)$")
		rest = ""
	end
	return tonumber(evtStr), rest or ""
end

function Server.ParseChunk(rest)
	if type(rest) ~= "string" then return nil end
	local mid, idx, total, slice = rest:match(
		"^@([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])\t([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])/([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])\t(.*)$")
	if not mid then return nil end
	return {
		mid = mid,
		index = tonumber(idx, 16),
		total = tonumber(total, 16),
		slice = slice,
	}
end

function Server.ParseLearnedAffixesPayload(body, getSpellInfo)
	local affixes = {}
	if body and body ~= "" then
		for entry in string.gmatch(body, "([^,]+)") do
			local spellIdStr, applyCostStr, appliedCountStr, difficultyStr, weaponOnlyStr, learnedStr =
				entry:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)$")
			if spellIdStr then
				local spellId = tonumber(spellIdStr)
				local spellName, _, spellIcon
				if type(getSpellInfo) == "function" then
					spellName, _, spellIcon = getSpellInfo(spellId)
				end
				table.insert(affixes, {
					id = spellId,
					name = spellName or ("Affix " .. spellId),
					icon = spellIcon,
					applyCost = tonumber(applyCostStr),
					appliedCount = tonumber(appliedCountStr),
					difficulty = tonumber(difficultyStr),
					weaponOnly = tonumber(weaponOnlyStr) == 1,
					learned = tonumber(learnedStr) == 1,
				})
			end
		end
	end
	return affixes
end

_G.AutoDelete_AffixServer = Server
