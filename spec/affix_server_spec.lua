describe("AutoDelete affix server helper", function()
	local Server

	setup(function()
		_G.AutoDelete_AffixServer = nil
		dofile("AffixServer.lua")
		Server = assert(_G.AutoDelete_AffixServer)
	end)

	it("parses learned-affix payload fields from the server packet", function()
		local function getSpellInfo(id)
			if id == 1001 then return "Iron Will IV", nil, "icon-iron" end
			if id == 1002 then return "Brain Hacker", nil, "icon-brain" end
		end

		local rows = Server.ParseLearnedAffixesPayload(
			"1001:250:2:4:0:1,1002:500:0:1:1:0",
			getSpellInfo)

		assert.are.equal(2, #rows)
		assert.are.same({
			id = 1001,
			name = "Iron Will IV",
			icon = "icon-iron",
			applyCost = 250,
			appliedCount = 2,
			difficulty = 4,
			weaponOnly = false,
			learned = true,
		}, rows[1])
		assert.are.same({
			id = 1002,
			name = "Brain Hacker",
			icon = "icon-brain",
			applyCost = 500,
			appliedCount = 0,
			difficulty = 1,
			weaponOnly = true,
			learned = false,
		}, rows[2])
	end)

	it("rejects addon messages that are not the player's server whisper reply", function()
		assert.is_true(Server.ShouldAcceptMessage("AAM0x9", "513\tbody", "WHISPER", "Disarrayed", "Disarrayed"))
		assert.is_true(Server.ShouldAcceptMessage("AAM0x9", "513\tbody", "WHISPER", "Disarrayed-Realm", "Disarrayed"))

		assert.is_false(Server.ShouldAcceptMessage("OTHER", "513\tbody", "WHISPER", "Disarrayed", "Disarrayed"))
		assert.is_false(Server.ShouldAcceptMessage("AAM0x9", "513\tbody", "PARTY", "Disarrayed", "Disarrayed"))
		assert.is_false(Server.ShouldAcceptMessage("AAM0x9", "513\tbody", "WHISPER", "Otherplayer", "Disarrayed"))
		assert.is_false(Server.ShouldAcceptMessage("AAM0x9", "999\tbody", "WHISPER", "Disarrayed", "Disarrayed"))
	end)

	it("parses direct and chunked learned-affix events", function()
		local evt, rest = Server.ParseEventPayload("513\tabc")
		assert.are.equal(513, evt)
		assert.are.equal("abc", rest)

		local chunk = Server.ParseChunk("@00AF\t001/002\tfirst-half")
		assert.are.equal("00AF", chunk.mid)
		assert.are.equal(1, chunk.index)
		assert.are.equal(2, chunk.total)
		assert.are.equal("first-half", chunk.slice)
	end)
end)
