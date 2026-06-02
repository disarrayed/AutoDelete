local function assertEq(actual, expected, label)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
	end
end

local function loadHelper()
	local f = assert(io.open("AutoDelete.lua", "r"))
	local src = f:read("*a")
	f:close()
	local helper = src:match("%-%- KEEPONE_TEST_HELPER_BEGIN(.-)%-%- KEEPONE_TEST_HELPER_END")
	if not helper then
		error("KeepOne test helper block is missing", 2)
	end
	assert(loadstring(helper))()
	if type(_G.AutoDelete_KeepOnePlanSlotAction) ~= "function" then
		error("AutoDelete_KeepOnePlanSlotAction is not defined", 2)
	end
	return _G.AutoDelete_KeepOnePlanSlotAction
end

local plan = loadHelper()

local action, amount = plan(1, 1)
assertEq(action, "keep", "one unit stays untouched")
assertEq(amount, 0, "one unit amount")

action, amount = plan(30, 30)
assertEq(action, "split-delete", "single stack keeps one unit")
assertEq(amount, 29, "single stack split amount")

action, amount = plan(30, 10)
assertEq(action, "delete-slot", "full stack can delete when other units remain")
assertEq(amount, 10, "full stack delete amount")

action, amount = plan(2, 2)
assertEq(action, "split-delete", "two-stack leaves one")
assertEq(amount, 1, "two-stack split amount")

print("keepone_unit_test.lua: OK")
