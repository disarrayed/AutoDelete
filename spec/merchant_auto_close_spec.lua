local function readFile(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

describe("Merchant auto-close setting", function()
	it("defaults to existing auto-close behavior but exposes a Pets merchant-card toggle", function()
		local autoDelete = readFile("AutoDelete.lua")
		local options = readFile("Options.lua")

		assert.is_not_nil(autoDelete:match("autoCloseMerchantAfterSell%s*=%s*true"))
		assert.is_not_nil(options:match("autoCloseMerchantAfterSell%s*=%s*true"))
		assert.is_nil(options:match('MakeToggle%(%s*card1,%s*"Close Vendor"'))
		assert.is_not_nil(options:match('MakeSubToggle%(%s*gCard2,%s*"Auto%-Close after sell"'))
		assert.is_not_nil(options:match("GetActiveProfile%(db%)%.autoCloseMerchantAfterSell%s*=%s*btn%._checked"))
		assert.is_not_nil(options:match("tglCloseVendor:SetChecked%(p%.autoCloseMerchantAfterSell%s*~=%s*false%)"))
	end)

	it("leaves the vendor open when the toggle is off", function()
		local autoDelete = readFile("AutoDelete.lua")
		local guardAt = autoDelete:find("profile%.autoCloseMerchantAfterSell%s*~=%s*false%s+and%s+MerchantFrame%s+and%s+MerchantFrame:IsShown%(%)")

		assert.is_not_nil(guardAt)
		assert.is_not_nil(autoDelete:sub(guardAt, guardAt + 180):match("MerchantFrame:Hide%(%)"))
	end)

	it("documents the Pets merchant-card answer for users", function()
		local readme = readFile("README.md")
		local changelog = readFile("CHANGELOG.md")

		assert.is_not_nil(readme:match("Auto%-Close after sell"))
		assert.is_not_nil(readme:match("unchecked leaves the vendor open"))
		assert.is_not_nil(changelog:match("Auto%-Close after sell"))
	end)
end)
