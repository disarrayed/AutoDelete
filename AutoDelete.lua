local ADDON_NAME = ...

-- ============================================================================
-- API upvalues
-- ============================================================================
-- File-top cache of hot-path Blizzard / Lua APIs as upvalues. A global lookup
-- is slower than a local read, so anything called in a per-bag-slot or
-- per-frame loop gets pinned here once and reused via the local symbol below.
-- Functions in
-- this file that capture these names by their original spelling continue
-- to resolve to the same value -- the local just shadows the global lookup.
--
-- Gathered in a table to keep the file-scope local count tame (Lua 5.1 caps
-- main-chunk locals at 200, and the rest of this file is already dense).
-- Call sites read `API.GetItemInfo(link)` etc. -- one table-field lookup
-- instead of a _G global resolve. Same perf class, much smaller local-count
-- footprint.
local API = {
	GetTime              = GetTime,
	GetItemInfo          = GetItemInfo,
	GetContainerItemInfo = GetContainerItemInfo,
	GetContainerItemLink = GetContainerItemLink,
	GetContainerNumSlots = GetContainerNumSlots,
	InCombatLockdown     = InCombatLockdown,
	UnitAffectingCombat  = UnitAffectingCombat,
	pairs                = pairs,
	ipairs               = ipairs,
	tinsert              = table.insert,
	tremove              = table.remove,
	wipe                 = wipe,
	format               = string.format,
	find                 = string.find,
	sub                  = string.sub,
	match                = string.match,
	gmatch               = string.gmatch,
	lower                = string.lower,
	floor                = math.floor,
	max                  = math.max,
	min                  = math.min,
}

function _G.AutoDelete_RegisterSpecialFrame(globalName)
	if not globalName or not UISpecialFrames then return end
	for _, existingName in API.ipairs(UISpecialFrames) do
		if existingName == globalName then return end
	end
	API.tinsert(UISpecialFrames, globalName)
end

-- ============================================================================
-- Perf instrumentation (opt-in via /del perf)
-- ============================================================================
-- Backed by debugprofilestop(), available on 3.3.5a since 2.0 -- returns
-- ms with sub-ms precision since UI init.
--
-- IMPORTANT: this module deliberately uses ONLY globals (no file-locals).
-- AutoDelete.lua's main chunk is right at Lua 5.1's 200-local cap; adding
-- six file-locals here for the perf functions pushed parsing over the
-- edge and broke the addon (see git history, the regression that broke
-- MakeSubToggle in Options.lua). Globals are slower per-call but the
-- whole point of AutoDelete_PerfBegin is a nil-check early return when disabled,
-- so the lookup cost is acceptable for the diagnostic-only use case.
--
-- Usage in code:
--     local _p = AutoDelete_PerfBegin("phase-name")
--     ...work...
--     AutoDelete_PerfEnd("phase-name", _p)
--
-- Report via /del perf report. Stats persist across reloads until /del
-- perf reset is run. Phase names are free-form strings; pick names that
-- group related work (one per hot-path function is the sweet spot).

_G.AutoDelete_PerfEnabled = _G.AutoDelete_PerfEnabled or false
_G.AutoDelete_PerfStats   = _G.AutoDelete_PerfStats or {}

-- ============================================================================
-- Spike debug (v3.20)
-- ============================================================================
-- Frame-level diagnostic for catching pickup-time stutter. When enabled, the
-- scanner OnUpdate watches `elapsed` (the previous frame's duration) and -- if it exceeds a threshold -- snapshots per-frame counters into a ring
-- buffer and rate-limits a chat print. The goal is to attribute spikes to
-- specific work (BAG_UPDATE storm, ElvUI repaint, tooltip scans, our own
-- walks/drain, etc.) without depending on a fixed list of perf phases.
--
-- attribMs is the sum of every AutoDelete_PerfEnd duration during the
-- frame. If a spike has frameMs=47 and attribMs=3, only 3ms is accounted
-- for by AutoDelete's instrumented phases -- the remaining 44ms came from
-- somewhere else (Blizzard internals, another addon, ElvUI rebuild
-- between our hook calls, etc.). Trustworthy ONLY when every pickup path
-- is wrapped in PerfBegin/PerfEnd; see the audit comment in
-- AutoDelete_SpikeRecord for the current list.
--
-- All state lives on _G to dodge Lua 5.1's 200-local cap on the main chunk.
_G.AutoDelete_SpikeDebug          = _G.AutoDelete_SpikeDebug          or false
-- Threshold default 33ms (was 20ms). At 20ms the chronological ring was
-- dominated by baseline server frame jitter (~17-22ms native), evicting
-- the actually-bad frames during a burst. 33ms catches real stutters
-- (dropped frames at 30fps) while leaving baseline jitter in the noise
-- floor. The worst-N ring (below) captures the actually-worst frames
-- regardless of when they happened in the session.
_G.AutoDelete_SpikeThresholdMs    = _G.AutoDelete_SpikeThresholdMs    or 33
_G.AutoDelete_SpikeAttribMs       = _G.AutoDelete_SpikeAttribMs       or 0
_G.AutoDelete_SpikeCounters       = _G.AutoDelete_SpikeCounters       or {}
_G.AutoDelete_SpikeRing           = _G.AutoDelete_SpikeRing           or {}
_G.AutoDelete_SpikeRingCap        = _G.AutoDelete_SpikeRingCap        or 20
_G.AutoDelete_SpikeRingNext       = _G.AutoDelete_SpikeRingNext       or 1
-- Worst-N ring (v3.20): top frames by frameMs, never evicted unless beaten.
-- Solves "post-burst quiet period floods the chronological ring with
-- baseline jitter, evicting the burst frames we actually wanted to see."
_G.AutoDelete_SpikeWorstRing      = _G.AutoDelete_SpikeWorstRing      or {}
_G.AutoDelete_SpikeWorstCap       = _G.AutoDelete_SpikeWorstCap       or 20
_G.AutoDelete_SpikeChatLastAt     = _G.AutoDelete_SpikeChatLastAt     or 0
_G.AutoDelete_SpikeChatCooldown   = _G.AutoDelete_SpikeChatCooldown   or 2.0
_G.AutoDelete_SpikeSuppressedCount = _G.AutoDelete_SpikeSuppressedCount or 0

-- v3.20 Goblin defer tracking. Used by the bag-full check below to
-- decide WHEN it's fair to start the BAGS_FULL_DELAY countdown. The
-- old logic started the timer the moment free slots dropped below
-- threshold, which fired Goblin even when AutoDelete hadn't yet had
-- a chance to walk + drain (e.g. during a sustained loot storm where
-- BAG_QUIESCENCE never settles). New logic distinguishes:
--   State 1: bags below threshold, pipeline has NOT scanned yet
--            -> defer Goblin, do NOT start the timer
--   State 2: bags below threshold, pipeline is active (queue has items,
--            or drain/enqueue recent)
--            -> start timer, reset on queue-shrink, fire if queue
--               stops shrinking for BAGS_FULL_DELAY
--   State 3: bags below threshold, last walk found NO deletable
--            candidates
--            -> start timer immediately, fire after BAGS_FULL_DELAY
-- Tracking fields:
_G.AutoDelete_LastDeleteWalkAt        = _G.AutoDelete_LastDeleteWalkAt        or 0
_G.AutoDelete_LastDeleteWalkEnqueued  = _G.AutoDelete_LastDeleteWalkEnqueued  or 0
_G.AutoDelete_LastDrainPopAt          = _G.AutoDelete_LastDrainPopAt          or 0
_G.AutoDelete_LastEnqueueAt           = _G.AutoDelete_LastEnqueueAt           or 0
_G.AutoDelete_BagsBelowAt             = _G.AutoDelete_BagsBelowAt             or 0
-- Last fire / defer reason for /del goblin diagnostic.
_G.AutoDelete_GoblinLastFireAt        = _G.AutoDelete_GoblinLastFireAt        or 0
_G.AutoDelete_GoblinLastFireReason    = _G.AutoDelete_GoblinLastFireReason    or "none"
_G.AutoDelete_GoblinLastDeferReason   = _G.AutoDelete_GoblinLastDeferReason   or "none"
-- Recency window for "drain/enqueue happened recently" (seconds). Tied
-- to BAG_QUIESCENCE: if drain or enqueue fired within 2 seconds, the
-- pipeline counts as "busy" regardless of current queue length.
_G.AutoDelete_GoblinRecencyS          = _G.AutoDelete_GoblinRecencyS          or 2.0

-- v3.20 ElvUI hook A/B gate. When true, the ElvUI:UpdateSlot hook
-- counts the call (updSlot counter) then returns immediately -- no
-- DecideDot, no SetButtonAffixDot, no PerfBegin. Used by /del elvuihook
-- to isolate whether AutoDelete's per-slot work is amplifying ElvUI's
-- own per-pickup stutter, without reloading. Default false (hook
-- active). Not persisted -- resets to false on /reload, which matches
-- the "diagnostic flag, opt in per session" semantic.
_G.AutoDelete_ElvUIHookDisabled = _G.AutoDelete_ElvUIHookDisabled or false

-- ============================================================================
-- Spike session counters (v3.20)
-- ============================================================================
-- Cumulative totals across an entire spike-debug session. Per-frame counters
-- in _G.AutoDelete_SpikeCounters get wiped every OnUpdate tick; these
-- accumulate so we can answer "how much work happened in this bench window?"
-- Used by /del bench finalize to attach session totals to saved benches.
--
-- Reset by /del spike on, /del spike clear, and /del bench arm. Otherwise
-- they keep growing until the user explicitly clears.
_G.AutoDelete_SpikeSession = _G.AutoDelete_SpikeSession or {
	startedAt      = 0,
	bagUpd         = 0,
	bagUpdDel      = 0,
	updSlot        = 0,
	slotsWalked    = 0,
	ttScanRan      = 0,
	axQueued       = 0,
	axRan          = 0,
	dWalk          = 0,
	dEarly         = 0,
	drain          = 0,
	drainSkip      = 0,
	sell           = 0,
	find           = 0,
	itemsEnqueued  = 0,
	itemsDeleted   = 0,
	spikesCaptured = 0,
}

function _G.AutoDelete_SpikeSessionReset()
	local s = _G.AutoDelete_SpikeSession
	s.startedAt      = GetTime()
	s.bagUpd         = 0
	s.bagUpdDel      = 0
	s.updSlot        = 0
	s.slotsWalked    = 0
	s.ttScanRan      = 0
	s.axQueued       = 0
	s.axRan          = 0
	s.dWalk          = 0
	s.dEarly         = 0
	s.drain          = 0
	s.drainSkip      = 0
	s.sell           = 0
	s.find           = 0
	s.itemsEnqueued  = 0
	s.itemsDeleted   = 0
	s.spikesCaptured = 0
end

-- ============================================================================
-- Bench harness (v3.20)
-- ============================================================================
-- Auto-arming benchmark runner. State machine: IDLE -> ARMED (waiting for
-- first BAG_UPDATE) -> ACTIVE (collecting) -> finalized (saved to SV +
-- report shown) -> IDLE. Transitions:
--   /del bench           IDLE   -> ARMED (snapshot config, reset counters)
--                        ARMED  -> IDLE  (cancel, never saw activity)
--                        ACTIVE -> FORCE-FINALIZE (manual stop)
--   BAG_UPDATE arrives   ARMED  -> ACTIVE (record startedAt)
--   5s of bag-quiet      ACTIVE -> AUTO-FINALIZE
--
-- Finalize captures:
--   * config snapshot (elvuiHookDisabled, spike threshold, profile)
--   * session counter totals
--   * spike ring buffer (deep copy)
--   * perf stats for the AutoDelete phases we care about
--   * start/end timestamps + duration
-- Stored in AutoDeleteDB.benches[name], capped at BenchMaxSaved.
_G.AutoDelete_Bench = _G.AutoDelete_Bench or {
	state            = nil,   -- nil = idle, "armed", "active"
	name             = nil,
	armedAt          = 0,
	startedAt        = 0,
	lastBagUpdateAt  = 0,
	configSnap       = nil,
}
_G.AutoDelete_BenchQuietSeconds = _G.AutoDelete_BenchQuietSeconds or 5.0
_G.AutoDelete_BenchMaxSaved     = _G.AutoDelete_BenchMaxSaved     or 20

-- Auto-name format: bench-<N>-<hookon|hookoff>. N auto-increments. Suffix
-- captures the most important variable so the list is self-describing.
function _G.AutoDelete_BenchAutoName()
	_G.AutoDeleteDB = _G.AutoDeleteDB or {}
	_G.AutoDeleteDB.benches = _G.AutoDeleteDB.benches or {}
	_G.AutoDeleteDB.benchCounter = (_G.AutoDeleteDB.benchCounter or 0) + 1
	local suffix = _G.AutoDelete_ElvUIHookDisabled and "hookoff" or "hookon"
	return string.format("bench-%d-%s", _G.AutoDeleteDB.benchCounter, suffix)
end

-- Snapshot the config that affects test interpretation. Captures both
-- AutoDelete-side state AND the ElvUI bag-display settings whose
-- toggling can dramatically change bench results (showBindType is the
-- canonical example -- disabling it dropped worst-frame stutter ~10x
-- in PE testing 2026-05-23). Without these in the snapshot, you can't
-- tell from saved bench data which test had which ElvUI config.
function _G.AutoDelete_BenchSnapConfig()
	local profileKey = (cachedProfile and cachedProfile._profileKey) or "?"
	-- ElvUI bag settings. Wrapped in pcall because the ElvUI module
	-- structure may not be initialized if the addon is loaded but the
	-- module hasn't run its Initialize yet, and we don't want a bench
	-- snapshot to ever throw.
	local elvBags = nil
	if _G.ElvUI then
		pcall(function()
			local E = _G.ElvUI[1]
			if E and E.db and E.db.bags then
				local db = E.db.bags
				elvBags = {
					showBindType        = db.showBindType        and true or false,
					itemLevel           = db.itemLevel           and true or false,
					itemLevelThreshold  = db.itemLevelThreshold,
					junkIcon            = db.junkIcon            and true or false,
					junkDesaturate      = db.junkDesaturate      and true or false,
					autoDeleteJunkIconSuppressed = _G.AutoDelete_ElvUIJunkIconState
						and _G.AutoDelete_ElvUIJunkIconState.active
						and true or false,
					qualityColors       = db.qualityColors       and true or false,
					questIcon           = db.questIcon           and true or false,
					questItemColors     = db.questItemColors     and true or false,
					professionBagColors = db.professionBagColors and true or false,
				}
			end
			-- Whether the Bags module itself is enabled (E.private.bags.enable
			-- on the live install; falls back to true if we can't read it).
			if E and E.private and E.private.bags then
				elvBags = elvBags or {}
				elvBags.moduleEnabled = E.private.bags.enable and true or false
			end
		end)
	end
	return {
		elvuiHookDisabled   = _G.AutoDelete_ElvUIHookDisabled and true or false,
		spikeThresholdMs    = _G.AutoDelete_SpikeThresholdMs,
		profileKey          = profileKey,
		elvuiLoaded         = _G.ElvUI and true or false,
		elvuiBags           = elvBags,  -- nil if ElvUI not loaded / not ready
		realmTime           = date and date("%Y-%m-%d %H:%M:%S") or "unknown",
	}
end

function _G.AutoDelete_BenchArm(name)
	local B = _G.AutoDelete_Bench
	if B.state then
		print("|cffff8000[AutoDelete BENCH]|r already " .. B.state .. " ('" .. tostring(B.name) .. "'). Re-issue /del bench to cancel/finalize.")
		return
	end
	name = name or _G.AutoDelete_BenchAutoName()
	-- Auto-enable spike if not on. Without spike data the bench is empty.
	if not _G.AutoDelete_SpikeDebug then
		_G.AutoDelete_SetSpikeDebug(true)
	end
	-- Clear ring + counters so the bench window starts clean.
	if _G.AutoDelete_SpikeReset then _G.AutoDelete_SpikeReset() end
	_G.AutoDelete_SpikeRing = {}
	_G.AutoDelete_SpikeRingNext = 1
	_G.AutoDelete_SpikeWorstRing = {}
	_G.AutoDelete_SpikeSuppressedCount = 0
	if _G.AutoDelete_SpikeSessionReset then _G.AutoDelete_SpikeSessionReset() end
	-- Reset perf stats too so /del perf report at finalize is bench-scoped.
	_G.AutoDelete_PerfStats = {}

	B.state           = "armed"
	B.name            = name
	B.armedAt         = GetTime()
	B.startedAt       = 0
	B.lastBagUpdateAt = 0
	B.configSnap      = _G.AutoDelete_BenchSnapConfig()
	print(string.format(
		"|cffff8000[AutoDelete BENCH]|r |cff00ff00ARMED|r '%s'. Loot a burst -- auto-finalizes %.0fs after bag activity stops.",
		name, _G.AutoDelete_BenchQuietSeconds
	))
end

-- Called by /del bench when state is non-nil. Branches on state.
function _G.AutoDelete_BenchToggle()
	local B = _G.AutoDelete_Bench
	if not B.state then
		_G.AutoDelete_BenchArm()
	elseif B.state == "armed" then
		print("|cffff8000[AutoDelete BENCH]|r |cffff5555CANCELED|r '" .. tostring(B.name) .. "' -- no activity captured.")
		B.state = nil
		B.name = nil
	elseif B.state == "active" then
		print("|cffff8000[AutoDelete BENCH]|r force-finalizing '" .. tostring(B.name) .. "' (manual stop).")
		_G.AutoDelete_BenchFinalize()
	end
end

-- Called by BAG_UPDATE handler. Transitions ARMED -> ACTIVE on first event;
-- otherwise just refreshes the quiet timer.
function _G.AutoDelete_BenchOnBagUpdate(now)
	local B = _G.AutoDelete_Bench
	if not B.state then return end
	if B.state == "armed" then
		B.state     = "active"
		B.startedAt = now
		print(string.format(
			"|cffff8000[AutoDelete BENCH]|r |cff00ff00STARTED|r '%s' -- bag activity detected.",
			B.name
		))
	end
	B.lastBagUpdateAt = now
end

-- Called every scanner OnUpdate when bench is non-idle. Detects auto-stop.
function _G.AutoDelete_BenchTick(now)
	local B = _G.AutoDelete_Bench
	if B.state ~= "active" then return end
	if B.lastBagUpdateAt > 0
		and (now - B.lastBagUpdateAt) >= _G.AutoDelete_BenchQuietSeconds then
		_G.AutoDelete_BenchFinalize()
	end
end

-- Save the bench to SV, evict oldest if over cap, show report popup.
function _G.AutoDelete_BenchFinalize()
	local B = _G.AutoDelete_Bench
	if not B.state then return end
	local now = GetTime()
	local durationSec = (B.startedAt > 0) and (now - B.startedAt) or 0

	-- Deep-copy the ring snapshots so subsequent /del spike runs don't
	-- mutate this bench's saved data. Both the chronological ring AND
	-- the worst-N ring -- the worst ring is what surfaces the actual
	-- burst frames; the chronological ring is "what just happened".
	local ringCopy = {}
	for i, s in ipairs(_G.AutoDelete_SpikeRing) do
		ringCopy[i] = {}
		for k, v in pairs(s) do ringCopy[i][k] = v end
	end
	local worstCopy = {}
	for i, s in ipairs(_G.AutoDelete_SpikeWorstRing or {}) do
		worstCopy[i] = {}
		for k, v in pairs(s) do worstCopy[i][k] = v end
	end
	-- Sort worst copy by frameMs desc so the saved data is display-ready.
	table.sort(worstCopy, function(a, c) return (a.frameMs or 0) > (c.frameMs or 0) end)
	-- Session counter snapshot.
	local sessionCopy = {}
	for k, v in pairs(_G.AutoDelete_SpikeSession) do sessionCopy[k] = v end
	-- Subset of perf stats (only AutoDelete phases, keep payload small).
	local perfCopy = {}
	for phase, stats in pairs(_G.AutoDelete_PerfStats or {}) do
		if phase:find("DeleteItems") or phase:find("AutoDelete") or phase:find("BAG_UPDATE")
			or phase:find("ElvUI") or phase:find("UpdateAffixDot")
			or phase:find("deferred") or phase:find("Find") then
			perfCopy[phase] = {
				count   = stats.count,
				totalMs = stats.totalMs,
				maxMs   = stats.maxMs,
				isCounter = stats.isCounter,
			}
		end
	end

	_G.AutoDeleteDB = _G.AutoDeleteDB or {}
	_G.AutoDeleteDB.benches = _G.AutoDeleteDB.benches or {}
	_G.AutoDeleteDB.benches[B.name] = {
		name        = B.name,
		finishedAt  = time and time() or 0,
		durationSec = durationSec,
		config      = B.configSnap,
		session     = sessionCopy,
		ring        = ringCopy,
		worstRing   = worstCopy,
		perf        = perfCopy,
		goblin      = {
			lastFireAt        = _G.AutoDelete_GoblinLastFireAt or 0,
			lastFireReason    = _G.AutoDelete_GoblinLastFireReason or "none",
			lastDeferReason   = _G.AutoDelete_GoblinLastDeferReason or "none",
		},
	}

	-- FIFO eviction if over cap. Order preserved via benchOrder list.
	_G.AutoDeleteDB.benchOrder = _G.AutoDeleteDB.benchOrder or {}
	-- Remove this name if already in the order (re-finalize case), then append.
	for i = #_G.AutoDeleteDB.benchOrder, 1, -1 do
		if _G.AutoDeleteDB.benchOrder[i] == B.name then
			table.remove(_G.AutoDeleteDB.benchOrder, i)
		end
	end
	table.insert(_G.AutoDeleteDB.benchOrder, B.name)
	while #_G.AutoDeleteDB.benchOrder > _G.AutoDelete_BenchMaxSaved do
		local evict = table.remove(_G.AutoDeleteDB.benchOrder, 1)
		_G.AutoDeleteDB.benches[evict] = nil
	end

	local finalName = B.name
	-- Reset bench state BEFORE printing so a quick repeat works.
	B.state           = nil
	B.name            = nil
	B.armedAt         = 0
	B.startedAt       = 0
	B.lastBagUpdateAt = 0
	B.configSnap      = nil

	print(string.format(
		"|cffff8000[AutoDelete BENCH]|r |cff00ff00FINALIZED|r '%s' -- %.1fs, %d items enqueued, %d deleted, %d spikes. Opening report.",
		finalName, durationSec,
		sessionCopy.itemsEnqueued or 0, sessionCopy.itemsDeleted or 0,
		sessionCopy.spikesCaptured or 0
	))

	-- Render the report and open the popup.
	if _G.AutoDelete_ShowBenchReport then
		_G.AutoDelete_ShowBenchReport(finalName)
	end
end

-- Render a single saved bench as a multi-line text block and show the popup.
function _G.AutoDelete_ShowBenchReport(name)
	_G.AutoDeleteDB = _G.AutoDeleteDB or {}
	local b = (_G.AutoDeleteDB.benches or {})[name]
	if not b then
		print("|cffff8000[AutoDelete BENCH]|r '" .. tostring(name) .. "' not found.")
		return
	end
	local lines = {}
	table.insert(lines, "=== Bench: " .. b.name .. " ===")
	if b.config then
		table.insert(lines, string.format(
			"  config: elvuiHookDisabled=%s spikeThresholdMs=%d profile=%s elvuiLoaded=%s when=%s",
			tostring(b.config.elvuiHookDisabled), b.config.spikeThresholdMs or 0,
			tostring(b.config.profileKey), tostring(b.config.elvuiLoaded),
			tostring(b.config.realmTime)
		))
		-- ElvUI bag-display settings snapshot (added 2026-05-23). Without
		-- this row, benches can't be told apart when only an ElvUI setting
		-- changed between tests. showBindType ON vs OFF is a ~10x worst-
		-- frame difference, so this is critical context.
		if b.config.elvuiBags then
			local eb = b.config.elvuiBags
			table.insert(lines, string.format(
				"  elvuiBags: showBindType=%s itemLevel=%s ilvlThresh=%s junkIcon=%s junkDesat=%s autoDeleteJunkIconSuppressed=%s qualityColors=%s questIcon=%s questItemColors=%s professionBagColors=%s moduleEnabled=%s",
				tostring(eb.showBindType), tostring(eb.itemLevel), tostring(eb.itemLevelThreshold or "?"),
				tostring(eb.junkIcon), tostring(eb.junkDesaturate), tostring(eb.autoDeleteJunkIconSuppressed),
				tostring(eb.qualityColors), tostring(eb.questIcon), tostring(eb.questItemColors),
				tostring(eb.professionBagColors), tostring(eb.moduleEnabled)
			))
		end
	end
	table.insert(lines, string.format("  duration: %.1fs", b.durationSec or 0))
	local s = b.session or {}
	table.insert(lines, "  --- session counters ---")
	table.insert(lines, string.format(
		"  items: enqueued=%d deleted=%d   throughput=%.1f/sec",
		s.itemsEnqueued or 0, s.itemsDeleted or 0,
		(b.durationSec and b.durationSec > 0) and ((s.itemsDeleted or 0) / b.durationSec) or 0
	))
	table.insert(lines, string.format(
		"  bag events: bagUpd=%d bagUpdDel=%d   ElvUI updSlot=%d   slotsWalked=%d",
		s.bagUpd or 0, s.bagUpdDel or 0, s.updSlot or 0, s.slotsWalked or 0
	))
	table.insert(lines, string.format(
		"  AutoDelete: dWalk=%d dEarly=%d   drain=%d drainSkip=%d   sell=%d find=%d",
		s.dWalk or 0, s.dEarly or 0, s.drain or 0, s.drainSkip or 0,
		s.sell or 0, s.find or 0
	))
	table.insert(lines, string.format(
		"  scans: ttScan=%d axQueued=%d axRan=%d   spikesCaptured=%d",
		s.ttScanRan or 0, s.axQueued or 0, s.axRan or 0, s.spikesCaptured or 0
	))
	-- Perf summary: top 10 by total ms.
	local perfRows = {}
	for phase, stats in pairs(b.perf or {}) do
		if not stats.isCounter then
			table.insert(perfRows, { name = phase, total = stats.totalMs or 0, max = stats.maxMs or 0, count = stats.count or 0 })
		end
	end
	table.sort(perfRows, function(a, c) return a.total > c.total end)
	if #perfRows > 0 then
		table.insert(lines, "  --- top perf phases (total ms) ---")
		for i = 1, math.min(10, #perfRows) do
			local r = perfRows[i]
			table.insert(lines, string.format(
				"    %-32s n=%-5d total=%7.1fms max=%6.1fms",
				r.name, r.count, r.total, r.max
			))
		end
	end
	-- Goblin diagnostic.
	if b.goblin then
		table.insert(lines, "  --- goblin ---")
		table.insert(lines, string.format(
			"  lastFireReason=%s   lastDeferReason=%s",
			tostring(b.goblin.lastFireReason or "none"),
			tostring(b.goblin.lastDeferReason or "none")
		))
	end
	-- Worst-N ring (sorted desc by frameMs).
	if b.worstRing and #b.worstRing > 0 then
		table.insert(lines, "  --- WORST " .. #b.worstRing .. " spikes (sorted by frameMs desc) ---")
		for i, spike in ipairs(b.worstRing) do
			local ourPct = spike.frameMs > 0 and math.floor((spike.attribMs or 0) / spike.frameMs * 100) or 0
			table.insert(lines, string.format(
				"  W%-2d frame=%.1fms attribMs=%.1fms ours=%d%% bagUpd=%d/%d updSlot=%d slotsWalked=%d ttScan=%d axQ=%d/%d dEarly=%d/%d drain=%d/%d sell=%d find=%d loot=%s",
				i, spike.frameMs or 0, spike.attribMs or 0, ourPct,
				spike.bagUpd or 0, spike.bagUpdDel or 0, spike.updSlot or 0,
				spike.slotsWalked or 0, spike.ttScanRan or 0,
				spike.axQueued or 0, spike.axRan or 0,
				spike.dEarly or 0, spike.dWalk or 0,
				spike.drain or 0, spike.drainSkip or 0,
				spike.sell or 0, spike.find or 0,
				(spike.lootEvts ~= "" and spike.lootEvts) or "none"
			))
		end
	end
	-- Chronological ring dump.
	if b.ring and #b.ring > 0 then
		table.insert(lines, "  --- LAST " .. #b.ring .. " spikes (chronological, oldest first) ---")
		for i, spike in ipairs(b.ring) do
			local ourPct = spike.frameMs > 0 and math.floor((spike.attribMs or 0) / spike.frameMs * 100) or 0
			table.insert(lines, string.format(
				"  #%-2d frame=%.1fms attribMs=%.1fms ours=%d%% bagUpd=%d/%d updSlot=%d slotsWalked=%d ttScan=%d axQ=%d/%d dEarly=%d/%d drain=%d/%d sell=%d find=%d loot=%s",
				i, spike.frameMs or 0, spike.attribMs or 0, ourPct,
				spike.bagUpd or 0, spike.bagUpdDel or 0, spike.updSlot or 0,
				spike.slotsWalked or 0, spike.ttScanRan or 0,
				spike.axQueued or 0, spike.axRan or 0,
				spike.dEarly or 0, spike.dWalk or 0,
				spike.drain or 0, spike.drainSkip or 0,
				spike.sell or 0, spike.find or 0,
				(spike.lootEvts ~= "" and spike.lootEvts) or "none"
			))
		end
	end
	local text = table.concat(lines, "\n")
	if _G.AutoDelete_ShowSpikeReportWindow then
		_G.AutoDelete_ShowSpikeReportWindow(text)
	else
		for _, ln in ipairs(lines) do print(ln) end
	end
end

-- List saved benches (in order finished, oldest first).
function _G.AutoDelete_BenchList()
	_G.AutoDeleteDB = _G.AutoDeleteDB or {}
	local order = _G.AutoDeleteDB.benchOrder or {}
	if #order == 0 then
		print("|cffff8000[AutoDelete BENCH]|r no saved benches. Run /del bench.")
		return
	end
	print(string.format("|cffff8000[AutoDelete BENCH]|r %d saved bench(es):", #order))
	for i = 1, #order do
		local name = order[i]
		local b = (_G.AutoDeleteDB.benches or {})[name]
		if b then
			local s = b.session or {}
			-- Worst frame: prefer the worstRing (preserves real bursts),
			-- fall back to chronological ring for older saved benches that
			-- didn't have a worstRing.
			local worst = 0
			for _, spike in ipairs(b.worstRing or b.ring or {}) do
				if (spike.frameMs or 0) > worst then worst = spike.frameMs end
			end
			-- Add showBindType state to the row so the list answers "which
			-- bench was the no-bind-type-scan run?" at a glance.
			local sbt = "?"
			if b.config and b.config.elvuiBags then
				sbt = tostring(b.config.elvuiBags.showBindType)
			end
			print(string.format(
				"  %-30s %.0fs  items=%d  worst=%.0fms  hookDisabled=%s  showBindType=%s",
				name, b.durationSec or 0,
				s.itemsDeleted or 0, worst,
				tostring((b.config or {}).elvuiHookDisabled),
				sbt
			))
		end
	end
end

-- Delete a saved bench by name.
function _G.AutoDelete_BenchDelete(name)
	_G.AutoDeleteDB = _G.AutoDeleteDB or {}
	if not (_G.AutoDeleteDB.benches or {})[name] then
		print("|cffff8000[AutoDelete BENCH]|r '" .. tostring(name) .. "' not found.")
		return
	end
	_G.AutoDeleteDB.benches[name] = nil
	for i = #(_G.AutoDeleteDB.benchOrder or {}), 1, -1 do
		if _G.AutoDeleteDB.benchOrder[i] == name then
			table.remove(_G.AutoDeleteDB.benchOrder, i)
		end
	end
	print("|cffff8000[AutoDelete BENCH]|r deleted '" .. name .. "'.")
end

-- Compare two benches side-by-side. If no args, picks the two newest.
function _G.AutoDelete_BenchCompare(nameA, nameB)
	_G.AutoDeleteDB = _G.AutoDeleteDB or {}
	local order = _G.AutoDeleteDB.benchOrder or {}
	if not nameA or not nameB then
		if #order < 2 then
			print("|cffff8000[AutoDelete BENCH]|r need at least 2 saved benches. Have " .. #order .. ".")
			return
		end
		nameB = order[#order]
		nameA = order[#order - 1]
	end
	local a = (_G.AutoDeleteDB.benches or {})[nameA]
	local b = (_G.AutoDeleteDB.benches or {})[nameB]
	if not a or not b then
		print("|cffff8000[AutoDelete BENCH]|r one or both benches not found: '" .. tostring(nameA) .. "', '" .. tostring(nameB) .. "'.")
		return
	end

	-- Worst-N ring preferred for these aggregates so the comparison
	-- reflects the actual burst frames, not post-burst baseline jitter.
	local function pickSource(bench) return bench.worstRing or bench.ring or {} end
	local function worstOf(bench)
		local w = 0
		for _, sp in ipairs(pickSource(bench)) do
			if (sp.frameMs or 0) > w then w = sp.frameMs end
		end
		return w
	end
	local function attribOf(bench)
		local tot = 0
		for _, sp in ipairs(pickSource(bench)) do tot = tot + (sp.attribMs or 0) end
		return tot
	end
	local function avgOursPct(bench)
		local n, sum = 0, 0
		for _, sp in ipairs(pickSource(bench)) do
			if (sp.frameMs or 0) > 0 then
				sum = sum + ((sp.attribMs or 0) / sp.frameMs * 100)
				n = n + 1
			end
		end
		return n > 0 and (sum / n) or 0
	end

	local lines = {}
	table.insert(lines, string.format("=== COMPARE: %s vs %s ===", nameA, nameB))
	local function rowStr(label, va, vb)
		table.insert(lines, string.format("  %-24s %-18s %-18s", label, tostring(va), tostring(vb)))
	end
	local function rowNum(label, va, vb, fmt, unit)
		fmt = fmt or "%.1f"
		unit = unit or ""
		local va_s = string.format(fmt, va) .. unit
		local vb_s = string.format(fmt, vb) .. unit
		local delta = vb - va
		local delta_s = string.format("%+" .. (fmt:sub(2)), delta) .. unit
		table.insert(lines, string.format("  %-24s %-18s %-18s %s", label, va_s, vb_s, delta_s))
	end
	table.insert(lines, string.format("  %-24s %-18s %-18s %s", "metric", nameA, nameB, "delta"))
	-- Config rows (text, no delta)
	local ca, cb = a.config or {}, b.config or {}
	rowStr("elvuiHookDisabled", ca.elvuiHookDisabled, cb.elvuiHookDisabled)
	rowStr("elvuiLoaded",       ca.elvuiLoaded, cb.elvuiLoaded)
	rowNum("spikeThresholdMs",  ca.spikeThresholdMs or 0, cb.spikeThresholdMs or 0, "%d")
	-- ElvUI bag-display settings -- critical context for diffing benches
	-- where the only difference was an ElvUI option toggle.
	local eba, ebb = ca.elvuiBags or {}, cb.elvuiBags or {}
	rowStr("E.bags showBindType",        eba.showBindType,        ebb.showBindType)
	rowStr("E.bags itemLevel",           eba.itemLevel,           ebb.itemLevel)
	rowStr("E.bags junkIcon",            eba.junkIcon,            ebb.junkIcon)
	rowStr("E.bags junkDesaturate",      eba.junkDesaturate,      ebb.junkDesaturate)
	rowStr("E.bags junkIcon suppressed", eba.autoDeleteJunkIconSuppressed, ebb.autoDeleteJunkIconSuppressed)
	rowStr("E.bags qualityColors",       eba.qualityColors,       ebb.qualityColors)
	rowStr("E.bags questIcon",           eba.questIcon,           ebb.questIcon)
	rowStr("E.bags questItemColors",     eba.questItemColors,     ebb.questItemColors)
	rowStr("E.bags professionBagColors", eba.professionBagColors, ebb.professionBagColors)
	rowStr("E.bags moduleEnabled",       eba.moduleEnabled,       ebb.moduleEnabled)
	-- Number rows
	rowNum("duration (sec)",       a.durationSec or 0, b.durationSec or 0, "%.1f", "s")
	rowNum("items enqueued",       (a.session or {}).itemsEnqueued or 0, (b.session or {}).itemsEnqueued or 0, "%d")
	rowNum("items deleted",        (a.session or {}).itemsDeleted or 0,  (b.session or {}).itemsDeleted or 0,  "%d")
	rowNum("worst frame",          worstOf(a), worstOf(b), "%.0f", "ms")
	rowNum("spikes captured",      (a.session or {}).spikesCaptured or 0, (b.session or {}).spikesCaptured or 0, "%d")
	rowNum("ring attribMs total",  attribOf(a), attribOf(b), "%.1f", "ms")
	rowNum("ring ours% avg",       avgOursPct(a), avgOursPct(b), "%.0f", "%%")
	rowNum("bagUpd",               (a.session or {}).bagUpd or 0, (b.session or {}).bagUpd or 0, "%d")
	rowNum("bagUpdDel",            (a.session or {}).bagUpdDel or 0, (b.session or {}).bagUpdDel or 0, "%d")
	rowNum("updSlot",              (a.session or {}).updSlot or 0, (b.session or {}).updSlot or 0, "%d")
	rowNum("slotsWalked",          (a.session or {}).slotsWalked or 0, (b.session or {}).slotsWalked or 0, "%d")
	rowNum("ttScanRan",            (a.session or {}).ttScanRan or 0, (b.session or {}).ttScanRan or 0, "%d")
	rowNum("axQueued",             (a.session or {}).axQueued or 0, (b.session or {}).axQueued or 0, "%d")
	rowNum("axRan",                (a.session or {}).axRan or 0, (b.session or {}).axRan or 0, "%d")
	rowNum("drain pops",           (a.session or {}).drain or 0, (b.session or {}).drain or 0, "%d")
	rowNum("dWalk",                (a.session or {}).dWalk or 0, (b.session or {}).dWalk or 0, "%d")
	rowNum("dEarly",               (a.session or {}).dEarly or 0, (b.session or {}).dEarly or 0, "%d")
	rowNum("find",                 (a.session or {}).find or 0, (b.session or {}).find or 0, "%d")
	rowNum("sell",                 (a.session or {}).sell or 0, (b.session or {}).sell or 0, "%d")

	local text = table.concat(lines, "\n")
	if _G.AutoDelete_ShowSpikeReportWindow then
		_G.AutoDelete_ShowSpikeReportWindow(text)
	else
		for _, ln in ipairs(lines) do print(ln) end
	end
end

-- Wipe per-frame state. Called by scanner OnUpdate after recording any
-- spike from the previous frame, before this frame's accumulators run.
function _G.AutoDelete_SpikeReset()
	local c = _G.AutoDelete_SpikeCounters
	c.bagUpd      = 0
	c.bagUpdDel   = 0
	c.updSlot     = 0
	c.slotsWalked = 0
	c.ttScanRan   = 0
	c.axQueued    = 0
	c.axRan       = 0
	c.dWalk       = 0
	c.dEarly      = 0
	c.drain       = 0
	c.drainSkip   = 0
	c.sell        = 0
	c.find        = 0
	c.lootEvts    = nil
	_G.AutoDelete_SpikeAttribMs = 0
end

-- Cheap counter bump. Caller is expected to inline the SpikeDebug check
-- when the hook is in a hot path (ElvUI:UpdateSlot, etc.); this helper
-- exists for cold paths where the function-call cost is negligible.
function _G.AutoDelete_SpikeBump(field, n)
	if not _G.AutoDelete_SpikeDebug then return end
	local c = _G.AutoDelete_SpikeCounters
	c[field] = (c[field] or 0) + (n or 1)
end

-- Append a loot-event name to the current frame's loot-event list.
function _G.AutoDelete_SpikeAddLootEvt(name)
	if not _G.AutoDelete_SpikeDebug then return end
	local c = _G.AutoDelete_SpikeCounters
	if c.lootEvts then
		c.lootEvts = c.lootEvts .. "," .. name
	else
		c.lootEvts = name
	end
end

-- Record a spike: snapshot counters into the ring buffer and print a
-- rate-limited chat summary. Called by scanner OnUpdate when the
-- previous frame's elapsed exceeds SpikeThresholdMs.
function _G.AutoDelete_SpikeRecord(elapsed)
	local frameMs = elapsed * 1000
	local attrib  = _G.AutoDelete_SpikeAttribMs or 0
	local c = _G.AutoDelete_SpikeCounters

	-- Snapshot for ring buffer (shallow-copy is enough; counters are scalars).
	local snap = {
		time        = GetTime(),
		frameMs     = frameMs,
		attribMs    = attrib,
		bagUpd      = c.bagUpd or 0,
		bagUpdDel   = c.bagUpdDel or 0,
		updSlot     = c.updSlot or 0,
		slotsWalked = c.slotsWalked or 0,
		ttScanRan   = c.ttScanRan or 0,
		axQueued    = c.axQueued or 0,
		axRan       = c.axRan or 0,
		dWalk       = c.dWalk or 0,
		dEarly      = c.dEarly or 0,
		drain       = c.drain or 0,
		drainSkip   = c.drainSkip or 0,
		sell        = c.sell or 0,
		find        = c.find or 0,
		lootEvts    = c.lootEvts or "",
	}

	-- Ring write (overwrites oldest entry when full).
	local ring = _G.AutoDelete_SpikeRing
	local idx  = _G.AutoDelete_SpikeRingNext
	ring[idx]  = snap
	_G.AutoDelete_SpikeRingNext = (idx % _G.AutoDelete_SpikeRingCap) + 1
	-- v3.20 Worst-N ring write. Keep top SpikeWorstCap by frameMs so the
	-- actually-worst frames survive even when post-burst baseline jitter
	-- floods the chronological ring. Maintained unsorted; report sorts
	-- at display time. Insert/replace cost is O(N) for N=20 = ~20 compares
	-- per spike record, negligible.
	local worst = _G.AutoDelete_SpikeWorstRing
	if #worst < _G.AutoDelete_SpikeWorstCap then
		worst[#worst + 1] = snap
	else
		-- Find current minimum frameMs; replace if new snap beats it.
		local minIdx, minMs = 1, worst[1].frameMs
		for i = 2, #worst do
			if worst[i].frameMs < minMs then
				minIdx, minMs = i, worst[i].frameMs
			end
		end
		if snap.frameMs > minMs then
			worst[minIdx] = snap
		end
	end
	-- Session counter: how many spikes this session has captured. Helps
	-- /del bench compare answer "did one test see more spikes than the other?"
	if _G.AutoDelete_SpikeSession then
		_G.AutoDelete_SpikeSession.spikesCaptured = (_G.AutoDelete_SpikeSession.spikesCaptured or 0) + 1
	end

	-- Chat-print gate (v3.20.x): the ring buffer captures every frame
	-- over threshold (default 20ms), but baseline server frame jitter
	-- around 17-22ms would flood chat. So chat only prints when the
	-- spike is either:
	--   (a) severe (frame > 50ms -- a perceptible stutter regardless of
	--       attribution), OR
	--   (b) moderate AND clearly ours (frame > 33ms AND ours >= 25%)
	-- Below those thresholds the spike still lands in the ring; the
	-- user reads it later via /del spike report.
	--
	-- Rate-limited on top of the gate so a sustained sub-second
	-- repetition of the SAME spike doesn't double-spam.
	local ourPct = frameMs > 0 and math.floor(attrib / frameMs * 100) or 0
	local shouldPrintChat = (frameMs > 50) or (frameMs > 33 and ourPct >= 25)
	local now = GetTime()
	if shouldPrintChat
		and now - (_G.AutoDelete_SpikeChatLastAt or 0) >= _G.AutoDelete_SpikeChatCooldown then
		_G.AutoDelete_SpikeChatLastAt = now
		local suppressed = _G.AutoDelete_SpikeSuppressedCount or 0
		_G.AutoDelete_SpikeSuppressedCount = 0
		local suffix = (suppressed > 0) and (" (+" .. suppressed .. " suppressed)") or ""
		print(string.format(
			"|cffff8000[AutoDelete SPIKE]|r frame=%.1fms attribMs=%.1fms ours=%d%%%s",
			frameMs, attrib, ourPct, suffix
		))
		print(string.format(
			"  bagUpd=%d/%d updSlot=%d slotsWalked=%d ttScan=%d axQ=%d/%d dEarly=%d/%d drain=%d/%d sell=%d find=%d loot=%s",
			snap.bagUpd, snap.bagUpdDel, snap.updSlot, snap.slotsWalked, snap.ttScanRan,
			snap.axQueued, snap.axRan, snap.dEarly, snap.dWalk,
			snap.drain, snap.drainSkip, snap.sell, snap.find,
			(snap.lootEvts ~= "" and snap.lootEvts or "none")
		))
	else
		_G.AutoDelete_SpikeSuppressedCount = (_G.AutoDelete_SpikeSuppressedCount or 0) + 1
	end
end

-- Spike report helpers are wrapped in a `do` block so the two locals
-- (_CollectSpikeRing, _FormatSpikeLine) don't count against the main
-- chunk's 200-local cap. Only the assignments to _G escape the block.
do
-- Collect the ring buffer in chronological order (oldest first). Returns
-- an array of snapshots. Used by both SpikeReport (popup) and
-- SpikeReportChat (chat fallback).
local function _CollectSpikeRing()
	local ring = _G.AutoDelete_SpikeRing
	local entries = {}
	local cap     = _G.AutoDelete_SpikeRingCap
	local nextIdx = _G.AutoDelete_SpikeRingNext
	-- Walk from nextIdx (oldest if wrapped), wrap to nextIdx - 1. Skip
	-- nil slots (haven't wrapped yet).
	for i = 0, cap - 1 do
		local idx = ((nextIdx - 1 + i) % cap) + 1
		if ring[idx] then table.insert(entries, ring[idx]) end
	end
	return entries
end

-- Format one snapshot into the standard one-line layout used by both
-- the real-time chat print and the report dump. Kept here so the format
-- stays in sync; if a counter is added/removed, only this string changes.
local function _FormatSpikeLine(prefix, s)
	local ourPct = s.frameMs > 0 and math.floor(s.attribMs / s.frameMs * 100) or 0
	return string.format(
		"%sframe=%.1fms attribMs=%.1fms ours=%d%% bagUpd=%d/%d updSlot=%d slotsWalked=%d ttScan=%d axQ=%d/%d dEarly=%d/%d drain=%d/%d sell=%d find=%d loot=%s",
		prefix,
		s.frameMs, s.attribMs, ourPct,
		s.bagUpd, s.bagUpdDel, s.updSlot, s.slotsWalked, s.ttScanRan,
		s.axQueued, s.axRan, s.dEarly, s.dWalk,
		s.drain, s.drainSkip, s.sell, s.find,
		(s.lootEvts ~= "" and s.lootEvts or "none")
	)
end

-- Dump the ring buffer to the popup window. Called by /del spike report.
-- Without ElvUI the default Blizzard chat is not selectable, so the popup
-- is the primary surface for grabbing spike data. SpikeReportChat below
-- is the chat fallback for users with chat-copy addons.
function _G.AutoDelete_SpikeReport()
	local entries = _CollectSpikeRing()
	if #entries == 0 then
		print("|cffff8000[AutoDelete SPIKE]|r ring empty -- no spikes captured. Enable with /del spike on and reproduce.")
		return
	end
	local lines = {}
	table.insert(lines, string.format(
		"AutoDelete Spike Report -- last %d spike(s), oldest first (threshold %dms)",
		#entries, _G.AutoDelete_SpikeThresholdMs
	))
	for i, s in ipairs(entries) do
		table.insert(lines, _FormatSpikeLine(string.format("#%-2d ", i), s))
	end
	local text = table.concat(lines, "\n")
	if _G.AutoDelete_ShowSpikeReportWindow then
		_G.AutoDelete_ShowSpikeReportWindow(text)
	else
		-- Options.lua not loaded yet (shouldn't happen post-PLAYER_LOGIN,
		-- but cheap insurance). Fall through to chat so the user isn't
		-- left without data.
		for _, ln in ipairs(lines) do print(ln) end
	end
end

-- Chat fallback for /del spike chat. For users who prefer text in the
-- chat frame (and have a chat-copy addon to read it back).
function _G.AutoDelete_SpikeReportChat()
	local entries = _CollectSpikeRing()
	if #entries == 0 then
		print("|cffff8000[AutoDelete SPIKE]|r ring empty -- no spikes captured.")
		return
	end
	print(string.format(
		"|cffff8000[AutoDelete SPIKE]|r last %d spike(s), oldest first (threshold %dms):",
		#entries, _G.AutoDelete_SpikeThresholdMs
	))
	for i, s in ipairs(entries) do
		print(_FormatSpikeLine(string.format("  #%-2d ", i), s))
	end
end
end  -- end of spike report helpers `do` block

-- Wipe ring buffer + counters. Called by /del spike clear.
function _G.AutoDelete_SpikeClear()
	_G.AutoDelete_SpikeRing = {}
	_G.AutoDelete_SpikeRingNext = 1
	_G.AutoDelete_SpikeWorstRing = {}
	_G.AutoDelete_SpikeSuppressedCount = 0
	if _G.AutoDelete_SpikeReset then _G.AutoDelete_SpikeReset() end
	if _G.AutoDelete_SpikeSessionReset then _G.AutoDelete_SpikeSessionReset() end
	print("|cffff8000[AutoDelete SPIKE]|r ring + counters cleared.")
end

-- Toggle. Registers/unregisters LOOT_* events so the "off" case has zero
-- overhead from extra event traffic. Also flips PerfEnabled on so
-- attribMs accumulates (the user can later disable perf separately if
-- desired; this just guarantees the dependency is satisfied while
-- spike debug is active).
--
-- `scanner` is forward-resolved at call time via _G.AutoDelete_ScannerFrame
-- so this helper can live up here (before scanner is defined). The
-- scanner sets that global once it's created.
function _G.AutoDelete_SetSpikeDebug(on)
	_G.AutoDelete_SpikeDebug = on and true or false
	local sf = _G.AutoDelete_ScannerFrame
	if on then
		_G.AutoDelete_PerfEnabled = true
		if _G.AutoDelete_SpikeReset then _G.AutoDelete_SpikeReset() end
		if sf then
			sf:RegisterEvent("LOOT_OPENED")
			sf:RegisterEvent("LOOT_SLOT_CLEARED")
			sf:RegisterEvent("LOOT_CLOSED")
		end
		print(string.format(
			"|cffff8000[AutoDelete SPIKE]|r tracking |cff00ff00ON|r. Threshold: %dms. Use /del spike report after testing.",
			_G.AutoDelete_SpikeThresholdMs
		))
	else
		if sf then
			sf:UnregisterEvent("LOOT_OPENED")
			sf:UnregisterEvent("LOOT_SLOT_CLEARED")
			sf:UnregisterEvent("LOOT_CLOSED")
		end
		print(string.format(
			"|cffff8000[AutoDelete SPIKE]|r tracking |cffff5555OFF|r. Ring holds %d spike(s) -- /del spike report.",
			(function() local n = 0 for _ in pairs(_G.AutoDelete_SpikeRing) do n = n + 1 end return n end)()
		))
	end
end

function _G.AutoDelete_PerfBegin(phase)
	if not _G.AutoDelete_PerfEnabled then return nil end
	return debugprofilestop()
end

function _G.AutoDelete_PerfEnd(phase, startMs)
	if not startMs then return end
	local elapsed = debugprofilestop() - startMs
	-- v3.20 spike debug: accumulate every instrumented phase's duration
	-- into the per-frame attribMs total. Trusted only when every pickup
	-- path is wrapped in PerfBegin/PerfEnd; see _G.AutoDelete_SpikeRecord
	-- for the audit list.
	if _G.AutoDelete_SpikeDebug then
		_G.AutoDelete_SpikeAttribMs = (_G.AutoDelete_SpikeAttribMs or 0) + elapsed
	end
	local s = _G.AutoDelete_PerfStats[phase]
	if not s then
		s = { count = 0, totalMs = 0, lastMs = 0, maxMs = 0 }
		_G.AutoDelete_PerfStats[phase] = s
	end
	s.count   = s.count + 1
	s.totalMs = s.totalMs + elapsed
	s.lastMs  = elapsed
	if elapsed > s.maxMs then s.maxMs = elapsed end
end

-- Counter-only perf phase: records item counts without timing. Used to
-- separate "how often this branch was taken" from "how long it took". e.g.
-- DeleteItems/items-deleted, DeleteItems/items-skipped-keep. PerfReport
-- renders rows with totalMs=0 as "(counter)" so the user can tell them
-- apart from timer rows at a glance.
function _G.AutoDelete_PerfCount(phase, n)
	if not _G.AutoDelete_PerfEnabled then return end
	n = n or 1
	local s = _G.AutoDelete_PerfStats[phase]
	if not s then
		s = { count = 0, totalMs = 0, lastMs = 0, maxMs = 0, isCounter = true }
		_G.AutoDelete_PerfStats[phase] = s
	end
	s.count = s.count + n
end

function _G.AutoDelete_PerfReport()
	local hasAny = false
	for _ in pairs(_G.AutoDelete_PerfStats) do hasAny = true; break end
	if not hasAny then
		print("|cffff8000[AutoDelete PERF]|r no data collected. Enable with /del perf, then loot/delete/sell something.")
		return
	end
	-- Sort by totalMs descending so the worst offender shows first.
	local rows = {}
	for k, v in pairs(_G.AutoDelete_PerfStats) do
		table.insert(rows, {
			name  = k,
			count = v.count,
			total = v.totalMs,
			avg   = v.totalMs / math.max(1, v.count),
			max   = v.maxMs,
		})
	end
	-- Timer rows sort by total ms desc (worst offender first). Counter
	-- rows (totalMs == 0, recorded via AutoDelete_PerfCount) print AFTER
	-- the timer block so they don't get lost at the bottom of a long
	-- timer-heavy report. v3.20: counters tell us how often a branch
	-- fired during the session (items deleted, items skipped, etc.).
	table.sort(rows, function(a, b) return a.total > b.total end)
	print("|cffff8000[AutoDelete PERF]|r timers (sorted by total ms):")
	print(string.format("  %-36s %7s %10s %8s %8s", "phase", "n", "total ms", "avg ms", "max ms"))
	local printedCounterHeader = false
	for _, r in ipairs(rows) do
		local stats = _G.AutoDelete_PerfStats[r.name]
		if stats and stats.isCounter then
			if not printedCounterHeader then
				print("|cffff8000[AutoDelete PERF]|r counters:")
				print(string.format("  %-36s %10s", "phase", "count"))
				printedCounterHeader = true
			end
			print(string.format("  %-36s %10d", r.name, r.count))
		else
			print(string.format(
				"  %-36s %7d %10.1f %8.2f %8.1f",
				r.name, r.count, r.total, r.avg, r.max))
		end
	end
end

function _G.AutoDelete_PerfReset()
	_G.AutoDelete_PerfStats = {}
	print("|cffff8000[AutoDelete PERF]|r stats cleared.")
end

function _G.AutoDelete_PerfToggle()
	_G.AutoDelete_PerfEnabled = not _G.AutoDelete_PerfEnabled
	if _G.AutoDelete_PerfEnabled then
		print("|cffff8000[AutoDelete PERF]|r tracking |cff00ff00ON|r. Loot/delete/sell normally, then /del perf report.")
	else
		print("|cffff8000[AutoDelete PERF]|r tracking |cffff5555OFF|r. Use /del perf report to view captured data.")
	end
end

-- cachedProfile is used throughout the file (Hide Greedy Spam filter, Auto-Invite
-- handlers, sell/delete logic). It MUST be declared before any function that
-- references it, otherwise Lua resolves `cachedProfile` to the global env (nil)
-- in those functions instead of this local. RefreshCachedProfile() below writes
-- to this same upvalue, so all closures see the latest value.
local cachedProfile = nil

-- Declared here (before any function that calls it) as a forward-assignable
-- local. The real body is assigned later once GetDB / GetActiveProfile are
-- defined. Do NOT redeclare with `local function` below - that shadows this.
local RefreshCachedProfile

-- ============================================================================
-- Shared Timer Helper
-- ============================================================================
-- 3.3.5 has no C_Timer. Several features need to "run something in N seconds":
-- DelayedSummon, the MerchantFrame.Hide flag-release, the post-login ElvUI
-- button setup, and so on.
--
-- The naive approach is CreateFrame("Frame") + SetScript("OnUpdate", ...) per
-- one-shot timer. WoW frames are never garbage-collected, so each call leaks a
-- frame for the rest of the session. Across hundreds of vendor visits or pet
-- summons this accumulates measurable garbage.
--
-- Instead: one persistent frame with an OnUpdate that walks a queue of pending
-- tasks. The OnUpdate detaches itself when the queue is empty so we pay zero
-- per-frame cost while idle. AfterDelay(seconds, fn) is the only API anyone
-- needs.
local timerQueue = {}  -- list of { fireAt = <GetTime> + delay, fn = <function> }
local timerFrame = CreateFrame("Frame")

local function PumpTimers(_, _)
	if #timerQueue == 0 then
		-- Nothing left; detach so this OnUpdate stops costing CPU until the
		-- next AfterDelay re-attaches it.
		timerFrame:SetScript("OnUpdate", nil)
		return
	end
	local now = GetTime()
	-- Walk in-place. Removing the entry shifts later items, so don't increment
	-- when we removed; otherwise advance.
	local i = 1
	while i <= #timerQueue do
		local t = timerQueue[i]
		if now >= t.fireAt then
			-- pcall so a buggy task can't break later tasks in the same frame.
			local ok, err = pcall(t.fn)
			if not ok then
				print("|cffff8000[AutoDelete]|r timer error: " .. tostring(err))
			end
			table.remove(timerQueue, i)
		else
			i = i + 1
		end
	end
end

local function AfterDelay(delaySeconds, fn)
	if type(fn) ~= "function" then return end
	tinsert(timerQueue, { fireAt = GetTime() + (delaySeconds or 0), fn = fn })
	-- Re-attach if we were idle. Setting the same script repeatedly is a no-op.
	timerFrame:SetScript("OnUpdate", PumpTimers)
end

_G.AutoDelete_OneKeyLockFloorSeconds = 1.5
_G.AutoDelete_OneKeyLocks = _G.AutoDelete_OneKeyLocks or {}
_G.AutoDelete_OneKeyPendingTargets = _G.AutoDelete_OneKeyPendingTargets or {}

function _G.AutoDelete_GetOneKeyButton(action)
	if action == "disenchant" then return _G.AutoDeleteDisenchantButton end
	if action == "mill" then return _G.AutoDeleteMillButton end
	if action == "prospect" then return _G.AutoDeleteProspectButton end
	if action == "open" then return _G.AutoDeleteOpenButton end
	return nil
end

function _G.AutoDelete_GetOneKeyLockRemaining(action)
	local lock = action and _G.AutoDelete_OneKeyLocks[action] or nil
	if not lock then return 0 end
	local left = (lock.untilAt or 0) - GetTime()
	if left <= 0 then return 0 end
	return left
end

function _G.AutoDelete_IsOneKeyLocked(action)
	return (_G.AutoDelete_GetOneKeyLockRemaining(action) or 0) > 0
end

function _G.AutoDelete_GetOneKeyLastTarget(action)
	if action == "disenchant" and _G.AutoDelete_GetDisenchantLastTarget then
		return _G.AutoDelete_GetDisenchantLastTarget()
	elseif action == "mill" and _G.AutoDelete_GetMillLastTarget then
		return _G.AutoDelete_GetMillLastTarget()
	elseif action == "prospect" and _G.AutoDelete_GetProspectLastTarget then
		return _G.AutoDelete_GetProspectLastTarget()
	elseif action == "open" and _G.AutoDelete_GetOpenLastTarget then
		return _G.AutoDelete_GetOpenLastTarget()
	end
	return nil
end

function _G.AutoDelete_SetOneKeyLastTarget(action, target)
	if action == "disenchant" and _G.AutoDelete_SetDisenchantLastTarget then
		_G.AutoDelete_SetDisenchantLastTarget(target)
	elseif action == "mill" and _G.AutoDelete_SetMillLastTarget then
		_G.AutoDelete_SetMillLastTarget(target)
	elseif action == "prospect" and _G.AutoDelete_SetProspectLastTarget then
		_G.AutoDelete_SetProspectLastTarget(target)
	elseif action == "open" and _G.AutoDelete_SetOpenLastTarget then
		_G.AutoDelete_SetOpenLastTarget(target)
	end
end

function _G.AutoDelete_UpdateOneKeyAction(action)
	if action == "disenchant" and _G.AutoDelete_UpdateDisenchantButton then
		_G.AutoDelete_UpdateDisenchantButton()
	elseif action == "mill" and _G.AutoDelete_UpdateMillButton then
		_G.AutoDelete_UpdateMillButton()
	elseif action == "prospect" and _G.AutoDelete_UpdateProspectButton then
		_G.AutoDelete_UpdateProspectButton()
	elseif action == "open" and _G.AutoDelete_UpdateOpenButton then
		_G.AutoDelete_UpdateOpenButton()
	end
	if _G.AutoDelete_RefreshProcessPanel then _G.AutoDelete_RefreshProcessPanel() end
	local panel = _G.AutoDeleteOptionsPanel
	if panel and panel.IsShown and panel:IsShown() then
		if panel._refreshDisenchantStatus then panel:_refreshDisenchantStatus() end
		if panel._refreshMillStatus then panel:_refreshMillStatus() end
		if panel._refreshProspectStatus then panel:_refreshProspectStatus() end
		if panel._refreshOpenStatus then panel:_refreshOpenStatus() end
		if panel._refreshProcessCount then panel:_refreshProcessCount() end
	end
end

function _G.AutoDelete_IsOneKeyTargetAllowed(action, target)
	if not action or not target or not target.bag or not target.slot then return false end
	local profile = _G.AutoDelete_GetCachedProfile and _G.AutoDelete_GetCachedProfile()
	if not profile then return false end
	if action == "disenchant" and _G.AutoDelete_IsDisenchantable then
		local override = _G.AutoDelete_KeepOverrideTargets and _G.AutoDelete_KeepOverrideTargets.disenchant
		if target.keepOverride and override and override.bag == target.bag and override.slot == target.slot then
			local link = GetContainerItemLink(target.bag, target.slot)
			local id = link and GetItemIDFromLink(link) or nil
			if id == override.id and _G.AutoDelete_IsDisenchantable_IgnoringKeep then
				return _G.AutoDelete_IsDisenchantable_IgnoringKeep(profile, target.bag, target.slot)
			end
			return false
		end
		return _G.AutoDelete_IsDisenchantable(profile, target.bag, target.slot)
	elseif action == "mill" and _G.AutoDelete_IsMillable then
		return _G.AutoDelete_IsMillable(profile, target.bag, target.slot)
	elseif action == "prospect" and _G.AutoDelete_IsProspectable then
		return _G.AutoDelete_IsProspectable(profile, target.bag, target.slot)
	elseif action == "open" and _G.AutoDelete_IsOpenable then
		return _G.AutoDelete_IsOpenable(profile, target.bag, target.slot)
	end
	return false
end

function _G.AutoDelete_ClearOneKeyTarget(action)
	if not action then return end
	_G.AutoDelete_SetOneKeyLastTarget(action, nil)
	local btn = _G.AutoDelete_GetOneKeyButton(action)
	if btn and btn.SetAttribute and not (InCombatLockdown and InCombatLockdown()) then
		btn:SetAttribute("macrotext", "")
	end
	local panel = _G.AutoDeleteOptionsPanel
	if panel and panel.IsShown and panel:IsShown() then
		if action == "disenchant" and panel._refreshDisenchantStatus then panel:_refreshDisenchantStatus() end
		if action == "mill" and panel._refreshMillStatus then panel:_refreshMillStatus() end
		if action == "prospect" and panel._refreshProspectStatus then panel:_refreshProspectStatus() end
		if action == "open" and panel._refreshOpenStatus then panel:_refreshOpenStatus() end
	end
	if _G.AutoDelete_RefreshProcessPanel then _G.AutoDelete_RefreshProcessPanel() end
end

function _G.AutoDelete_StartOneKeyLock(action, seconds)
	if not action then return end
	local btn = _G.AutoDelete_GetOneKeyButton(action)
	local now = GetTime()
	local duration = math.max(tonumber(seconds) or 0, _G.AutoDelete_OneKeyLockFloorSeconds or 1.5)
	local untilAt = now + duration
	_G.AutoDelete_OneKeyLocks[action] = { untilAt = untilAt }
	if btn then
		if not (InCombatLockdown and InCombatLockdown()) then
			btn:SetAttribute("macrotext", "")
			if btn.Disable then btn:Disable() end
		end
	end
	if _G.AutoDelete_ProcessClearArmed then _G.AutoDelete_ProcessClearArmed(action) end
	AfterDelay(duration, function()
		local lock = _G.AutoDelete_OneKeyLocks[action]
		if lock and (lock.untilAt or 0) <= GetTime() + 0.01 then
			_G.AutoDelete_OneKeyLocks[action] = nil
			local lockedBtn = _G.AutoDelete_GetOneKeyButton(action)
			if lockedBtn and lockedBtn.Enable then
				local function enableWhenSafe()
					if InCombatLockdown and InCombatLockdown() then
						AfterDelay(0.25, enableWhenSafe)
						return
					end
					lockedBtn:Enable()
					if _G.AutoDelete_UpdateOneKeyAction then _G.AutoDelete_UpdateOneKeyAction(action) end
				end
				enableWhenSafe()
				return
			end
			if _G.AutoDelete_UpdateOneKeyAction then _G.AutoDelete_UpdateOneKeyAction(action) end
		end
	end)
	if _G.AutoDelete_UpdateOneKeyAction then _G.AutoDelete_UpdateOneKeyAction(action) end
end

function _G.AutoDelete_OnOneKeyPostClick(action)
	local target = _G.AutoDelete_GetOneKeyLastTarget and _G.AutoDelete_GetOneKeyLastTarget(action)
	if not target then return end
	_G.AutoDelete_OneKeyPendingTargets[action] = {
		target = target,
		untilAt = GetTime() + 3,
	}
	_G.AutoDelete_StartOneKeyLock(action, _G.AutoDelete_OneKeyLockFloorSeconds)
end

function _G.AutoDelete_OnOneKeySpellStart(spellName)
	if not spellName then return end
	local action = nil
	if _G.AutoDelete_GetCachedDisenchantName and spellName == (_G.AutoDelete_GetCachedDisenchantName() or "Disenchant") then
		action = "disenchant"
	elseif _G.AutoDelete_GetCachedMillName and spellName == (_G.AutoDelete_GetCachedMillName() or "Milling") then
		action = "mill"
	elseif _G.AutoDelete_GetCachedProspectName and spellName == (_G.AutoDelete_GetCachedProspectName() or "Prospecting") then
		action = "prospect"
	end
	if not action then return end
	local duration = _G.AutoDelete_OneKeyLockFloorSeconds or 1.5
	if UnitCastingInfo then
		local _, _, _, _, startTimeMS, endTimeMS = UnitCastingInfo("player")
		if startTimeMS and endTimeMS and endTimeMS > startTimeMS then
			duration = math.max(duration, (endTimeMS - startTimeMS) / 1000)
		end
	end
	local pending = _G.AutoDelete_OneKeyPendingTargets[action]
	if pending then
		pending.untilAt = GetTime() + duration + 2
	end
	_G.AutoDelete_StartOneKeyLock(action, duration)
end

-- ============================================================================
-- Database
-- ============================================================================

local function GetCharKey()
	local name = UnitName("player")
	local realm = GetRealmName and GetRealmName() or nil
	if not name then return nil end
	if realm and realm ~= "" then return name .. "-" .. realm end
	return name
end

local DEFAULT_PROFILE = {
	-- ============================================================
	-- Master switch
	-- ============================================================
	-- Gates the periodic delete/sell scanner, vendor auto-repair,
	-- vendor auto-sell, and the companion watcher (mount-aware
	-- dismiss/re-summon, stuck-detection, bag-full merchant summon).
	-- Auto-Invite and Hide Greedy Spam are deliberately INDEPENDENT
	-- of this switch - they run regardless.
	enabled = false,

	-- ============================================================
	-- Item lists (newline-delimited "item:<id>" strings)
	-- ============================================================
	-- Mutually-exclusive lists. AddItemToList enforces this:
	-- adding an item to one list rejects the add if it's already on
	-- another. The Keep list always wins at scan time; nothing on it
	-- can be auto-sold or auto-deleted by any rule.
	listText      = "",   -- Delete list  (auto-destroyed every scan)
	sellListText  = "",   -- Sell list    (auto-sold at any vendor)
	whitelistText = "",   -- Keep list    (protected from all rules)
	keepOneText   = "",   -- KeepOne list (delete extras, leave one unit)
	keepStackText = "",   -- KeepStack list (delete extra stacks, leave one stack)

	-- ============================================================
	-- Periodic scan
	-- ============================================================
	scanInterval = 0.5,    -- seconds; floored at 0.5 in the scanner

	-- ============================================================
	-- Auto-Delete / Auto-Sell by quality (General tab, three rows)
	-- ============================================================
	-- These three run on every scan and are independent of the BoE
	-- Armor / BoP / BoE Weapons category sections below. They all
	-- skip quest items, items on the Keep list, and shirts/tabards.
	-- ============================================================
	-- Tools (Tools tab)
	-- ============================================================
	-- Affix Protection (Affix tab): tier checkboxes block destructive rules
	-- before Delete or Sell can act. Checked tiers are absolute and run
	-- before Show/Keep Missing Affix or KeepOne Missing Affix cleanup.
	protectAffixFromDelete = false, -- legacy; retained for old profiles
	protectAffixFromSell   = false, -- legacy migration source
	affixIlvlMin           = 0,     -- legacy; no longer used
	protectAffixTier1      = false,
	protectAffixTier2      = false,
	protectAffixTier3      = false,
	protectAffixTier4      = false,
	protectAffixTier5      = false,
	keepSingleMissingAffix    = false,

	-- Visual cyan dot in the bottom-left corner of bag slots with affixed
	-- items. On by default since most users want the visual cue; toggle
	-- lives on the General tab next to Scan Speed.
	showAffixDot           = true,

	-- Affix Collection Mode (Filters tab, Affix Protection card).
	-- When OFF (default): the affix dot shows on every affixed item,
	-- colored by tier (white/green/blue/purple/orange). Affix
	-- tier protection applies to all checked affix tiers.
	-- When ON: the dot ONLY shows for affixes the player hasn't yet
	-- learned in PE's perk system (reads ExtractionService.learnedAffixes
	-- directly), colored with missingAffixColor. Items whose affix is
	-- already owned at the same tier pass through to normal sell/delete
	-- rules (duplicate-cleanup behavior). Fallback when the PE addon
	-- isn't loaded: behaves as if mode is OFF.
	affixCollectionMode    = false,
	missingAffixColor      = "red",
	missingAffixColorR     = 1.00,
	missingAffixColorG     = 0.231,
	missingAffixColorB     = 0.255,

	-- Bag Space / Goblin summon (Pets tab):
	--   bagSpaceWarnThreshold is the free-slot count at or below which
	--   the Goblin Merchant auto-summon fires (after BAGS_FULL_DELAY of
	--   sustained-low). Default 2 = "really almost full" -- matches what
	--   "bags full" intuitively means; previous default of 5 conflated
	--   "heads-up warning" with "actually need a merchant" and caused
	--   premature summons during normal play.
	--
	--   The migration in RunDBMigrations() upgrades existing profiles
	--   whose stored value is exactly 5 (the old default) to 2 so users
	--   don't have to manually adjust after upgrade.
	--
	--   bagSpaceWarnEnabled is retained in defaults as `false` for
	--   backward compatibility with profiles created before v3.20; the
	--   chat-warning code that read this field has been removed.
	bagSpaceWarnEnabled       = false,   -- legacy; no longer consumed
	bagSpaceWarnThreshold     = 2,       -- Goblin summon threshold

	-- One-Key Disenchant (Keybinds tab): a SecureActionButton wired to the
	-- next disenchantable item in bags. The user binds a key in the panel's
	-- in-panel key-capture row; pressing it fires `/cast Disenchant` + `/use
	-- bag slot`. 3.3.5a's protected-function gate is satisfied because the
	-- hardware keypress (not addon code) is what triggers the macro.
	--   disenchantEnabled   gates the whole feature (off by default; opt-in).
	--   disenchantBoP       targets Soulbound items. Default ON: the common
	--                       case is clearing greens you ground out.
	--   disenchantBoE       targets items that are still BoE (haven't been
	--                       equipped yet). Default OFF because BoE items are
	--                       often more valuable to AH or pass to alts.
	--   disenchantUncommon  greens. Default ON.
	--   disenchantRare      blues. Default OFF.
	--   disenchantEpic      epics. Default OFF.
	--   disenchantIlvlMin   per-quality floor (0 = use Blizzard mechanical
	--                       floor: 5 for greens, 55 for blues, 95 for epics).
	--   disenchantIlvlMax   per-quality ceiling (0 = no cap; Disenchant will
	--                       still refuse to cast on items above the live game
	--                       maximum, ~373 in WotLK).
	disenchantEnabled  = false,
	disenchantBoP      = true,
	disenchantBoE      = false,
	disenchantUncommon = true,
	disenchantRare     = false,
	disenchantEpic     = false,
	disenchantIlvlMin  = 0,
	disenchantIlvlMax  = 0,

	-- One-Key Mill (Inscription). SecureActionButton + macrotext + user
	-- keypress, same shape as Disenchant. Targets the next stack of 5+
	-- herbs in bags (the cast requires a stack of 5 to consume). Skill
	-- check: character must know Milling (spell 51005).
	millEnabled = false,

	-- One-Key Prospect (Jewelcrafting). Same shape as Mill but for ore.
	-- Skill check: character must know Prospecting (spell 31252).
	prospectEnabled = false,

	-- One-Key Open (Tools tab): wires a SecureActionButton to the next
	-- openable item in bags so the user can clear clams, lockboxes,
	-- coin purses, eggs, etc. with one keypress. Architecture mirrors
	-- One-Key Disenchant; see that module's header for the protected-
	-- function-gate rationale and the SecureActionButton + macrotext
	-- pattern.
	--   autoOpenEnabled gates the feature (off by default; opt-in).
	--   autoOpenIncludeLocked controls whether locked-tier items (junkboxes
	--   etc.) are eligible targets when currently unlocked. Items marked
	--   "false" in the allow-list (lockable items) only become a target
	--   when unlocked AND this toggle is on. Default ON because a player
	--   who has a key/rogue would always want unlocked junkboxes to be
	--   targetable; turning it off hides the entire locked-tier set.
	autoOpenEnabled       = false,
	autoOpenIncludeLocked = true,

	-- Quality filters are tri-state cycle toggles: "off" | "delete" | "sell".
	-- Each quality can be independently set to do nothing, auto-delete, or
	-- auto-sell at vendor. Old booleans (autoGray, autoDeleteCommon,
	-- autoSellGreens) are migrated to these fields by RunDBMigrations v3
	-- and then left in place for one version as a fallback read for older
	-- code paths; the canonical fields going forward are the qualityAction*
	-- enums.
	--   Junk    = gray quality, any item type
	--   Common  = white quality, equippable gear only
	--   Greens  = green quality, equippable gear only
	qualityActionJunk    = "off",
	qualityActionCommon  = "off",
	qualityActionGreens  = "off",

	-- Legacy booleans -- retained for one version while migration settles.
	-- DO NOT read these in new code; read qualityAction* instead. Removed
	-- in v3.21 after we confirm no users are running un-migrated profiles.
	autoGray         = false,  -- DEPRECATED: see qualityActionJunk
	autoDeleteCommon = false,  -- DEPRECATED: see qualityActionCommon
	autoSellGreens   = false,  -- DEPRECATED: see qualityActionGreens

	-- ============================================================
	-- Auto-Add Equipped (General tab)
	-- ============================================================
	-- When ON, two behaviours run together:
	--   1) On enable (toggle flip false->true): one-time sync of every
	--      currently equipped slot into the Keep list.
	--   2) Reactive: PLAYER_EQUIPMENT_CHANGED fires any time you swap
	--      gear; the new item is added to Keep automatically.
	-- Existing Keep entries are deduped by item id, so this is safe to
	-- re-trigger. Defaults to true so new users are protected without
	-- having to know about the feature.
	autoAddEquipped  = true,

	-- ============================================================
	-- Sell categories (Sell tab, three cards)
	-- ============================================================
	-- Each section is independent. An item only ever matches one
	-- category at scan time. Priority order: BoE Weapons > BoP >
	-- BoE Armor (so a BoE weapon never gets caught by BoE Armor's
	-- "all weapon slots excluded" rule because BoE Weapons fires
	-- first). Each section sells items whose iLvl is inside
	-- [Min, Max] AND whose rarity matches an enabled toggle.

	-- BoE Armor: BoE items NOT in WEAPON_SLOTS (i.e. armor and
	-- accessories). WEAPON_SLOTS covers everything Hand Affix
	-- Enchant can target on Project Ebonhold.
	boeArmorEnabled = false,
	boeArmorIlvlMin = 1,
	boeArmorIlvlMax = 199,
	boeArmorRare    = false,
	boeArmorEpic    = false,

	-- BoP: any Bind-on-Pickup gear (any slot, including weapons).
	bopEnabled = false,
	bopIlvlMin = 1,
	bopIlvlMax = 199,
	bopRare    = false,
	bopEpic    = false,

	-- BoE Weapons: BoE items in WEAPON_SLOTS (weapons, shields,
	-- holdables, ranged, thrown, relics). Takes priority over BoE
	-- Armor for items that match both.
	boeWeaponsEnabled = false,
	boeWeaponsIlvlMin = 1,
	boeWeaponsIlvlMax = 199,
	boeWeaponsRare    = false,
	boeWeaponsEpic    = false,

	-- Sell Known Recipes: vendor-only cleanup for Project Ebonhold recipe items.
	-- When enabled, a recipe is sold only if its bag tooltip positively says
	-- ITEM_SPELL_KNOWN. Recipe-like items are kept out of automatic delete
	-- rules while this feature is on; explicit Delete/KeepOne/KeepStack lists
	-- still behave as user intent.
	knownRecipeSellEnabled  = false,
	knownRecipeSellCommon   = true,
	knownRecipeSellUncommon = true,
	knownRecipeSellRare     = false,
	knownRecipeSellEpic     = false,

	-- ============================================================
	-- Companion management (Goblin tab)
	-- ============================================================
	-- summonScavenger is the master toggle for ALL companion
	-- features: it gates mount-aware dismiss/re-summon, the
	-- stuck-detection re-summon, the after-sell + after-close
	-- summons, AND the bag-full Goblin Merchant trigger. The
	-- master AutoDelete `enabled` flag also gates this feature
	-- group as a whole.
	summonScavenger            = false,
	summonAfterSell            = true,    -- summon scav after vendor sell completes
	summonAfterClose           = false,   -- summon scav after vendor window closes
	summonOnlyInCombat         = true,    -- gate ALL auto-summon paths on UnitAffectingCombat("player")
	summonMerchantWhenBagsFull = false,   -- summon Goblin Merchant when bags hit 0 free for 3s+

	-- ============================================================
	-- Vendor extras (Goblin tab)
	-- ============================================================
	-- Both fire at MERCHANT_SHOW. Gated by `enabled`.
	autoRepair             = false,
	autoRepairUseGuildBank = false,   -- prefer guild bank funds when available

	-- ============================================================
	-- Hide Greedy Scavenger spam (Goblin tab)
	-- ============================================================
	-- Suppresses the scavenger's chat lines AND chat bubbles.
	-- Independent of the master `enabled` toggle.
	hideGreedySpam = false,

	-- ============================================================
	-- Auto-Invite (AutoInv tab)
	-- ============================================================
	-- Independent of the master `enabled` toggle.
	-- autoInviteLootRule values: "freeforall" | "roundrobin"
	--                           | "group" | "needbeforegreed" | "master"
	autoInviteEnabled         = false,
	autoInviteKeywords        = "inv,invite",
	autoInviteApplyLootRule   = false,
	autoInviteLootRule        = "freeforall",
	autoInviteConvertToRaid   = false,    -- convert party→raid when 6th player joins
}

local function NewProfile(overrides)
	local p = {}
	for k, v in pairs(DEFAULT_PROFILE) do p[k] = v end
	if overrides then
		for k, v in pairs(overrides) do p[k] = v end
	end
	return p
end

local function MigrateDB(db)
	if db.profiles then return end
	db.profiles = {}
	db.chars = {}
	local charKey = GetCharKey() or "Default"
	db.profiles[charKey] = NewProfile({
		enabled = db.enabled and true or false,
		listText = db.listText or "",
	})
	db.chars[charKey] = charKey
end

local function EnsureProfileFields(p)
	-- Invert old dontSellBoEWeapons field into sellBoEWeapons.
	if p.dontSellBoEWeapons ~= nil then
		p.sellBoEWeapons = not p.dontSellBoEWeapons
		p.dontSellBoEWeapons = nil
	end
	-- Old profiles stored the weapon iLvl threshold in sellBoEWeaponMinIlvl
	-- as a floor. The range model renamed it to sellBoEWeaponMaxIlvl as the
	-- ceiling. Only migrate if the new field is still absent so legitimate
	-- range-min values on current profiles are preserved.
	if p.sellBoEWeaponMinIlvl ~= nil and p.sellBoEWeaponMaxIlvl == nil then
		p.sellBoEWeaponMaxIlvl = p.sellBoEWeaponMinIlvl
		p.sellBoEWeaponMinIlvl = nil
	end

	-- v3.02 schema migration: collapse the old split (sell filters + sell
	-- conditions) into category cards. Runs only once per profile thanks to
	-- the _v302Migrated flag. Detection: any of the old field names present.
	local hasOldFields = (p.sellJunk ~= nil) or (p.sellGreen ~= nil)
		or (p.sellBlue ~= nil) or (p.sellEpic ~= nil)
		or (p.sellBoE ~= nil) or (p.sellBoEWeapons ~= nil)
		or (p.sellIlvlEnabled ~= nil)
	if hasOldFields and not p._v302Migrated then
		-- Old global rarity toggles: Junk/Common become DELETE actions,
		-- Greens become a SELL action.
		-- Junk: existing autoGray field is the canonical Auto-Delete Junk
		-- toggle (was already wired). If a profile had sellJunk=true but
		-- autoGray was unset/false, prefer the user's intent.
		if p.sellJunk == true then p.autoGray = true end
		p.autoDeleteCommon = false                 -- old schema had no Common toggle
		p.autoSellGreens   = (p.sellGreen == true)

		-- Old sellBoE was a generic "BoE gear" flag with shared iLvl range
		-- (sellIlvlMin/Max if sellIlvlEnabled). Map it to BoE Armor.
		local hadIlvlRange = (p.sellIlvlEnabled == true)
		p.boeArmorEnabled = (p.sellBoE == true)
		p.boeArmorRare    = (p.sellBoE == true) and (p.sellBlue == true)
		p.boeArmorEpic    = (p.sellBoE == true) and (p.sellEpic == true)
		if hadIlvlRange and p.sellIlvlMin then
			p.boeArmorIlvlMin = p.sellIlvlMin
		end
		if hadIlvlRange and p.sellIlvlMax then
			p.boeArmorIlvlMax = p.sellIlvlMax
		end

		-- BoP didn't exist in the old schema as its own category. Default off.
		p.bopEnabled = false
		p.bopRare    = false
		p.bopEpic    = false

		-- BoE Weapons had its own toggle and iLvl range.
		p.boeWeaponsEnabled = (p.sellBoEWeapons == true)
		p.boeWeaponsRare    = (p.sellBoEWeapons == true) and (p.sellBlue == true)
		p.boeWeaponsEpic    = (p.sellBoEWeapons == true) and (p.sellEpic == true)
		if p.sellBoEWeaponMinIlvl then
			p.boeWeaponsIlvlMin = p.sellBoEWeaponMinIlvl
		end
		if p.sellBoEWeaponMaxIlvl then
			p.boeWeaponsIlvlMax = p.sellBoEWeaponMaxIlvl
		end

		-- Strip the old fields so they can't accidentally still be read.
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
		-- Flag that the chat notice is owed for this profile. The notice
		-- itself is printed once at PLAYER_LOGIN; this just marks it.
		_G._AutoDelete_NeedMigrationNotice = true
	end

	local hasAffixTierProtection = p.protectAffixTier1 ~= nil
		or p.protectAffixTier2 ~= nil
		or p.protectAffixTier3 ~= nil
		or p.protectAffixTier4 ~= nil
		or p.protectAffixTier5 ~= nil
	if not hasAffixTierProtection and p.protectAffixFromSell == true then
		p.protectAffixTier1 = true
		p.protectAffixTier2 = true
		p.protectAffixTier3 = true
		p.protectAffixTier4 = true
		p.protectAffixTier5 = true
	end

	for k, v in pairs(DEFAULT_PROFILE) do
		if p[k] == nil then p[k] = v end
	end
	if p.missingAffixColor ~= "red"
		and p.missingAffixColor ~= "gold"
		and p.missingAffixColor ~= "mage"
		and p.missingAffixColor ~= "green"
		and p.missingAffixColor ~= "purple"
		and p.missingAffixColor ~= "custom" then
		p.missingAffixColor = DEFAULT_PROFILE.missingAffixColor
	end
	if type(p.missingAffixColorR) ~= "number" then p.missingAffixColorR = DEFAULT_PROFILE.missingAffixColorR end
	if type(p.missingAffixColorG) ~= "number" then p.missingAffixColorG = DEFAULT_PROFILE.missingAffixColorG end
	if type(p.missingAffixColorB) ~= "number" then p.missingAffixColorB = DEFAULT_PROFILE.missingAffixColorB end
	if p.missingAffixColorR < 0 then p.missingAffixColorR = 0 elseif p.missingAffixColorR > 1 then p.missingAffixColorR = 1 end
	if p.missingAffixColorG < 0 then p.missingAffixColorG = 0 elseif p.missingAffixColorG > 1 then p.missingAffixColorG = 1 end
	if p.missingAffixColorB < 0 then p.missingAffixColorB = 0 elseif p.missingAffixColorB > 1 then p.missingAffixColorB = 1 end
end

-- AutoDeleteDB schema version. Bumped when a non-additive change to the
-- SavedVariables shape lands (a field rename, a removed field, a type
-- change). Additive default-field changes do NOT need a bump because
-- EnsureProfileFields backfills via DEFAULT_PROFILE on every login.
--
-- The migration scaffold below is intentionally empty for now; future
-- breaking changes append a numbered block:
--
--   if (db.version or 0) < 2 then
--       -- migration logic
--       db.version = 2
--   end
--
-- One canonical migration spot so a future reader knows exactly where to add a
-- new step.
local AUTODELETE_DB_VERSION = 4

local function RunDBMigrations(db)
	if not db then return end
	db.version = db.version or 0
	-- Migrations land here, in numeric order, each bumping db.version.
	--
	-- v1: introduce db.version field. No-op for existing data.
	-- v2 (2026-05-20): the bag-space chat warning was removed and the
	--     bagSpaceWarnThreshold field repurposed as the Goblin summon
	--     threshold only. Old default was 5 (sized for "heads up, bags
	--     filling"); new default is 2 (sized for "actually need a
	--     merchant now"). Bump any profile whose stored value is exactly
	--     5 (the old default) to 2 so users don't see premature summons
	--     after upgrade. Leave non-5 user-set values alone.
	if db.version < 2 and db.profiles then
		for _, profile in pairs(db.profiles) do
			if profile and profile.bagSpaceWarnThreshold == 5 then
				profile.bagSpaceWarnThreshold = 2
			end
		end
	end
	-- v3 (2026-05-22): three independent quality booleans
	-- (autoGray, autoDeleteCommon, autoSellGreens) become three tri-state
	-- enum fields (qualityActionJunk/Common/Greens) so each quality can be
	-- independently set to Off / Delete / Sell. Migration: existing TRUE
	-- becomes the same semantic the old field had (delete for Junk and
	-- Common, sell for Greens); FALSE becomes "off". Legacy booleans stay
	-- present for one version so any straggler code path that still reads
	-- the old field doesn't crash, but new code reads the new enum only.
	if db.version < 3 and db.profiles then
		local migrated = 0
		for _, profile in pairs(db.profiles) do
			if profile then
				-- Only set the new field if it isn't already present so
				-- re-running the migration on a partially-migrated profile
				-- doesn't overwrite a deliberate user choice.
				if profile.qualityActionJunk == nil then
					profile.qualityActionJunk = (profile.autoGray == true) and "delete" or "off"
				end
				if profile.qualityActionCommon == nil then
					profile.qualityActionCommon = (profile.autoDeleteCommon == true) and "delete" or "off"
				end
				if profile.qualityActionGreens == nil then
					profile.qualityActionGreens = (profile.autoSellGreens == true) and "sell" or "off"
				end
				migrated = migrated + 1
			end
		end
		if migrated > 0 then
			-- One-time chat note so the user knows their settings carried
			-- over and they don't get blamed for "weird new defaults."
			print("|cffff8000[AutoDelete]|r migrated " .. migrated ..
				" profile(s) to the new Junk/Common/Greens tri-state quality filters. " ..
				"Your existing Delete/Sell choices were preserved.")
		end
	end
	-- v4 (2026-05-22, then NEUTRALIZED 2026-05-23): originally normalized
	-- qualityActionGreens == "delete" -> "off" because the Auto Actions UI
	-- briefly dropped Delete for Greens. The user reverted that decision
	-- the same release cycle and asked for Greens-Delete back, so the
	-- migration body is now a no-op -- we keep the version bump so any
	-- stored db.version > 3 still advances cleanly, but we don't touch
	-- any profile data here. Players whose data was clobbered during the
	-- brief v4 window (i.e. anyone who tested between 2026-05-22 and the
	-- restore) just need to re-pick Del on the Greens row.
	if db.version < 4 and db.profiles then
		-- intentionally empty -- see comment above.
	end
	db.version = AUTODELETE_DB_VERSION
end

local function GetDB()
	_G.AutoDeleteDB = _G.AutoDeleteDB or {}
	local db = _G.AutoDeleteDB
	if not db.profiles then MigrateDB(db) end
	db.profiles = db.profiles or {}
	db.chars = db.chars or {}
	-- Run versioned migrations once profiles are present. Safe to call
	-- every GetDB() entry; idempotent on a fully-migrated DB.
	RunDBMigrations(db)
	local charKey = GetCharKey() or "Default"
	local profileKey = db.chars[charKey] or charKey
	if not db.profiles[profileKey] then
		db.profiles[profileKey] = NewProfile()
	end
	EnsureProfileFields(db.profiles[profileKey])
	if not db.chars[charKey] then db.chars[charKey] = profileKey end
	return db
end

local function GetActiveProfile(db)
	local charKey = GetCharKey() or "Default"
	local profileKey = (db and db.chars and db.chars[charKey]) or charKey
	if not db.profiles[profileKey] then
		db.profiles[profileKey] = NewProfile()
	end
	EnsureProfileFields(db.profiles[profileKey])
	return db.profiles[profileKey], profileKey, charKey
end

-- ============================================================================
-- Tracking Stats (per-character, saved in AutoDeleteStatsDB)
-- ============================================================================
-- Lifetime stats persist across sessions. Session stats reset on /reload or
-- login. Both are per-character via the SavedVariablesPerCharacter TOC line.

local DEFAULT_STATS = {
	-- Lifetime totals (persisted)
	goldEarned = 0,           -- copper total from selling
	itemsSold = 0,            -- count of sell actions
	itemsDeleted = 0,         -- count of delete actions
	repairs = 0,              -- count of repair events
	repairSpend = 0,          -- copper total spent on repairs
	inventoryWorthTotal = 0,  -- running sum of inventory worth samples
	inventoryWorthCount = 0,  -- number of samples (for avg = total / count)
}

-- Session counters (in-memory only, not saved). Reset on login/reload.
local sessionStats = {
	goldEarned = 0,
	itemsSold = 0,
	itemsDeleted = 0,
	repairs = 0,
	repairSpend = 0,
	inventoryWorthTotal = 0,
	inventoryWorthCount = 0,
}

local function EnsureStatsDB()
	if AutoDeleteStatsDB == nil then AutoDeleteStatsDB = {} end
	for k, v in pairs(DEFAULT_STATS) do
		if type(AutoDeleteStatsDB[k]) ~= "number" then
			AutoDeleteStatsDB[k] = v
		end
	end
	return AutoDeleteStatsDB
end

local function GetStats()
	return EnsureStatsDB()
end

-- Record lifetime + session increments for any of the tracked fields.
local function BumpStat(key, amount)
	if not key or not amount or amount == 0 then return end
	local s = EnsureStatsDB()
	s[key] = (s[key] or 0) + amount
	sessionStats[key] = (sessionStats[key] or 0) + amount
end

-- Reset ALL tracking stats (lifetime + session). Fires from the Tracking tab
-- Reset button.
local function ResetAllStats()
	local s = EnsureStatsDB()
	for k, v in pairs(DEFAULT_STATS) do
		s[k] = v
	end
	for k, v in pairs(DEFAULT_STATS) do
		sessionStats[k] = v
	end
end

-- Expose to Options.lua via a shared namespace.
_G.AutoDelete_Stats = {
	GetLifetime = GetStats,
	GetSession = function() return sessionStats end,
	Reset = ResetAllStats,
	-- Format helpers so the UI doesn't have to reimplement these.
	-- FormatMoney rounds to gold only; silver/copper are noise for tracking
	-- displays. Sub-1g values floor to 0g.
	FormatMoney = function(copper)
		copper = tonumber(copper) or 0
		if copper <= 0 then return "0g" end
		local gold = math.floor(copper / 10000)
		return gold .. "g"
	end,
	-- Insert thousand separators: 14532 → "14,532"
	FormatNumber = function(n)
		n = tonumber(n) or 0
		local s = tostring(math.floor(n))
		-- Repeatedly insert commas from the right until no more groups of 3.
		local k
		while true do
			s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
			if k == 0 then break end
		end
		return s
	end,
}

-- ============================================================================
-- Recent Decision History
-- ============================================================================
-- In-memory ring for the most recent meaningful decisions. It is intentionally
-- not saved: this is a troubleshooting trail for the current session, not a
-- permanent audit database.
_G.AutoDelete_DecisionHistory = _G.AutoDelete_DecisionHistory or {
	entries = {},
	cap = 200,
	lastKey = nil,
	lastAt = 0,
}

function _G.AutoDelete_RecordDecision(data)
	if not data then return end
	local hist = _G.AutoDelete_DecisionHistory
	hist.entries = hist.entries or {}
	hist.cap = math.max(hist.cap or 0, 200)
	local now = (GetTime and GetTime()) or 0
	local itemId = data.itemId or data.id
	local itemName = data.itemName or data.name or (itemId and GetItemInfo(itemId)) or "Unknown item"
	local action = data.action or "unknown"
	local reason = data.reason or "No reason recorded"
	local source = data.sourceRule or data.source or "Unknown rule"
	local affixName = data.affixName or data.affixKey
	local recipeLike = data.recipeLike == true
	local recipeState = data.recipeState
	local recipeQuality = data.recipeQuality
	local recipeQualityLabel = data.recipeQualityLabel
		or (recipeQuality ~= nil and _G.AutoDelete_GetRecipeQualityLabel and _G.AutoDelete_GetRecipeQualityLabel(recipeQuality))
	local recipeQualityEnabled = data.recipeQualityEnabled
	if not affixName and _G.AutoDelete_GetAffixKeyForItemName then
		affixName = _G.AutoDelete_GetAffixKeyForItemName(itemName)
	end
	local key = table.concat({
		tostring(itemId or itemName),
		tostring(action),
		tostring(reason),
		tostring(source),
		tostring(affixName or ""),
		tostring(recipeLike),
		tostring(recipeState or ""),
		tostring(recipeQualityLabel or ""),
		tostring(recipeQualityEnabled),
	}, "|")
	local first = hist.entries[1]
	if first and hist.lastKey == key and (now - (hist.lastAt or 0)) < 10 then
		first.time = now
		first.repeatCount = (first.repeatCount or 1) + 1
		hist.lastAt = now
		return
	end
	table.insert(hist.entries, 1, {
		time = now,
		itemName = itemName,
		itemId = itemId,
		action = action,
		reason = reason,
		sourceRule = source,
		affixName = affixName,
		recipeLike = recipeLike,
		recipeState = recipeState,
		recipeQuality = recipeQuality,
		recipeQualityLabel = recipeQualityLabel,
		recipeQualityEnabled = recipeQualityEnabled,
		bag = data.bag,
		slot = data.slot,
		repeatCount = 1,
	})
	while #hist.entries > hist.cap do
		table.remove(hist.entries)
	end
	hist.lastKey = key
	hist.lastAt = now
end

function _G.AutoDelete_ClearDecisionHistory()
	local hist = _G.AutoDelete_DecisionHistory
	hist.entries = {}
	hist.lastKey = nil
	hist.lastAt = 0
end

function _G.AutoDelete_FormatDecisionHistoryAgo(entry, now)
	local t = entry and entry.time
	if not t or t == 0 then return "unknown" end
	return string.format("%.1fs ago", math.max(0, (now or 0) - t))
end

function _G.AutoDelete_BuildDecisionHistoryReport(searchText)
	local hist = _G.AutoDelete_DecisionHistory or {}
	local entries = hist.entries or {}
	local now = (GetTime and GetTime()) or 0
	local function SearchKey(value)
		value = tostring(value or "")
		value = string.lower(value)
		value = string.gsub(value, "^%s+", "")
		value = string.gsub(value, "%s+$", "")
		return value
	end
	local query = SearchKey(searchText or "")
	local filtered = {}
	local function Matches(entry)
		if query == "" then return true end
		local fields = {
			entry.itemName,
			entry.itemId and ("item:" .. tostring(entry.itemId)) or nil,
			entry.action,
			entry.reason,
			entry.sourceRule,
			entry.affixName,
			entry.recipeLike and "recipe" or nil,
			entry.recipeState,
			entry.recipeQualityLabel,
			entry.recipeQualityEnabled ~= nil and ("recipe quality " .. (entry.recipeQualityEnabled and "enabled" or "disabled")) or nil,
			entry.bag and entry.slot and (tostring(entry.bag) .. "." .. tostring(entry.slot)) or nil,
		}
		for _, value in ipairs(fields) do
			if value and string.find(SearchKey(value), query, 1, true) then
				return true
			end
		end
		return false
	end
	for _, entry in ipairs(entries) do
		if Matches(entry) then table.insert(filtered, entry) end
	end
	local lines = {
		"AutoDelete recent decision history",
		"Session entries: " .. tostring(#entries),
		"",
	}
	if query ~= "" then
		table.insert(lines, 3, "Search: " .. tostring(searchText) .. " (" .. tostring(#filtered) .. " match" .. (#filtered == 1 and "" or "es") .. ")")
	end
	if query ~= "" and #filtered == 0 then
		table.insert(lines, "No matching decisions found this session.")
		return table.concat(lines, "\n")
	end
	if #entries == 0 then
		table.insert(lines, "No decisions recorded this session.")
		table.insert(lines, "")
		table.insert(lines, "This log records actual deletes, actual sells, recipe sales/protection, and matching rules blocked by Keep or Affix Protection.")
		return table.concat(lines, "\n")
	end
	for i, entry in ipairs(filtered) do
		table.insert(lines, string.format("%d. %s", i, _G.AutoDelete_FormatDecisionHistoryAgo(entry, now)))
		table.insert(lines, "   Item: " .. tostring(entry.itemName) .. (entry.itemId and (" (item:" .. entry.itemId .. ")") or ""))
		if entry.affixName then
			table.insert(lines, "   Affix: " .. tostring(entry.affixName))
		end
		if entry.recipeLike then
			table.insert(lines, "   Recipe: yes"
				.. (entry.recipeState and ("; knowledge=" .. tostring(entry.recipeState)) or "")
				.. (entry.recipeQualityLabel and ("; quality=" .. tostring(entry.recipeQualityLabel)) or "")
				.. (entry.recipeQualityEnabled ~= nil and ("; quality toggle=" .. (entry.recipeQualityEnabled and "on" or "off")) or ""))
		end
		table.insert(lines, "   Final action: " .. tostring(entry.action))
		table.insert(lines, "   Reason: " .. tostring(entry.reason))
		table.insert(lines, "   Source rule: " .. tostring(entry.sourceRule))
		if entry.bag and entry.slot then
			table.insert(lines, "   Bag slot: " .. tostring(entry.bag) .. "." .. tostring(entry.slot))
		end
		if (entry.repeatCount or 1) > 1 then
			table.insert(lines, "   Repeated: " .. tostring(entry.repeatCount) .. " times")
		end
		if i < #filtered then table.insert(lines, "") end
	end
	return table.concat(lines, "\n")
end

function _G.AutoDelete_ShowDecisionHistory()
	local text = _G.AutoDelete_BuildDecisionHistoryReport()
	if _G.AutoDelete_ShowReportWindow then
		_G.AutoDelete_ShowReportWindow(text, "Decision History", {
			searchPlaceholder = "Search item, recipe, affix, rule...",
			searchBuilder = function(query)
				return _G.AutoDelete_BuildDecisionHistoryReport(query)
			end,
		})
	else
		print("|cffff8000[AutoDelete]|r " .. text:gsub("\n", "\n|cffff8000[AutoDelete]|r "))
	end
end

-- ============================================================================
-- String Helpers
-- ============================================================================

local function Trim(s)
	-- Parens around the whole expression truncate gsub's multi-return (string
	-- plus substitution count) down to just the string. Without this, calls
	-- like `table.insert(t, Trim(x))` silently pass the count as a third arg
	-- and Lua treats the result as the 3-arg form of table.insert.
	return (string.gsub(string.gsub(tostring(s or ""), "^%s+", ""), "%s+$", ""))
end

function _G.AutoDelete_NormalizeTextKey(s)
	local t = string.lower(Trim(s))
	-- PE can surface affix names with escaped or typographic apostrophes.
	-- Canonicalize before using strings as lookup keys or suffix operands.
	t = string.gsub(t, "\226\128\153", "'")
	t = string.gsub(t, "\226\128\152", "'")
	while string.find(t, "\\'", 1, true) do
		t = string.gsub(t, "\\'", "'")
	end
	return t
end

local function Normalize(s)
	return _G.AutoDelete_NormalizeTextKey(s)
end

local function GetItemIDFromLink(link)
	if not link then return nil end
	return tonumber(string.match(link, "item:(%d+)"))
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

-- ============================================================================
-- Item Set Builders
-- ============================================================================
-- BuildWantedSets parses a Delete or Sell list's text and returns two tables:
-- one keyed by item id, one keyed by lowercased+trimmed item name. The scan
-- loop uses these for O(1) "is this item on the list" lookups.

-- v3.20 (2026-05-23): added an optional cacheKey arg. Each DeleteItems /
-- SellItems / HasPendingDeleteItems call previously re-parsed the delete
-- list AND the keep list (two full O(n) walks per invocation, twice per
-- scan tick). With cacheKey set, the parsed (nameSet, idSet) is memoized
-- per logical list ("delete-list", "keep-list", "sell-list") and only
-- rebuilt when the underlying text changes (string equality check is
-- fast for interned listText strings). Cache lives on _G so its single
-- table isn't a new file-scope local against Lua 5.1's 200-cap.
-- Measured impact: ~3-4 ms saved per DeleteItems call on a list of ~100
-- entries (user perf report 2026-05-23 had DeleteItems peaking at 41.5 ms
-- avg 10.96 ms; this drops both numbers noticeably).
_G.AutoDelete_WSCache = _G.AutoDelete_WSCache or {}

local function BuildWantedSets(listText, cacheKey)
	listText = listText or ""
	if cacheKey then
		local entry = _G.AutoDelete_WSCache[cacheKey]
		if entry and entry.listText == listText then
			return entry.names, entry.ids
		end
	end
	local nameSet, idSet = {}, {}
	for line in string.gmatch(listText, "[^\r\n]+") do
		local raw = Trim(line)
		-- Strip comments
		raw = string.gsub(raw, "%s*#.*$", "")
		raw = Trim(raw)
		-- Match item:ID (lenient - don't require end anchor)
		local itemId = tonumber(string.match(raw, "^item:(%d+)"))
		if itemId then
			idSet[itemId] = true
		elseif raw ~= "" then
			nameSet[Normalize(raw)] = true
		end
	end
	if cacheKey then
		_G.AutoDelete_WSCache[cacheKey] = {
			listText = listText, names = nameSet, ids = idSet,
		}
	end
	return nameSet, idSet
end

local function IsWhitelisted(profile, itemId, itemName)
	local wlText = profile.whitelistText or ""
	if wlText == "" then return false end
	for line in string.gmatch(wlText, "[^\r\n]+") do
		local raw = Trim(line)
		raw = string.gsub(raw, "%s*#.*$", "")
		raw = Trim(raw)
		local wlId = tonumber(string.match(raw, "^item:(%d+)"))
		if wlId and itemId and wlId == itemId then return true end
		if raw ~= "" and itemName and Normalize(raw) == Normalize(itemName) then return true end
	end
	return false
end

-- Fast-path Keep-list check used by hot loops (DeleteItems / SellItems).
-- IsWhitelisted above re-parses the whitelist text from scratch on every
-- call (gmatch + gsub + tonumber + Normalize per line). For a 50-line
-- Keep list and 80 bag slots that's 4000 string ops per pass -- which
-- /del perf identified as the dominant cost in DeleteItems (~25ms avg
-- per call). This helper takes pre-built hash sets (via BuildWantedSets
-- on profile.whitelistText) and does two O(1) lookups instead.
--
-- Build once at the top of a scan:
--   local keepNames, keepIDs = BuildWantedSets(profile.whitelistText)
-- Then inside the loop:
--   if AutoDelete__G.AutoDelete_IsWhitelistedFast(keepIDs, keepNames, itemId, itemName) then ...
--
-- Globalized (via _G) instead of declared `local function` because the
-- main chunk is at Lua 5.1's 200-local cap; adding one more local-scope
-- function would push us past the limit and break the addon at load. The
-- existing helpers AutoDelete_DecideDot / AutoDelete_RefreshOwnedAffixes
-- follow the same pattern for the same reason.
--
-- IsWhitelisted (the slow path) is kept for non-hot callers (secure
-- button candidate selection at /Open/Mill/Prospect/Disenchant) where
-- the call frequency is one-per-keypress, not one-per-slot-per-tick.
function _G.AutoDelete_IsWhitelistedFast(keepIDs, keepNames, itemId, itemName)
	if itemId and keepIDs[itemId] then return true end
	if itemName and keepNames[Normalize(itemName)] then return true end
	return false
end

-- ============================================================================
-- Add Item to List (used by ElvUI buttons and Options panel)
-- ============================================================================

-- Check if `line` already exists on either of the OTHER two lists
-- (delete/sell/whitelist). Returns (hasConflict, conflictingListKey).
local function FindCrossListConflict(profile, targetKey, line)
	local otherKeys
	if targetKey == "listText" then
		otherKeys = { "sellListText", "whitelistText", "keepOneText", "keepStackText" }
	elseif targetKey == "sellListText" then
		otherKeys = { "listText", "whitelistText", "keepOneText", "keepStackText" }
	elseif targetKey == "whitelistText" then
		otherKeys = { "listText", "sellListText", "keepOneText", "keepStackText" }
	elseif targetKey == "keepOneText" then
		otherKeys = { "listText", "sellListText", "whitelistText", "keepStackText" }
	elseif targetKey == "keepStackText" then
		otherKeys = { "listText", "sellListText", "whitelistText", "keepOneText" }
	else
		return false, nil
	end
	for _, k in ipairs(otherKeys) do
		if HasExactLine(profile[k] or "", line) then return true, k end
	end
	return false, nil
end

local function ListLabelForKey(key)
	if key == "listText" then return "Delete" end
	if key == "sellListText" then return "Sell" end
	if key == "whitelistText" then return "Keep" end
	if key == "keepOneText" then return "KeepOne" end
	if key == "keepStackText" then return "KeepStack" end
	return key
end

local function AddItemToList(listKey, itemId)
	local db = GetDB()
	local profile = GetActiveProfile(db)
	local line = "item:" .. tostring(itemId)
	local itemName = GetItemInfo(itemId) or ("Item " .. itemId)

	if HasExactLine(profile[listKey], line) then
		print("|cffff8000[AutoDelete]|r " .. itemName .. " is already in the list")
		return false
	end

	-- Refuse to add if item is on another list; user must remove there first.
	local hasConflict, conflictKey = FindCrossListConflict(profile, listKey, line)
	if hasConflict then
		print("|cffff4444[AutoDelete]|r: Cannot add " .. itemName
			.. " to " .. ListLabelForKey(listKey)
			.. " - already on the " .. ListLabelForKey(conflictKey)
			.. " list. Remove it from there first.")
		return false
	end

	profile[listKey] = AddLineIfMissing(profile[listKey] or "", line)
	GetItemInfo("item:" .. itemId)
	local label
	if listKey == "sellListText" then label = "sell"
	elseif listKey == "whitelistText" then label = "keep"
	elseif listKey == "keepOneText" then label = "KeepOne"
	elseif listKey == "keepStackText" then label = "KeepStack"
	else label = "delete" end
	print("|cffff8000[AutoDelete]|r Added " .. itemName .. " to " .. label .. " list")
	return true
end

local function HandleItemDrop(listKey)
	local cursorType, itemID, itemLink = GetCursorInfo()
	if cursorType ~= "item" then ClearCursor() return end
	local id = (type(itemID) == "number") and itemID or GetItemIDFromLink(itemLink)
	ClearCursor()
	if not id then return end
	if AddItemToList(listKey, id) then
		local panel = _G.AutoDeleteOptionsPanel
		if panel and panel._built and panel:IsVisible() and not (panel._rawBoxHolder and panel._rawBoxHolder:IsShown()) then
			panel:Refresh()
		end
	end
end

-- Remove a single item id from the named list. Used by the row context
-- menu's Remove and Move-to actions. Silent on no-op (item wasn't on the
-- list anyway). Returns true if a line was actually removed.
local function RemoveItemFromList(listKey, itemId)
	if not itemId then return false end
	local db = GetDB()
	local profile = GetActiveProfile(db)
	local line = "item:" .. tostring(itemId)
	local current = profile[listKey] or ""
	if not HasExactLine(current, line) then return false end
	-- Rebuild the list text without the matching line.
	local kept = {}
	for entry in string.gmatch(current, "[^\r\n]+") do
		if entry ~= line then table.insert(kept, entry) end
	end
	profile[listKey] = table.concat(kept, "\n") .. (#kept > 0 and "\n" or "")
	return true
end

-- Globals for the row context menu in Options.lua to call.
_G.AutoDelete_AddItemToList = AddItemToList
_G.AutoDelete_RemoveItemFromList = RemoveItemFromList
function _G.AutoDelete_RemoveItemFromAllLists(itemId)
	local removed = {}
	local keys = {
		{ key = "listText", label = "Delete" },
		{ key = "sellListText", label = "Sell" },
		{ key = "whitelistText", label = "Keep" },
		{ key = "keepOneText", label = "KeepOne" },
		{ key = "keepStackText", label = "KeepStack" },
	}
	for _, itemList in ipairs(keys) do
		if RemoveItemFromList(itemList.key, itemId) then
			table.insert(removed, itemList.label)
		end
	end
	return #removed, table.concat(removed, ", ")
end

-- Global functions for ElvUI buttons - always target the correct list
function _G.AutoDelete_AddToDeleteList() HandleItemDrop("listText") end
function _G.AutoDelete_AddToSellList() HandleItemDrop("sellListText") end
function _G.AutoDelete_AddToKeepList() HandleItemDrop("whitelistText") end
function _G.AutoDelete_AddToKeepStackList() HandleItemDrop("keepStackText") end

-- Opens the AutoDelete options panel and switches the Delete/Sell/Keep
-- list tab to the requested mode. Used by the ElvUI bag buttons so a
-- right-click on Delete jumps straight to the Delete list, etc.
-- Accepts: "delete", "sell", "whitelist".
function _G.AutoDelete_OpenPanelToList(mode)
	local panel = _G.AutoDeleteOptionsPanel
	if not panel then return end
	if not panel:IsShown() then panel:Show() end
	-- The Options.lua panel exposes a SwitchListMode helper for this.
	if panel.SwitchListMode then panel:SwitchListMode(mode) end
end

-- ============================================================================
-- Manual Sell Tracking (hooksecurefunc UseContainerItem + bag snapshot)
-- ============================================================================
-- Blizzard's merchant UI sells an item by calling UseContainerItem(bag, slot)
-- when you right-click a bag item while the merchant window is open. We track
-- those manual sells so the gold/items session counters work.
--
-- IMPORTANT: We use hooksecurefunc, NOT a global override. Replacing
-- UseContainerItem globally (UseContainerItem = TrackedUseContainerItem)
-- breaks the secure-action call path on 3.3.5 because UseContainerItem is
-- protected for items that trigger spells/casts (Hearthstone, potions,
-- mounts, scrolls, food, anything castable). Blizzard's secure dispatch
-- silently rejects calls to a non-Blizzard function, so right-click on those
-- items stops working entirely. hooksecurefunc preserves the original.
--
-- Implementation: hooksecurefunc fires AFTER Blizzard's handler, by which
-- time the bag slot has already been emptied or shifted. So we can't read
-- the item from the slot post-call. Instead we keep a snapshot of bag
-- contents (link + count per slot) that we refresh on:
--   * MERCHANT_SHOW (initial full snapshot when vendor opens)
--   * After every hooked UseContainerItem call (refresh just that slot)
-- When the hook fires, we look up (bag, slot) in the snapshot to know what
-- was just sold.
--
-- The autoDeleteSelling flag keeps our own SellItems() calls from being
-- double-counted - those record the stat directly, not via this hook.

local autoDeleteSelling = false
local merchantBagSnapshot = {}

-- Merchant-state flag for the auto-open feature. UseContainerItem at a
-- vendor SELLS the item instead of opening it, so auto-open must never
-- fire while a vendor is or has just been open. This flag is set at
-- MERCHANT_SHOW and cleared on a delay after MERCHANT_CLOSED so that
-- trailing BAG_UPDATE events from the sell loop's tail don't slip
-- through and trigger an auto-open attempt on a freshly-emptied slot.
local merchantOpen = false
local MERCHANT_CLOSE_GRACE = 1.5

local function SnapshotAllBags()
	merchantBagSnapshot = {}
	for bag = 0, 4 do
		local n = GetContainerNumSlots(bag) or 0
		for slot = 1, n do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local _, count = GetContainerItemInfo(bag, slot)
				merchantBagSnapshot[bag .. ":" .. slot] = {
					link = link, count = count or 1,
				}
			end
		end
	end
end

local function RefreshSnapshotSlot(bag, slot)
	local key = bag .. ":" .. slot
	local link = GetContainerItemLink(bag, slot)
	if link then
		local _, count = GetContainerItemInfo(bag, slot)
		merchantBagSnapshot[key] = { link = link, count = count or 1 }
	else
		merchantBagSnapshot[key] = nil
	end
end

hooksecurefunc("UseContainerItem", function(bag, slot)
	-- Skip our own SellItems() path - it records BumpStat directly.
	if autoDeleteSelling then return end
	if not bag or not slot then return end
	if not (MerchantFrame and MerchantFrame:IsShown()) then return end

	local key = bag .. ":" .. slot
	local snap = merchantBagSnapshot[key]
	if snap and snap.link then
		local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(snap.link)
		if sellPrice and sellPrice > 0 then
			local copper = sellPrice * (snap.count or 1)
			BumpStat("itemsSold", 1)
			BumpStat("goldEarned", copper)
		end
	end

	-- Refresh the snapshot for this slot after the sell completes. Use a
	-- short delay so the bag has time to update.
	AfterDelay(0.1, function() RefreshSnapshotSlot(bag, slot) end)
end)

-- ============================================================================
-- Profile Management (copy settings from another character)
-- ============================================================================
-- Every character has its own profile keyed in db.profiles. The Profiles tab
-- in the UI exposes a "copy from another character" action: pick a source
-- character, confirm, and their full profile (lists + toggles + everything)
-- gets deep-copied onto the current character's profile key.
--
-- This is intentionally NOT a named-profile system - just a one-way copy
-- across alts. Tracking stats are NOT copied (those are per-character data,
-- not settings).

-- Deep copy a table (handles nested tables). Values that aren't tables are
-- copied by value - functions, userdata, etc. get reference-copied but we
-- don't store those in profiles anyway.
local function DeepCopyTable(src)
	if type(src) ~= "table" then return src end
	local out = {}
	for k, v in pairs(src) do
		if type(v) == "table" then
			out[k] = DeepCopyTable(v)
		else
			out[k] = v
		end
	end
	return out
end

-- Returns an array of character names that have profiles in the DB,
-- EXCLUDING the current character. Sorted alphabetically for stable UI.
local function GetOtherCharacterNames()
	local db = GetDB()
	local currentKey = GetCharKey() or "Default"
	local out = {}
	if db and db.profiles then
		for name in pairs(db.profiles) do
			if name ~= currentKey then
				table.insert(out, name)
			end
		end
	end
	table.sort(out)
	return out
end

-- Returns ALL character profile names (current included), alphabetically sorted.
-- Used by the Profiles tab dropdown which shows every profile so the user can
-- even delete the current character's (which then re-initializes to defaults).
local function GetAllCharacterNames()
	local db = GetDB()
	local out = {}
	if db and db.profiles then
		for name in pairs(db.profiles) do
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

-- Copy the full profile from `sourceCharKey` onto the current character.
-- Overwrites everything in the current profile. Returns true on success,
-- false + reason string on failure.
local function CopyProfileFromCharacter(sourceCharKey)
	if not sourceCharKey or sourceCharKey == "" then
		return false, "no source specified"
	end
	local db = GetDB()
	local currentKey = GetCharKey() or "Default"

	if sourceCharKey == currentKey then
		return false, "source is current character"
	end
	if not db.profiles[sourceCharKey] then
		return false, "source profile not found"
	end

	-- Deep copy so no shared table references between characters.
	local copied = DeepCopyTable(db.profiles[sourceCharKey])
	db.profiles[currentKey] = copied
	db.chars[currentKey] = currentKey

	-- Keep migrations applied in case the source had pre-migration fields.
	EnsureProfileFields(db.profiles[currentKey])

	-- Refresh the cached profile immediately so active toggles reflect the
	-- new data without waiting for a bag event.
	if RefreshCachedProfile then RefreshCachedProfile() end
	return true
end

-- Delete a character's saved profile. If the target is the current character,
-- their profile is cleared and re-initialized to defaults on next access.
-- Otherwise the entry is removed entirely from the DB.
local function DeleteProfile(targetCharKey)
	if not targetCharKey or targetCharKey == "" then
		return false, "no target specified"
	end
	local db = GetDB()
	local currentKey = GetCharKey() or "Default"

	if not db.profiles[targetCharKey] then
		return false, "profile not found"
	end

	if targetCharKey == currentKey then
		-- Current character: reset to defaults (we can't remove the entry
		-- entirely because the addon immediately re-creates it on next access).
		db.profiles[currentKey] = NewProfile()
		db.chars[currentKey] = currentKey
	else
		-- Other character: fully remove.
		db.profiles[targetCharKey] = nil
		if db.chars then
			-- Also clear any chars-alias pointing at the deleted profile.
			for char, key in pairs(db.chars) do
				if key == targetCharKey then db.chars[char] = nil end
			end
		end
	end

	if RefreshCachedProfile then RefreshCachedProfile() end
	return true
end

-- Reset the current character's profile to all defaults. Does not touch other
-- characters' profiles.
local function ResetCurrentProfile()
	local db = GetDB()
	local currentKey = GetCharKey() or "Default"
	db.profiles[currentKey] = NewProfile()
	db.chars[currentKey] = currentKey
	if RefreshCachedProfile then RefreshCachedProfile() end
	return true
end

-- Clear one list or all item lists on the current character's profile.
-- `target` is "Delete" / "Sell" / "Keep" / "KeepOne" / "KeepStack" / "All".
-- Returns true, cleared-count
-- on success, or false, reason on failure.
local function ClearListOnCurrent(target)
	local db = GetDB()
	local profile = GetActiveProfile(db)
	if not profile then return false, "no active profile" end

	local function CountEntries(listText)
		local n = 0
		for line in string.gmatch(listText or "", "[^\r\n]+") do
			local trimmed = Trim(line)
			if trimmed ~= "" and not string.match(trimmed, "^#") then n = n + 1 end
		end
		return n
	end

	local clearedCount = 0
	if target == "Delete" then
		clearedCount = CountEntries(profile.listText)
		profile.listText = ""
	elseif target == "Sell" then
		clearedCount = CountEntries(profile.sellListText)
		profile.sellListText = ""
	elseif target == "Keep" then
		clearedCount = CountEntries(profile.whitelistText)
		profile.whitelistText = ""
	elseif target == "KeepOne" then
		clearedCount = CountEntries(profile.keepOneText)
		profile.keepOneText = ""
	elseif target == "KeepStack" then
		clearedCount = CountEntries(profile.keepStackText)
		profile.keepStackText = ""
	elseif target == "All" then
		clearedCount = CountEntries(profile.listText)
			+ CountEntries(profile.sellListText)
			+ CountEntries(profile.whitelistText)
			+ CountEntries(profile.keepOneText)
			+ CountEntries(profile.keepStackText)
		profile.listText = ""
		profile.sellListText = ""
		profile.whitelistText = ""
		profile.keepOneText = ""
		profile.keepStackText = ""
	else
		return false, "invalid target"
	end

	if RefreshCachedProfile then RefreshCachedProfile() end
	return true, clearedCount
end

-- Scan the Delete and Sell lists. For each entry that resolves to a real
-- item (item:ID), check its quality via GetItemInfo; if quality == 0 (gray
-- junk), remove that entry from the list. Entries that can't be resolved
-- (cache miss, or plain-name entries we can't identify) are preserved.
-- Returns true, { deleteRemoved=N, sellRemoved=N, uncached=N }.
local function RemoveJunkFromLists()
	local db = GetDB()
	local profile = GetActiveProfile(db)
	if not profile then return false, "no active profile" end

	local uncachedCount = 0

	local function CleanList(listText)
		local kept = {}
		local removed = 0
		for line in string.gmatch(listText or "", "[^\r\n]+") do
			local trimmed = Trim(line)
			local keep = true
			if trimmed ~= "" and not string.match(trimmed, "^#") then
				-- Try to pull an item id from "item:NNN" form
				local id = tonumber(string.match(trimmed, "^item:(%d+)"))
				if id then
					local name, _, quality = GetItemInfo("item:" .. id)
					if name then
						-- Got cached info. Quality 0 = gray/junk.
						if quality == 0 then
							keep = false
							removed = removed + 1
						end
					else
						-- Item not in client cache. Skip cleanup for this entry
						-- rather than guessing, and count it so we can tell the user.
						uncachedCount = uncachedCount + 1
					end
				end
				-- Plain-name entries (no item:ID) we can't identify reliably
				-- without a bag scan; leave them alone.
			end
			if keep then table.insert(kept, trimmed) end
		end
		local rebuilt = table.concat(kept, "\n")
		if #kept > 0 then rebuilt = rebuilt .. "\n" end
		return rebuilt, removed
	end

	local newDelete, delRemoved   = CleanList(profile.listText)
	local newSell,   sellRemoved  = CleanList(profile.sellListText)
	profile.listText     = newDelete
	profile.sellListText = newSell

	if RefreshCachedProfile then RefreshCachedProfile() end
	return true, {
		deleteRemoved = delRemoved,
		sellRemoved   = sellRemoved,
		uncached      = uncachedCount,
	}
end

-- Scan ONLY the Delete list. Remove entries whose item has a vendor sell
-- price > 0 (i.e. items that could be sold instead of deleted). Entries
-- that can't be resolved (cache miss, or plain-name entries) are preserved.
-- Returns true, { removed=N, uncached=N } on success.
local function RemoveSellableFromDeleteList()
	local db = GetDB()
	local profile = GetActiveProfile(db)
	if not profile then return false, "no active profile" end

	local uncachedCount = 0
	local kept = {}
	local removed = 0
	for line in string.gmatch(profile.listText or "", "[^\r\n]+") do
		local trimmed = Trim(line)
		local keep = true
		if trimmed ~= "" and not string.match(trimmed, "^#") then
			local id = tonumber(string.match(trimmed, "^item:(%d+)"))
			if id then
				-- GetItemInfo returns: name, link, quality, iLevel, reqLevel,
				-- type, subType, stackCount, equipLoc, texture, sellPrice
				local name, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo("item:" .. id)
				if name then
					if sellPrice and sellPrice > 0 then
						keep = false
						removed = removed + 1
					end
				else
					uncachedCount = uncachedCount + 1
				end
			end
		end
		if keep then table.insert(kept, trimmed) end
	end

	local rebuilt = table.concat(kept, "\n")
	if #kept > 0 then rebuilt = rebuilt .. "\n" end
	profile.listText = rebuilt

	if RefreshCachedProfile then RefreshCachedProfile() end
	return true, { removed = removed, uncached = uncachedCount }
end

-- Exposed API for Options.lua.
-- Scan Delete + Sell + Keep and remove any entry whose
-- item's GetItemInfo 7th return (localized itemSubType) matches the target.
-- KeepOne and KeepStack are intentionally excluded; they are not filter-cleanup lists.
-- Used by the "Remove Patterns by Profession" UI to prune recipes/patterns/
-- plans/schematics/formulas/designs/techniques/manuals from the user's lists.
-- Plain-name entries (no item:ID) are preserved -- we can't identify them
-- without a bag scan and the user typed them deliberately. Uncached items
-- are also preserved and reported in the summary.
local function RemovePatternsBySubtype(targetSubtype)
	local db = GetDB()
	local profile = GetActiveProfile(db)
	if not profile then return false, "no active profile" end
	if not targetSubtype or targetSubtype == "" then
		return false, "no subtype specified"
	end

	local uncachedCount = 0

	local function CleanList(listText)
		local kept = {}
		local removed = 0
		for line in string.gmatch(listText or "", "[^\r\n]+") do
			local trimmed = Trim(line)
			local keep = true
			if trimmed ~= "" and not string.match(trimmed, "^#") then
				local id = tonumber(string.match(trimmed, "^item:(%d+)"))
				if id then
					-- 7th return = localized itemSubType ("Pattern", "Recipe",
					-- "Plans", "Schematic", "Formula", "Design", "Technique",
					-- "Manual"). On non-enUS clients the strings differ; the
					-- caller must pass the locale-correct token. TODO localize.
					local name, _, _, _, _, _, itemSubType = GetItemInfo("item:" .. id)
					if name then
						if itemSubType == targetSubtype then
							keep = false
							removed = removed + 1
						end
					else
						uncachedCount = uncachedCount + 1
					end
				end
			end
			if keep then table.insert(kept, trimmed) end
		end
		local rebuilt = table.concat(kept, "\n")
		if #kept > 0 then rebuilt = rebuilt .. "\n" end
		return rebuilt, removed
	end

	local newDelete, delRemoved  = CleanList(profile.listText)
	local newSell,   sellRemoved = CleanList(profile.sellListText)
	local newKeep,   keepRemoved = CleanList(profile.whitelistText)
	profile.listText      = newDelete
	profile.sellListText  = newSell
	profile.whitelistText = newKeep

	if RefreshCachedProfile then RefreshCachedProfile() end
	return true, {
		subtype       = targetSubtype,
		deleteRemoved = delRemoved,
		sellRemoved   = sellRemoved,
		keepRemoved   = keepRemoved,
		uncached      = uncachedCount,
	}
end

_G.AutoDelete_Profiles = {
	GetOtherCharacters = GetOtherCharacterNames,
	GetAllCharacters = GetAllCharacterNames,
	GetCurrentCharacter = function() return GetCharKey() or "Default" end,
	CopyFrom = CopyProfileFromCharacter,
	DeleteProfile = DeleteProfile,
	ResetCurrent = ResetCurrentProfile,
	ClearList = ClearListOnCurrent,
	RemoveJunk = RemoveJunkFromLists,
	RemoveSellableFromDelete = RemoveSellableFromDeleteList,
	RemovePatternsBySubtype = RemovePatternsBySubtype,
}

-- ============================================================================
-- Deletion Scanner
-- ============================================================================
-- Periodic + event-driven scanner that walks the player's bags and either
-- deletes (Delete list, Auto-Delete Junk, Auto-Delete Common) or - when at
-- a vendor - sells (handled by SellItems below). Quest items are hard-
-- exempt: they short-circuit before any rule evaluation.

local nextScanAt = 0
local periodicInterval = 2.0
local nextPeriodicAt = 0
local scanRequested = false

local function RequestScan() scanRequested = true end

-- Items deleted per scan tick. Capped here, not by total bag walk -- the
-- Walk-time enqueue cap per delete scan. The queue drain is the real throttle
-- (see _G.AutoDelete_DeleteQueue.DELAY); this cap just bounds how much work one
-- scan does before yielding back to the frame loop.
local DELETE_BATCH_SIZE = 32

-- v3.20 (2026-05-23): Queue-throttled deletes. Before the refactor, DeleteItems
-- executed many PickupContainerItem + DeleteCursorItem pairs back-to-back in a
-- single scanner tick. With the old inline path, the user's perf report showed
-- user's perf report showed a 41.5ms peak (~five dropped frames at
-- 60fps) -- visible as a chug when a loot burst triggered the scan.
--
-- New model: DeleteItems WALKS the bags once and ENQUEUES every
-- candidate it finds. A separate drain function (called from the
-- scanner OnUpdate) pops one item per DELAY interval and executes
-- the PickupContainerItem + DeleteCursorItem pair. Per-API cost
-- (~4-6ms) is now spread across multiple frames -- no single frame
-- exceeds budget, no chug.
--
-- Throughput tradeoff: steady-state at 90ms is ~11
-- items/sec. For a typical scav burst of 20-30 items this is the
-- difference between a 1.5s clean-up and a 2-3s clean-up -- well
-- under the 5s BAG_QUIESCENCE_MAX_S anti-starvation cap.
--
-- Drain re-validates the slot link before executing: between walk
-- and drain the user may have moved/used/swapped the item. Stale
-- entries are silently dropped (counter: DeleteItems/queue-stale).
-- Keep-list and Affix-Protection checks happen at WALK time, so
-- the drain trusts the queue.
_G.AutoDelete_DeleteQueue = _G.AutoDelete_DeleteQueue or {
	items  = {},
	lastAt = 0,
	DELAY  = 0.09,  -- 90ms; slight speed nudge, still one pop per tick
}

local function PlanKeepOneSlotAction(totalUnits, slotCount)
	totalUnits = tonumber(totalUnits) or 0
	slotCount = tonumber(slotCount) or 0
	if totalUnits <= 1 or slotCount <= 0 then
		return "keep", 0
	end
	local maxDeletable = totalUnits - 1
	if slotCount <= maxDeletable then
		return "delete-slot", slotCount
	end
	return "split-delete", maxDeletable
end

function _G.AutoDelete_CountBagUnitsByItemId(itemId)
	if not itemId then return 0 end
	local total = 0
	for bag = 0, 4 do
		for slot = 1, GetContainerNumSlots(bag) do
			local _, count, locked, _, _, _, link = GetContainerItemInfo(bag, slot)
			if link and not locked and GetItemIDFromLink(link) == itemId then
				total = total + (count or 1)
			end
		end
	end
	return total
end

function _G.AutoDelete_GetKeepStackSlotChoice(itemId)
	if not itemId then return 0, nil, nil end
	local stackCount, keepBag, keepSlot, keepCount = 0, nil, nil, -1
	for bag = 0, 4 do
		for slot = 1, GetContainerNumSlots(bag) do
			local _, count, locked, _, _, _, link = GetContainerItemInfo(bag, slot)
			if link and not locked and GetItemIDFromLink(link) == itemId then
				stackCount = stackCount + 1
				count = count or 1
				if count > keepCount then
					keepCount = count
					keepBag = bag
					keepSlot = slot
				end
			end
		end
	end
	return stackCount, keepBag, keepSlot
end

-- Cosmetic slots (shirts + tabards). Items in these slots are NEVER touched
-- by the automatic rules (Auto-Delete Junk, Auto-Delete Common, Auto-Sell
-- Greens, the BoE/BoP/BoE Weapons sell categories). They must be explicitly
-- added to the Delete or Sell list to be removed. Used by DeleteItems.
local COSMETIC_SLOTS = {
	INVTYPE_BODY = true,    -- shirts
	INVTYPE_TABARD = true,  -- tabards
}
local function IsCosmeticSlot(itemLink)
	if not itemLink then return false end
	local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
	return equipLoc and COSMETIC_SLOTS[equipLoc] or false
end

-- Forward declaration. IsAffixProtected is assigned its function body later
-- (after the BoE scan tooltip is set up, since HasAffix needs that frame).
-- DeleteItems below captures this name as an upvalue; without the forward
-- declaration the call inside DeleteItems would resolve to a nil global,
-- because `local function` is not hoisted in Lua.
local IsAffixProtected

-- Forward declaration for ComputeTotalFreeSlots: it's defined later (near
-- the companion watcher) but the BAG_UPDATE handler below uses it for the
-- bag-space warning check. Same hoisting issue as IsAffixProtected above.
local ComputeTotalFreeSlots

-- (bag-space chat warning removed v3.20; bagSpaceLastWarnAt file-local
-- deleted. Goblin Merchant arrival serves as the user-visible "bags
-- filling" indicator; the chat print was redundant and spammed during
-- oscillation around the threshold. Threshold field 'bagSpaceWarnThreshold'
-- is now read only by GetGoblinBagThreshold for summon timing.)

local function DeleteItems()
	local _p = AutoDelete_PerfBegin("DeleteItems")
	if CursorHasItem() then AutoDelete_PerfEnd("DeleteItems", _p); return end
	-- v3.20: Queue-throttled. If the previous walk's queue is still
	-- draining, skip this walk -- otherwise we'd re-enqueue the same
	-- slots and risk double-deletes once the drain catches up. The
	-- drain re-runs every OnUpdate frame and pops at 90ms cadence, so
	-- skipping here just defers until the queue is empty.
	if #_G.AutoDelete_DeleteQueue.items > 0 then
		-- v3.20 spike debug: count early-returns separately so the
		-- per-frame counter shows queue activity vs full-walk activity.
		if _G.AutoDelete_SpikeDebug then
			local c = _G.AutoDelete_SpikeCounters
			local sess = _G.AutoDelete_SpikeSession
			c.dEarly    = (c.dEarly or 0) + 1
			sess.dEarly = (sess.dEarly or 0) + 1
		end
		AutoDelete_PerfEnd("DeleteItems", _p)
		return
	end
	-- Open a "self-update" suppression window so the BAG_UPDATE events
	-- caused by our own PickupContainerItem + DeleteCursorItem calls
	-- (now fired by the drain, not inline) don't restart the burst-
	-- quiescence wait in the scanner. Without this, after every drain
	-- pop the scanner would see "BAG_UPDATE arrived <1s ago" and wait
	-- another full second -- turning the queue drain into a crawl.
	-- 0.5s window covers the typical 1-2 frame delay between API call
	-- and BAG_UPDATE arrival; the drain re-arms it on every pop.
	_G.AutoDelete_SelfBagUpdateUntil = GetTime() + 0.5
	local db = GetDB()
	local profile = GetActiveProfile(db)
	if not profile.enabled then
		if _G.AutoDelete_DebugSell then
			-- Print at most once per scan attempt to avoid spam.
			if not _G._AutoDelete_DebugDelGateLogged then
				print("|cffff8000[AutoDelete DEBUG]|r delete scan SKIPPED: master Enable is OFF (profile.enabled=false). Turn it on in the General tab.")
				_G._AutoDelete_DebugDelGateLogged = true
			end
		end
		AutoDelete_PerfEnd("DeleteItems", _p)
		return
	end
	_G._AutoDelete_DebugDelGateLogged = false

	-- v3.20 perf instrumentation: separate parse / walk / api sub-phases
	-- so /del perf report can pinpoint where the per-call cost goes.
	-- Pre-cached BuildWantedSets (added 2026-05-23) should make "parse"
	-- near-zero on a 2nd+ call against the same list text.
	local _pParse = AutoDelete_PerfBegin("DeleteItems/parse")
	local wantedNames, wantedIDs = BuildWantedSets(profile.listText, "delete-list")
	local hasWanted = next(wantedNames) or next(wantedIDs)
	local keepOneIDs = select(2, BuildWantedSets(profile.keepOneText, "keepone-list"))
	local hasKeepOne = next(keepOneIDs) ~= nil
	local keepStackIDs = select(2, BuildWantedSets(profile.keepStackText, "keepstack-list"))
	local hasKeepStack = next(keepStackIDs) ~= nil
	-- Pre-built Keep-list hash sets so the inner loop doesn't re-parse
	-- the whitelist text per-item. See IsWhitelistedFast for the perf
	-- rationale (the slow path was the dominant cost in DeleteItems).
	local keepNames, keepIDs = BuildWantedSets(profile.whitelistText, "keep-list")
	local singleAffixPlan = _G.AutoDelete_BuildSingleAffixPlan(profile, keepIDs, keepNames)
	AutoDelete_PerfEnd("DeleteItems/parse", _pParse)
	-- Tri-state quality filter: only "delete" is a delete-path trigger.
	-- "sell" is handled in SellItems; "off" is a no-op for both paths.
	local doGray = (profile.qualityActionJunk == "delete")
	local doCommon = (profile.qualityActionCommon == "delete")
	-- v3.20 (post-spec change 2026-05-23): Greens can now be auto-deleted
	-- too, but ONLY for equippable gear (same gate as doCommon). Reagents,
	-- consumables, bags, and quest items stay safe.
	local doGreens = (profile.qualityActionGreens == "delete")

	if not hasWanted and not hasKeepOne and not hasKeepStack and not doGray and not doCommon and not doGreens then
		if _G.AutoDelete_DebugSell and not _G._AutoDelete_DebugDelEmptyLogged then
			print("|cffff8000[AutoDelete DEBUG]|r delete scan: no work - Delete/KeepOne/KeepStack lists empty AND Junk/Common/Greens quality filters not in delete mode.")
			_G._AutoDelete_DebugDelEmptyLogged = true
		end
		AutoDelete_PerfEnd("DeleteItems", _p)
		return
	end
	_G._AutoDelete_DebugDelEmptyLogged = false

	local enqueued = 0
	local Q = _G.AutoDelete_DeleteQueue
	local keepOneTotals = {}

	-- v3.20 perf instrumentation: time the whole bag-walk + per-item
	-- decision pass as "DeleteItems/loop". Per-API cost (now paid by
	-- the drain, not this walk) is recorded as "DeleteItems/api-delete"
	-- in AutoDelete_DrainDeleteQueue. So the addon-side walk cost
	-- IS DeleteItems/loop; api-delete is the drain's per-pop cost.
	-- Slot/item counters give the user a sense of how much work the walk
	-- did (slots-walked is per-non-empty-slot, separate counters for
	-- enqueue / keep-skip / affix-skip outcomes; items-deleted is
	-- bumped by the drain when the API call actually executes).
	local _pLoop = AutoDelete_PerfBegin("DeleteItems/loop")
	-- v3.20 spike debug: count this as a full DeleteItems walk (vs early-return).
	if _G.AutoDelete_SpikeDebug then
		local c = _G.AutoDelete_SpikeCounters
		local sess = _G.AutoDelete_SpikeSession
		c.dWalk    = (c.dWalk or 0) + 1
		sess.dWalk = (sess.dWalk or 0) + 1
	end

	for bag = 0, 4 do
		for slot = 1, GetContainerNumSlots(bag) do
			if enqueued >= DELETE_BATCH_SIZE then
				AutoDelete_PerfEnd("DeleteItems/loop", _pLoop)
				-- v3.20 Goblin defer: stamp walk completion + enqueue count
				-- on the batch-full early-return path too. Goblin logic
				-- uses these to decide if the pipeline has had a chance
				-- to scan since bags went below threshold.
				_G.AutoDelete_LastDeleteWalkAt       = GetTime()
				_G.AutoDelete_LastDeleteWalkEnqueued = enqueued
				AutoDelete_PerfEnd("DeleteItems", _p)
				return
			end
			local _, itemCount, locked, _, _, _, itemLink = GetContainerItemInfo(bag, slot)
			if itemLink and not locked then
				AutoDelete_PerfCount("DeleteItems/slots-walked", 1)
				-- v3.20 spike debug: count per-frame slots-touched by AutoDelete's
				-- own walk loops (separate from updSlot, which counts external
				-- bag-repaint hook fires).
				if _G.AutoDelete_SpikeDebug then
					local _sc = _G.AutoDelete_SpikeCounters
					local _ss = _G.AutoDelete_SpikeSession
					_sc.slotsWalked = (_sc.slotsWalked or 0) + 1
					_ss.slotsWalked = (_ss.slotsWalked or 0) + 1
				end
				-- 6th return = itemType. Quest items (itemType "Quest") are
				-- normally protected from auto-rules - but the Delete list is
				-- explicit user intent and overrides quest protection. Auto
				-- rules (autoGray, autoDeleteCommon) still respect it.
				local itemName, _, itemQuality, _, _, itemClass, itemSubType = GetItemInfo(itemLink)
				local isQuestItem = (itemClass == "Quest")
				local itemId = GetItemIDFromLink(itemLink)
				local shouldDelete = false
				local onDeleteList = false
				local onKeepOneList = false
				local onKeepStackList = false
				local deleteSourceRule = nil
				local keepOneUnitsToDelete = nil
				local singleAffixExtra = false
				local singleAffixKey = nil
				local singleAffixKept = false
				local singleAffixSlot = nil

				-- Check KeepOne FIRST. It is explicit user intent to delete
				-- extras while leaving exactly one unit. Runtime only accepts
				-- item-ID entries; name-only KeepOne lines are ignored so
				-- same-name/different-ID traps cannot delete the wrong item.
				if hasKeepOne and itemId and keepOneIDs[itemId] then
					onKeepOneList = true
					local total = keepOneTotals[itemId]
					if total == nil then
						total = _G.AutoDelete_CountBagUnitsByItemId(itemId)
					end
					local action, amount = PlanKeepOneSlotAction(total, itemCount or 1)
					if action ~= "keep" and amount > 0 then
						shouldDelete = true
						deleteSourceRule = "KeepOne"
						keepOneUnitsToDelete = amount
						keepOneTotals[itemId] = total - amount
					else
						keepOneTotals[itemId] = total
						if _G.AutoDelete_RecordDecision then
							_G.AutoDelete_RecordDecision({
								itemName = itemName,
								itemId = itemId,
								action = "kept",
								reason = "KeepOne kept final unit",
								sourceRule = "KeepOne",
								bag = bag,
								slot = slot,
							})
						end
					end
				end

				-- Check KeepStack next. It preserves one bag stack for the item
				-- and removes additional stacks. Runtime only accepts item-ID
				-- entries for the same same-name safety reason as KeepOne.
				if not shouldDelete and hasKeepStack and itemId and keepStackIDs[itemId] then
					onKeepStackList = true
					local stackCount, keepBag, keepSlot = _G.AutoDelete_GetKeepStackSlotChoice(itemId)
					if stackCount > 1 and (bag ~= keepBag or slot ~= keepSlot) then
						shouldDelete = true
						deleteSourceRule = "KeepStack"
					elseif _G.AutoDelete_RecordDecision then
						_G.AutoDelete_RecordDecision({
							itemName = itemName,
							itemId = itemId,
							action = "kept",
							reason = "KeepStack kept one stack",
							sourceRule = "KeepStack",
							bag = bag,
							slot = slot,
						})
					end
				end

				-- Check delete list next. If listed, user wants it gone
				-- regardless of quest type. KeepOne/KeepStack are mutually exclusive
				-- and wins here if legacy/manual data overlaps.
				if hasWanted then
					if itemId and wantedIDs[itemId] then onDeleteList = true end
					if not onDeleteList and itemName and wantedNames[Normalize(itemName)] then onDeleteList = true end
				end

				if not shouldDelete and onDeleteList then
					shouldDelete = true
					deleteSourceRule = "Delete list"
				end

				if singleAffixPlan then
					singleAffixSlot = singleAffixPlan.slots[bag .. ":" .. slot]
					if singleAffixSlot then
						singleAffixExtra = singleAffixSlot.extra == true
						singleAffixKey = singleAffixSlot.affixKey
						singleAffixKept = not singleAffixExtra
						if singleAffixKept and not shouldDelete and _G.AutoDelete_RecordDecision then
							_G.AutoDelete_RecordDecision({
								itemName = itemName,
								itemId = itemId,
								action = "kept",
								reason = "KeepOne Missing Affix protected missing-affix item",
								sourceRule = "KeepOne Missing Affix",
								affixName = singleAffixSlot.affixKey,
								bag = bag,
								slot = slot,
							})
						end
					end
				end

				if singleAffixKept then
					-- The selected keeper is protected; duplicate extras fall
					-- through to the normal Delete/Sell rule checks.
				elseif not shouldDelete and not isQuestItem then
					-- Auto rules: only run when item is NOT on Delete list AND
					-- NOT a quest item. Quest protection still applies here.

					-- Check gray auto-delete (quality 0 = Poor/gray).
					-- Shirts and tabards are always protected from auto-gray even
					-- if they somehow came through as gray quality. Put them on
					-- the Delete list explicitly if you want them gone.
					if doGray and itemQuality and itemQuality == 0
						and not IsCosmeticSlot(itemLink) then
						shouldDelete = true
						deleteSourceRule = "Auto Actions: Junk delete"
					end

					-- Check Common (white) auto-delete. Only deletes equippable
					-- gear so reagents/consumables/keys are safe. Cosmetic slots
					-- (shirts/tabards) are also protected.
					if not shouldDelete and doCommon and itemQuality and itemQuality == 1
						and not IsCosmeticSlot(itemLink) then
						-- Only equippable gear (must have an equipSlot).
						local _, _, _, _, _, _, _, _, equipSlot = GetItemInfo(itemLink)
						if equipSlot and equipSlot ~= "" and equipSlot ~= "INVTYPE_BAG" then
							shouldDelete = true
							deleteSourceRule = "Auto Actions: Common gear delete"
						end
					end

					-- v3.20: Check Greens (uncommon, quality 2) auto-delete.
					-- Mirrors the Common branch: only equippable gear, never
					-- bags or cosmetic slots. Reagents/consumables are safe
					-- because they have no equipSlot. Spec: 2026-05-23, user
					-- explicitly asked for Greens to support Delete again
					-- (was Sell-only earlier this cycle).
					if not shouldDelete and doGreens and itemQuality and itemQuality == 2
						and not IsCosmeticSlot(itemLink) then
						local _, _, _, _, _, _, _, _, equipSlot = GetItemInfo(itemLink)
						if equipSlot and equipSlot ~= "" and equipSlot ~= "INVTYPE_BAG" then
							shouldDelete = true
							deleteSourceRule = "Auto Actions: Green gear delete"
						end
					end
				end

				-- Execute the delete. Keep list always overrides - even Delete
				-- list entries can't bypass it (Keep is the safety net of
				-- last resort). Affix Protection is the second safety net. Uses
				-- IsWhitelistedFast against pre-built keepNames/keepIDs to
				-- avoid the per-item re-parse of the entire whitelist text.
				--
				-- v3.20 perf: split the gating check so we can count
				-- skipped-by-keep vs skipped-by-affix separately. Same
				-- semantic outcome as the single combined `if`, just
				-- with diagnostic counters.
				if shouldDelete then
					local keepBlocked = _G.AutoDelete_IsWhitelistedFast(keepIDs, keepNames, itemId, itemName)
					local missingAffixBlocked = false
					local missingAffixState = nil
					if not keepBlocked then
						missingAffixBlocked, missingAffixState = _G.AutoDelete_IsMissingAffixHardStop(profile, bag, slot, itemLink, singleAffixSlot)
					end
					local affixBlocked = (not keepBlocked) and (missingAffixBlocked or IsAffixProtected(profile, bag, slot, itemLink, "delete", singleAffixSlot))
					local recipeDeleteBlocked = (not keepBlocked) and (not affixBlocked)
						and _G.AutoDelete_IsRecipeDeleteProtected(profile, itemClass, itemSubType, deleteSourceRule)
					if not keepBlocked and not affixBlocked and not recipeDeleteBlocked then
						if _G.AutoDelete_DebugSell then
							local reason = (deleteSourceRule == "KeepOne" and "KeepOne")
								or (deleteSourceRule == "KeepStack" and "KeepStack")
								or (onDeleteList and "DeleteList")
								or "auto"
							local questNote = (onDeleteList and isQuestItem) and " [QUEST ITEM, overridden by Delete list]" or ""
							print(string.format(
								"|cffff8000[AutoDelete DEBUG]|r ENQUEUE: %s (id=%s) | quality=%s | reason=%s%s",
								tostring(itemName), tostring(itemId), tostring(itemQuality), reason, questNote
							))
						end
						-- v3.20 queue-throttled deletes: enqueue instead of
						-- executing the API call now. AutoDelete_DrainDeleteQueue
						-- (called from the scanner OnUpdate) pops one item per
						-- DELAY (90ms) and runs PickupContainerItem +
						-- DeleteCursorItem then. Capture link+name+id so the
						-- drain can re-validate the slot before acting (the
						-- user may move/use/swap the item between walk and
						-- drain). items-deleted counter + BumpStat happen at
						-- drain time when the API call actually executes.
						Q.items[#Q.items + 1] = {
							bag   = bag,
							slot  = slot,
							link  = itemLink,
							name  = itemName,
							id    = itemId,
							sourceRule = deleteSourceRule or "Delete scanner",
							keepOne = onKeepOneList,
							keepOneUnits = keepOneUnitsToDelete,
							keepStack = onKeepStackList,
							singleAffix = singleAffixExtra,
							affixKey = singleAffixKey,
							-- Retry counter for the drain's locked-slot
							-- deferral. Incremented when the slot is briefly
							-- locked (server-lag race, mid-flight BAG_UPDATE)
							-- and the entry is requeued. Dropped after
							-- QUEUE_MAX_TRIES (4) so a permanently stuck
							-- slot can't wedge the queue.
							tries = 0,
						}
						AutoDelete_PerfCount("DeleteItems/items-enqueued", 1)
						enqueued = enqueued + 1
						-- v3.20 spike session: cumulative itemsEnqueued total.
						if _G.AutoDelete_SpikeDebug then
							local _ss = _G.AutoDelete_SpikeSession
							_ss.itemsEnqueued = (_ss.itemsEnqueued or 0) + 1
						end
						-- v3.20 Goblin defer: stamp when an enqueue happened.
						-- Bag-full check counts an enqueue within the recency
						-- window as "pipeline busy."
						_G.AutoDelete_LastEnqueueAt = GetTime()
					elseif keepBlocked then
						AutoDelete_PerfCount("DeleteItems/items-skipped-keep", 1)
						if _G.AutoDelete_RecordDecision then
							_G.AutoDelete_RecordDecision({
								itemName = itemName,
								itemId = itemId,
								action = "kept",
								reason = "Keep list blocked delete",
								sourceRule = deleteSourceRule or "Delete scanner",
								bag = bag,
								slot = slot,
							})
						end
						if _G.AutoDelete_DebugSell then
							print(string.format(
								"|cffff8000[AutoDelete DEBUG]|r delete BLOCKED by Keep list: %s (id=%s)",
								tostring(itemName), tostring(itemId)
							))
						end
					elseif recipeDeleteBlocked then
						AutoDelete_PerfCount("DeleteItems/items-skipped-recipe", 1)
						if _G.AutoDelete_RecordDecision then
							_G.AutoDelete_RecordDecision({
								itemName = itemName,
								itemId = itemId,
								action = "kept",
								reason = "Sell Known Recipes blocked delete",
								sourceRule = deleteSourceRule or "Delete scanner",
								recipeLike = true,
								recipeState = _G.AutoDelete_GetRecipeKnowledgeState(bag, slot, itemLink),
								recipeQuality = itemQuality,
								recipeQualityEnabled = _G.AutoDelete_IsKnownRecipeQualityEnabled(profile, itemQuality),
								bag = bag,
								slot = slot,
							})
						end
						if _G.AutoDelete_DebugSell then
							print(string.format(
								"|cffff8000[AutoDelete DEBUG]|r delete BLOCKED by Sell Known Recipes: %s (id=%s)",
								tostring(itemName), tostring(itemId)
							))
						end
					else  -- affixBlocked
						AutoDelete_PerfCount("DeleteItems/items-skipped-affix", 1)
						if _G.AutoDelete_RecordDecision then
							_G.AutoDelete_RecordDecision({
								itemName = itemName,
								itemId = itemId,
								action = "kept",
								reason = missingAffixBlocked
									and ("Missing affix hard stop blocked delete" .. (missingAffixState == "unknown" and " (ownership unknown)" or ""))
									or "Affix Protection blocked delete",
								sourceRule = deleteSourceRule or "Delete scanner",
								bag = bag,
								slot = slot,
							})
						end
						if _G.AutoDelete_DebugSell then
							print(string.format(
								"|cffff8000[AutoDelete DEBUG]|r delete BLOCKED by %s: %s (id=%s)",
								missingAffixBlocked and "missing affix hard stop" or "Affix Protection",
								tostring(itemName), tostring(itemId)
							))
						end
					end
				end
			end
		end
	end
	AutoDelete_PerfEnd("DeleteItems/loop", _pLoop)
	-- v3.20 Goblin defer: stamp WHEN the walk finished and HOW MANY items
	-- it enqueued. Bag-full check reads these to decide whether to defer
	-- (pipeline busy or just-scanned) vs fire (scanned and found nothing).
	-- See _G.AutoDelete_BagsBelowAt / LastDeleteWalkAt / LastDeleteWalkEnqueued.
	_G.AutoDelete_LastDeleteWalkAt       = GetTime()
	_G.AutoDelete_LastDeleteWalkEnqueued = enqueued
	AutoDelete_PerfEnd("DeleteItems", _p)
end

-- v3.20 queue drain. Called once per scanner OnUpdate tick. Pops at most
-- one entry from _G.AutoDelete_DeleteQueue.items per DELAY interval and
-- runs the actual PickupContainerItem + DeleteCursorItem pair. Cheap
-- early-out when the queue is empty or the throttle hasn't elapsed.
--
-- Re-validates the slot link before acting: between walk and drain the
-- user may have moved/swapped/used the item (slot now empty, holding a
-- different item, or item locked because they're dragging).
--
-- Three outcomes:
--   1. Link matches, slot not locked -> execute delete, advance lastAt.
--   2. Link matches, slot LOCKED (server-lag race, mid-flight bag
--      update, etc.) -> defer by re-queueing to the tail with an
--      entry.tries counter. Drop only after QUEUE_MAX_TRIES (4), so
--      transient locks don't lose us an item. Drop-after-cap is
--      counted as DeleteItems/queue-stale.
--   3. Link mismatch (item really moved/used/destroyed) -> drop
--      immediately, count as DeleteItems/queue-stale, let the next
--      scan tick re-enqueue from the new slot if still applicable.
--
-- Throttle clamp: instead of "Q.lastAt = now" (which
-- after a long stall like a loading screen could in theory let a
-- subsequent change to the loop pop multiple items per frame), we
-- advance lastAt by EXACTLY Q.DELAY, capped at now. That way even if
-- some future change consolidates multiple pops into a single tick,
-- the throttle cadence is preserved.
--
-- Self-update suppression: re-arms _G.AutoDelete_SelfBagUpdateUntil on
-- every successful pop so the BAG_UPDATE handler keeps treating our
-- own deletes as not-a-real-loot and the burst-quiescence wait
-- doesn't restart.
-- Locked-slot retry cap. Lives on _G (not file-local) because the main
-- chunk is at Lua 5.1's 200-local ceiling; adding a file-local here
-- triggers "main function has more than 200 local variables".
_G.AutoDelete_QueueMaxTries = _G.AutoDelete_QueueMaxTries or 4

-- v3.20 drain-time re-validation. The walk filters at enqueue time, but
-- between enqueue and drain (up to a few seconds for a 32-item queue
-- at 90ms throttle) the user may have:
--   * Added the item to the Keep list
--   * Toggled Affix Protection on / changed protected tiers
--   * Changed quality-action filters (e.g. Greens delete -> off)
--   * Removed the item from the Delete list
--   * Switched to a different profile entirely
-- All of those should void the queued delete. We re-run the same gates
-- the walk used, against the CURRENT cachedProfile, before calling
-- PickupContainerItem. Cost per call is small: GetItemInfo on a warm
-- cache + cached BuildWantedSets hash lookups + cached affix check.
--
-- Returns (eligible, reason) where reason on the false branch is one
-- of: "rule-changed" / "keep-blocked" / "affix-blocked". Counters with
-- the same suffix are bumped by the drain.
--
-- Lives on _G to dodge the 200-local cap. Closure still captures the
-- file-local upvalues (BuildWantedSets, Normalize, IsCosmeticSlot,
-- IsAffixProtected) so the helper behaves identically to inline code.
function _G.AutoDelete_ValidateDrainEntry(profile, entry, currentLink)
	-- GetItemInfo on a warm cache is near-free; we need name + quality
	-- + itemClass for quest detection + equipSlot for the auto-rule
	-- gates that only fire on equippable gear.
	local itemName, _, itemQuality, _, _, itemClass, _, _, equipSlot = GetItemInfo(currentLink)
	if not itemName then
		-- Cache went cold somehow (extreme edge case). Refuse to act;
		-- next walk will re-enqueue if the item still qualifies.
		return false, "rule-changed"
	end
	local isQuestItem = (itemClass == "Quest")

	-- Re-read lists from the CURRENT profile. BuildWantedSets is cached
	-- by listText pointer so an unchanged list returns the prior tables
	-- in O(1); a changed list rebuilds once and caches the new tables.
	local wantedNames, wantedIDs = BuildWantedSets(profile.listText,      "delete-list")
	local sellNames,   sellIDs   = BuildWantedSets(profile.sellListText,  "sell-list")
	local keepNames,   keepIDs   = BuildWantedSets(profile.whitelistText, "keep-list")
	local keepOneIDs = select(2, BuildWantedSets(profile.keepOneText, "keepone-list"))
	local keepStackIDs = select(2, BuildWantedSets(profile.keepStackText, "keepstack-list"))
	local function ValidateAffixBlock()
		local plan = _G.AutoDelete_BuildSingleAffixPlan(profile, keepIDs, keepNames)
		local slotPlan = plan and plan.slots[entry.bag .. ":" .. entry.slot]
		local missingBlocked, missingState = _G.AutoDelete_IsMissingAffixHardStop(profile, entry.bag, entry.slot, currentLink, slotPlan)
		if missingBlocked then
			return false, missingState == "unknown" and "missing-affix-unknown" or "missing-affix-blocked"
		end
		if IsAffixProtected(profile, entry.bag, entry.slot, currentLink, "delete", slotPlan) then
			return false, "affix-blocked"
		end
		return true, nil
	end

	if entry.keepOne then
		if not entry.id or not keepOneIDs[entry.id] then
			return false, "rule-changed"
		end
		if _G.AutoDelete_IsWhitelistedFast(keepIDs, keepNames, entry.id, itemName) then
			return false, "keep-blocked"
		end
		local affixOk, affixReason = ValidateAffixBlock()
		if not affixOk then return false, affixReason end
		local _, currentCount = GetContainerItemInfo(entry.bag, entry.slot)
		local total = _G.AutoDelete_CountBagUnitsByItemId(entry.id)
		local action, amount = PlanKeepOneSlotAction(total, currentCount or 1)
		if action == "keep" or amount <= 0 then
			return false, "keepone-complete"
		end
		if action == "split-delete" and type(SplitContainerItem) ~= "function" then
			return false, "rule-changed"
		end
		entry.keepOneAction = action
		entry.keepOneUnits = amount
		return true, nil
	end

	if entry.keepStack then
		if not entry.id or not keepStackIDs[entry.id] then
			return false, "rule-changed"
		end
		if _G.AutoDelete_IsWhitelistedFast(keepIDs, keepNames, entry.id, itemName) then
			return false, "keep-blocked"
		end
		local affixOk, affixReason = ValidateAffixBlock()
		if not affixOk then return false, affixReason end
		local stackCount, keepBag, keepSlot = _G.AutoDelete_GetKeepStackSlotChoice(entry.id)
		if stackCount <= 1 or entry.bag == keepBag and entry.slot == keepSlot then
			return false, "keepstack-complete"
		end
		return true, nil
	end

	if entry.singleAffix then
		if _G.AutoDelete_IsWhitelistedFast(keepIDs, keepNames, entry.id, itemName) then
			return false, "keep-blocked"
		end
		local affixOk, affixReason = ValidateAffixBlock()
		if not affixOk then return false, affixReason end
		local onDeleteList = false
		if entry.id and wantedIDs[entry.id] then onDeleteList = true end
		if not onDeleteList and itemName and wantedNames[Normalize(itemName)] then
			onDeleteList = true
		end
		local onSellList = false
		if entry.id and sellIDs[entry.id] then onSellList = true end
		if not onSellList and itemName and sellNames[Normalize(itemName)] then
			onSellList = true
		end
		if onSellList and not onDeleteList then
			return false, "rule-changed"
		end
		local plan = _G.AutoDelete_BuildSingleAffixPlan(profile, keepIDs, keepNames)
		local slotPlan = plan and plan.slots[entry.bag .. ":" .. entry.slot]
		if not slotPlan or not slotPlan.extra then
			return false, "single-affix-complete"
		end
		return true, nil
	end

	-- Step 1: still on the Delete list? (overrides quest protection)
	local onDeleteList = false
	if entry.id and wantedIDs[entry.id] then onDeleteList = true end
	if not onDeleteList and itemName and wantedNames[Normalize(itemName)] then
		onDeleteList = true
	end

	-- Step 2: still matches an auto-rule? (only when not on Delete list
	-- AND not a quest item).
	local stillMatches = false
	if onDeleteList then
		stillMatches = true
	elseif not isQuestItem then
		if profile.qualityActionJunk == "delete"
			and itemQuality == 0
			and not IsCosmeticSlot(currentLink) then
			stillMatches = true
		end
		if not stillMatches
			and profile.qualityActionCommon == "delete"
			and itemQuality == 1
			and not IsCosmeticSlot(currentLink)
			and equipSlot and equipSlot ~= "" and equipSlot ~= "INVTYPE_BAG" then
			stillMatches = true
		end
		if not stillMatches
			and profile.qualityActionGreens == "delete"
			and itemQuality == 2
			and not IsCosmeticSlot(currentLink)
			and equipSlot and equipSlot ~= "" and equipSlot ~= "INVTYPE_BAG" then
			stillMatches = true
		end
	end

	if not stillMatches then return false, "rule-changed" end

	-- Step 3: NOW on the Keep list? (was checked at walk time, but the
	-- user may have just added it via drag-and-drop or the override
	-- popup's "Take off Keep list" path).
	if _G.AutoDelete_IsWhitelistedFast(keepIDs, keepNames, entry.id, itemName) then
		return false, "keep-blocked"
	end

	local singleAffixPlan = _G.AutoDelete_BuildSingleAffixPlan(profile, keepIDs, keepNames)
	local singleAffixSlot = singleAffixPlan and singleAffixPlan.slots[entry.bag .. ":" .. entry.slot]
	if singleAffixSlot and not singleAffixSlot.extra and not onDeleteList then
		return false, "single-affix-kept"
	end

	-- Step 4: NOW affix-protected? (Affix Protection toggle or iLvl
	-- floor change between enqueue and drain).
	local affixOk, affixReason = ValidateAffixBlock()
	if not affixOk then return false, affixReason end

	return true, nil
end

function _G.AutoDelete_DrainDeleteQueue(now)
	local Q = _G.AutoDelete_DeleteQueue
	local n = #Q.items
	if n == 0 then return end
	if now - Q.lastAt < Q.DELAY then
		-- v3.20 spike debug: count throttle-skipped tick (queue has work,
		-- but DELAY hasn't elapsed). Helps distinguish "drain idle" from
		-- "drain throttle-waiting" in the per-frame breakdown.
		if _G.AutoDelete_SpikeDebug then
			local c = _G.AutoDelete_SpikeCounters
			local sess = _G.AutoDelete_SpikeSession
			c.drainSkip    = (c.drainSkip or 0) + 1
			sess.drainSkip = (sess.drainSkip or 0) + 1
		end
		return
	end
	-- Cursor busy: user is dragging or another action holds it. Skip
	-- this tick; the queue waits and we try again next frame.
	if CursorHasItem() then
		if _G.AutoDelete_SpikeDebug then
			local c = _G.AutoDelete_SpikeCounters
			local sess = _G.AutoDelete_SpikeSession
			c.drainSkip    = (c.drainSkip or 0) + 1
			sess.drainSkip = (sess.drainSkip or 0) + 1
		end
		return
	end

	local _pDrain = AutoDelete_PerfBegin("DeleteItems/drain")
	-- v3.20 spike debug: count actual drain pops (one item processed).
	if _G.AutoDelete_SpikeDebug then
		local c = _G.AutoDelete_SpikeCounters
		local sess = _G.AutoDelete_SpikeSession
		c.drain    = (c.drain or 0) + 1
		sess.drain = (sess.drain or 0) + 1
	end
	-- Pop head. Small max length (DELETE_BATCH_SIZE = 32) so the O(n)
	-- table.remove at index 1 isn't a concern; a ring-buffer head
	-- index would add bookkeeping for no measurable win.
	local entry = table.remove(Q.items, 1)

	-- Re-validate against current slot state.
	local _, _, locked, _, _, _, currentLink = GetContainerItemInfo(entry.bag, entry.slot)
	local linkMatches = (currentLink == entry.link)

	if linkMatches and not locked then
		-- v3.20 drain-time re-validation: trust nothing the walk decided.
		-- Between enqueue and now (up to several seconds for a full
		-- queue at 90ms throttle) the user may have changed Keep list,
		-- Affix Protection, quality filters, or the Delete list itself.
		-- The validator returns (eligible, reason). Drop with the
		-- matching counter on any failure; the item stays out of bags
		-- until the next walk reconfirms it under current settings.
		local profile = cachedProfile  -- master-enable already gated by OnUpdate
		local eligible, reason = _G.AutoDelete_ValidateDrainEntry(profile, entry, currentLink)
		if not eligible then
			AutoDelete_PerfCount("DeleteItems/queue-" .. reason, 1)
			if _G.AutoDelete_RecordDecision then
				_G.AutoDelete_RecordDecision({
					itemName = entry.name,
					itemId = entry.id,
					action = "kept",
					reason = (reason == "keep-blocked" and "Keep list blocked queued delete")
						or (reason == "missing-affix-blocked" and "Missing affix hard stop blocked queued delete")
						or (reason == "missing-affix-unknown" and "Missing affix hard stop blocked queued delete (ownership unknown)")
						or (reason == "affix-blocked" and "Affix Protection blocked queued delete")
						or (reason == "single-affix-kept" and "KeepOne Missing Affix kept queued delete")
						or (reason == "keepone-complete" and "KeepOne already has one unit left")
						or (reason == "keepstack-complete" and "KeepStack already has one stack left")
						or (reason == "single-affix-complete" and "KeepOne Missing Affix already has one item left")
						or "Delete rule changed before queued delete executed",
					sourceRule = entry.sourceRule or "Delete scanner",
					bag = entry.bag,
					slot = entry.slot,
				})
			end
			if _G.AutoDelete_DebugSell then
				print(string.format(
					"|cffff8000[AutoDelete DEBUG]|r drain BLOCKED (%s): %s",
					reason, tostring(entry.name)
				))
			end
			-- Advance lastAt so this validation tick counts; next entry
			-- gets its 90ms window like any successful or stale pop.
			Q.lastAt = math.max(now, Q.lastAt + Q.DELAY)
			AutoDelete_PerfEnd("DeleteItems/drain", _pDrain)
			return
		end

		-- Outcome 1: execute the delete (all gates re-confirmed).
		_G.AutoDelete_SelfBagUpdateUntil = now + 0.5
		local _pApi = AutoDelete_PerfBegin("DeleteItems/api-delete")
		ClearCursor()
		if entry.keepOne and entry.keepOneAction == "split-delete" then
			if type(SplitContainerItem) == "function" then
				SplitContainerItem(entry.bag, entry.slot, entry.keepOneUnits or 1)
				if CursorHasItem() then DeleteCursorItem(); ClearCursor() end
			end
		else
			PickupContainerItem(entry.bag, entry.slot)
			if CursorHasItem() then DeleteCursorItem(); ClearCursor() end
		end
		AutoDelete_PerfEnd("DeleteItems/api-delete", _pApi)
		AutoDelete_PerfCount("DeleteItems/items-deleted", 1)
		BumpStat("itemsDeleted", 1)
		if _G.AutoDelete_RecordDecision then
			_G.AutoDelete_RecordDecision({
				itemName = entry.name,
				itemId = entry.id,
				action = "deleted",
				reason = entry.keepOne and "KeepOne extra unit(s) deleted"
					or (entry.keepStack and "KeepStack extra stack deleted")
					or (entry.singleAffix and "KeepOne Missing Affix extra item deleted")
					or "Queued delete executed",
				sourceRule = entry.sourceRule or "Delete scanner",
				bag = entry.bag,
				slot = entry.slot,
			})
		end
		-- v3.20 spike session: cumulative itemsDeleted total.
		if _G.AutoDelete_SpikeDebug then
			local _ss = _G.AutoDelete_SpikeSession
			_ss.itemsDeleted = (_ss.itemsDeleted or 0) + 1
		end
		-- v3.20 Goblin defer: stamp when a drain pop succeeded. Bag-full
		-- check counts a drain within the recency window as "pipeline busy."
		_G.AutoDelete_LastDrainPopAt = now
		if _G.AutoDelete_DebugSell then
			print(string.format(
				"|cffff8000[AutoDelete DEBUG]|r DELETED (queued): %s",
				tostring(entry.name)
			))
		end
		-- Throttle clamp: advance lastAt by EXACTLY one DELAY. After a
		-- long stall (loading screen, alt-tab) lastAt may be way in the
		-- past; advancing to now+DELAY would skip the next several pop
		-- windows we'd otherwise be entitled to, but we don't want a
		-- burst either. math.max keeps lastAt at or after `now` so the
		-- next pop is at least DELAY away in real time.
		Q.lastAt = math.max(now, Q.lastAt + Q.DELAY)
	elseif linkMatches and locked then
		-- Outcome 2: locked-slot deferral. Server-lag race or mid-flight
		-- BAG_UPDATE briefly locked the slot. Re-queue to the tail with
		-- an incremented tries counter so other items get a turn while
		-- this one waits for the lock to clear. Drop only after the
		-- retry cap, which is high enough to ride out normal latency
		-- but low enough that a stuck slot eventually frees the queue.
		entry.tries = (entry.tries or 0) + 1
		if entry.tries < _G.AutoDelete_QueueMaxTries then
			Q.items[#Q.items + 1] = entry
			AutoDelete_PerfCount("DeleteItems/queue-deferred", 1)
			if _G.AutoDelete_DebugSell then
				print(string.format(
					"|cffff8000[AutoDelete DEBUG]|r drain DEFERRED (slot locked, try %d/%d): %s",
					entry.tries, _G.AutoDelete_QueueMaxTries, tostring(entry.name)
				))
			end
		else
			AutoDelete_PerfCount("DeleteItems/queue-stale", 1)
			if _G.AutoDelete_DebugSell then
				print(string.format(
					"|cffff8000[AutoDelete DEBUG]|r drain DROPPED (locked past %d tries): %s",
					_G.AutoDelete_QueueMaxTries, tostring(entry.name)
				))
			end
		end
		-- Still advance lastAt: deferring a locked entry counts as a
		-- "tick spent" so we don't burn through the rest of the queue
		-- back-to-back while this one cycles.
		Q.lastAt = math.max(now, Q.lastAt + Q.DELAY)
	else
		-- Outcome 3: link mismatch. Item really moved/used/destroyed.
		-- Drop immediately; the next scan tick will re-enqueue from
		-- the new slot if the item is still in bags and still matches
		-- a delete rule.
		AutoDelete_PerfCount("DeleteItems/queue-stale", 1)
		if _G.AutoDelete_DebugSell then
			print(string.format(
				"|cffff8000[AutoDelete DEBUG]|r drain DROPPED stale entry: %s (slot changed)",
				tostring(entry.name)
			))
		end
		Q.lastAt = math.max(now, Q.lastAt + Q.DELAY)
	end

	AutoDelete_PerfEnd("DeleteItems/drain", _pDrain)
end

-- ============================================================================
-- AutoDelete_HasPendingDeleteItems
-- ============================================================================
-- Cheap predicate: returns true if any item currently in the player's bags
-- would be deleted on the next DeleteItems pass. Used by the bag-full
-- Goblin Merchant auto-summon to defer firing while AutoDelete still has
-- trash to clear -- looting a stack of grays into a near-full bag should
-- result in "wait for the delete pass to free space", not "burn a Goblin
-- Merchant summon for items that are about to disappear anyway".
--
-- Decision mirrors DeleteItems' decision chain MINUS the affix-protection
-- tooltip scan (which is expensive). We deliberately do NOT call IsAffix-
-- Protected here: an affix-protected gray would still count as "pending"
-- under this check, which leans toward delaying the summon a beat longer
-- than strictly necessary. That's the safe direction -- a delayed summon
-- is recoverable; a summon burned on items that vanish is not.
--
-- Returns on the first eligible item found (early break) so the average
-- cost is well under a full bag scan.
function _G.AutoDelete_HasPendingDeleteItems(profile)
	if not profile then return false end
	-- Tri-state quality filter: only "delete" mode counts as pending here.
	-- "sell" items don't block the bag-full Goblin summon -- selling requires
	-- the player to interact with a merchant, which is a different flow.
	local doGray   = (profile.qualityActionJunk == "delete")
	local doCommon = (profile.qualityActionCommon == "delete")
	-- BuildWantedSets returns (nameSet, idSet) in that order. `hasWanted`
	-- mirrors DeleteItems' canonical "is the user's Delete list non-empty"
	-- check via next(); it's the cheap way to skip the per-slot list
	-- match when the list has zero entries.
	local wantedNames, wantedIDs = BuildWantedSets(profile.listText, "delete-list")
	local hasWanted = next(wantedNames) or next(wantedIDs)
	local keepOneIDs = select(2, BuildWantedSets(profile.keepOneText, "keepone-list"))
	local hasKeepOne = next(keepOneIDs) ~= nil
	local keepStackIDs = select(2, BuildWantedSets(profile.keepStackText, "keepstack-list"))
	local hasKeepStack = next(keepStackIDs) ~= nil
	local hasSingleAffixCleanup = profile.keepSingleMissingAffix == true
	-- Bail early if there's nothing to look for. Saves the full bag walk
	-- in the common case of a brand-new profile with no rules enabled.
	if not (hasWanted or hasKeepOne or hasKeepStack or doGray or doCommon) then return false end

	-- Pre-built Keep-list sets so the inner loop's up-to-3 IsWhitelisted
	-- calls per slot become 3 hash lookups instead of 3 full whitelist
	-- re-parses. Same optimization as DeleteItems' hot path. Shares the
	-- "keep-list" cache slot with DeleteItems / SellItems.
	local keepNames, keepIDs = BuildWantedSets(profile.whitelistText, "keep-list")

	local affixPlan = nil
	if hasSingleAffixCleanup then
		affixPlan = _G.AutoDelete_BuildSingleAffixPlan(profile, keepIDs, keepNames)
	end

	for bag = 0, 4 do
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local itemName, _, itemQuality, _, _, itemClass, _, _, equipSlot = GetItemInfo(link)
				local itemId = GetItemIDFromLink(link)
				local isQuestItem = (itemClass == "Quest")
				local singleAffixSlot = affixPlan and affixPlan.slots[bag .. ":" .. slot]
				local singleAffixKept = singleAffixSlot and not singleAffixSlot.extra

				if hasKeepOne and itemId and keepOneIDs[itemId]
					and not _G.AutoDelete_IsWhitelistedFast(keepIDs, keepNames, itemId, itemName)
					and not IsAffixProtected(profile, bag, slot, link, "delete")
					and _G.AutoDelete_CountBagUnitsByItemId(itemId) > 1 then
					return true
				end

				if hasKeepStack and itemId and keepStackIDs[itemId]
					and not _G.AutoDelete_IsWhitelistedFast(keepIDs, keepNames, itemId, itemName)
					and not IsAffixProtected(profile, bag, slot, link, "delete") then
					local stackCount, keepBag, keepSlot = _G.AutoDelete_GetKeepStackSlotChoice(itemId)
					if stackCount > 1 and (bag ~= keepBag or slot ~= keepSlot) then
						return true
					end
				end

				-- (1) Explicit Delete list. Wins over quest protection.
				if hasWanted then
					local onList = false
					if itemId and wantedIDs[itemId] then onList = true end
					if not onList and itemName and wantedNames[Normalize(itemName)] then
						onList = true
					end
					if onList and not _G.AutoDelete_IsWhitelistedFast(keepIDs, keepNames, itemId, itemName) then
						return true
					end
				end

				-- (2) Auto rules. Quest-protected; respect cosmetic slots.
				-- Quality codes: 0 = Poor (gray), 1 = Common (white).
				if not isQuestItem then
					if doGray and itemQuality and itemQuality == 0
						and not IsCosmeticSlot(link)
						and not singleAffixKept
						and not _G.AutoDelete_IsWhitelistedFast(keepIDs, keepNames, itemId, itemName) then
						return true
					end
					if doCommon and itemQuality and itemQuality == 1
						and not IsCosmeticSlot(link)
						and equipSlot and equipSlot ~= "" and equipSlot ~= "INVTYPE_BAG"
						and not singleAffixKept
						and not _G.AutoDelete_IsWhitelistedFast(keepIDs, keepNames, itemId, itemName) then
						return true
					end
				end
			end
		end
	end
	return false
end

-- ============================================================================
-- Sell Logic
-- ============================================================================
-- SellItems scans bags at a vendor and sells items matching the rules.
-- Called from MERCHANT_SHOW (gated by master Enable), from the periodic
-- scanner while a vendor window is open, and from /del sell (manual,
-- ungated). The decision chain is documented inline at the top of the
-- per-slot loop.
--
-- Two slot tables drive what's eligible:
--   GEAR_SLOTS    = every equippable slot the rules can act on
--   WEAPON_SLOTS  = the subset that counts as a "weapon" for BoE Weapons
--                   (everything Hand-Affix-Enchant targets on PE)

local GEAR_SLOTS = {
	INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true,
	INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
	INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
	INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true,
	INVTYPE_ROBE = true, INVTYPE_WAIST = true, INVTYPE_LEGS = true,
	INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
	INVTYPE_CLOAK = true, INVTYPE_SHIELD = true,
	-- Accessories: rings, necks, trinkets, held off-hands, relics.
	-- INVTYPE_BODY (shirts), INVTYPE_TABARD, INVTYPE_BAG, INVTYPE_AMMO,
	-- and INVTYPE_QUIVER are DELIBERATELY excluded - they're either
	-- cosmetic or non-gear and should never be auto-sold by category
	-- rules. The Delete and Sell lists can still touch them via explicit
	-- entries (which bypass these filters).
	INVTYPE_FINGER = true, INVTYPE_NECK = true, INVTYPE_TRINKET = true,
	INVTYPE_HOLDABLE = true, INVTYPE_RELIC = true,
}

-- "Weapon" for the BoE weapons iLvl range covers anything a Hands/Weapon
-- affix can be applied to on PE: main-hand, off-hand, two-handers, shields,
-- off-hand holdables (tomes, orbs), ranged (bows), ranged-right (guns,
-- crossbows, wands), thrown, and relics (idols, librams, totems, sigils).
local WEAPON_SLOTS = {
	INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true,
	INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
	INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
	INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_RELIC = true,
}

-- Hidden tooltip used to read "Binds when equipped" text from bag items.
-- 3.3.5 has no API to query bind type directly, so we scan the actual
-- tooltip lines.
--
-- Important quirk: setting the owner to UIParent with ANCHOR_NONE works on
-- a vanilla client but on some setups (notably PE-ElvUI) SetBagItem leaves
-- the tooltip with 0 lines until the tooltip is actually shown. The fix is
-- to give it a real off-screen owner frame and force a Show/Hide cycle
-- around the read so the engine populates lines synchronously.
local boeTipOwner = CreateFrame("Frame", nil, UIParent)
boeTipOwner:SetSize(1, 1)
boeTipOwner:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
boeTipOwner:Hide()  -- never visible; just an owner anchor

local boeTip = CreateFrame("GameTooltip", "AutoDelete_BoETip", UIParent, "GameTooltipTemplate")
boeTip:SetClampedToScreen(false)

_G.AutoDelete_RecipeTip = CreateFrame("GameTooltip", "AutoDelete_RecipeTip", UIParent, "GameTooltipTemplate")
_G.AutoDelete_RecipeTip:SetClampedToScreen(false)

-- ============================================================================
-- Tooltip-result cache (Phase D)
-- ============================================================================
-- Tooltip scans are the single most expensive thing the addon does on every
-- BAG_UPDATE: each Is*/HasAffix call does ClearLines + SetBagItem + Show +
-- NumLines + N GetText calls + Hide. With four scan types and ~50 bag slots,
-- a full re-scan touches 200+ tooltip operations per BAG_UPDATE.
--
-- Items don't change tooltip text mid-session except for:
--   * Equipping/unequipping a BoE -> becomes Soulbound (handled below)
--   * Picking a Battered Junkbox -> Locked clears (NOT cached, see below)
--
-- itemLink is a stable per-instance identifier on 3.3.5a (uniqueID is
-- persistent across moves), so it's a safe cache key. itemID alone is not
-- safe because PE attaches per-instance @affix@ data to specific item
-- instances of the same template.
--
-- Cleared on /reload (table is recreated on file load). Soulbound entries
-- additionally cleared on PLAYER_EQUIPMENT_CHANGED so equipping a BoE
-- doesn't leave a stale "not soulbound" result. Locked is NOT cached
-- because key-lock state can change without an event we hook.
-- Exposed as _G.AutoDelete_TooltipCache (not file-local) so we don't
-- bump the main chunk past Lua 5.1's 200-local cap.
_G.AutoDelete_TooltipCache = _G.AutoDelete_TooltipCache or {
	affix     = {},
	affixName = {},
	boe       = {},
	recipeKnown = {},
	soulbound = {},
}
-- Versioned cache invalidation. When the parsing logic (esp.
-- AutoDelete_ExtractAffixLevel) changes between addon builds, cached values from
-- prior loads can disagree with what the new code would produce
-- (e.g. an item that used to cache as `true` boolean now needs to be
-- 1-4; an item that used to cache at the wrong level under an Arabic-
-- only parser needs to re-classify under the Roman-numeral parser).
-- /reload only re-runs this file, it doesn't drop the global table,
-- so we drop the affected sub-cache here when the version doesn't
-- match. Bump _CACHE_VERSION whenever parsing semantics change.
do
	local _CACHE_VERSION = 8
	if _G.AutoDelete_TooltipCache._cacheVersion ~= _CACHE_VERSION then
		_G.AutoDelete_TooltipCache.affix     = {}
		_G.AutoDelete_TooltipCache.affixName = {}
		_G.AutoDelete_TooltipCache.soulbound = {}
		_G.AutoDelete_TooltipCache.boe       = {}
		_G.AutoDelete_TooltipCache.recipeKnown = {}
		_G.AutoDelete_TooltipCache._cacheVersion = _CACHE_VERSION
	end
end

function _G.AutoDelete_GetRecipeKnowledgeState(bag, slot, link)
	if not bag or not slot or not link then return "uncertain" end
	local cache = _G.AutoDelete_TooltipCache and _G.AutoDelete_TooltipCache.recipeKnown
	if _G.AutoDelete_GetRecipeKnowledgeCacheHit then
		local cachedState = _G.AutoDelete_GetRecipeKnowledgeCacheHit(cache, link)
		if cachedState then return cachedState end
	elseif cache and cache[link] == "known" then
		return "known"
	end

	local knownToken = ITEM_SPELL_KNOWN
	if type(knownToken) ~= "string" or knownToken == "" then
		knownToken = "Already known"
	end

	local recipeTip = _G.AutoDelete_RecipeTip
	recipeTip:Hide()
	recipeTip:SetOwner(boeTipOwner, "ANCHOR_NONE")
	recipeTip:ClearLines()
	recipeTip:SetBagItem(bag, slot)
	recipeTip:Show()
	local n = recipeTip:NumLines()
	local lines = {}
	for i = 1, n do
		local leftFS  = _G["AutoDelete_RecipeTipTextLeft"  .. i]
		local rightFS = _G["AutoDelete_RecipeTipTextRight" .. i]
		local leftTxt  = leftFS  and leftFS:GetText()  or nil
		local rightTxt = rightFS and rightFS:GetText() or nil
		if leftTxt then lines[#lines + 1] = leftTxt end
		if rightTxt then lines[#lines + 1] = rightTxt end
	end
	local state = _G.AutoDelete_DetectRecipeKnowledgeFromTooltipLines(lines, knownToken)
	recipeTip:Hide()

	if _G.AutoDelete_RememberRecipeKnowledgeState then
		_G.AutoDelete_RememberRecipeKnowledgeState(cache, link, state)
	elseif cache then
		if state == "known" then
			cache[link] = "known"
		else
			cache[link] = nil
		end
	end
	return state
end

-- Combined-marker tooltip scan. Walks the bag-slot tooltip ONCE and
-- extracts all three flags we care about (BoE, Soulbound, affix-level)
-- in a single pass, then writes them to the corresponding global
-- caches. This is the cold-path for IsBindOnEquip / IsSoulbound /
-- HasAffix when the caller's specific cache is empty -- whichever
-- function gets called first warms the other two for free.
--
-- Before this consolidation, FindDisenchantTarget on a freshly-looted
-- 100-item bag did up to 200 tooltip scans (IsSoulbound + IsBindOnEquip
-- per slot, both cold). The combined scan halves that: each fresh
-- item incurs ONE scan that fills both caches; the second check is a
-- cache hit. Dot-rendering through HasAffix benefits the same way.
--
-- Cost per combined scan is roughly the same as one previous single-
-- marker scan: most items have NEITHER BoE nor Soulbound nor affix,
-- so the single-marker scans were already walking the full tooltip
-- (no early break possible when the marker is absent). Items WITH a
-- marker may walk slightly more (no early break here either), but
-- they're the minority and the cache savings dominate.
--
-- Caller must pass a non-nil `link` (used as the cache key). Returns
-- (hasBoE, isSoulbound, affixLevel-or-false). Debug-mode scans
-- bypass this function so the per-marker debug prints still work.
function _G.AutoDelete_ScanBagItemMarkers(bag, slot, link)
	local _p = AutoDelete_PerfBegin("AutoDelete_ScanBagItemMarkers")
	-- v3.20 spike debug: count cold tooltip scans (this function is
	-- the unified entry for affix + soulbound + BoE marker scans).
	if _G.AutoDelete_SpikeDebug then
		local c = _G.AutoDelete_SpikeCounters
		local sess = _G.AutoDelete_SpikeSession
		c.ttScanRan    = (c.ttScanRan or 0) + 1
		sess.ttScanRan = (sess.ttScanRan or 0) + 1
	end
	boeTip:Hide()
	boeTip:SetOwner(boeTipOwner, "ANCHOR_NONE")
	boeTip:ClearLines()
	boeTip:SetBagItem(bag, slot)
	-- Force population on environments where SetBagItem alone leaves
	-- NumLines == 0 until the tooltip is shown.
	boeTip:Show()
	local n = boeTip:NumLines()
	local nameLine = _G["AutoDelete_BoETipTextLeft1"]
	local tooltipName = nameLine and nameLine:GetText() or nil
	local hasBoE, isSoulbound, hasAffixMarker = false, false, false
	for i = 1, n do
		local leftFS  = _G["AutoDelete_BoETipTextLeft"  .. i]
		local rightFS = _G["AutoDelete_BoETipTextRight" .. i]
		local leftTxt  = leftFS  and leftFS:GetText()  or nil
		local rightTxt = rightFS and rightFS:GetText() or nil
		if leftTxt then
			if not hasBoE and ITEM_BIND_ON_EQUIP
				and string.find(leftTxt, ITEM_BIND_ON_EQUIP, 1, true) then
				hasBoE = true
			end
			if not isSoulbound and ITEM_SOULBOUND
				and string.find(leftTxt, ITEM_SOULBOUND, 1, true) then
				isSoulbound = true
			end
			if not hasAffixMarker and string.find(leftTxt, "@affix@", 1, true) then
				hasAffixMarker = true
			end
		end
		if rightTxt and not hasAffixMarker
			and string.find(rightTxt, "@affix@", 1, true) then
			hasAffixMarker = true
		end
	end
	boeTip:Hide()
	-- Determine affix tier. The @affix@ tooltip markers tell us an item
	-- HAS an affix, but the actual tier (I-V) is encoded as a trailing
	-- Roman numeral on the item NAME. If the marker is hidden/missing,
	-- fall back to PE's known affix names so learned affixes still obey
	-- No Auto-Sell tier protection.
	local itemName = GetItemInfo(link)
	_G.AutoDelete_TooltipCache.affixName[link] = tooltipName or itemName
	local affixLevel = false
	if hasAffixMarker then
		affixLevel = AutoDelete_ExtractAffixLevel(itemName) or 1
		if _G.AutoDelete_DebugSell then
			print(string.format(
				"|cffff8000[AutoDelete DEBUG]|r affix-marker found: name='%s' -> tier=%d",
				tostring(itemName), affixLevel))
		end
	else
		affixLevel = AutoDelete_ExtractKnownAffixLevel(itemName) or false
		if affixLevel and _G.AutoDelete_DebugSell then
			print(string.format(
				"|cffff8000[AutoDelete DEBUG]|r affix-name fallback: name='%s' -> tier=%d",
				tostring(itemName), affixLevel))
		end
	end
	_G.AutoDelete_TooltipCache.affix[link]     = affixLevel
	_G.AutoDelete_TooltipCache.soulbound[link] = isSoulbound
	_G.AutoDelete_TooltipCache.boe[link]       = hasBoE
	AutoDelete_PerfEnd("AutoDelete_ScanBagItemMarkers", _p)
	return hasBoE, isSoulbound, affixLevel
end

local function IsBindOnEquip(bag, slot)
	-- Phase D cache: BoE state is intrinsic to the item template and never
	-- changes for the same instance. Skip the cache when debug is on so the
	-- user always sees a fresh tooltip dump.
	local link = GetContainerItemLink(bag, slot)
	local debug = _G.AutoDelete_DebugSell
	if link and not debug then
		local cached = _G.AutoDelete_TooltipCache.boe[link]
		if cached ~= nil then return cached end
	end
	if debug then
		-- Verbose debug-mode scan. Walks the tooltip and prints every
		-- line so the user can verify what we're seeing. Doesn't go
		-- through AutoDelete_ScanBagItemMarkers (which is the fast non-debug
		-- combined-marker path) so the per-line print logic stays.
		boeTip:Hide()
		boeTip:SetOwner(boeTipOwner, "ANCHOR_NONE")
		boeTip:ClearLines()
		boeTip:SetBagItem(bag, slot)
		boeTip:Show()
		local n = boeTip:NumLines()
		local foundBoE = false
		local lines = {}
		for i = 2, n do
			local text = _G["AutoDelete_BoETipTextLeft" .. i]
			if text then
				local line = text:GetText()
				if line then
					table.insert(lines, "  ["..i.."] "..line)
				end
				if line and string.find(line, ITEM_BIND_ON_EQUIP, 1, true) then
					foundBoE = true
				end
			end
		end
		print("|cffff8000[AutoDelete DEBUG]|r tooltip scan ("..n.." lines, foundBoE="..tostring(foundBoE).."):")
		for _, l in ipairs(lines) do print(l) end
		boeTip:Hide()
		return foundBoE
	end
	if not link then return false end
	local boe = AutoDelete_ScanBagItemMarkers(bag, slot, link)
	return boe
end

-- Auto-Open Containers uses this to gate "locked" items (e.g. Battered
-- Junkbox) on whether the player has actually picked the lock yet. 3.3.5a
-- does NOT return a usable "locked" flag from GetContainerItemInfo for most
-- container types (the field is for stack-merging locks, not key-locks),
-- so we tooltip-scan for the global LOCKED string the same way we scan for
-- "Binds when equipped". Cheap (one SetBagItem call), locale-correct via
-- the LOCKED global.
local function IsItemLocked(bag, slot)
	boeTip:Hide()
	boeTip:SetOwner(boeTipOwner, "ANCHOR_NONE")
	boeTip:ClearLines()
	boeTip:SetBagItem(bag, slot)
	boeTip:Show()
	local n = boeTip:NumLines()
	-- LOCKED is a WoW FrameXML global string; pre-localized by the client
	-- on every locale. We rely on it directly rather than literal "Locked"
	-- so non-enUS players see the correct match.
	for i = 2, n do
		local fs = _G["AutoDelete_BoETipTextLeft" .. i]
		local txt = fs and fs:GetText()
		-- Anchor at line start so "Unlocking..." (a cast-state line) never
		-- false-positives if it ever sneaks into the tooltip.
		if txt and string.find(txt, "^" .. LOCKED) then
			boeTip:Hide()
			return true
		end
	end
	boeTip:Hide()
	return false
end

-- One-Key Disenchant uses this to confirm an item is bound to the player
-- (BoP) before allowing it to be auto-targeted by the disenchant macro.
-- 3.3.5a does not expose a direct "is bound to me" API on container slots
-- (GetContainerItemInfo only returns quality/locked/quantity), so we scan
-- the tooltip for the localized ITEM_SOULBOUND line. Same scan frame and
-- defensive Show() pattern as IsBindOnEquip.
local function IsSoulbound(bag, slot)
	-- Phase D cache: Soulbound transitions are one-way (BoE -> Soulbound on
	-- equip). Cache is invalidated wholesale on PLAYER_EQUIPMENT_CHANGED so
	-- a freshly-equipped BoE can't return a stale "not soulbound" hit.
	local link = GetContainerItemLink(bag, slot)
	if not link then return false end
	local cached = _G.AutoDelete_TooltipCache.soulbound[link]
	if cached ~= nil then return cached end
	-- Cold path: combined scan also warms boe + affix caches for free.
	-- See AutoDelete_ScanBagItemMarkers for the rationale.
	local _, sb = AutoDelete_ScanBagItemMarkers(bag, slot, link)
	return sb
end

-- Affix Protection: PE wraps server-set affix tooltip lines with literal
-- @affix@TEXT@affix@ markers. Reuses the same scan-tooltip pattern as
-- IsBindOnEquip. Returns true if any tooltip line on the given bag slot
-- contains the @affix@ marker.
--
-- Tooltip compatibility: this uses our custom-named tooltip frame
-- (AutoDelete_BoETip), not GameTooltip or ItemRefTooltip. Standard tooltip
-- recolor hooks target the two standard
-- named tooltips by reference, so they do NOT modify our scan tooltip's
-- text. The raw @affix@ markers pass through untouched. PE's own affix
-- detection uses this exact pattern (extraction.lua: EbonholdAffixScanTooltip)
-- so if it works for them in any configuration, it works for us too.
--
-- Defense in depth: we scan BOTH the left and right text columns and
-- emit a debug print when /del debug is active so the user can verify
-- the scan is finding what it should.
-- Extract the affix level (1-4) from a tooltip line that contains the
-- @affix@TEXT@affix@ marker pair. PE encodes the level as a Roman
-- numeral inside the markers: `@affix@I@affix@` / `@affix@II@affix@` /
-- `@affix@III@affix@` / `@affix@IV@affix@`. Returns the level on hit,
-- or 1 (default to white/lowest tier) if the markers are present but
-- no parseable level is found. Returns false if no marker pair on the
-- line at all.
--
-- Color mapping for AutoDelete_SetButtonAffixDot:
--   1 -> white (#FFFFFF)   common-tier affix    (Roman "I")
--   2 -> green (#1EFF00)   uncommon-tier affix  (Roman "II")
--   3 -> blue  (#0070DD)   rare-tier affix      (Roman "III")
--   4 -> purple(#A335EE)   epic-tier affix      (Roman "IV")
--
-- Robustness:
--   * Whitespace inside the markers is tolerated via a trim-then-exact
--     check on the inner string.
--   * If the inner content has extra text around the numeral (some PE
--     builds wrap it as "Tier II" or "Rank IV"), we fall back to a
--     longest-first substring search. Longest-first matters: "III"
--     contains "II" contains "I" as substrings, so searching shorter
--     numerals first would misclassify higher tiers as lower ones.
--   * Arabic digit fallback (1-4) is kept for forward compatibility in
--     case a future PE build switches encoding.
--   * Last resort: markers present but no numeral parsed -> level 1.
-- Extract the affix tier (1-5) from an item NAME.
--
-- PE encodes the affix tier as a trailing Roman numeral on the item
-- name (NOT inside the @affix@ tooltip markers -- those wrap the
-- affix effect description, not the tier number). Confirmed via
-- /del debug capture 2026-05-20 and cross-verified against PE's own
-- ParseAffixNameAndTier in extraction.lua, which uses this exact
-- pattern. Examples:
--   "Belt of Draconic Runes of Iron Will IV"          -> 4
--   "Belt of Draconic Runes of Arcane Mind II"        -> 2
--   "Lola's Lifegiving Branch of Iron Will III"       -> 3
--   "Hydra-fang Necklace of Cold II"                  -> 2
--   "Milan's Mastercraft Band of Block IV"            -> 4
--   (PE supports up to V too -- "Foo of Bar V" -> 5)
--
-- Returns 1-5 if a trailing Roman is present, nil otherwise. The
-- caller (ScanBagItemMarkers) decides what to do with a nil result
-- when an affix marker IS present on the item -- currently defaults
-- to tier 1 so the dot still renders.
local AFFIX_ROMAN_TO_NUM = { i = 1, ii = 2, iii = 3, iv = 4, v = 5 }
function _G.AutoDelete_ExtractAffixLevel(itemName)
	if not itemName then return nil end
	-- Lowercase + match a trailing Roman numeral run anchored at end of
	-- string, preceded by whitespace. The [iv]+ pattern matches any
	-- combination of i/v chars; the table lookup is the actual gate
	-- (so weird suffixes like "vii" or "ivi" fall through to nil).
	-- This is the same pattern PE uses internally in extraction.lua.
	local roman = itemName:lower():match("%s+([iv]+)$")
	if not roman then return nil end
	return AFFIX_ROMAN_TO_NUM[roman]
end

function _G.AutoDelete_ExtractKnownAffixLevel(itemName)
	local tier = AutoDelete_ExtractAffixLevel(itemName)
	if not tier then return nil end
	if _G.AutoDelete_GetAffixKeyForItemName
		and _G.AutoDelete_GetAffixKeyForItemName(itemName) then
		return tier
	end
	return nil
end

-- ============================================================================
-- Affix Collection Mode
-- ============================================================================
-- When the user enables `affixCollectionMode`, the affix dot becomes a
-- "you haven't learned this yet" indicator rather than a "this item has
-- an affix" indicator. Owned-at-this-tier items pass through normal
-- sell/delete rules so the player can clear duplicates; missing-affix
-- items get the chosen missing-affix color AND keep their affix protection.
--
-- Data source: PE's ExtractionService.learnedAffixes global (populated
-- by PE's SEND_LEARNED_AFFIXES server packet). Each entry has fields
-- { id, name = "Iron Will IV", learned = true|false, ... }. We mirror
-- only the `learned == true` entries into a lowercase-keyed lookup so
-- per-item membership checks are O(1).
--
-- When ExtractionService is nil (PE addon not loaded), the lookup
-- table stays empty and IsAffixOwnedByItemName returns nil -- callers
-- treat nil as "can't determine" and fall back to non-collection-mode
-- behavior so nothing breaks for non-PE users.
--
-- State lives on _G to keep the main chunk under Lua 5.1's 200-local
-- cap (we've already had to globalize a lot for this reason).
_G.AutoDelete_OwnedAffixes = _G.AutoDelete_OwnedAffixes or {}
_G.AutoDelete_KnownAffixes = _G.AutoDelete_KnownAffixes or {}
_G.AutoDelete_OwnedAffixCount = _G.AutoDelete_OwnedAffixCount or 0

-- Mirror of PE's AFFIX_ALIASES table at extraction.lua:129. PE's
-- internal spell names don't always match the names that appear in
-- item suffixes (e.g. spell "Shield Block IV" -> item suffix "Block
-- IV"; spell "Cold IV" -> item suffix "Precision IV"). PE handles
-- this via GetAffixSearchNames at extraction.lua:184; we must do the
-- same or our suffix-match check returns false on every aliased
-- affix and draws a "missing" dot on items the player actually
-- owns.
--
-- KEEP THIS TABLE IN SYNC with PE's extraction.lua AFFIX_ALIASES and
-- PE creature-family item suffixes. If PE adds/changes an alias, add/change
-- it here too. Version bump forces the mirrored owned-affix map to rebuild
-- after /reload because the map itself lives on _G.
_G.AutoDelete_AffixAliasVersionCurrent = 4
local AUTODELETE_AFFIX_ALIASES = {
	["cold"]            = "precision",
	["enduring flesh"]  = "ironhide",
	["feral grace"]     = "swift footwork",
	["keen strikes"]    = "keen strike",
	["shield block"]    = "block",
	["spirit surge"]    = "inner light",
	["beast"]           = "the beast",
	["beast bane"]      = "the beast",
	["beast slayer"]    = "the beast",
	["dragon"]          = "the dragon",
	["dragonkin"]       = "the dragon",
	["dragonkin bane"]  = "the dragon",
	["dragon slayer"]   = "the dragon",
	["demon"]           = "the demon",
	["demon bane"]      = "the demon",
	["demon slayer"]    = "the demon",
	["elemental"]       = "the elemental",
	["elemental bane"]  = "the elemental",
	["elemental slayer"] = "the elemental",
	["giant"]           = "the giant",
	["giant bane"]      = "the giant",
	["giant slayer"]    = "the giant",
	["mechanical"]      = "the mechanical",
	["mechanical bane"] = "the mechanical",
	["machine"]         = "the machine",
	["machine slayer"]  = "the machine",
	["undead"]          = "the undead",
	["undead bane"]     = "the undead",
	["undead slayer"]   = "the undead",
}

-- Rebuild the owned-affixes lookup from PE's data. Cheap; called from
-- PLAYER_LOGIN, SPELLS_CHANGED, ExtractionUI.OnLearnedAffixesReceived
-- (auto-hook -- see AutoDelete_InstallPEAffixHook below), and on the
-- affixCollectionMode toggle. Idempotent. Returns the count of learned
-- affixes mirrored, useful for a debug print.
function _G.AutoDelete_RefreshOwnedAffixes()
	local map = {}
	local known = {}
	local count = 0
	if _G.ExtractionService and _G.ExtractionService.learnedAffixes then
		for _, entry in ipairs(_G.ExtractionService.learnedAffixes) do
			if entry and entry.name then
				local lname = Normalize(entry.name)
				known[lname] = true
				if entry.learned then
					map[lname] = true
					count = count + 1
				end
				-- Alias expansion: if PE renames this spell for item
				-- naming purposes, also store the renamed form so the
				-- suffix-match check at AutoDelete_IsAffixOwnedByItemName
				-- hits both spellings. Mirrors PE's GetAffixSearchNames
				-- logic at extraction.lua:184.
				local base = lname:match("^(.-)%s+[iv]+$") or lname
				local roman = lname:match("%s+([iv]+)$")
				local alias = AUTODELETE_AFFIX_ALIASES[base]
				if alias then
					local aliasName
					if roman then
						aliasName = alias .. " " .. roman
					else
						aliasName = alias
					end
					aliasName = Normalize(aliasName)
					known[aliasName] = true
					if entry.learned then
						map[aliasName] = true
					end
				end
			end
		end
	end
	_G.AutoDelete_OwnedAffixes = map
	_G.AutoDelete_KnownAffixes = known
	_G.AutoDelete_OwnedAffixCount = count
	_G.AutoDelete_OwnedAffixAliasVersion = _G.AutoDelete_AffixAliasVersionCurrent
	if _G.AutoDelete_DebugSell then
		print(string.format(
			"|cffff8000[AutoDelete DEBUG]|r owned-affix map rebuilt: %d learned affixes mirrored (alias expansion included).",
			count))
	end
	return count
end

function _G.AutoDelete_EnsureOwnedAffixMirror()
	if not _G.ExtractionService or not _G.ExtractionService.learnedAffixes then
		return false
	end
	if _G.AutoDelete_OwnedAffixAliasVersion ~= _G.AutoDelete_AffixAliasVersionCurrent
		or not next(_G.AutoDelete_KnownAffixes or {}) then
		AutoDelete_RefreshOwnedAffixes()
		return true
	end
	return false
end

_G.AutoDelete_LastPEAffixRequestAt = _G.AutoDelete_LastPEAffixRequestAt or 0
local PE_AFFIX_REQUEST_THROTTLE_SECONDS = 5

function _G.AutoDelete_RequestPELearnedAffixes(reason, force)
	local service = _G.ExtractionService
	if type(service) ~= "table" or type(service.RequestLearnedAffixes) ~= "function" then
		return false, "unavailable"
	end

	local affixes = service.learnedAffixes
	if not force and type(affixes) == "table" and next(affixes) ~= nil then
		return false, "has-data"
	end

	local now = GetTime and GetTime() or 0
	local last = _G.AutoDelete_LastPEAffixRequestAt or 0
	if not force and last > 0 and now > 0
		and now - last < PE_AFFIX_REQUEST_THROTTLE_SECONDS then
		return false, "throttled"
	end

	_G.AutoDelete_LastPEAffixRequestAt = now
	local ok, err = pcall(service.RequestLearnedAffixes)
	if not ok then
		if _G.AutoDelete_DebugSell then
			print("|cffff8000[AutoDelete DEBUG]|r PE learned-affix request failed: " .. tostring(err))
		end
		return false, "error"
	end

	if _G.AutoDelete_DebugSell then
		print("|cffff8000[AutoDelete DEBUG]|r requested PE learned-affix packet"
			.. (reason and (" (" .. tostring(reason) .. ")") or "") .. ".")
	end
	return true, "requested"
end

-- Auto-refresh hook: install once at PLAYER_LOGIN. PE's packet handler
-- at extraction_service.lua line 62 rebuilds ExtractionService
-- .learnedAffixes from a server-pushed SEND_LEARNED_AFFIXES packet,
-- THEN calls ExtractionUI.OnLearnedAffixesReceived(). hooksecurefunc on
-- that UI callback gives us a notification the instant PE's table
-- changes -- which is the ONLY time our mirror can be stale -- so we
-- don't need a BAG_UPDATE poll, a manual toggle re-run, or any other
-- manual refresh trigger.
--
-- PE fires SEND_LEARNED_AFFIXES on:
--   1. PLAYER_ENTERING_WORLD (post-login initial fetch)
--   2. Successful extraction (server re-pushes the updated list)
--   3. Any other server-initiated update (rare)
--
-- We can't subscribe via ProjectEbonhold.onEventReceived because that's
-- a SINGLE-callback registry (projectebonhold.lua line 114: assignment,
-- not append), so registering would silently overwrite PE's own handler
-- and break PE's UI. hooksecurefunc is the only safe path.
--
-- Returns true if the hook installed (PE present + ExtractionUI loaded),
-- false otherwise. Idempotent -- second call is a no-op.
_G.AutoDelete_PEAffixHookInstalled = false
function _G.AutoDelete_InstallPEAffixHook()
	if _G.AutoDelete_PEAffixHookInstalled then return true end
	if type(_G.ExtractionUI) ~= "table" then return false end
	if type(_G.ExtractionUI.OnLearnedAffixesReceived) ~= "function" then
		return false
	end
	hooksecurefunc(_G.ExtractionUI, "OnLearnedAffixesReceived", function()
		-- PE just rebuilt learnedAffixes. Mirror it now.
		AutoDelete_RefreshOwnedAffixes()
		-- Missing-affix color is visible even when collection mode is off,
		-- so any ownership refresh can change dots: recognized missing
		-- affixes turn to that color, newly learned affixes return to tier color or
		-- hide if Show/Keep Missing Affix is on.
		if cachedProfile and cachedProfile.showAffixDot ~= false then
			if _G.AutoDelete_RefreshAffixDots then
				_G.AutoDelete_RefreshAffixDots()
			end
		end
		if _G.AutoDelete_DebugSell then
			print("|cffff8000[AutoDelete DEBUG]|r PE affix hook fired -- mirror refreshed.")
		end
	end)
	_G.AutoDelete_PEAffixHookInstalled = true

	if _G.AutoDelete_DebugSell then
		print("|cffff8000[AutoDelete DEBUG]|r installed ExtractionUI.OnLearnedAffixesReceived hook.")
	end
	return true
end

-- Returns true if the given item NAME ends with " of <known-owned-affix>".
-- Returns false if no owned-affix name matches the suffix.
-- Returns nil if PE data hasn't been observed yet (so callers can fall
-- back to the non-collection-mode path instead of incorrectly hiding
-- dots before PE has finished initializing).
function _G.AutoDelete_IsAffixOwnedByItemName(itemName)
	if not itemName then return nil end
	-- nil-vs-empty distinction: if we have no PE data at all, return nil
	-- ("can't determine"). If we have PE data but the item's affix isn't
	-- in it, return false ("not owned").
	if not _G.ExtractionService or not _G.ExtractionService.learnedAffixes then
		return nil
	end
	_G.AutoDelete_EnsureOwnedAffixMirror()
	local lower = Normalize(itemName)
	if _G.AutoDelete_OwnedAffixes[lower] then
		return true
	end
	local directAlias = AUTODELETE_AFFIX_ALIASES[lower]
	if directAlias and _G.AutoDelete_OwnedAffixes[Normalize(directAlias)] then
		return true
	end
	for affixName in pairs(_G.AutoDelete_OwnedAffixes) do
		-- Item names follow "<base item> of <affix name>" so the affix
		-- name appears as a suffix preceded by " of ". Match against the
		-- end of the item name string.
		local suffix = " of " .. affixName
		if #lower >= #suffix and lower:sub(-#suffix) == suffix then
			return true
		end
	end
	return false
end

_G.AutoDelete_MissingAffixColorPresets = {
	red    = { 1.00, 0.231, 0.255 },
	gold   = { 1.00, 0.82, 0.00 },
	mage   = { 0.247, 0.780, 0.922 },
	green  = { 0.20, 1.00, 0.20 },
	purple = { 0.64, 0.21, 0.93 },
}
_G.AutoDelete_MissingAffixColorLabels = {
	red    = "bright red",
	gold   = "gold",
	mage   = "mage blue",
	green  = "green",
	purple = "purple",
	custom = "custom color",
}
_G.AutoDelete_MissingAffixColorScratch = _G.AutoDelete_MissingAffixColorScratch or { 1.00, 0.231, 0.255 }
function _G.AutoDelete_GetMissingAffixColorKey(profile)
	local key = profile and profile.missingAffixColor or DEFAULT_PROFILE.missingAffixColor
	if not _G.AutoDelete_MissingAffixColorPresets[key]
		and key ~= "custom" then
		key = DEFAULT_PROFILE.missingAffixColor
	end
	return key
end
function _G.AutoDelete_GetMissingAffixDotColor(profile)
	if profile and type(profile.missingAffixColorR) == "number"
		and type(profile.missingAffixColorG) == "number"
		and type(profile.missingAffixColorB) == "number" then
		_G.AutoDelete_MissingAffixColorScratch[1] = profile.missingAffixColorR
		_G.AutoDelete_MissingAffixColorScratch[2] = profile.missingAffixColorG
		_G.AutoDelete_MissingAffixColorScratch[3] = profile.missingAffixColorB
		return _G.AutoDelete_MissingAffixColorScratch
	end
	return _G.AutoDelete_MissingAffixColorPresets[_G.AutoDelete_GetMissingAffixColorKey(profile)]
end
function _G.AutoDelete_GetMissingAffixColorLabel(profile)
	return _G.AutoDelete_MissingAffixColorLabels[_G.AutoDelete_GetMissingAffixColorKey(profile)] or "bright red"
end

local function HasAffix(bag, slot)
	-- Phase D cache: @affix@ marker is server-attached to a specific item
	-- instance and never changes mid-session. itemLink is a stable per-
	-- instance key. Cache value: 1-4 on affix hit (carries level for the
	-- dot renderer), false on miss. Skip cache when debug is on so every
	-- call dumps fresh tooltip lines.
	local debug = _G.AutoDelete_DebugSell
	local link = GetContainerItemLink(bag, slot)
	if link and not debug then
		local cached = _G.AutoDelete_TooltipCache.affix[link]
		if cached ~= nil then return cached end
	end
	if debug then
		-- Verbose debug-mode scan: walks the tooltip, prints every
		-- line containing @affix@ so the user can verify the marker
		-- is being seen, then resolves the tier from the item name.
		boeTip:Hide()
		boeTip:SetOwner(boeTipOwner, "ANCHOR_NONE")
		boeTip:ClearLines()
		boeTip:SetBagItem(bag, slot)
		boeTip:Show()
		local n = boeTip:NumLines()
		local nameLine = _G["AutoDelete_BoETipTextLeft1"]
		local tooltipName = nameLine and nameLine:GetText() or nil
		if link then
			_G.AutoDelete_TooltipCache.affixName[link] = tooltipName or GetItemInfo(link)
		end
		local hasAffixMarker = false
		local foundLine = nil
		for i = 1, n do
			local leftFS  = _G["AutoDelete_BoETipTextLeft"  .. i]
			local rightFS = _G["AutoDelete_BoETipTextRight" .. i]
			local leftTxt  = leftFS  and leftFS:GetText()  or nil
			local rightTxt = rightFS and rightFS:GetText() or nil
			if leftTxt and string.find(leftTxt, "@affix@", 1, true) then
				hasAffixMarker = true
				foundLine = "L[" .. i .. "] " .. leftTxt
				break
			end
			if rightTxt and string.find(rightTxt, "@affix@", 1, true) then
				hasAffixMarker = true
				foundLine = "R[" .. i .. "] " .. rightTxt
				break
			end
		end
		boeTip:Hide()
		local foundLevel = false
		if hasAffixMarker then
			local itemName = link and GetItemInfo(link) or nil
			foundLevel = AutoDelete_ExtractAffixLevel(itemName) or 1
			print(string.format(
				"|cffff8000[AutoDelete DEBUG]|r HasAffix bag=%d slot=%d lines=%d name='%s' level=%d%s",
				bag, slot, n, tostring(itemName), foundLevel,
				foundLine and (" | " .. foundLine) or ""))
		else
			local itemName = link and GetItemInfo(link) or nil
			foundLevel = AutoDelete_ExtractKnownAffixLevel(itemName) or false
			if foundLevel then
				print(string.format(
					"|cffff8000[AutoDelete DEBUG]|r HasAffix bag=%d slot=%d lines=%d name='%s' level=%d (known-affix name fallback)",
					bag, slot, n, tostring(itemName), foundLevel))
			else
				print(string.format(
					"|cffff8000[AutoDelete DEBUG]|r HasAffix bag=%d slot=%d lines=%d (no @affix@ marker or known affix suffix)",
					bag, slot, n))
			end
		end
		return foundLevel
	end
	if not link then return false end
	-- Cold path: combined scan also warms boe + soulbound caches for
	-- free. See AutoDelete_ScanBagItemMarkers for the rationale.
	local _, _, level = AutoDelete_ScanBagItemMarkers(bag, slot, link)
	return level
end

function _G.AutoDelete_GetAffixDisplayName(link, bag, slot, fallbackName)
	if link and _G.AutoDelete_TooltipCache and _G.AutoDelete_TooltipCache.affixName then
		local cachedName = _G.AutoDelete_TooltipCache.affixName[link]
		if cachedName and cachedName ~= "" then return cachedName end
	end
	if link and bag and slot then
		boeTip:Hide()
		boeTip:SetOwner(boeTipOwner, "ANCHOR_NONE")
		boeTip:ClearLines()
		boeTip:SetBagItem(bag, slot)
		boeTip:Show()
		local nameLine = _G["AutoDelete_BoETipTextLeft1"]
		local tooltipName = nameLine and nameLine:GetText() or nil
		boeTip:Hide()
		if tooltipName and tooltipName ~= "" then
			_G.AutoDelete_TooltipCache.affixName[link] = tooltipName
			return tooltipName
		end
	end
	return fallbackName or (link and GetItemInfo(link)) or nil
end

-- Wrapped in `do ... end` so the two helper locals don't bump the main
-- chunk past Lua 5.1's 200-local cap; only the global export survives
-- to the outer scope. boeTip and boeTipOwner are upvalues from above.
do

-- HasAffix variant for items NOT in bags (Delete / Sell list entries the
-- user added but isn't currently holding). SetHyperlink shows the item
-- template tooltip, which still gets PE's server-injected @affix@ line
-- because the marker is on the item record. Cheap one-shot scan.
local function HasAffixByLink(link)
	if not link then return false end
	-- Phase D cache: same store as the bag-slot variant. Cache value:
	-- 1-4 on hit (tier), false on miss.
	local cached = _G.AutoDelete_TooltipCache.affix[link]
	if cached ~= nil then return cached end
	-- Scan the item-template tooltip for the @affix@ marker. We only
	-- need to detect PRESENCE here; the actual tier comes from the
	-- item name (PE encodes it as a trailing Roman numeral). See
	-- AutoDelete_ExtractAffixLevel for the name-parsing details.
	boeTip:Hide()
	boeTip:SetOwner(boeTipOwner, "ANCHOR_NONE")
	boeTip:ClearLines()
	boeTip:SetHyperlink(link)
	boeTip:Show()
	local n = boeTip:NumLines()
	local hasAffixMarker = false
	for i = 1, n do
		local leftFS  = _G["AutoDelete_BoETipTextLeft"  .. i]
		local rightFS = _G["AutoDelete_BoETipTextRight" .. i]
		local leftTxt  = leftFS  and leftFS:GetText()  or nil
		local rightTxt = rightFS and rightFS:GetText() or nil
		if leftTxt and string.find(leftTxt, "@affix@", 1, true) then
			hasAffixMarker = true
			break
		end
		if rightTxt and string.find(rightTxt, "@affix@", 1, true) then
			hasAffixMarker = true
			break
		end
	end
	boeTip:Hide()
	local itemName = GetItemInfo(link)
	if not hasAffixMarker then
		local fallbackLevel = AutoDelete_ExtractKnownAffixLevel(itemName) or false
		_G.AutoDelete_TooltipCache.affix[link] = fallbackLevel
		return fallbackLevel
	end
	-- Marker present: resolve the tier from the item name. Default to
	-- tier 1 if the name has no trailing Roman numeral (still better
	-- than hiding the dot entirely).
	local level = AutoDelete_ExtractAffixLevel(itemName) or 1
	_G.AutoDelete_TooltipCache.affix[link] = level
	return level
end

-- Audit the user's Delete + Sell lists for items carrying the @affix@
-- tooltip marker. Doesn't modify the lists (explicit user-list entries
-- are user intent); just surfaces a chat summary so the user can review
-- and decide. Capped at 10 reported items per list so a 400-line list
-- doesn't spam chat; remainder is summarized by count.
local function AuditAffixOnLists(profile)
	if not profile then return end
	local function collectAffix(listText)
		local affixed = {}
		for line in string.gmatch(listText or "", "[^\r\n]+") do
			local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
			if trimmed ~= "" then
				local id = tonumber(trimmed:match("item:(%d+)"))
				if id then
					local _, link = GetItemInfo("item:" .. id)
					if link and HasAffixByLink(link) then
						table.insert(affixed, link)
					end
				end
			end
		end
		return affixed
	end

	local deleteAffixed = collectAffix(profile.listText)
	local sellAffixed   = collectAffix(profile.sellListText)
	local total = #deleteAffixed + #sellAffixed

	if total == 0 then
		print("|cffff8000[AutoDelete]|r Affix audit: no affixed items on your Delete or Sell lists.")
		return
	end

	local function summarize(name, affixed)
		if #affixed == 0 then return end
		local shown = {}
		for i = 1, math.min(#affixed, 10) do
			table.insert(shown, affixed[i])
		end
		print(string.format(
			"|cffff8000[AutoDelete]|r %d affixed item(s) on your %s list: %s%s",
			#affixed, name, table.concat(shown, " "),
			(#affixed > 10) and (" (+" .. (#affixed - 10) .. " more)") or ""))
	end
	summarize("Delete", deleteAffixed)
	summarize("Sell",   sellAffixed)
end

_G.AutoDelete_AuditAffixOnLists = AuditAffixOnLists

-- Scan + display the player's learned and unlearned affixes. Two jobs in one call:
--   1. Refresh the owned-affix mirror from PE's current data (same call
--      Show/Keep Missing Affix makes internally) so we're not displaying stale
--      info if PE's table changed since the last hook fire.
--   2. Build tier-grouped roster strings and hand them off to the
--      Learned Affixes popup (lives in Options.lua) for display.
-- Output goes to a scrollable themed window, not the chat frame -- the
-- user explicitly asked for a window so this function never prints unless
-- the UI side failed to load (defensive fallback).
local function ScanLearnedAffixes()
	-- Step 1: refresh the mirror. Safe to call any time; idempotent.
	if _G.AutoDelete_RefreshOwnedAffixes then
		_G.AutoDelete_RefreshOwnedAffixes()
	end

	-- Defensive: if the UI popup didn't load (Options.lua bailed early or
	-- the global isn't registered yet), we have nowhere to display. Fall
	-- back to a single chat line so the user knows the click did something
	-- and what to investigate.
	local showFn = _G.AutoDelete_ShowLearnedAffixesWindow
	if type(showFn) ~= "function" then
		print("|cffff8000[AutoDelete]|r Learned Affixes window not available. "
			.. "Options panel may not have finished loading -- try again in a moment.")
		return
	end

	-- Helper to build "|cff...COLOR HEX...|r text |r" wrapped strings so the
	-- popup's FontString renders tier headers in legendary orange. C_ACCENT
	-- here is fixed in chat color escape form so it matches the addon's
	-- chrome without re-importing the table from Options.lua.
	local ACCENT_OPEN  = "|cffff8000"
	local DIM_OPEN     = "|cff8a8a8a"
	local COLOR_CLOSE  = "|r"

	-- Empty / error states render as their own in-window message rather
	-- than chat noise. Keeps the user experience consistent regardless of
	-- whether PE is loaded.
	if type(_G.ExtractionService) ~= "table"
		or type(_G.ExtractionService.learnedAffixes) ~= "table" then
		local requested = AutoDelete_RequestPELearnedAffixes
			and AutoDelete_RequestPELearnedAffixes("learned-affixes-scan", false)
		showFn(ACCENT_OPEN .. "Project Ebonhold not loaded" .. COLOR_CLOSE
			.. "\n\nNo learned-affix data is available yet. Open the "
			.. "Extraction UI in-game once to trigger data sync, then click "
			.. "Update Affix List again."
			.. (requested and "\n\nAutoDelete also requested a fresh sync from Project Ebonhold." or ""))
		return
	end

	local function addAffix(byTier, name)
		-- Group by Roman-numeral tier so a 40-entry roster reads as a handful
		-- of headed sections instead of a wall of text. Affix names look like
		-- "Iron Will IV" -- strip the trailing roman and use it as a key.
		local base, roman = name:match("^(.-)%s+([IVX]+)$")
		if not base then
			base, roman = name, "?"
		end
		byTier[roman] = byTier[roman] or {}
		table.insert(byTier[roman], base)
	end

	local function buildRosterText(byTier, total, learned)
		if total == 0 then
			if learned then
				local requested = AutoDelete_RequestPELearnedAffixes
					and AutoDelete_RequestPELearnedAffixes("learned-affixes-empty", false)
				return ACCENT_OPEN .. "No learned affixes found" .. COLOR_CLOSE
					.. "\n\nEither this character has not learned any affixes yet, "
					.. "or Project Ebonhold has not received the SEND_LEARNED_AFFIXES "
					.. "packet yet. Try opening the Extraction UI once, then re-scan."
					.. (requested and "\n\nAutoDelete also requested a fresh sync from Project Ebonhold." or "")
			end
			return ACCENT_OPEN .. "No unlearned affixes found" .. COLOR_CLOSE
				.. "\n\nProject Ebonhold reports every known affix as learned "
				.. "for this character."
		end

		-- Build the body string. Summary first, then one section per tier in
		-- the canonical order, with affixes one-per-line and alphabetically
		-- sorted within each section. Catch-all loop at the end picks up any
		-- unexpected tier (e.g. PE adds VI later, or a name with no roman
		-- suffix landed in byTier["?"]).
		local lines = {}
		local rows = {}
		local label = learned and "learned" or "unlearned"
		local function addRow(kind, text, copyText)
			table.insert(lines, text or "")
			table.insert(rows, { kind = kind, text = text or "", copyText = copyText })
		end

		addRow("summary", string.format("%s%d %s affix(es) mirrored from PE.%s",
			DIM_OPEN, total, label, COLOR_CLOSE))
		addRow("blank", "")

		local function emitTier(tier, group)
			table.sort(group)
			-- Display-only special case: affixes with no Roman-numeral suffix
			-- get bucketed under the "?" key during the grouping pass, but in
			-- the rendered list they read as "Weapon Affix" (per user feedback).
			-- The underlying bucket key stays "?" so the catch-all loop after
			-- the canonical tiers still picks them up alongside any other
			-- unexpected tier code; only the header label changes.
			local header
			if tier == "?" then
				header = string.format("%sWeapon Affix (%d)%s",
					ACCENT_OPEN, #group, COLOR_CLOSE)
			else
				header = string.format("%sTier %s (%d)%s",
					ACCENT_OPEN, tier, #group, COLOR_CLOSE)
			end
			addRow("header", header)
			for _, name in ipairs(group) do
				addRow("affix", "    " .. name, name)
			end
			addRow("blank", "")
		end

		local tierOrder = { "I", "II", "III", "IV", "V" }
		for _, t in ipairs(tierOrder) do
			local group = byTier[t]
			if group and #group > 0 then
				emitTier(t, group)
				byTier[t] = nil
			end
		end

		local extraTiers = {}
		for tier, group in pairs(byTier) do
			if #group > 0 then
				table.insert(extraTiers, tier)
			end
		end
		table.sort(extraTiers)
		for _, tier in ipairs(extraTiers) do
			emitTier(tier, byTier[tier])
		end

		-- Drop the trailing blank line so the last tier doesn't render with a
		-- dead-space gap at the bottom of the scroll content.
		if lines[#lines] == "" then
			lines[#lines] = nil
			rows[#rows] = nil
		end

		return table.concat(lines, "\n"), rows
	end

	local learnedByTier, unlearnedByTier = {}, {}
	local learnedTotal, unlearnedTotal = 0, 0
	local knownTotal = 0
	for _, entry in ipairs(_G.ExtractionService.learnedAffixes) do
		if entry and entry.name then
			knownTotal = knownTotal + 1
			if entry.learned then
				addAffix(learnedByTier, entry.name)
				learnedTotal = learnedTotal + 1
			else
				addAffix(unlearnedByTier, entry.name)
				unlearnedTotal = unlearnedTotal + 1
			end
		end
	end

	if knownTotal == 0 then
		showFn(ACCENT_OPEN .. "No affixes found" .. COLOR_CLOSE
			.. "\n\nProject Ebonhold has not populated any affix entries yet. "
			.. "Try opening the Extraction UI once, then re-scan.")
		return
	end

	local learnedText, learnedRows = buildRosterText(learnedByTier, learnedTotal, true)
	local unlearnedText, unlearnedRows = buildRosterText(unlearnedByTier, unlearnedTotal, false)

	showFn({
		learned = learnedText,
		unlearned = unlearnedText,
		learnedRows = learnedRows,
		unlearnedRows = unlearnedRows,
		learnedCount = learnedTotal,
		unlearnedCount = unlearnedTotal,
		defaultTab = (unlearnedTotal > 0) and "unlearned" or "learned",
	})
end

_G.AutoDelete_ScanLearnedAffixes = ScanLearnedAffixes

end  -- end of audit `do` block

-- ============================================================================
-- Affix dot indicator on bag slot buttons
-- ============================================================================
-- Affix-level marker in the bottom-left of every bag slot that contains
-- an affixed item. Color encodes the affix level (1-4) using the WoW
-- item-quality palette so the dot reads the same way as item borders:
--   1 white (common), 2 green (uncommon), 3 blue (rare), 4 purple (epic).
--
-- Cache by item LINK so we don't run a tooltip scan every time
-- ContainerFrame_Update fires (which is often). When an item moves
-- between slots its link is unchanged, so we get a cache hit. When the
-- slot empties or holds a different item, the new link triggers a fresh
-- HasAffix scan. Cache stores the level (1-4) on hit, false on miss.
local affixLinkCache = {}

-- ============================================================================
-- Deferred affix-scan queue
-- ============================================================================
-- Each cold HasAffix call costs ~5-15ms on PE: SetBagItem on our hidden
-- tooltip frame, NumLines walk, dozens of GetText calls. Doing 100 cold
-- scans in one frame (the typical "AOE loot just dropped 100 items"
-- pattern) produces a visible 0.5-1.5s freeze even with AutoDelete's
-- master toggle OFF, because the affix-dot renderer still wants to
-- classify every fresh slot.
--
-- The queue spreads the cost: cache misses from the dot-rendering path
-- (UpdateAffixDotForFrame and the ElvUI B:UpdateSlot hook) enqueue and
-- return false (no dot yet); the scanner OnUpdate pops a small batch
-- per tick and runs the real HasAffix. The button is updated when its
-- scan completes, as long as the slot still holds the same link
-- (otherwise the new occupant has its own queue entry from the natural
-- bag-refresh path).
--
-- Synchronous callers (IsAffixProtected from DeleteItems/SellItems,
-- ProcessScan from the settings panel) keep the existing behavior: they
-- omit the `button` argument to ClassifyAffixByLink and pay the cold
-- scan inline. Those paths are already throttled by DELETE/SELL_BATCH
-- size and the 0.5s scan-tick interval, so the per-tick cost is bounded.
_G.AutoDelete_affixScanQueue       = {}
_G.AutoDelete_AFFIX_SCAN_PER_TICK  = 3      -- cold scans per processed tick
_G.AutoDelete_AFFIX_SCAN_INTERVAL  = 0.05   -- seconds between processed ticks (60 scans/sec budget)
_G.AutoDelete_nextAffixScanAt      = 0      -- GetTime() of next eligible scan tick

function _G.AutoDelete_QueueAffixScan(link, bag, slot, button)
	if not link or not button then return end
	-- De-dupe: if the same button is already queued for this link
	-- (common during ContainerFrame_Update bursts that refire for the
	-- same bag), skip re-queueing. Linear scan is fine -- the queue
	-- is small (drained ~60/sec, fills at the rate of new items
	-- entering bags) and we early-break on first match.
	for i = 1, #AutoDelete_affixScanQueue do
		local entry = AutoDelete_affixScanQueue[i]
		if entry.button == button and entry.link == link then return end
	end
	table.insert(AutoDelete_affixScanQueue, { link = link, bag = bag, slot = slot, button = button })
	-- v3.20 spike debug: count items queued for cold affix scan this frame.
	if _G.AutoDelete_SpikeDebug then
		local c = _G.AutoDelete_SpikeCounters
		local sess = _G.AutoDelete_SpikeSession
		c.axQueued    = (c.axQueued or 0) + 1
		sess.axQueued = (sess.axQueued or 0) + 1
	end
end

-- Called from scanner:OnUpdate every frame. No-op when the queue is
-- empty (the common steady-state case). When non-empty, processes up to
-- AutoDelete_AFFIX_SCAN_PER_TICK entries per AutoDelete_AFFIX_SCAN_INTERVAL window.
function _G.AutoDelete_ProcessAffixScanQueue(now)
	if #AutoDelete_affixScanQueue == 0 then return end
	if now < AutoDelete_nextAffixScanAt then return end
	local _p = AutoDelete_PerfBegin("AutoDelete_ProcessAffixScanQueue")
	AutoDelete_nextAffixScanAt = now + AutoDelete_AFFIX_SCAN_INTERVAL
	local budget = AutoDelete_AFFIX_SCAN_PER_TICK
	while budget > 0 and #AutoDelete_affixScanQueue > 0 do
		local entry = table.remove(AutoDelete_affixScanQueue, 1)
		budget = budget - 1
		-- v3.20 spike debug: count actual cold affix scans this frame
		-- (separate from axQueued so we can see the queue's drain rate).
		if _G.AutoDelete_SpikeDebug then
			local c = _G.AutoDelete_SpikeCounters
			local sess = _G.AutoDelete_SpikeSession
			c.axRan    = (c.axRan or 0) + 1
			sess.axRan = (sess.axRan or 0) + 1
		end
		-- Validate: did the slot's occupant change while queued? If so,
		-- skip the scan (the new occupant has its own queue entry from
		-- the natural ContainerFrame_Update / B:UpdateSlot path).
		local currentLink = GetContainerItemLink(entry.bag, entry.slot)
		if currentLink == entry.link then
			-- Combined scan: ONE tooltip walk populates affix +
			-- soulbound + boe caches. Critical for the
			-- FindDisenchantTarget path -- when the deferred button
			-- refresh fires 150ms later, the soulbound/boe caches it
			-- needs are already warm from this queue's processing.
			local _, _, level = AutoDelete_ScanBagItemMarkers(entry.bag, entry.slot, entry.link)
			affixLinkCache[entry.link] = level
			-- Resolve the final (level, color) through DecideDot so the
			-- queue path honors affixCollectionMode + ownership the same
			-- way the live ContainerFrame_Update / B:UpdateSlot hooks do.
			-- Previously we drew tier-color dots here unconditionally,
			-- which produced wrong dots on owned items (should be hidden)
			-- and tier-color instead of the selected color on missing items, with the
			-- per-button link-cache short-circuit then locking the wrong
			-- dot in until the next item move / version bump.
			local effLevel, effColor = _G.AutoDelete_DecideDot(
				entry.link, entry.bag, entry.slot, nil)
			AutoDelete_SetButtonAffixDot(entry.button, effLevel, effColor)
			-- Stamp the button's per-slot cache so the next natural
			-- ContainerFrame_Update / B:UpdateSlot pass sees a cache HIT
			-- and short-circuits (we just drew the authoritative dot).
			-- Without this, the very next refresh sees a version mismatch
			-- and re-runs DecideDot, which is harmless but wasteful.
			entry.button._autoDeleteCachedLink   = entry.link
			entry.button._autoDeleteAffixVersion = affixDotVersion
		end
	end
	AutoDelete_PerfEnd("AutoDelete_ProcessAffixScanQueue", _p)
end

local function ClassifyAffixByLink(link, bag, slot, button)
	if not link then return false end
	local cached = affixLinkCache[link]
	if cached ~= nil then return cached end
	-- Cache miss. If the caller passed a button (= dot-rendering path),
	-- defer to the queue and return false (no dot shown yet). The
	-- queue processor will set the dot when the scan completes.
	-- Callers WITHOUT a button (IsAffixProtected, ProcessScan) get
	-- synchronous behavior -- they're invoked from already-throttled
	-- delete/sell scan ticks where the per-call cost is bounded.
	if button then
		AutoDelete_QueueAffixScan(link, bag, slot, button)
		return false
	end
	local level = HasAffix(bag, slot)
	affixLinkCache[link] = level
	return level
end

-- Color table indexed by affix level. Values are the standard WoW item-
-- quality RGB tints so a player who already reads quality borders
-- instinctively understands the dot color. Levels outside 1-5 fall back
-- to level 1 (white) -- safe default for unrecognized PE name formats.
-- Tier 5 is rare on PE but supported; coloring it WoW-legendary orange
-- (#FF8000) matches PE's own affix-tier conventions in extraction.lua.
local AFFIX_DOT_COLORS = {
	[1] = { 1.00, 1.00, 1.00 },   -- #FFFFFF white   (common)
	[2] = { 0.12, 1.00, 0.00 },   -- #1EFF00 green   (uncommon)
	[3] = { 0.00, 0.44, 0.87 },   -- #0070DD blue    (rare)
	[4] = { 0.64, 0.21, 0.93 },   -- #A335EE purple  (epic)
	[5] = { 1.00, 0.50, 0.00 },   -- #FF8000 orange  (legendary)
}
-- 9px dot inside a 12px black backing ring. Sizes were 12+16 in v3.19;
-- shrunk to 9+12 in v3.20 because the larger dot covered too much of
-- the item icon. The 4:3 ratio between dot and backing keeps the
-- contrast frame visible without dominating the slot. The colored dot is
-- center-anchored inside the backing so odd/even pixel sizes do not leave
-- a visible off-center margin.
local AFFIX_DOT_SIZE         = 9
local AFFIX_DOT_BACKING_SIZE = 12
_G.AutoDelete_ElvUIBindTypeYOffset  = 0
_G.AutoDelete_ElvUIItemLevelYOffset = 1
-- Custom dot texture shipped with the addon. 32x32 RGBA TGA with a white
-- anti-aliased filled circle on transparent background. Tinting via
-- SetVertexColor produces a clean colored dot. Used instead of a Blizzard
-- built-in because Interface\Common\Indicator-* is post-3.3.5 and doesn't
-- exist on PE clients.
local AFFIX_DOT_TEXTURE = "Interface\\AddOns\\AutoDelete\\textures\\dot.tga"

function _G.AutoDelete_SetButtonAffixDot(button, affixLevel, colorOverride)
	if not button then return end
	-- Respect user preference. When the dot is toggled off, treat every
	-- slot as "no affix" so any previously-drawn dot/backing gets hidden.
	if cachedProfile and cachedProfile.showAffixDot == false then
		affixLevel = false
	end
	local dot = button._autoDeleteAffixDot
	local back = button._autoDeleteAffixBacking
	if affixLevel then
		-- Color comes from colorOverride if provided (missing-affix
		-- path uses the profile color); otherwise pick the tier
		-- color. Fall back to level 1 (white) for unrecognized tiers.
		local color = colorOverride
			or AFFIX_DOT_COLORS[affixLevel]
			or AFFIX_DOT_COLORS[1]
		-- Backing goes on ARTWORK and the colored dot goes on OVERLAY. Anchor
		-- both to the item slot center; do not move ElvUI's BoE/iLvl text.
		if not back then
			back = button:CreateTexture(nil, "ARTWORK")
			back:SetTexture(AFFIX_DOT_TEXTURE)
			back:SetSize(AFFIX_DOT_BACKING_SIZE, AFFIX_DOT_BACKING_SIZE)
			button._autoDeleteAffixBacking = back
		end
		if back.SetDrawLayer then back:SetDrawLayer("ARTWORK") end
		back:ClearAllPoints()
		back:SetPoint("CENTER", button, "CENTER", 0, 0)
		back:SetVertexColor(0, 0, 0, 1)
		back:Show()
		-- Colored dot on top. Use OVERLAY while the backing stays ARTWORK;
		-- this is more reliable on 3.3.5 than relying on the 4th
		-- CreateTexture sublevel argument. We re-apply SetVertexColor on
		-- every call (not just on first creation) because the same button can
		-- be reused across items of different affix levels as the player moves
		-- items between slots; the dot must recolor immediately, not wait for
		-- a frame teardown.
		if not dot then
			dot = button:CreateTexture(nil, "OVERLAY")
			dot:SetTexture(AFFIX_DOT_TEXTURE)
			dot:SetSize(AFFIX_DOT_SIZE, AFFIX_DOT_SIZE)
			button._autoDeleteAffixDot = dot
		end
		dot:ClearAllPoints()
		dot:SetPoint("CENTER", back, "CENTER", 0, 0)
		if dot.SetDrawLayer then dot:SetDrawLayer("OVERLAY") end
		dot:SetVertexColor(color[1], color[2], color[3], 1)
		dot:Show()
	else
		if dot then dot:Hide() end
		if back then back:Hide() end
	end
end

function _G.AutoDelete_ApplyElvUIBagTextNudge(slot)
	if not slot or not _G.ElvUI then return end
	if slot.bindType and slot.bindType.ClearAllPoints and slot.bindType.Point then
		slot.bindType:ClearAllPoints()
		slot.bindType:Point("TOP", 0, _G.AutoDelete_ElvUIBindTypeYOffset)
	end
	if slot.itemLevel and slot.itemLevel.ClearAllPoints and slot.itemLevel.Point then
		slot.itemLevel:ClearAllPoints()
		slot.itemLevel:Point("BOTTOMRIGHT", -1, _G.AutoDelete_ElvUIItemLevelYOffset)
	end
end

-- Per-frame refresh-skip version counter. Bumped by RefreshAffixDots
-- (the toggle path) so that the link-equality short-circuit below
-- still updates dots when the showAffixDot setting flips, even if the
-- underlying item link in each slot is unchanged. Buttons carry their
-- last-seen version in button._autoDeleteAffixVersion; mismatch forces
-- a full AutoDelete_SetButtonAffixDot rebuild for that slot.
local affixDotVersion = 0

-- Centralizes the "what dot do we draw for this slot?" decision so the
-- Blizzard bag hook and the ElvUI B:UpdateSlot hook share one logic
-- path. Returns (affixLevel, colorOverride) suitable for direct pass
-- into AutoDelete_SetButtonAffixDot:
--   * affixLevel = 1-5 or false (false hides the dot)
--   * colorOverride = nil (use tier color from AFFIX_DOT_COLORS) or
--     a {r,g,b} table forcing a specific color
--
-- Decision tree:
--   no marker / showAffixDot off       -> (false, nil)  hide
--   PE data unknown                    -> (tier, nil)   tier color
--   collection OFF, affix is owned     -> (tier, nil)   tier color
--   collection OFF, affix is missing   -> (tier, color) selected missing color
--   collection ON, affix is owned      -> (false, nil)  hide (dup)
--   collection ON, affix is missing    -> (tier, color) selected missing color
--
-- Globalized so the deferred-scan queue (ProcessAffixScanQueue, declared
-- earlier in the file) can call it without a forward-reference dance.
-- The locals-cap pressure on the main chunk also makes a global cheaper
-- than a forward-declared file-local.
function _G.AutoDelete_DecideDot(link, bag, slot, button)
	if not link then return false, nil end
	if cachedProfile and cachedProfile.showAffixDot == false then
		return false, nil
	end
	-- Pass `button` so cache misses defer to the rate-limited scan
	-- queue instead of a synchronous tooltip walk.
	local tier = ClassifyAffixByLink(link, bag, slot, button)
	if not tier then return false, nil end

	-- If PE ownership data is available, missing affixes should always
	-- use the selected attention dot. Show/Keep Missing Affix only changes
	-- what happens to owned affixes: hide them instead of tier-coloring
	-- them. If PE data is not ready yet, keep the tier color so dots do
	-- not silently disappear during PE's startup window.
	local itemName = _G.AutoDelete_GetAffixDisplayName
		and _G.AutoDelete_GetAffixDisplayName(link, bag, slot, GetItemInfo(link))
		or GetItemInfo(link)
	local owned = AutoDelete_IsAffixOwnedByItemName(itemName)
	if owned == nil then
		return tier, nil
	end
	if owned then
		if cachedProfile and cachedProfile.affixCollectionMode then
			-- User already has this affix at this tier; suppress dot so
			-- duplicates blend with regular sell/delete-eligible items.
			return false, nil
		end
		return tier, nil
	end
	-- Missing affix -> selected attention dot regardless of tier.
	return tier, _G.AutoDelete_GetMissingAffixDotColor(cachedProfile)
end

function _G.AutoDelete_GetAffixKeyForItemName(itemName)
	if not itemName or not _G.ExtractionService or not _G.ExtractionService.learnedAffixes then
		return nil
	end
	_G.AutoDelete_EnsureOwnedAffixMirror()
	local lower = Normalize(itemName)
	if _G.AutoDelete_KnownAffixes[lower] then
		return lower
	end
	local directAlias = AUTODELETE_AFFIX_ALIASES[lower]
	if directAlias then
		local aliasKey = Normalize(directAlias)
		if _G.AutoDelete_KnownAffixes[aliasKey] then
			return aliasKey
		end
	end
	local best = nil
	for affixName in pairs(_G.AutoDelete_KnownAffixes or {}) do
		local suffix = " of " .. affixName
		if #lower >= #suffix and lower:sub(-#suffix) == suffix then
			if not best or #affixName > #best then
				best = affixName
			end
		end
	end
	return best
end

function _G.AutoDelete_IsSingleAffixSlot(itemClass, equipSlot)
	if not equipSlot or not GEAR_SLOTS[equipSlot] then return false end
	return itemClass == "Armor" or itemClass == "Weapon"
end

function _G.AutoDelete_GetMissingAffixKeyForSlot(profile, bag, slot, link, itemName, itemClass, equipSlot)
	if not profile or profile.keepSingleMissingAffix ~= true then return nil end
	if not _G.AutoDelete_IsSingleAffixSlot(itemClass, equipSlot) then return nil end
	if not HasAffix(bag, slot) then return nil end
	local owned = AutoDelete_IsAffixOwnedByItemName(itemName)
	if owned ~= false then return nil end
	return _G.AutoDelete_GetAffixKeyForItemName(itemName)
end

function _G.AutoDelete_BuildSingleAffixPlan(profile, keepIDs, keepNames)
	if not profile or profile.keepSingleMissingAffix ~= true then return nil end
	local byAffix = {}
	local slots = {}
	local hasExtras = false

	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			local _, _, locked, _, _, _, link = GetContainerItemInfo(bag, slot)
			if link and not locked then
				local name, _, quality, ilvl, _, itemClass, _, _, equipSlot = GetItemInfo(link)
				local key = _G.AutoDelete_GetMissingAffixKeyForSlot(profile, bag, slot, link, name, itemClass, equipSlot)
				if key then
					local id = GetItemIDFromLink(link)
					local onKeep = _G.AutoDelete_IsWhitelistedFast(keepIDs or {}, keepNames or {}, id, name)
					local rec = {
						bag = bag,
						slot = slot,
						id = id,
						name = name,
						quality = quality or 0,
						ilvl = ilvl or 0,
						affixKey = key,
						onKeep = onKeep,
					}
					byAffix[key] = byAffix[key] or { items = {}, keepCount = 0 }
					table.insert(byAffix[key].items, rec)
					if onKeep then byAffix[key].keepCount = byAffix[key].keepCount + 1 end
				end
			end
		end
	end

	for affixKey, group in pairs(byAffix) do
		local items = group.items
		if #items >= 1 then
			local keeper = nil
			if group.keepCount == 0 then
				for _, rec in ipairs(items) do
					if not keeper
						or rec.ilvl > keeper.ilvl
						or (rec.ilvl == keeper.ilvl and rec.quality > keeper.quality)
						or (rec.ilvl == keeper.ilvl and rec.quality == keeper.quality
							and (rec.bag < keeper.bag or (rec.bag == keeper.bag and rec.slot < keeper.slot))) then
						keeper = rec
					end
				end
			end
			for _, rec in ipairs(items) do
				local slotKey = rec.bag .. ":" .. rec.slot
				local extra = false
				if group.keepCount > 0 then
					extra = not rec.onKeep
				else
					extra = rec ~= keeper
				end
				slots[slotKey] = {
					extra = extra,
					affixKey = affixKey,
					count = #items,
					keepCount = group.keepCount,
				}
				if extra then hasExtras = true end
			end
		end
	end

	return { slots = slots, hasExtras = hasExtras }
end

local function UpdateAffixDotForFrame(frame)
	local _p = AutoDelete_PerfBegin("UpdateAffixDotForFrame")
	-- v3.20 spike debug: count Blizzard ContainerFrame_Update hook fires
	-- against updSlot so the per-frame counter reflects total bag-slot
	-- work from ALL sources (ours + Blizzard + ElvUI). Inline check
	-- because this fires per-slot during bag rebuilds.
	if _G.AutoDelete_SpikeDebug then
		local c = _G.AutoDelete_SpikeCounters
		local sess = _G.AutoDelete_SpikeSession
		c.updSlot    = (c.updSlot or 0) + 1
		sess.updSlot = (sess.updSlot or 0) + 1
	end
	if not frame then AutoDelete_PerfEnd("UpdateAffixDotForFrame", _p); return end
	-- Visibility short-circuit. Blizzard fires ContainerFrame_Update on
	-- ALL default container frames during a bag refresh storm, even if
	-- the frame is hidden (which is the common case when ElvUI or
	-- another bag addon owns the visible UI). Running a full slot walk
	-- for an off-screen frame is pure waste -- in a 100-item AOE loot
	-- burst it accounted for the bulk of our per-event cost on ElvUI
	-- setups. The ElvUI side has its own hook (B:UpdateSlot) so we
	-- don't lose coverage by gating here.
	if not frame:IsShown() then return end
	local name = frame:GetName()
	if not name then return end
	local bag = frame:GetID()
	local size = frame.size or 0
	-- ContainerFrame slot buttons are reverse-indexed in their names
	-- (button "Item1" is the LAST slot visually).
	for slot = 1, size do
		local button = _G[name .. "Item" .. (size - slot + 1)]
		if button then
			local link = GetContainerItemLink(bag, slot)
			-- Per-slot short-circuit: if the link hasn't changed AND
			-- the affix-dot version hasn't bumped, skip the whole
			-- DecideDot + AutoDelete_SetButtonAffixDot pipeline. Most
			-- slots in a bag don't change during a single loot event,
			-- so this skips ~90% of calls in the burst case.
			if button._autoDeleteCachedLink ~= link
				or button._autoDeleteAffixVersion ~= affixDotVersion then
				button._autoDeleteCachedLink   = link
				button._autoDeleteAffixVersion = affixDotVersion
				local level, color = _G.AutoDelete_DecideDot(link, bag, slot, button)
				AutoDelete_SetButtonAffixDot(button, level, color)
			end
		end
	end
	AutoDelete_PerfEnd("UpdateAffixDotForFrame", _p)
end

-- Install hook so dots refresh whenever Blizzard updates a bag frame.
-- hooksecurefunc preserves any other addon's hook on this function.
if ContainerFrame_Update then
	hooksecurefunc("ContainerFrame_Update", UpdateAffixDotForFrame)
end

-- Exposed so Options.lua can force an immediate refresh when the user
-- toggles the affix-dot setting (otherwise dots persist until the next
-- natural bag event). Walks visible default Blizzard bag frames AND
-- pokes ElvUI's bag refresh if loaded. Bumps affixDotVersion so the
-- per-slot link-cache short-circuit above (and the matching one in
-- the ElvUI B:UpdateSlot hook below) still re-runs AutoDelete_SetButtonAffixDot
-- on every slot even when the item link is unchanged.
--
-- WARNING: do NOT call this function from BAG_UPDATE or any other
-- per-event path. ElvUI's B:UpdateAllBagSlots() is a full bag-UI
-- rebuild that costs >100ms per call. A previous build invoked this
-- inline on every BAG_UPDATE and the result was 1 FPS during 100-item
-- delete bursts. The natural ContainerFrame_Update / B:UpdateSlot
-- hooks handle live bag changes cheaply via the per-slot caches.
function _G.AutoDelete_RefreshAffixDots()
	affixDotVersion = affixDotVersion + 1
	for i = 1, (NUM_CONTAINER_FRAMES or 12) do
		local frame = _G["ContainerFrame" .. i]
		if frame and frame:IsShown() then
			UpdateAffixDotForFrame(frame)
		end
	end
	pcall(function()
		if not _G.ElvUI then return end
		local E = _G.ElvUI[1]
		if not E or not E.GetModule then return end
		local B = E:GetModule("Bags")
		if B and B.UpdateAllBagSlots then B:UpdateAllBagSlots() end
	end)
end

-- ElvUI bag dot support. Prefer the Blizzard ContainerFrame_Update path
-- above; this hook is only a guarded compatibility layer for ElvUI's
-- replacement bag UI, which does not repaint through the default container
-- frames. Has to be called AFTER ElvUI has loaded, so we invoke it from the
-- post-login AfterDelay block alongside CreateElvUIBagButton.
local function InstallElvUIAffixDotHook()
	-- Bail-out chain (any failure = silently skip ElvUI integration,
	-- default Blizzard bag dots still work via the ContainerFrame_Update
	-- hook installed above):
	--   (1) ElvUI not loaded at all
	--   (2) ElvUI loaded but malformed (no E or no GetModule)
	--   (3) Bags module missing / API changed (no UpdateSlot)
	-- The whole body is also wrapped in pcall so any unexpected error
	-- during hook install is swallowed without breaking AutoDelete.
	pcall(function()
		if not _G.ElvUI then return end                          -- (1)
		local E = _G.ElvUI[1]
		if not E or type(E) ~= "table" or not E.GetModule then return end  -- (2)
		local ok, B = pcall(E.GetModule, E, "Bags")
		if not ok or not B or not B.UpdateSlot then return end   -- (3)

		hooksecurefunc(B, "UpdateSlot", function(self, frame, bagID, slotID)
			-- v3.20 spike debug: count ElvUI per-slot repaint fires.
			-- Bumped BEFORE the disabled-gate below so the counter still
			-- reflects how often ElvUI calls UpdateSlot during the test,
			-- regardless of whether we do any AutoDelete work.
			if _G.AutoDelete_SpikeDebug then
				local c = _G.AutoDelete_SpikeCounters
				local sess = _G.AutoDelete_SpikeSession
				c.updSlot    = (c.updSlot or 0) + 1
				sess.updSlot = (sess.updSlot or 0) + 1
			end
			-- v3.20 A/B gate (set via /del elvuihook off): skip ALL
			-- AutoDelete work in this hook to isolate whether our
			-- per-slot DecideDot/SetButtonAffixDot work is amplifying
			-- ElvUI's per-pickup stutter. Placed BEFORE PerfBegin so
			-- attribMs doesn't include the skipped path; the test
			-- frame's attribMs reflects only the work we actually did.
			if _G.AutoDelete_ElvUIHookDisabled then return end

			local _p = AutoDelete_PerfBegin("ElvUI:UpdateSlot hook")
			if not frame or not frame.Bags then AutoDelete_PerfEnd("ElvUI:UpdateSlot hook", _p); return end
			local bagFrame = frame.Bags[bagID]
			if not bagFrame then AutoDelete_PerfEnd("ElvUI:UpdateSlot hook", _p); return end
			local slot = bagFrame[slotID]
			if not slot then AutoDelete_PerfEnd("ElvUI:UpdateSlot hook", _p); return end
			_G.AutoDelete_ApplyElvUIBagTextNudge(slot)
			-- Bank/reagent slots have bagID outside the 0..4 player-bag range;
			-- skip those (auto-rules don't act on bank contents anyway).
			if bagID < 0 or bagID > 4 then AutoDelete_PerfEnd("ElvUI:UpdateSlot hook", _p); return end
			local link = GetContainerItemLink(bagID, slotID)
			-- Per-slot short-circuit: mirrors UpdateAffixDotForFrame's
			-- link-cache so that ElvUI's per-slot update storm during a
			-- loot burst doesn't redundantly re-run AutoDelete_SetButtonAffixDot
			-- on slots whose item hasn't changed. ElvUI calls UpdateSlot
			-- for every slot in a bag on many of its internal refresh
			-- paths, so without this check a 100-item loot fired the
			-- full pipeline ~16 * (number-of-bags-rebuilt) times.
			if slot._autoDeleteCachedLink == link
				and slot._autoDeleteAffixVersion == affixDotVersion then
				return
			end
			slot._autoDeleteCachedLink   = link
			slot._autoDeleteAffixVersion = affixDotVersion
			-- DecideDot handles every gating concern (showAffixDot
			-- toggle, affixCollectionMode owned/missing logic, deferred
			-- queue for cache misses). One code path for both Blizzard
			-- and ElvUI bag UIs -- see DecideDot above for the full
			-- decision tree.
			local level, color = _G.AutoDelete_DecideDot(link, bagID, slotID, slot)
			AutoDelete_SetButtonAffixDot(slot, level, color)
			AutoDelete_PerfEnd("ElvUI:UpdateSlot hook", _p)
		end)

		-- Trigger an initial refresh so dots appear immediately on already-
		-- visible bags without waiting for the next bag event.
		if B.UpdateAllBagSlots then
			pcall(B.UpdateAllBagSlots, B)
		end
	end)
end

_G.AutoDelete_AffixTierProtectionFields = {
	[1] = "protectAffixTier1",
	[2] = "protectAffixTier2",
	[3] = "protectAffixTier3",
	[4] = "protectAffixTier4",
	[5] = "protectAffixTier5",
}

function _G.AutoDelete_HasAnyAffixTierProtection(profile)
	if not profile then return false end
	for _, field in pairs(_G.AutoDelete_AffixTierProtectionFields) do
		if profile[field] == true then return true end
	end
	return false
end

function _G.AutoDelete_IsMissingAffixHardStop(profile, bag, slot, itemLink, singleAffixSlot)
	if not profile or not (profile.affixCollectionMode or profile.keepSingleMissingAffix) then
		return false, nil
	end
	if singleAffixSlot and singleAffixSlot.extra then return false, nil end
	if not HasAffix(bag, slot) then return false, nil end
	local itemName = GetItemInfo(itemLink)
	local owned = AutoDelete_IsAffixOwnedByItemName(itemName)
	if owned == false then return true, "missing" end
	if owned == nil then return true, "unknown" end
	return false, nil
end

-- Combined check used by destructive actions. Returns true
-- when the item should be protected from destructive rules. Checked tier
-- protection is absolute. Missing-affix hard stop blocks destructive actions when
-- Show/Keep Missing Affix or KeepOne Missing Affix is on; KeepOne Missing Affix extras
-- bypass only that hard stop, not checked tier protection.
IsAffixProtected = function(profile, bag, slot, itemLink, action, singleAffixSlot)
	if action ~= "delete" and action ~= "sell" and action ~= "disenchant" then return false end

	if _G.AutoDelete_HasAnyAffixTierProtection(profile) then
		local tier = HasAffix(bag, slot)
		local field = tier and _G.AutoDelete_AffixTierProtectionFields[tonumber(tier)]
		if field and profile[field] == true then return true end
	end

	if _G.AutoDelete_IsMissingAffixHardStop(profile, bag, slot, itemLink, singleAffixSlot) then return true end
	return false
end

function _G.AutoDelete_IsDestructiveRuleProtected(profile, bag, slot, itemLink, action, singleAffixSlot, keepIDs, keepNames, keepOneIDs, keepStackIDs)
	if not profile or not itemLink then return false, nil end
	local itemId = GetItemIDFromLink(itemLink)
	local itemName = GetItemInfo(itemLink)

	if not keepIDs or not keepNames then
		keepNames, keepIDs = BuildWantedSets(profile.whitelistText, "keep-list")
	end
	if _G.AutoDelete_IsWhitelistedFast(keepIDs or {}, keepNames or {}, itemId, itemName) then
		return true, "keep-blocked"
	end

	if not keepOneIDs then
		keepOneIDs = select(2, BuildWantedSets(profile.keepOneText, "keepone-list"))
	end
	if itemId and keepOneIDs and keepOneIDs[itemId] then
		return true, "keepone-blocked"
	end

	if not keepStackIDs then
		keepStackIDs = select(2, BuildWantedSets(profile.keepStackText, "keepstack-list"))
	end
	if itemId and keepStackIDs and keepStackIDs[itemId] then
		return true, "keepstack-blocked"
	end

	if singleAffixSlot and not singleAffixSlot.extra then
		return true, "single-affix-kept"
	end

	local missingBlocked, missingState = _G.AutoDelete_IsMissingAffixHardStop(profile, bag, slot, itemLink, singleAffixSlot)
	if missingBlocked then
		return true, missingState == "unknown" and "missing-affix-unknown" or "missing-affix-blocked"
	end

	if IsAffixProtected(profile, bag, slot, itemLink, action, singleAffixSlot) then
		return true, "affix-blocked"
	end
	return false, nil
end

-- Copper → "Xg Ys Zc" string. Defined before functions that use it.
local function FormatMoney(totalCopper)
	local gold = math.floor(totalCopper / 10000)
	local silver = math.floor((totalCopper % 10000) / 100)
	local copper = totalCopper % 100
	local money = ""
	if gold > 0 then money = money .. gold .. "g " end
	if silver > 0 then money = money .. silver .. "s " end
	if copper > 0 then money = money .. copper .. "c" end
	return money
end

-- Creature IDs for the PE companions we care about. These are the canonical
-- identifiers Blizzard's GetCompanionInfo returns. Caching them lets us
-- look up by ID instead of a fragile name-string-match. We discover the IDs
-- on first use (the user must own the companion for it to appear in the
-- companion list, so we can't hardcode the ID here without risk of staleness
-- on future server changes).
local SCAVENGER_CREATURE_ID = nil  -- discovered on first lookup
local MERCHANT_CREATURE_ID  = nil  -- discovered on first lookup

-- Find a companion by name and cache its creature ID for future lookups.
-- Returns: (index, isSummoned, creatureID) or (nil, false, nil)
local function FindCompanionByName(name)
	if not name or name == "" then return nil, false, nil end
	local numCritters = GetNumCompanions("CRITTER") or 0
	local needle = string.lower(name)
	for i = 1, numCritters do
		local cId, cName, _, _, summoned = GetCompanionInfo("CRITTER", i)
		if cName and string.find(string.lower(cName), needle) then
			return i, (summoned == 1 or summoned == true), cId
		end
	end
	return nil, false, nil
end

-- ID-first companion lookup. If the cached ID isn't found (rare: server
-- reshuffled companion list), falls back to name search and re-caches.
local function FindCompanionById(creatureId, fallbackName)
	if not creatureId then
		return FindCompanionByName(fallbackName)
	end
	local numCritters = GetNumCompanions("CRITTER") or 0
	for i = 1, numCritters do
		local cId, _, _, _, summoned = GetCompanionInfo("CRITTER", i)
		if cId == creatureId then
			return i, (summoned == 1 or summoned == true), cId
		end
	end
	-- ID not found - re-resolve from name. This also re-caches the ID.
	return FindCompanionByName(fallbackName)
end

-- Check if any companion OTHER than the named one is currently summoned.
-- Used by the summon helpers to decide whether to dismiss-first before
-- calling CallCompanion. Some realms drop the second call when the slot
-- is occupied, so an explicit dismiss is more reliable than relying on
-- CallCompanion's atomic-toggle behavior.
local function IsOtherCompanionSummoned(skipName)
	local n = GetNumCompanions("CRITTER")
	if not n or n <= 0 then return false end
	skipName = string.lower(skipName or "")
	for i = 1, n do
		local _, cName, _, _, summoned = GetCompanionInfo("CRITTER", i)
		if (summoned == 1 or summoned == true) and cName then
			if not string.find(string.lower(cName), skipName) then
				return true
			end
		end
	end
	return false
end

-- Per-pet cooldown gate so we don't fire CallCompanion for the SAME pet
-- more than once every few seconds. The server can take a moment to
-- confirm a summon under load, and a second call inside that window can
-- either no-op or get queued as a redundant toggle.
--
-- Per-pet (NOT shared) because the common after-sell flow goes:
--   1. SummonGoblinMerchant fires      -> lastSummonCallAt.merchant = T0
--   2. User sells items at the Goblin  -> takes 1-4 seconds
--   3. After-sell SummonGreedyScavenger fires at T0 + 2-4s
-- A SHARED cooldown made step 3 drop the Scav summon silently because
-- the recent Goblin summon kept the gate closed. (User report
-- 2026-05-20: "scav sometimes won't summon after sell.") Per-pet keys
-- mean a Goblin summon no longer blocks a Scav summon and vice versa.
local lastSummonCallAt = { scavenger = 0, merchant = 0 }
local SUMMON_RESPECT_WINDOW = 5
_G.AutoDelete_GoblinConfirmDelay = 1.5
_G.AutoDelete_GoblinConfirmMaxAttempts = 3
_G.AutoDelete_GoblinConfirmPending = false
_G.AutoDelete_ScavengerConfirmDelay = 1.5
_G.AutoDelete_ScavengerConfirmMaxAttempts = 3
_G.AutoDelete_ScavengerConfirmPending = false
_G.AutoDelete_CompanionSummonOwner = nil
_G.AutoDelete_CompanionSummonOwnerUntil = 0
_G.AutoDelete_GoblinAutoBackoffS = 30
_G.AutoDelete_GoblinAutoBackoffUntil = 0
_G.AutoDelete_SummonFailureChatUntil = _G.AutoDelete_SummonFailureChatUntil or {}

function _G.AutoDelete_AcquireCompanionSummon(owner, duration)
	local now = GetTime()
	local current = _G.AutoDelete_CompanionSummonOwner
	if current and current ~= owner and now < (_G.AutoDelete_CompanionSummonOwnerUntil or 0) then
		return false, current
	end
	_G.AutoDelete_CompanionSummonOwner = owner
	_G.AutoDelete_CompanionSummonOwnerUntil = now + (duration or 8)
	return true, owner
end

function _G.AutoDelete_ReleaseCompanionSummon(owner)
	if _G.AutoDelete_CompanionSummonOwner == owner then
		_G.AutoDelete_CompanionSummonOwner = nil
		_G.AutoDelete_CompanionSummonOwnerUntil = 0
		if owner == "merchant" and _G.AutoDelete_PendingScavengerAfterCompanion then
			_G.AutoDelete_PendingScavengerAfterCompanion = false
			if _G.AutoDelete_RequestDelayedScavengerSummon then
				_G.AutoDelete_RequestDelayedScavengerSummon(1.0)
			end
		end
	end
end

function _G.AutoDelete_IsCompanionSummonBusyFor(owner)
	local current = _G.AutoDelete_CompanionSummonOwner
	return current and current ~= owner and GetTime() < (_G.AutoDelete_CompanionSummonOwnerUntil or 0)
end

function _G.AutoDelete_GoblinAutoBackoffActive()
	return GetTime() < (_G.AutoDelete_GoblinAutoBackoffUntil or 0)
end

function _G.AutoDelete_ShouldMerchantHavePriority(profile)
	profile = profile or cachedProfile
	if not profile or not profile.summonMerchantWhenBagsFull then return false end
	if profile.summonOnlyInCombat and not (UnitAffectingCombat and UnitAffectingCombat("player")) then return false end
	local threshold = tonumber(profile.bagSpaceWarnThreshold) or 3
	local free = 0
	for bag = 0, 4 do
		local slots = GetContainerNumFreeSlots and GetContainerNumFreeSlots(bag) or 0
		if slots then free = free + slots end
	end
	return free <= threshold
end

-- Central combat gate for every AutoDelete-owned Scavenger summon path.
-- Delayed timers re-check here so "Only in Combat" cannot leak a summon after
-- combat ends.
function _G.AutoDelete_ScavengerCombatAllowed(profile)
	profile = profile or cachedProfile
	if not profile or not profile.summonOnlyInCombat then return true end
	return (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false
end

function _G.AutoDelete_PrintSummonAttempt(name, attempt, maxAttempts)
	if attempt and attempt > 1 then
		_G.AutoDelete_LastSuppressedSummonAttempt = tostring(name) .. " " .. tostring(attempt) .. "/" .. tostring(maxAttempts or "?")
		return
	end
	print("|cffff8000[AutoDelete]|r Trying to summon " .. tostring(name) .. ".")
end

function _G.AutoDelete_ShouldPrintSummonFailure(key, cooldown)
	local now = GetTime()
	cooldown = cooldown or 30
	_G.AutoDelete_SummonFailureChatUntil = _G.AutoDelete_SummonFailureChatUntil or {}
	if now < (_G.AutoDelete_SummonFailureChatUntil[key] or 0) then return false end
	_G.AutoDelete_SummonFailureChatUntil[key] = now + cooldown
	return true
end

function _G.AutoDelete_ConfirmScavengerIsOut(callAt)
	if _G.AutoDelete_SetActiveTrackedPet then
		_G.AutoDelete_SetActiveTrackedPet("scavenger")
	end
	if _G.AutoDelete_RecordSummonAt then
		_G.AutoDelete_RecordSummonAt(callAt or GetTime())
	end
	_G.AutoDelete_ScavengerLastSummonResult = "confirmed"
	_G.AutoDelete_ScavengerConfirmPending = false
	_G.AutoDelete_PendingScavengerAfterCompanion = false
	if _G.AutoDelete_ReleaseCompanionSummon then
		_G.AutoDelete_ReleaseCompanionSummon("scavenger")
	end
end

function _G.AutoDelete_FinishScavengerFailure(reason)
	_G.AutoDelete_ScavengerLastSummonResult = reason or "failed-after-retries"
	_G.AutoDelete_ScavengerConfirmPending = false
	if _G.AutoDelete_ReleaseCompanionSummon then
		_G.AutoDelete_ReleaseCompanionSummon("scavenger")
	end
	if _G.AutoDelete_ScavengerLastSummonResult == "failed-after-retries" then
		if _G.AutoDelete_ShouldPrintSummonFailure("scavenger", 30) then
			print("|cffff8000[AutoDelete]|r Greedy Scavenger did not appear after AutoDelete retried. It will try again on the next summon trigger.")
		end
	end
end

function _G.AutoDelete_CallScavengerForConfirm(attempt)
	attempt = attempt or 1
	local ok, owner = _G.AutoDelete_AcquireCompanionSummon("scavenger", 8)
	if not ok then
		_G.AutoDelete_ScavengerLastSummonResult = "waiting-for-" .. tostring(owner)
		_G.AutoDelete_PendingScavengerAfterCompanion = true
		return
	end
	if not _G.AutoDelete_ScavengerCombatAllowed(cachedProfile) then
		_G.AutoDelete_FinishScavengerFailure("combat-blocked")
		return
	end

	local idx, isUp, cId = FindCompanionById(SCAVENGER_CREATURE_ID, "greedy scavenger")
	if cId then SCAVENGER_CREATURE_ID = cId end
	if isUp then
		_G.AutoDelete_ConfirmScavengerIsOut(GetTime())
		return
	end
	if not idx then
		_G.AutoDelete_FinishScavengerFailure("not-found")
		return
	end

	if IsOtherCompanionSummoned("greedy scavenger") then
		if DismissCompanion then DismissCompanion("CRITTER") end
		AfterDelay(0.5, function()
			if not _G.AutoDelete_ScavengerCombatAllowed(cachedProfile) then
				_G.AutoDelete_FinishScavengerFailure("combat-blocked")
				return
			end
			local idx2, isUp2, cId2 = FindCompanionById(SCAVENGER_CREATURE_ID, "greedy scavenger")
			if cId2 then SCAVENGER_CREATURE_ID = cId2 end
			if isUp2 then
				_G.AutoDelete_ConfirmScavengerIsOut(GetTime())
				return
			end
			if not idx2 then
				_G.AutoDelete_FinishScavengerFailure("not-found")
				return
			end
			_G.AutoDelete_PrintSummonAttempt("Greedy Scavenger", attempt, _G.AutoDelete_ScavengerConfirmMaxAttempts)
			CallCompanion("CRITTER", idx2)
			lastSummonCallAt.scavenger = GetTime()
			_G.AutoDelete_CompanionSummonOwnerUntil = GetTime() + 8
			_G.AutoDelete_ScavengerLastSummonAttempt = attempt
			_G.AutoDelete_ConfirmScavengerSummon(lastSummonCallAt.scavenger, attempt)
		end)
		return
	end

	_G.AutoDelete_PrintSummonAttempt("Greedy Scavenger", attempt, _G.AutoDelete_ScavengerConfirmMaxAttempts)
	CallCompanion("CRITTER", idx)
	lastSummonCallAt.scavenger = GetTime()
	_G.AutoDelete_CompanionSummonOwnerUntil = GetTime() + 8
	_G.AutoDelete_ScavengerLastSummonAttempt = attempt
	_G.AutoDelete_ConfirmScavengerSummon(lastSummonCallAt.scavenger, attempt)
end

function _G.AutoDelete_ConfirmScavengerSummon(callAt, attempt)
	attempt = attempt or 1
	if attempt == 1 and _G.AutoDelete_ScavengerConfirmPending then return end
	_G.AutoDelete_ScavengerConfirmPending = true
	AfterDelay(_G.AutoDelete_ScavengerConfirmDelay, function()
		if not _G.AutoDelete_ScavengerCombatAllowed(cachedProfile) then
			_G.AutoDelete_FinishScavengerFailure("combat-blocked")
			return
		end

		local idx, isUp, cId = FindCompanionById(SCAVENGER_CREATURE_ID, "greedy scavenger")
		if cId then SCAVENGER_CREATURE_ID = cId end
		if isUp then
			_G.AutoDelete_ConfirmScavengerIsOut(callAt)
			return
		end

		if attempt < _G.AutoDelete_ScavengerConfirmMaxAttempts and idx then
			_G.AutoDelete_ScavengerLastSummonResult = "retry-" .. tostring(attempt)
			_G.AutoDelete_CallScavengerForConfirm(attempt + 1)
			return
		end

		_G.AutoDelete_FinishScavengerFailure(idx and "failed-after-retries" or "not-found")
	end)
end

local function SummonGreedyScavenger(force)
	if not _G.AutoDelete_ScavengerCombatAllowed(cachedProfile) then return end
	if (not force) and _G.AutoDelete_ShouldMerchantHavePriority and _G.AutoDelete_ShouldMerchantHavePriority(cachedProfile) then
		_G.AutoDelete_ScavengerLastSummonResult = "waiting-for-bags-full-merchant"
		_G.AutoDelete_PendingScavengerAfterBags = true
		return
	end
	local idx, isUp, cId = FindCompanionById(SCAVENGER_CREATURE_ID, "greedy scavenger")
	if cId then SCAVENGER_CREATURE_ID = cId end  -- cache for next time
	if not idx then return end  -- player doesn't own it
	-- Idempotent: already summoned, don't toggle off and re-call.
	-- Skipped when force=true (used by distance-based stuck detection where
	-- we just dismissed the pet and need to re-summon at the new position
	-- regardless of what the API still claims).
	if isUp and not force then
		if _G.AutoDelete_SetActiveTrackedPet then
			_G.AutoDelete_SetActiveTrackedPet("scavenger")
		end
		return
	end
	-- Server-confirm window: if we fired a CallCompanion for the SCAVENGER
	-- specifically very recently, keep waiting for confirmation instead of
	-- firing another call or assuming success.
	if (GetTime() - lastSummonCallAt.scavenger) < SUMMON_RESPECT_WINDOW then
		_G.AutoDelete_ConfirmScavengerSummon(lastSummonCallAt.scavenger, 1)
		return
	end
	_G.AutoDelete_CallScavengerForConfirm(1)
end

function _G.AutoDelete_ConfirmGoblinMerchantIsOut(callAt)
	print("|cffff8000[AutoDelete]|r Goblin Merchant is out. Target it and press your Interact With Target keybind to open the vendor.")
	if _G.AutoDelete_SetActiveTrackedPet then
		_G.AutoDelete_SetActiveTrackedPet("merchant")
	end
	if _G.AutoDelete_RecordSummonAt then
		_G.AutoDelete_RecordSummonAt(callAt or GetTime())
	end
	_G.AutoDelete_GoblinLastSummonResult = "confirmed"
	_G.AutoDelete_GoblinConfirmPending = false
	if _G.AutoDelete_ReleaseCompanionSummon then
		_G.AutoDelete_ReleaseCompanionSummon("merchant")
	end
end

function _G.AutoDelete_FinishGoblinMerchantFailure(reason)
	_G.AutoDelete_GoblinLastSummonResult = reason or "failed-after-retries"
	_G.AutoDelete_GoblinConfirmPending = false
	_G.AutoDelete_GoblinAutoBackoffUntil = GetTime() + (_G.AutoDelete_GoblinAutoBackoffS or 30)
	if _G.AutoDelete_ReleaseCompanionSummon then
		_G.AutoDelete_ReleaseCompanionSummon("merchant")
	end
	if _G.AutoDelete_RearmGoblinAfterBackoff then
		_G.AutoDelete_RearmGoblinAfterBackoff(_G.AutoDelete_GoblinLastSummonResult)
	end
	if _G.AutoDelete_ShouldPrintSummonFailure("goblin", 30) then
		print("|cffff8000[AutoDelete]|r Goblin Merchant did not appear after AutoDelete retried. Auto-summon will wait briefly so you can summon it manually. Run |cffffd700/del goblin|r if this keeps happening.")
	end
end

function _G.AutoDelete_CallGoblinMerchantForConfirm(attempt)
	local ok, owner = _G.AutoDelete_AcquireCompanionSummon("merchant", 8)
	if not ok then
		_G.AutoDelete_GoblinLastSummonResult = "waiting-for-" .. tostring(owner)
		return
	end
	local idx, isUp, cId = FindCompanionById(MERCHANT_CREATURE_ID, "goblin merchant")
	if cId then MERCHANT_CREATURE_ID = cId end
	if isUp then
		_G.AutoDelete_ConfirmGoblinMerchantIsOut(GetTime())
		return
	end
	if not idx then
		_G.AutoDelete_FinishGoblinMerchantFailure("not-found")
		return
	end

	if IsOtherCompanionSummoned("goblin merchant") then
		if DismissCompanion then DismissCompanion("CRITTER") end
		AfterDelay(0.5, function()
			local idx2, isUp2, cId2 = FindCompanionById(MERCHANT_CREATURE_ID, "goblin merchant")
			if cId2 then MERCHANT_CREATURE_ID = cId2 end
			if isUp2 then
				_G.AutoDelete_ConfirmGoblinMerchantIsOut(GetTime())
				return
			end
			if not idx2 then
				_G.AutoDelete_FinishGoblinMerchantFailure("not-found")
				return
			end
			_G.AutoDelete_PrintSummonAttempt("Goblin Merchant", attempt, _G.AutoDelete_GoblinConfirmMaxAttempts)
			CallCompanion("CRITTER", idx2)
			lastSummonCallAt.merchant = GetTime()
			_G.AutoDelete_CompanionSummonOwnerUntil = GetTime() + 8
			_G.AutoDelete_GoblinLastSummonAttempt = attempt
			_G.AutoDelete_ConfirmGoblinMerchantSummon(lastSummonCallAt.merchant, attempt)
		end)
		return
	end

	_G.AutoDelete_PrintSummonAttempt("Goblin Merchant", attempt, _G.AutoDelete_GoblinConfirmMaxAttempts)
	CallCompanion("CRITTER", idx)
	lastSummonCallAt.merchant = GetTime()
	_G.AutoDelete_CompanionSummonOwnerUntil = GetTime() + 8
	_G.AutoDelete_GoblinLastSummonAttempt = attempt
	_G.AutoDelete_ConfirmGoblinMerchantSummon(lastSummonCallAt.merchant, attempt)
end

-- Summon confirmation retries quietly because CallCompanion can be dropped or
-- delayed while another companion is despawning. Do not tell the player to act
-- until AutoDelete has exhausted its own retry attempts.
function _G.AutoDelete_ConfirmGoblinMerchantSummon(callAt, attempt)
	attempt = attempt or 1
	if attempt == 1 and _G.AutoDelete_GoblinConfirmPending then return end
	_G.AutoDelete_GoblinConfirmPending = true
	AfterDelay(_G.AutoDelete_GoblinConfirmDelay, function()
		local idx, isUp, cId = FindCompanionById(MERCHANT_CREATURE_ID, "goblin merchant")
		if cId then MERCHANT_CREATURE_ID = cId end
		if isUp then
			_G.AutoDelete_ConfirmGoblinMerchantIsOut(callAt)
			return
		end

		if attempt < _G.AutoDelete_GoblinConfirmMaxAttempts and idx then
			_G.AutoDelete_GoblinLastSummonResult = "retry-" .. tostring(attempt)
			_G.AutoDelete_CallGoblinMerchantForConfirm(attempt + 1)
			return
		end

		_G.AutoDelete_FinishGoblinMerchantFailure(idx and "failed-after-retries" or "not-found")
	end)
end

local function SummonGoblinMerchant(force)
	if (not force) and _G.AutoDelete_GoblinAutoBackoffActive and _G.AutoDelete_GoblinAutoBackoffActive() then
		_G.AutoDelete_GoblinLastSummonResult = "backoff"
		_G.AutoDelete_GoblinLastDeferReason = "summon-backoff"
		return false
	end
	local idx, isUp, cId = FindCompanionById(MERCHANT_CREATURE_ID, "goblin merchant")
	if cId then MERCHANT_CREATURE_ID = cId end  -- cache for next time
	if not idx then return false end  -- player doesn't own it
	-- Idempotent unless force=true. See SummonGreedyScavenger for rationale.
	if isUp and not force then
		if _G.AutoDelete_SetActiveTrackedPet then
			_G.AutoDelete_SetActiveTrackedPet("merchant")
		end
		return true
	end
	-- Per-pet cooldown -- see SummonGreedyScavenger for rationale. Only
	-- a recent Goblin summon blocks another Goblin summon; a recent Scav
	-- summon does not.
	if (GetTime() - lastSummonCallAt.merchant) < SUMMON_RESPECT_WINDOW then
		_G.AutoDelete_ConfirmGoblinMerchantSummon(lastSummonCallAt.merchant, 1)
		return true
	end
	_G.AutoDelete_CallGoblinMerchantForConfirm(1)
	return true
end

-- Fire SummonGreedyScavenger after a delay. Guarded so concurrent callers
-- (e.g. dismount restore + after-sell trigger) don't stack two pending summons.
local summonPending = false
local function DelayedSummon(delaySeconds)
	if summonPending then return end
	summonPending = true
	AfterDelay(delaySeconds or 1.5, function()
		summonPending = false
		if not _G.AutoDelete_ScavengerCombatAllowed(cachedProfile) then return end
		if _G.AutoDelete_ShouldMerchantHavePriority and _G.AutoDelete_ShouldMerchantHavePriority(cachedProfile) then
			_G.AutoDelete_ScavengerLastSummonResult = "waiting-for-bags-full-merchant"
			_G.AutoDelete_PendingScavengerAfterBags = true
			return
		end
		if _G.AutoDelete_IsCompanionSummonBusyFor and _G.AutoDelete_IsCompanionSummonBusyFor("scavenger") then
			_G.AutoDelete_ScavengerLastSummonResult = "waiting-for-" .. tostring(_G.AutoDelete_CompanionSummonOwner)
			_G.AutoDelete_PendingScavengerAfterCompanion = true
			DelayedSummon(2.0)
			return
		end
		SummonGreedyScavenger()
	end)
end
_G.AutoDelete_RequestDelayedScavengerSummon = DelayedSummon

-- ============================================================================
-- Hide Greedy Scavenger spam (chat filter + bubble suppressor)
-- Gated at runtime by cachedProfile.hideGreedySpam. Installed once at load;
-- the filter/bubble functions become no-ops when the toggle is off.
-- ============================================================================

-- Author-name matcher: true if the speaker is the Greedy Scavenger.
-- Strips color codes since monster-say events can include them.
local function IsGreedyAuthor(author)
	if not author or author == "" then return false end
	-- Strip color codes: |cAARRGGBB...|r  and texture codes |TpATH|t
	author = author:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	author = author:gsub("|T[^|]+|t", "")
	return string.find(string.lower(author), "greedy scavenger") ~= nil
end

-- Track recent greedy-say messages so we can match them to chat bubbles.
-- Bubbles aren't tagged with author, so we match by text content within a window.
local greedyRecentMessages = {}   -- [msg] = timestamp
local GREEDY_MSG_TTL = 8          -- seconds to remember each message for bubble matching

local function RememberGreedyMessage(msg)
	if not msg or msg == "" then return end
	greedyRecentMessages[msg] = GetTime()
end

local function IsRecentGreedyMessage(msg)
	if not msg or msg == "" then return false end
	local t = greedyRecentMessages[msg]
	if not t then return false end
	if GetTime() - t > GREEDY_MSG_TTL then
		greedyRecentMessages[msg] = nil
		return false
	end
	return true
end

-- Chat event filter: runs for EVERY message on the listed event types.
-- Returns true to suppress. Always remembers matched greedy lines so the
-- bubble killer can silence the matching chat bubble even when the chat
-- toggle is on (bubbles appear regardless of chat filters).
local function GreedyChatFilter(_, _, msg, author)
	if IsGreedyAuthor(author) then
		RememberGreedyMessage(msg)
		-- Mark the scav as "alive and looting" for stuck detection. Every
		-- monster-chat line from the scav corresponds to a successful pickup.
		if _G.AutoDelete_RecordScavLootChat then
			_G.AutoDelete_RecordScavLootChat(GetTime())
		end
		if cachedProfile and cachedProfile.hideGreedySpam then
			return true   -- swallow the message
		end
	end
	return false
end

-- Install chat filters once. Covers say/yell/whisper/emote/monster_* variants.
local greedyFiltersInstalled = false
local function InstallGreedyChatFilters()
	if greedyFiltersInstalled then return end
	greedyFiltersInstalled = true
	local events = {
		"CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL",
		"CHAT_MSG_MONSTER_WHISPER", "CHAT_MSG_MONSTER_EMOTE",
		"CHAT_MSG_MONSTER_PARTY",
		"CHAT_MSG_SAY", "CHAT_MSG_YELL",
		"CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
	}
	for _, ev in ipairs(events) do
		ChatFrame_AddMessageEventFilter(ev, GreedyChatFilter)
	end
end

-- Chat bubble suppression. Bubbles are WorldFrame children whose only region
-- is a FontString matching the message. We scan at 0.1s intervals and hide
-- bubbles whose text matches a recent Greedy message.
local bubbleWatcher = CreateFrame("Frame")
local bubbleTimer = 0
local BUBBLE_CHECK_INTERVAL = 0.1
local killedBubbles = setmetatable({}, { __mode = "k" })   -- weak keys so GC works

local function KillBubble(frame)
	if not frame or killedBubbles[frame] then return end
	killedBubbles[frame] = true
	frame:Hide()
	-- Defensive: also kill its regions in case something re-shows the parent
	if frame.SetAlpha then frame:SetAlpha(0) end
end

bubbleWatcher:SetScript("OnUpdate", function(self, dt)
	bubbleTimer = bubbleTimer + dt
	if bubbleTimer < BUBBLE_CHECK_INTERVAL then return end
	bubbleTimer = 0
	if not cachedProfile or not cachedProfile.hideGreedySpam then return end
	if not next(greedyRecentMessages) then return end

	for i = 1, WorldFrame:GetNumChildren() do
		local f = select(i, WorldFrame:GetChildren())
		if f and not killedBubbles[f] and f:GetName() == nil and f.GetRegions then
			-- Chat bubbles: no name, small region count, has a FontString
			local isBubble = false
			local text = nil
			for r = 1, f:GetNumRegions() do
				local region = select(r, f:GetRegions())
				if region and region.GetObjectType and region:GetObjectType() == "FontString" then
					isBubble = true
					text = region:GetText()
					break
				end
			end
			if isBubble and text and IsRecentGreedyMessage(text) then
				KillBubble(f)
			end
		end
	end
end)

-- Install filters once (bubble watcher is already running above).
InstallGreedyChatFilters()

-- ============================================================================
-- Auto-Invite
-- ============================================================================
-- Invites players who whisper you any of the configured keywords (default:
-- "inv,invite"). Matching is case-insensitive and triggers when the keyword
-- appears at a word-start (so "inv" matches "inv", "invite", "invited", but
-- not "binv"). Comma-separated list in profile.autoInviteKeywords.
--
-- Gated by:
--   cachedProfile.autoInviteEnabled (master toggle for this feature)
--   player must be group leader OR raid assistant (silently ignored otherwise)
-- INDEPENDENT of the AutoDelete master Enable toggle by design.
--
-- Active everywhere (party, raid, BG, solo).
--
-- Extras (all off by default):
--   autoInviteApplyLootRule + autoInviteLootRule: apply a loot rule after inviting
--   autoInviteConvertToRaid: convert to raid when party is full (5 members)
-- ============================================================================

-- Loot rule values for SetLootMethod (3.3.5 API).
-- Maps profile string → (method, threshold-arg-for-master-loot).
local LOOT_METHOD_MAP = {
	freeforall      = { method = "freeforall" },
	roundrobin      = { method = "roundrobin" },
	group           = { method = "group" },
	needbeforegreed = { method = "needbeforegreed" },
	master          = { method = "master" },
}

-- Strip WoW cross-realm suffix and normalize whitespace for name comparison.
local function NormalizePlayerName(name)
	if not name or name == "" then return "" end
	name = name:gsub("%-.+$", "")   -- strip "-RealmName" if present
	return (name:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Parse the keyword string ("inv,invite") into a normalized array of lowercase
-- keywords. Trims whitespace, drops blanks.
local function ParseInviteKeywords(rawStr)
	local out = {}
	for word in string.gmatch(rawStr or "", "[^,]+") do
		local w = word:gsub("^%s+", ""):gsub("%s+$", ""):lower()
		if w ~= "" then table.insert(out, w) end
	end
	return out
end

-- Does `msg` contain any of the `keywords` as the start of a word?
-- "Word start" means the keyword is preceded by start-of-string or a
-- non-alphanumeric character. What comes AFTER the keyword doesn't matter,
-- the keyword acts as a prefix. Examples for keyword "inv":
--   "inv"                → yes
--   "invite"             → yes
--   "invited"            → yes
--   "please invite me"   → yes
--   "invent"             → yes
--   "investigation"      → yes
--   "uninvited"          → NO  ('inv' is mid-word, not at a word start)
-- Keyword "invite" → matches any word starting with "invite"
--   (so "invite", "invites", "invited" all match).
local function MessageMatchesKeyword(msg, keywords)
	if not msg or msg == "" or not keywords or #keywords == 0 then return false end
	local lower = msg:lower()

	for _, kw in ipairs(keywords) do
		local start = 1
		while true do
			local s, e = lower:find(kw, start, true)   -- plain find (no magic)
			if not s then break end

			-- Check char BEFORE the match (must be start-of-string or non-alphanumeric).
			-- This ensures the keyword is at a WORD START. No check after the match,
			-- so "inv" matches "invite", "invent", "invited", etc.
			local okBefore = (s == 1)
			if not okBefore then
				local prev = lower:sub(s - 1, s - 1)
				okBefore = (prev:match("[%w]") == nil)
			end

			if okBefore then return true end
			start = e + 1
		end
	end
	return false
end

-- True if the player has invite authority:
--   - Solo (not in party/raid) → always true (can start a group)
--   - In party → must be leader
--   - In raid → must be leader OR assistant
local function PlayerCanInvite()
	local inRaid = GetNumRaidMembers and GetNumRaidMembers() > 0
	local inParty = GetNumPartyMembers and GetNumPartyMembers() > 0

	if inRaid then
		-- IsRaidLeader() and IsRaidOfficer() exist on 3.3.5
		if IsRaidLeader and IsRaidLeader() then return true end
		if IsRaidOfficer and IsRaidOfficer() then return true end
		return false
	end

	if inParty then
		if IsPartyLeader and IsPartyLeader() then return true end
		return false
	end

	-- Solo → we can start a party
	return true
end

-- True if the current group is a 5-person party at capacity.
local function IsPartyFullForRaidConvert()
	if GetNumRaidMembers and GetNumRaidMembers() > 0 then return false end   -- already in raid
	if not GetNumPartyMembers then return false end
	-- GetNumPartyMembers counts members EXCLUDING the player; 4 means 5 total.
	return GetNumPartyMembers() >= 4
end

-- Apply the configured loot rule. Silent. Only applies if toggle is on AND
-- the player actually has loot-setting authority.
local function ApplyConfiguredLootRule()
	if not cachedProfile or not cachedProfile.autoInviteApplyLootRule then return end
	local ruleKey = cachedProfile.autoInviteLootRule or "freeforall"
	local info = LOOT_METHOD_MAP[ruleKey]
	if not info or not SetLootMethod then return end

	-- Loot method can only be changed by party leader (and raid leader).
	local inRaid = GetNumRaidMembers and GetNumRaidMembers() > 0
	if inRaid then
		if not (IsRaidLeader and IsRaidLeader()) then return end
	else
		if not (IsPartyLeader and IsPartyLeader()) then return end
	end

	if info.method == "master" then
		-- Master loot needs a master looter name; use self.
		local me = UnitName("player")
		if me then SetLootMethod("master", me) end
	else
		SetLootMethod(info.method)
	end
end

-- Convert party to raid if configured AND the party is full.
local function MaybeConvertToRaid()
	if not cachedProfile or not cachedProfile.autoInviteConvertToRaid then return end
	if not IsPartyFullForRaidConvert() then return end
	if not (IsPartyLeader and IsPartyLeader()) then return end
	if ConvertToRaid then ConvertToRaid() end
end

-- Invite the given player. Silent. Handles solo→party transition naturally.
local function SafeInvitePlayer(targetName)
	if not targetName or targetName == "" then return end
	if not InviteUnit then return end

	-- Don't re-invite someone already in our group.
	if UnitInParty and UnitInParty(targetName) then return end
	if UnitInRaid and UnitInRaid(targetName) then return end

	InviteUnit(targetName)
end

-- After a successful invite, we want to apply loot rules + raid-convert ON A
-- DELAY, because the party state doesn't update instantly when the target
-- accepts. We schedule a follow-up check via the shared AfterDelay timer
-- (same machinery that powers DelayedSummon and other one-shots).
local function ScheduleInviteFollowup(delaySec, fn)
	AfterDelay(delaySec or 3, fn)
end

-- Incoming whisper handler. Called for CHAT_MSG_WHISPER events.
-- If the message matches a keyword → invite the whisperer.
local function HandleIncomingWhisper(msg, author)
	-- Always refresh cached profile here; UI toggles don't fire any event
	-- that would otherwise update it, so stale data would silently block invites.
	RefreshCachedProfile()
	if not cachedProfile or not cachedProfile.autoInviteEnabled then return end
	if not PlayerCanInvite() then return end

	local keywords = ParseInviteKeywords(cachedProfile.autoInviteKeywords)
	if not MessageMatchesKeyword(msg, keywords) then return end

	local target = NormalizePlayerName(author)
	if target == "" then return end

	SafeInvitePlayer(target)

	-- Follow up: apply loot rule + convert to raid if configured.
	-- 3s gives the invited player time to accept.
	ScheduleInviteFollowup(3, function()
		ApplyConfiguredLootRule()
		MaybeConvertToRaid()
	end)
end



-- Dedicated event frame for whisper events (kept separate from the main
-- scanner to avoid clutter).
local inviteFrame = CreateFrame("Frame")
inviteFrame:RegisterEvent("CHAT_MSG_WHISPER")
inviteFrame:SetScript("OnEvent", function(_, event, msg, author)
	if event == "CHAT_MSG_WHISPER" then
		HandleIncomingWhisper(msg, author)
	end
end)

-- Inventory worth sampler: called from MERCHANT_SHOW.
-- Walks all bag slots, sums vendor sell prices, adds one sample to the running
-- lifetime stats (total + count; average = total / count). Also adds to the
-- session counters. Non-vendorable items contribute 0 to the sample.
local function SampleInventoryWorth()
	local totalCopper = 0
	for bag = 0, 4 do
		local slots = GetContainerNumSlots(bag)
		if slots and slots > 0 then
			for slot = 1, slots do
				local _, itemCount, locked, _, _, _, itemLink = GetContainerItemInfo(bag, slot)
				if itemLink and not locked then
					local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemLink)
					if sellPrice and sellPrice > 0 then
						totalCopper = totalCopper + (sellPrice * (itemCount or 1))
					end
				end
			end
		end
	end
	BumpStat("inventoryWorthTotal", totalCopper)
	BumpStat("inventoryWorthCount", 1)
end

-- Auto-repair: called from MERCHANT_SHOW.
-- Respects profile.autoRepair and profile.autoRepairUseGuildBank.
local function TryAutoRepair()
	if not cachedProfile or not cachedProfile.autoRepair then return end
	if not CanMerchantRepair or not CanMerchantRepair() then return end
	if not GetRepairAllCost or not RepairAllItems then return end

	local cost, canRepair = GetRepairAllCost()
	if not canRepair or not cost or cost <= 0 then return end

	-- Use Guild Bank money if the toggle is on AND the player is in a guild
	-- AND has guild-bank withdraw/repair permission.
	local useGuild = cachedProfile.autoRepairUseGuildBank
		and IsInGuild and IsInGuild()
		and CanGuildBankRepair and CanGuildBankRepair()
		and GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() >= cost

	if useGuild then
		RepairAllItems(1)  -- 1 = use guild bank funds
		BumpStat("repairs", 1)
		BumpStat("repairSpend", cost)
		print("|cffff8000[AutoDelete]|r Repaired from guild bank (" .. FormatMoney(cost) .. ")")
	else
		-- Fall back to personal gold; skip if the player can't afford it.
		if GetMoney and GetMoney() >= cost then
			RepairAllItems()
			BumpStat("repairs", 1)
			BumpStat("repairSpend", cost)
			print("|cffff8000[AutoDelete]|r Repaired for " .. FormatMoney(cost))
		else
			print("|cffff8000[AutoDelete]|r Not enough gold to repair (need " .. FormatMoney(cost) .. ")")
		end
	end
end

-- Items sold per scan tick. Same throttle rationale as DELETE_BATCH_SIZE
-- (see comment there). Kept equal so delete and sell behave the same
-- under the scan-tick gate, matching user-facing expectation.
local SELL_BATCH_SIZE = 30
local sellSessionCount = 0
local sellSessionCopper = 0
local sellDryTicks = 0

local function SellItems(silent)
	if not MerchantFrame or not MerchantFrame:IsShown() then
		if not silent then print("|cffff8000[AutoDelete]|r You must be at a vendor to sell.") end
		return
	end
	if CursorHasItem() then return end
	if _G.AutoDelete_SpikeDebug then
		local _sc = _G.AutoDelete_SpikeCounters
		local _ss = _G.AutoDelete_SpikeSession
		_sc.sell = (_sc.sell or 0) + 1
		_ss.sell = (_ss.sell or 0) + 1
	end

	local db = GetDB()
	local profile = GetActiveProfile(db)

	local sellNames, sellIDs = BuildWantedSets(profile.sellListText, "sell-list")
	-- Pre-built Keep-list sets so the per-slot Keep-list short-circuit
	-- below is an O(1) hash lookup instead of a full whitelist re-parse.
	-- Same optimization as DeleteItems' hot path -- /del perf showed the
	-- old IsWhitelisted re-parse was the dominant cost in scan loops.
	-- "keep-list" cache key is shared with DeleteItems / HasPendingDeleteItems.
	local keepNames, keepIDs = BuildWantedSets(profile.whitelistText, "keep-list")
	local singleAffixPlan = _G.AutoDelete_BuildSingleAffixPlan(profile, keepIDs, keepNames)

	local batchCount = 0

	for bag = 0, 4 do
		for slot = 1, GetContainerNumSlots(bag) do
			if batchCount >= SELL_BATCH_SIZE then break end
			local _, itemCount, locked, _, _, _, itemLink = GetContainerItemInfo(bag, slot)
			if itemLink and not locked then
				-- 6th return from GetItemInfo = itemType (top-level category, e.g.
				-- "Armor", "Weapon", "Quest", "Consumable", "Miscellaneous").
				-- We use this as a defensive second-layer gear check alongside
				-- equipSlot so that books, glyphs, consumables, and other
				-- miscellaneous items with unexpected equipSlot values can
				-- never be caught by the quality-based auto-sell rules.
				local name, _, itemQuality, ilvl, _, itemClass, itemSubType, _, equipSlot, _, vendorPrice = GetItemInfo(itemLink)

				-- Quest items are normally protected from auto-rules, but
				-- the explicit Sell list overrides quest protection (user
				-- intent wins). Auto rules still respect quest items.
				local isQuestItem = (itemClass == "Quest")

				if vendorPrice and vendorPrice > 0 then
					-- "Gear" = equippable slot.
					-- For weapon-slot items (weapons, shields, holdables, ranged,
					-- thrown, relics) we accept ANY itemClass because on PE these
					-- are all treated uniformly as Weapon-affix targets.
					-- For non-weapon gear we still require itemClass to be Armor.
					local isGearItem = false
					local isWeaponSlot = false
					if equipSlot and GEAR_SLOTS[equipSlot] then
						if WEAPON_SLOTS[equipSlot] then
							isGearItem = true
							isWeaponSlot = true
						elseif itemClass == "Armor" or itemClass == "Weapon" then
							isGearItem = true
						end
					end

					-- ============================================================
					-- SELL DECISION CHAIN (this function handles vendoring only;
					-- Auto-Delete Junk/Common live in the delete scanner).
					--
					-- Priority order (highest first):
					--   1. Keep list  - always wins, skips everything below
					--   2. Sell list  - explicit user intent (overrides quest protection)
					--   3. Sell Known Recipes protection/sell - tooltip-confirmed only
					--   4. Greens     - auto-sell, gear only, skips quest items
					--   5. BoE Weapons - Rare/Epic, iLvl gated, skips quest items
					--   6. BoP         - Rare/Epic, iLvl gated, skips quest items
					--   7. BoE Armor   - Rare/Epic, iLvl gated, skips quest items
					-- An item can only match one rule per scan.
					-- ============================================================

					local shouldSell = false
					local sellReason = nil   -- "list" | "knownRecipe" | "greens" | "boeArmor" | "bop" | "boeWeapons"
					local itemId = GetItemIDFromLink(itemLink)
					local onSellList = (itemId and sellIDs[itemId]) or (name and sellNames[Normalize(name)])
					local recipeAction, recipeReason, recipeRule, recipeState, recipeQualityEnabled = nil, nil, nil, nil, nil

					-- Step 1: Keep list short-circuits the whole chain.
					-- Step 1b: Affix Protection also short-circuits before any sell rule.
					local isOnKeepList = _G.AutoDelete_IsWhitelistedFast(keepIDs, keepNames, itemId, name)
					local singleAffixSlot = singleAffixPlan and singleAffixPlan.slots[bag .. ":" .. slot]
					local missingAffixBlocked, missingAffixState = _G.AutoDelete_IsMissingAffixHardStop(profile, bag, slot, itemLink, singleAffixSlot)
					local isAffixProtected = missingAffixBlocked or IsAffixProtected(profile, bag, slot, itemLink, "sell", singleAffixSlot)

					if not isOnKeepList and not isAffixProtected then

						recipeAction, recipeReason, recipeRule, recipeState, recipeQualityEnabled =
							_G.AutoDelete_GetKnownRecipeSellDecision(profile, bag, slot, itemLink, itemClass, itemSubType, itemQuality, isQuestItem, onSellList)

						if recipeAction == "sell" then
							shouldSell = true
							sellReason = recipeReason
						elseif recipeAction == "protect" then
							local blockedSourceRule = nil
							if onSellList then
								blockedSourceRule = "Sell list"
							elseif not isQuestItem and itemQuality == 0 and profile.qualityActionJunk == "sell" then
								blockedSourceRule = "Auto Actions: Junk sell"
							elseif not isQuestItem and itemQuality == 1 and isGearItem and profile.qualityActionCommon == "sell" then
								blockedSourceRule = "Auto Actions: Common gear sell"
							elseif not isQuestItem and itemQuality == 2 and isGearItem and profile.qualityActionGreens == "sell" then
								blockedSourceRule = "Auto Actions: Green gear sell"
							end
							if _G.AutoDelete_RecordDecision and blockedSourceRule then
								_G.AutoDelete_RecordDecision({
									itemName = name,
									itemId = itemId,
									action = "kept",
									reason = recipeReason,
									sourceRule = blockedSourceRule,
									recipeLike = true,
									recipeState = recipeState,
									recipeQuality = itemQuality,
									recipeQualityEnabled = recipeQualityEnabled,
									bag = bag,
									slot = slot,
								})
							end
							if _G.AutoDelete_DebugSell then
								print(string.format(
									"|cffff8000[AutoDelete DEBUG]|r recipe PROTECTED: %s (id=%s) | state=%s | quality=%s | qualityToggle=%s | source=%s | reason=%s",
									tostring(name), tostring(itemId), tostring(recipeState),
									tostring(_G.AutoDelete_GetRecipeQualityLabel(itemQuality)),
									tostring(recipeQualityEnabled), tostring(blockedSourceRule), tostring(recipeReason)
								))
							end
						else
							-- Step 2: Explicit Sell list entry.
							if onSellList then
								shouldSell = true; sellReason = "list"
							end
						end

						-- Steps 3-6 only run for non-quest items. A quest
						-- item only sells if Step 2 matched it explicitly.
						if recipeAction ~= "protect" and not shouldSell and not isQuestItem then

							-- Step 3: Tri-state quality filters (Junk / Common /
							-- Greens). When a quality is set to "sell", items
							-- of that quality are vendored from this loop.
							-- When set to "delete" they're handled by the
							-- delete scanner; "off" skips entirely.
							--
							-- Junk (quality 0): any item type. Junk is universally
							-- vendor-trash; no gear-only restriction.
							-- Common (quality 1): gear only (matches the old
							-- Auto-Delete Common semantics -- selling a stack of
							-- white reagents on a "Sell Common" toggle would be
							-- surprising and destructive).
							-- Greens (quality 2): gear only, same as before.
							if not shouldSell and itemQuality == 0
								and profile.qualityActionJunk == "sell" then
								shouldSell = true; sellReason = "junk"
							end
							if not shouldSell and itemQuality == 1 and isGearItem
								and profile.qualityActionCommon == "sell" then
								shouldSell = true; sellReason = "common"
							end
							if not shouldSell and itemQuality == 2 and isGearItem
								and profile.qualityActionGreens == "sell" then
								shouldSell = true; sellReason = "greens"
							end

							-- Steps 4-6: Sell-tab category sections. Each is
							-- independent. An item is matched to exactly one
							-- category (the first that fits in priority order).
							if not shouldSell and isGearItem
								and (itemQuality == 3 or itemQuality == 4) then

								local isBoE = IsBindOnEquip(bag, slot)
								local rarityIsRare = (itemQuality == 3)
								local rarityIsEpic = (itemQuality == 4)

								-- Helper: is the item's iLvl inside [min, max]?
								local function inRange(min, max)
									return ilvl and ilvl >= (min or 1) and ilvl <= (max or 199)
								end

								-- Step 4: BoE Weapons (BoE + WEAPON_SLOTS).
								if isBoE and isWeaponSlot and profile.boeWeaponsEnabled then
									local rarityOn = (rarityIsRare and profile.boeWeaponsRare)
										or (rarityIsEpic and profile.boeWeaponsEpic)
									if rarityOn and inRange(profile.boeWeaponsIlvlMin, profile.boeWeaponsIlvlMax) then
										shouldSell = true; sellReason = "boeWeapons"
									end

								-- Step 5: BoP (any non-BoE gear).
								elseif (not isBoE) and profile.bopEnabled then
									local rarityOn = (rarityIsRare and profile.bopRare)
										or (rarityIsEpic and profile.bopEpic)
									if rarityOn and inRange(profile.bopIlvlMin, profile.bopIlvlMax) then
										shouldSell = true; sellReason = "bop"
									end

								-- Step 6: BoE Armor (BoE, NOT weapon-slot).
								elseif isBoE and (not isWeaponSlot) and profile.boeArmorEnabled then
									local rarityOn = (rarityIsRare and profile.boeArmorRare)
										or (rarityIsEpic and profile.boeArmorEpic)
									if rarityOn and inRange(profile.boeArmorIlvlMin, profile.boeArmorIlvlMax) then
										shouldSell = true; sellReason = "boeArmor"
									end
								end
							end
						end  -- close: if not shouldSell and not isQuestItem
					elseif _G.AutoDelete_RecordDecision then
						local blockedSourceRule = nil
						if onSellList then
							blockedSourceRule = "Sell list"
						elseif not isQuestItem and itemQuality == 0 and profile.qualityActionJunk == "sell" then
							blockedSourceRule = "Auto Actions: Junk sell"
						elseif not isQuestItem and itemQuality == 1 and isGearItem and profile.qualityActionCommon == "sell" then
							blockedSourceRule = "Auto Actions: Common gear sell"
						elseif not isQuestItem and itemQuality == 2 and isGearItem and profile.qualityActionGreens == "sell" then
							blockedSourceRule = "Auto Actions: Green gear sell"
						end
						if blockedSourceRule then
							_G.AutoDelete_RecordDecision({
								itemName = name,
								itemId = itemId,
								action = "kept",
								reason = isOnKeepList and "Keep list blocked sell"
									or (missingAffixBlocked
										and ("Missing affix hard stop blocked sell" .. (missingAffixState == "unknown" and " (ownership unknown)" or "")))
									or "Affix Protection blocked sell",
								sourceRule = blockedSourceRule,
								bag = bag,
								slot = slot,
							})
						end
					end

					if shouldSell then
						-- DEBUG TRACE: print why the item is selling. Toggle with /del debug.
						-- Shows every input that fed the decision chain so the user can
						-- pinpoint which rule is matching when something unexpected sells.
						if _G.AutoDelete_DebugSell then
							local idStr = itemId and tostring(itemId) or "nil"
							local boeStr = "?"
							if sellReason == "boeWeapons" or sellReason == "boeArmor" or sellReason == "bop" then
								boeStr = (sellReason == "bop") and "BoP" or "BoE"
							end
							print(string.format(
								"|cffff8000[AutoDelete DEBUG]|r SOLD: %s (id=%s) | reason=%s | quality=%s | ilvl=%s | equipSlot=%s | itemClass=%s | isGear=%s | isWeaponSlot=%s | bind=%s",
								tostring(name), idStr, tostring(sellReason),
								tostring(itemQuality), tostring(ilvl),
								tostring(equipSlot), tostring(itemClass),
								tostring(isGearItem), tostring(isWeaponSlot), boeStr
							))
							if _G.AutoDelete_IsRecipeLikeItem(itemClass, itemSubType) then
								print(string.format(
									"|cffff8000[AutoDelete DEBUG]|r recipe SOLD: %s (id=%s) | state=%s | quality=%s | qualityToggle=%s | source=%s",
									tostring(name), idStr, tostring(recipeState),
									tostring(_G.AutoDelete_GetRecipeQualityLabel(itemQuality)),
									tostring(recipeQualityEnabled),
									tostring((sellReason == "knownRecipe" and "Sell Known Recipes") or sellReason)
								))
							end
						end
						-- Flag this call so the UseContainerItem hook skips
						-- (we record the BumpStat directly below).
						autoDeleteSelling = true
						UseContainerItem(bag, slot)
						autoDeleteSelling = false
						batchCount = batchCount + 1
						sellSessionCount = sellSessionCount + 1
						local soldCopper = vendorPrice * (itemCount or 1)
						sellSessionCopper = sellSessionCopper + soldCopper
						-- Tracking: one sell action = one item stack sold (not one unit).
						-- Gold earned counts the actual copper received.
						BumpStat("itemsSold", 1)
						BumpStat("goldEarned", soldCopper)
						if _G.AutoDelete_RecordDecision then
							_G.AutoDelete_RecordDecision({
								itemName = name,
								itemId = itemId,
								action = "sold",
								reason = "Vendor sale executed",
								sourceRule = (sellReason == "list" and "Sell list")
									or (sellReason == "knownRecipe" and "Sell Filters: Sell Known Recipes")
									or (sellReason == "junk" and "Auto Actions: Junk sell")
									or (sellReason == "common" and "Auto Actions: Common gear sell")
									or (sellReason == "greens" and "Auto Actions: Green gear sell")
									or (sellReason == "boeWeapons" and "Sell Filters: BoE Weapons")
									or (sellReason == "bop" and "Sell Filters: BoP")
									or (sellReason == "boeArmor" and "Sell Filters: BoE Armor")
									or tostring(sellReason),
								recipeLike = _G.AutoDelete_IsRecipeLikeItem(itemClass, itemSubType),
								recipeState = recipeState,
								recipeQuality = itemQuality,
								recipeQualityEnabled = recipeQualityEnabled,
								bag = bag,
								slot = slot,
							})
						end
					end
				end
			end
		end
		if batchCount >= SELL_BATCH_SIZE then break end
	end

	if batchCount > 0 then
		sellDryTicks = 0
	else
		sellDryTicks = sellDryTicks + 1
		if sellDryTicks >= 2 and sellSessionCount > 0 then
			print("|cffff8000[AutoDelete]|r Sold " .. sellSessionCount .. " item(s) for " .. FormatMoney(sellSessionCopper))
			sellSessionCount = 0
			sellSessionCopper = 0
			sellDryTicks = 0
			-- After-sell summon: gated by summonScavenger master + summonAfterSell.
			-- Vendor window is still open here (MERCHANT_CLOSED fires later).
			-- If summonOnlyInCombat is set, the player must be in combat here
			-- and when the delayed summon fires.
			if cachedProfile and cachedProfile.summonScavenger and cachedProfile.summonAfterSell then
				local combatOk = (not cachedProfile.summonOnlyInCombat) or (UnitAffectingCombat and UnitAffectingCombat("player"))
				if combatOk then
					_G.AutoDelete_ScavengerLastTriggerReason = "after-sell"
					DelayedSummon(2.0)
				else
					_G.AutoDelete_ScavengerLastTriggerReason = "after-sell-combat-blocked"
				end
			end
		end
	end
end

-- ============================================================================
-- ElvUI Bag Buttons
-- ============================================================================
-- Three buttons attached to the top-right of ElvUI's main bag frame, ordered
-- left-to-right to match the Delete | Sell | Keep tabs in the options panel:
--
--   Delete (red X)         → drop item to add to Delete list; right-click
--                            opens the panel and jumps to the Delete tab
--   Sell (gold coin)       → drop item to add to Sell list; left-click while
--                            at a vendor triggers a sell pass; right-click
--                            opens the panel and jumps to the Sell tab
--   Keep (chocolate box)   → drop item to add to Keep list; right-click
--                            opens the panel and jumps to the Keep tab
--
-- Anchor: Delete is pinned at TOPRIGHT -98 -4 so the row of three (each 20px
-- wide + 4px gap) lands at roughly the same right-edge position as the
-- single-button layout did historically. Sell anchors RIGHT of Delete; Keep
-- RIGHT of Sell. CreateElvUIBagButton runs once at PLAYER_LOGIN (after a 2s
-- delay so ElvUI's container frame is constructed first); no anti-restack
-- guard is needed because there's only one call site.

local function CreateElvUIBagButton()
	local bagFrame = _G.ElvUI_ContainerFrame
	if not bagFrame then return end
	local C_BAG_BUTTON_BG = { 0, 0, 0, 0.6 }
	local C_BAG_BUTTON_BORDER = { 0.20, 0.20, 0.20, 1 }
	local C_BAG_BUTTON_BORDER_HOVER = { 0.40, 0.40, 0.40, 1 }
	local C_TOOLTIP_TITLE = { 0.247, 0.780, 0.922 }
	local C_TOOLTIP_TEXT = { 1, 1, 1 }
	local C_TOOLTIP_WARN = { 1, 0.30, 0.30 }

	-- =====================================================
	-- Delete button (red X) - leftmost in the Delete | Sell | Keep row
	-- =====================================================
	local btn = CreateFrame("Button", "AutoDelete_ElvUIBagBtn", bagFrame)
	btn:SetSize(20, 20)
	btn:SetPoint("TOPRIGHT", bagFrame, "TOPRIGHT", -98, -4)
	btn:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		tile = false, tileSize = 16, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 }
	})
	btn:SetBackdropColor(unpack(C_BAG_BUTTON_BG))
	btn:SetBackdropBorderColor(unpack(C_BAG_BUTTON_BORDER))

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 2, -2)
	icon:SetPoint("BOTTOMRIGHT", -2, 2)
	icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")

	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
		GameTooltip:AddLine("AutoDelete", unpack(C_TOOLTIP_TITLE))
		GameTooltip:AddLine("Drop item to add to Delete List.", unpack(C_TOOLTIP_TEXT))
		GameTooltip:AddLine("Right-click to open settings.", unpack(C_TOOLTIP_TEXT))
		GameTooltip:Show()
		btn:SetBackdropBorderColor(unpack(C_BAG_BUTTON_BORDER_HOVER))
		icon:SetVertexColor(1, 0.2, 0.2)
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
		btn:SetBackdropBorderColor(unpack(C_BAG_BUTTON_BORDER))
		icon:SetVertexColor(1, 1, 1)
	end)

	btn:RegisterForDrag("LeftButton")
	btn:RegisterForClicks("AnyUp")
	btn:SetScript("OnReceiveDrag", function() _G.AutoDelete_AddToDeleteList() end)
	btn:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			-- Right-click: open the panel and jump straight to the Delete
			-- list tab so the user lands on the right list.
			_G.AutoDelete_OpenPanelToList("delete")
		elseif CursorHasItem() then
			_G.AutoDelete_AddToDeleteList()
		end
	end)

	-- =====================================================
	-- Sell button (gold coin) - middle of the row
	-- =====================================================
	local sellBtn = CreateFrame("Button", "AutoDelete_ElvUISellBtn", bagFrame)
	sellBtn:SetSize(20, 20)
	sellBtn:SetPoint("LEFT", btn, "RIGHT", 4, 0)
	sellBtn:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		tile = false, tileSize = 16, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 }
	})
	sellBtn:SetBackdropColor(unpack(C_BAG_BUTTON_BG))
	sellBtn:SetBackdropBorderColor(unpack(C_BAG_BUTTON_BORDER))

	local sellIcon = sellBtn:CreateTexture(nil, "ARTWORK")
	sellIcon:SetPoint("TOPLEFT", 2, -2)
	sellIcon:SetPoint("BOTTOMRIGHT", -2, 2)
	sellIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
	sellIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	sellBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
		GameTooltip:AddLine("Sell Items", unpack(C_TOOLTIP_TITLE))
		GameTooltip:AddLine("Click to sell at vendor.", unpack(C_TOOLTIP_TEXT))
		GameTooltip:AddLine("Drop item to add to Sell List.", unpack(C_TOOLTIP_TEXT))
		GameTooltip:AddLine("Right-click to open settings.", unpack(C_TOOLTIP_TEXT))
		if not MerchantFrame or not MerchantFrame:IsShown() then
			GameTooltip:AddLine("Not at a vendor.", unpack(C_TOOLTIP_WARN))
		end
		GameTooltip:Show()
		sellBtn:SetBackdropBorderColor(unpack(C_BAG_BUTTON_BORDER_HOVER))
		sellIcon:SetVertexColor(1, 1, 0.6)
	end)
	sellBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
		sellBtn:SetBackdropBorderColor(unpack(C_BAG_BUTTON_BORDER))
		sellIcon:SetVertexColor(1, 1, 1)
	end)

	sellBtn:RegisterForDrag("LeftButton")
	sellBtn:RegisterForClicks("AnyUp")
	sellBtn:SetScript("OnReceiveDrag", function() _G.AutoDelete_AddToSellList() end)
	sellBtn:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			-- Right-click: open the panel and jump to the Sell list tab.
			_G.AutoDelete_OpenPanelToList("sell")
		elseif CursorHasItem() then
			_G.AutoDelete_AddToSellList()
		else
			SellItems()
		end
	end)

	-- =====================================================
	-- Keep button (chocolate box) - rightmost in the row
	-- =====================================================
	-- Drop item to add to Keep list; right-click opens the panel and jumps
	-- to the Keep tab. No left-click action (Keep has no vendor/destroy
	-- equivalent - it's a passive protection list).
	local keepBtn = CreateFrame("Button", "AutoDelete_ElvUIKeepBtn", bagFrame)
	keepBtn:SetSize(20, 20)
	keepBtn:SetPoint("LEFT", sellBtn, "RIGHT", 4, 0)
	keepBtn:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		tile = false, tileSize = 16, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 }
	})
	keepBtn:SetBackdropColor(unpack(C_BAG_BUTTON_BG))
	keepBtn:SetBackdropBorderColor(unpack(C_BAG_BUTTON_BORDER))

	local keepIcon = keepBtn:CreateTexture(nil, "ARTWORK")
	keepIcon:SetPoint("TOPLEFT", 2, -2)
	keepIcon:SetPoint("BOTTOMRIGHT", -2, 2)
	keepIcon:SetTexture("Interface\\Icons\\INV_ValentinesBoxOfChocolates02")
	keepIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	keepBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
		GameTooltip:AddLine("Keep List", unpack(C_TOOLTIP_TITLE))
		GameTooltip:AddLine("Drop item to add to Keep List.", unpack(C_TOOLTIP_TEXT))
		GameTooltip:AddLine("Right-click to open settings.", unpack(C_TOOLTIP_TEXT))
		GameTooltip:AddLine("Items on this list are never auto-sold or auto-deleted.", unpack(C_TOOLTIP_TEXT))
		GameTooltip:Show()
		keepBtn:SetBackdropBorderColor(unpack(C_BAG_BUTTON_BORDER_HOVER))
		keepIcon:SetVertexColor(0.6, 0.85, 1)
	end)
	keepBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
		keepBtn:SetBackdropBorderColor(unpack(C_BAG_BUTTON_BORDER))
		keepIcon:SetVertexColor(1, 1, 1)
	end)

	keepBtn:RegisterForDrag("LeftButton")
	keepBtn:RegisterForClicks("AnyUp")
	keepBtn:SetScript("OnReceiveDrag", function() _G.AutoDelete_AddToKeepList() end)
	keepBtn:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then
			-- Right-click: open the panel and jump to the Keep list tab.
			_G.AutoDelete_OpenPanelToList("whitelist")
		elseif CursorHasItem() then
			_G.AutoDelete_AddToKeepList()
		end
	end)
end

-- ============================================================================
-- Cached Profile + Event Frame
-- ============================================================================
-- RefreshCachedProfile updates the upvalue declared at the top of the file
-- (do NOT use `local function` here - that would shadow the forward-declared
-- local that all the closures captured).
--
-- ElvUI shows a coin marker on junk items when E.db.bags.junkIcon is on.
-- If AutoDelete is set to delete junk, that marker becomes misleading: those
-- items will be destroyed, not sold. Suppress only ElvUI's native setting and
-- restore the user's prior value once Junk is no longer in Delete mode.
local function RefreshElvUIJunkIconSuppression(profile)
	local E = _G.ElvUI and _G.ElvUI[1]
	local bags = E and E.db and E.db.bags
	if not bags then return end
	local db = _G.AutoDeleteDB or {}
	_G.AutoDeleteDB = db
	local state = _G.AutoDelete_ElvUIJunkIconState or { active = false, restore = nil }
	_G.AutoDelete_ElvUIJunkIconState = state
	local shouldSuppress = profile and profile.qualityActionJunk == "delete"
	local changed = false

	if shouldSuppress then
		if not state.active then
			if db.elvuiJunkIconRestore == nil then
				db.elvuiJunkIconRestore = bags.junkIcon and true or false
			end
			state.restore = db.elvuiJunkIconRestore
			state.active = true
		end
		if bags.junkIcon ~= false then
			bags.junkIcon = false
			changed = true
		end
	elseif state.active or db.elvuiJunkIconRestore ~= nil then
		local restore = state.restore
		if restore == nil then restore = db.elvuiJunkIconRestore end
		if restore ~= nil and bags.junkIcon ~= restore then
			bags.junkIcon = restore
			changed = true
		end
		state.active = false
		state.restore = nil
		db.elvuiJunkIconRestore = nil
	end

	if changed then
		pcall(function()
			local B = E.GetModule and E:GetModule("Bags", true)
			if B and B.UpdateAllBagSlots then B:UpdateAllBagSlots() end
		end)
	end
end
_G.AutoDelete_RefreshElvUIJunkIconSuppression = RefreshElvUIJunkIconSuppression

-- The `scanner` Frame is the single event hub for the addon. Its OnEvent
-- handler lives further down (after Welcome Popup is defined, because that
-- handler calls ShowWelcomePopup). Its OnUpdate handler is at the very
-- bottom of this file. The frame is created here only so its event
-- registrations happen before any of the function bodies that depend on
-- those events.

RefreshCachedProfile = function()
	local db = GetDB()
	cachedProfile = GetActiveProfile(db)
	RefreshElvUIJunkIconSuppression(cachedProfile)
end
_G.AutoDelete_RefreshCachedProfile = RefreshCachedProfile
-- Read-only accessor for the cached profile. Used by the Process Bags
-- panel (Options.lua) to scan bags without re-reading the DB on every
-- refresh.
function _G.AutoDelete_GetCachedProfile() return cachedProfile end

-- ============================================================================
-- Auto-Add Equipped (settings.autoAddEquipped)
-- ============================================================================
-- Two behaviours, both gated on the same toggle:
--   1) Sync (one-time per toggle-flip from false to true): walk all 19
--      inventory slots and add each equipped item to the Keep list.
--   2) Reactive: PLAYER_EQUIPMENT_CHANGED fires whenever the player swaps
--      gear; the new item in that slot is added to Keep.
-- Both paths funnel through AddItemToKeepQuiet, which is identical to
-- AddItemToList("whitelistText", id) except it suppresses the "added/already
-- in list" chat prints that would spam during a 19-slot sync. Per-list
-- conflict checks still run; conflicts are reported with a single chat line.

-- Inventory slot range to sync. 19 is the upper bound for the equipped
-- inventory in 3.3.5a (1=head ... 19=tabard, with 0=ammo skipped). We skip
-- shirts/tabards since they aren't gear and don't benefit from Keep
-- protection (the auto-rules already exclude them).
local EQUIPPED_SLOT_FIRST = 1
local EQUIPPED_SLOT_LAST  = 19
local SKIPPED_EQUIP_SLOTS = {
	[4]  = true,   -- shirt
	[19] = true,   -- tabard
}

-- Quiet variant of AddItemToList for the keep list. Honors cross-list
-- conflicts (won't add an item that's already on Delete or Sell) but does
-- not print success messages. Returns true on add, false on skip/conflict.
local function AddItemToKeepQuiet(itemId)
	if not itemId then return false end
	local db = GetDB()
	local profile = GetActiveProfile(db)
	local line = "item:" .. tostring(itemId)
	if HasExactLine(profile.whitelistText, line) then return false end

	local hasConflict, conflictKey = FindCrossListConflict(profile, "whitelistText", line)
	if hasConflict then
		local itemName = GetItemInfo(itemId) or ("Item " .. itemId)
		print("|cffff4444[AutoDelete]|r: Cannot auto-add " .. itemName
			.. " to Keep, already on the " .. ListLabelForKey(conflictKey)
			.. " list. Remove it from there first.")
		return false
	end

	profile.whitelistText = AddLineIfMissing(profile.whitelistText or "", line)
	GetItemInfo("item:" .. itemId)   -- prime client cache for the next refresh
	return true
end

-- Walk the equipped inventory and add each item to Keep. Used on toggle
-- flip-to-on and (optionally) PLAYER_LOGIN if we ever wire it that way.
local function SyncEquippedToKeep()
	local added = 0
	for slot = EQUIPPED_SLOT_FIRST, EQUIPPED_SLOT_LAST do
		if not SKIPPED_EQUIP_SLOTS[slot] then
			local link = GetInventoryItemLink("player", slot)
			if link then
				local id = GetItemIDFromLink(link)
				if id and AddItemToKeepQuiet(id) then
					added = added + 1
				end
			end
		end
	end
	if added > 0 then
		print("|cffff8000[AutoDelete]|r Auto-added " .. added
			.. " currently equipped item" .. (added == 1 and "" or "s") .. " to Keep.")
		local panel = _G.AutoDeleteOptionsPanel
		if panel and panel._built and panel:IsVisible()
			and not (panel._rawBoxHolder and panel._rawBoxHolder:IsShown()) then
			panel:Refresh()
		end
	end
	return added
end
_G.AutoDelete_SyncEquippedToKeep = SyncEquippedToKeep

-- Reactive handler for PLAYER_EQUIPMENT_CHANGED. arg1 is the slot id (1-19)
-- of the slot that just changed. We re-read it (instead of trusting an item
-- id from the event) since the event fires on un-equip too, where the slot
-- is now empty.
local function HandleEquipmentChanged(slot)
	if not cachedProfile or not cachedProfile.autoAddEquipped then return end
	if not slot or SKIPPED_EQUIP_SLOTS[slot] then return end
	local link = GetInventoryItemLink("player", slot)
	if not link then return end
	local id = GetItemIDFromLink(link)
	if not id then return end
	if AddItemToKeepQuiet(id) then
		local itemName = GetItemInfo(id) or ("Item " .. id)
		print("|cffff8000[AutoDelete]|r Auto-added " .. itemName .. " to Keep.")
		local panel = _G.AutoDeleteOptionsPanel
		if panel and panel._built and panel:IsVisible()
			and not (panel._rawBoxHolder and panel._rawBoxHolder:IsShown()) then
			panel:Refresh()
		end
	end
end

-- ============================================================================
-- One-Key Open
-- ============================================================================
-- Wires a SecureActionButton to the next "openable" item in the player's
-- bags. The user binds a key in the AutoDelete options panel; pressing it
-- fires `/use <bag> <slot>` for the next targeted item from a hardware-
-- event path, which is the ONLY path on WoW 3.3.5a that satisfies the
-- protected-function gate for UseContainerItem.
--
-- Why a keybind rather than an auto-scanner: confirmed by both Blizzard
-- docs and disassembly of the 3.3.5a client, the protection check lives
-- inside Wow.exe and tests a hardware-event flag set only by real OS
-- input. No Lua technique flips it; every working WotLK addon in this
-- space uses this same SecureActionButton + macrotext + user-keypress
-- pattern. An earlier draft of this module shipped an automatic scanner; testing on
-- Project Ebonhold confirmed every clam, junkbox, and lockbox tripped
-- ADDON_ACTION_BLOCKED. We deleted it.
--
-- AUTO_OPEN_ALLOW: explicit allow-list of items the keybind can target.
-- 3.3.5a does NOT expose an "is openable" flag on container slots, and
-- class/subclass inference catches the wrong items (every potion is
-- "consumable"). Values:
--   true  = always targetable
--   false = targetable ONLY if currently unlocked (e.g. a Battered Junkbox
--           the rogue has Pick-Locked). IsItemLocked confirms the state.
--
-- Wrapped in a `do ... end` block so all the locals stay out of the main
-- chunk's 200-local cap (Lua 5.1 limit; we'd otherwise bump against it).
do

local AUTO_OPEN_ALLOW = {
	-- Clams (food + pearl drops). Mob drops and fishing pulls.
	[5523]  = true,  -- Small Barnacled Clam
	[5524]  = true,  -- Thick-shelled Clam
	[7973]  = true,  -- Big-mouth Clam
	[15874] = true,  -- Soft-shelled Clam
	[24476] = true,  -- Jaggal Clam
	[36781] = true,  -- Darkwater Clam
	-- Coin purses (rogue pickpocket loot, vendor-buyable consumables).
	[10456] = true,  -- A Bulging Coin Purse
	[10654] = true,  -- A Heavy Coin Purse
	[10720] = true,  -- A Small Coin Purse
	[10940] = true,  -- A Rich Coin Purse
	-- Crates / sealed shipments. No cast required.
	[4633]  = true,  -- Heavy Crate
	[4634]  = true,  -- Iron-Bound Trunk
	[4638]  = true,  -- Reinforced Locked Chest
	[34440] = true,  -- Tightly Sealed Trunk
	-- Lockboxes / locked chests. Targetable only when unlocked.
	[4636]  = false, -- Strong Iron Lockbox
	[4637]  = false, -- Sturdy Locked Chest
	[5758]  = false, -- Mithril Lockbox
	[5759]  = false, -- Thorium Lockbox
	[5760]  = false, -- Eternium Lockbox
	[6354]  = false, -- Small Locked Chest
	[6355]  = false, -- Sturdy Locked Chest
	-- Junkboxes (rogue Pick Lock targets).
	[16882] = false, -- Battered Junkbox
	[16883] = false, -- Worn Junkbox
	[16884] = false, -- Sturdy Junkbox
	[16885] = false, -- Heavy Junkbox
	[29569] = false, -- Strong Junkbox (TBC)
	[43575] = false, -- Reinforced Junkbox (WotLK)
	-- WotLK lockboxes.
	[43622] = false, -- Iceforged Lockbox
	[43624] = false, -- Frozen Lockbox
	-- Mysterious Eggs / oracle holiday loot.
	[39878] = true,  -- Mysterious Egg (Oracle)
	[44663] = true,  -- Cracked Egg
	-- Gift bags / event containers.
	[34480] = true,  -- Sealed Pollen-Packed Envelope (Noblegarden)
}

-- Module state. The button is created at PLAYER_LOGIN; before then the
-- helpers below safely no-op via the `if not openButton` guard.
local openButton          = nil
local openUpdatePending   = false  -- true while a SetAttribute is deferred for combat
local openLastTarget      = nil    -- { bag, slot, link, name } or nil

-- Walks the bags looking for the next eligible target. Priority order is
-- bag/slot ascending so two players standing at the same vendor with the
-- same loot will see the same "next" item. Returns (bag, slot, link, name)
-- or nil on no match.
-- Per-slot predicate. Returns true if the slot holds an item that the
-- One-Key Open feature should target. Profile flags gate the answer so
-- the Process Bags panel can call this with the live profile and get
-- the same answer the keybind scanner would.
-- IgnoringKeep variant: runs every eligibility check EXCEPT the Keep-list
-- filter. The v3.20 Keep-list override popup needs to detect items that
-- WOULD have been the next target if not for the Keep list, then offer
-- the user a choice; that requires a predicate that ignores Keep. The
-- public IsOpenable wrapper layers the Keep check back on so external
-- callers (Process Bags panel, etc.) see the same "Keep wins" behavior
-- as the other three actions.
--
-- Exposed on _G to keep the main chunk under Lua 5.1's 200-local cap
-- (wiki §13.1). Same pattern the addon already uses for cross-file
-- helpers like _G.AutoDelete_RefreshOwnedAffixes.
function _G.AutoDelete_IsOpenable_IgnoringKeep(profile, bag, slot)
	if not profile or not profile.autoOpenEnabled then return false end
	local link = GetContainerItemLink(bag, slot)
	if not link then return false end
	local id = GetItemIDFromLink(link)
	if not id then return false end
	local allow = AUTO_OPEN_ALLOW[id]
	if allow == nil then return false end
	-- Lock check: items with allow==true bypass it; items with allow==false
	-- are skipped while still locked. The autoOpenIncludeLocked toggle gates
	-- whether locked-tier items are considered at all.
	if allow == true then return true end
	if not profile.autoOpenIncludeLocked then return false end
	return not IsItemLocked(bag, slot)
end

local function IsOpenable(profile, bag, slot)
	if not _G.AutoDelete_IsOpenable_IgnoringKeep(profile, bag, slot) then return false end
	-- v3.20: Keep-list check added (was missing in prior versions; the gap
	-- meant a clam on the Keep list could still be auto-opened by the
	-- keybind, contradicting "Keep wins" behavior the other three actions
	-- already had).
	local link = GetContainerItemLink(bag, slot)
	local id = GetItemIDFromLink(link)
	local name = GetItemInfo(link)
	if not name then return false end
	if IsWhitelisted(profile, id, name) then return false end
	return true
end

local function FindNextOpenable(profile)
	if not profile or not profile.autoOpenEnabled then return nil end
	if _G.AutoDelete_SpikeDebug then
		local _sc = _G.AutoDelete_SpikeCounters
		local _ss = _G.AutoDelete_SpikeSession
		_sc.find = (_sc.find or 0) + 1
		_ss.find = (_ss.find or 0) + 1
	end
	for bag = 0, NUM_BAG_SLOTS do
		local slots = GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			if IsOpenable(profile, bag, slot) then
				local link = GetContainerItemLink(bag, slot)
				local name = GetItemInfo(link) or "?"
				return bag, slot, link, name
			end
		end
	end
	return nil
end

-- Export so the Process Bags aggregator can call this predicate alongside
-- the disenchant / mill / prospect predicates exported from their modules.
_G.AutoDelete_IsOpenable = IsOpenable

-- Writes the macrotext attribute. MUST be out of combat (caller's job to
-- check). Empty body on no-target so a stale keypress no-ops cleanly
-- rather than firing `/use` against a slot whose contents changed since
-- the last rescan (e.g. the player looted an item into the staged slot).
local function ApplyOpenMacrotext(bag, slot)
	if not openButton then return end
	if bag and slot then
		openButton:SetAttribute("macrotext", "/use " .. bag .. " " .. slot)
	else
		openButton:SetAttribute("macrotext", "")
	end
end

-- Rescans and rewires the button. Self-defers via InCombatLockdown so we
-- never trip the SetAttribute taint protection; PLAYER_REGEN_ENABLED's
-- handler flushes the deferred update post-combat. Cheap when the feature
-- is off (one bool check, no scan).
local function UpdateOpenButton()
	if not openButton then return end
	if _G.AutoDelete_IsOneKeyLocked and _G.AutoDelete_IsOneKeyLocked("open") then
		if InCombatLockdown and InCombatLockdown() then
			openUpdatePending = true
			return
		end
		ApplyOpenMacrotext(nil, nil)
		return
	end
	local profile = cachedProfile
	if not profile or not profile.autoOpenEnabled then
		-- Cheap idempotent short-circuit: if we've already cleared the
		-- target, the macrotext is empty too -- no SetAttribute call
		-- needed. This is the hot path for users with the feature off.
		if openLastTarget == nil and not openUpdatePending then return end
		openLastTarget = nil
		if InCombatLockdown and InCombatLockdown() then
			openUpdatePending = true
		else
			ApplyOpenMacrotext(nil, nil)
		end
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		openUpdatePending = true
		return
	end
	-- v3.20 Keep-list override (see UpdateDisenchantButton for the pattern).
	local _oo = _G.AutoDelete_KeepOverrideTargets and _G.AutoDelete_KeepOverrideTargets.open
	if _oo then
		local _oLink = GetContainerItemLink(_oo.bag, _oo.slot)
		local _oId = _oLink and GetItemIDFromLink(_oLink) or nil
		if _oId == _oo.id then
			local _oName = GetItemInfo(_oLink)
			openLastTarget = { bag = _oo.bag, slot = _oo.slot, link = _oLink, name = _oName }
			ApplyOpenMacrotext(_oo.bag, _oo.slot)
			local panel = _G.AutoDeleteOptionsPanel
			if panel and panel.IsShown and panel:IsShown() and panel._refreshOpenStatus then
				panel:_refreshOpenStatus()
			end
			return
		end
		_G.AutoDelete_KeepOverrideTargets.open = nil
	end
	local bag, slot, link, name = FindNextOpenable(profile)
	if bag and slot then
		openLastTarget = { bag = bag, slot = slot, link = link, name = name }
	else
		openLastTarget = nil
	end
	ApplyOpenMacrotext(bag, slot)
	-- Push the new "Next: ..." text to the options panel if it's open.
	local panel = _G.AutoDeleteOptionsPanel
	if panel and panel.IsShown and panel:IsShown() and panel._refreshOpenStatus then
		panel:_refreshOpenStatus()
	end
end

-- Status string for the options UI. Pure helper, safe to call any time.
local function GetOpenStatus()
	local profile = cachedProfile
	if not profile or not profile.autoOpenEnabled then
		return "Disabled", 0.55, 0.55, 0.55
	end
	local lockLeft = _G.AutoDelete_GetOneKeyLockRemaining and _G.AutoDelete_GetOneKeyLockRemaining("open") or 0
	if lockLeft > 0 then
		return string.format("Waiting %.1fs", lockLeft), 1.0, 0.82, 0.0
	end
	if openLastTarget and openLastTarget.link then
		return "Next: " .. openLastTarget.link, 0.7, 0.85, 1.0
	end
	return "No openable items in bags", 0.55, 0.55, 0.55
end

function _G.AutoDelete_GetOpenLastTarget() return openLastTarget end
function _G.AutoDelete_SetOpenLastTarget(target) openLastTarget = target end

-- Returns/creates the secure button. Called from PLAYER_LOGIN. Separate
-- function so the event handler can call this and immediately do an
-- UpdateOpenButton() pass to wire the first target.
local function EnsureOpenButton()
	if openButton then return openButton end
	openButton = CreateFrame(
		"Button",
		"AutoDeleteOpenButton",
		UIParent,
		"SecureActionButtonTemplate"
	)
	openButton:Hide()                    -- invisible; only the bound key matters
	openButton:RegisterForClicks("AnyUp")
	openButton:SetAttribute("type", "macro")
	openButton:SetAttribute("macrotext", "")
	openButton:HookScript("PreClick", function()
		if _G.AutoDelete_OnOneKeyPreClick then _G.AutoDelete_OnOneKeyPreClick("open") end
	end)
	openButton:HookScript("PostClick", function()
		if _G.AutoDelete_OnOneKeyPostClick then _G.AutoDelete_OnOneKeyPostClick("open") end
	end)
	return openButton
end

-- Called from the PLAYER_REGEN_ENABLED handler. If the macrotext update
-- was blocked by combat, flush it now. The pending flag prevents redundant
-- scans when nothing actually changed.
local function FlushDeferredOpenUpdate()
	if not openUpdatePending then return end
	openUpdatePending = false
	UpdateOpenButton()
end

-- Exports. Inside the `do` block so the locals above stay scoped here;
-- only these globals leak out to the main chunk.
_G.AutoDelete_EnsureOpenButton        = EnsureOpenButton
_G.AutoDelete_UpdateOpenButton        = UpdateOpenButton
_G.AutoDelete_FlushDeferredOpenUpdate = FlushDeferredOpenUpdate
_G.AutoDelete_GetOpenStatus           = GetOpenStatus

end  -- end of One-Key Open `do` block

-- ============================================================================
-- One-Key Mill
-- ============================================================================
-- SecureActionButton wired to the next stack of 5+ herbs in bags. User
-- binds a key in the Keybinds tab; pressing it fires `/cast Milling` +
-- `/use bag slot` for the staged stack. Same hardware-event-required gate
-- as One-Key Disenchant; same wrap-in-do-block pattern to stay under Lua
-- 5.1's main-chunk local cap.
--
-- Eligibility (IsMillable):
--   - Character knows Milling spell (spellbook scan)
--   - Stack of 5+ in a single slot (Milling consumes 5 per cast)
--   - itemType == "Trade Goods" and itemSubType == "Herb" per GetItemInfo
--   - Not on the Keep list, not a quest item
do

local MILL_SPELL_ID = 51005
local cachedMillName    = nil
local cachedMillKnown   = false

local function RefreshMillKnown()
	cachedMillName = cachedMillName or GetSpellInfo(MILL_SPELL_ID)
	if not cachedMillName then cachedMillKnown = false; return end
	local i = 1
	while true do
		local name = GetSpellName(i, BOOKTYPE_SPELL)
		if not name then break end
		if name == cachedMillName then cachedMillKnown = true; return end
		i = i + 1
	end
	cachedMillKnown = false
end

local function CharacterCanMill() return cachedMillKnown end
function _G.AutoDelete_CanMill() return cachedMillKnown end

-- IgnoringKeep variant on _G to dodge Lua 5.1's 200-local cap (see
-- AutoDelete_IsOpenable_IgnoringKeep for rationale). Same eligibility
-- checks as IsMillable but skips IsWhitelisted so the Keep-override popup
-- can detect blocked items.
function _G.AutoDelete_IsMillable_IgnoringKeep(profile, bag, slot)
	local link = GetContainerItemLink(bag, slot)
	if not link then return false end
	local id = GetItemIDFromLink(link)
	if not id then return false end
	if IsQuestItem and IsQuestItem(bag, slot) then return false end
	-- Stack-of-5 check: Milling fails to cast otherwise.
	local _, count = GetContainerItemInfo(bag, slot)
	if not count or count < 5 then return false end
	local name, _, _, _, _, itemType, itemSubType = GetItemInfo(link)
	if not name then return false end
	-- Herb classification via the localized "Trade Goods / Herb" subtype.
	-- NOTE: enUS-only by design. Project Ebonhold is English. If AutoDelete
	-- is ever ported to another locale fork, swap to numeric item subclass
	-- IDs (3.3.5a Trade Goods herbs = LE_ITEM_TRADE_GOODS_HERB).
	if itemType ~= "Trade Goods" then return false end
	if itemSubType ~= "Herb" then return false end
	return true
end

local function IsMillable(profile, bag, slot)
	if not _G.AutoDelete_IsMillable_IgnoringKeep(profile, bag, slot) then return false end
	local link = GetContainerItemLink(bag, slot)
	local id = GetItemIDFromLink(link)
	local name = GetItemInfo(link)
	if IsWhitelisted(profile, id, name) then return false end
	return true
end

local function FindMillTarget(profile)
	if not profile or not profile.millEnabled then return nil end
	if not CharacterCanMill() then return nil end
	if _G.AutoDelete_SpikeDebug then
		local _sc = _G.AutoDelete_SpikeCounters
		local _ss = _G.AutoDelete_SpikeSession
		_sc.find = (_sc.find or 0) + 1
		_ss.find = (_ss.find or 0) + 1
	end
	for bag = 0, NUM_BAG_SLOTS do
		local slots = GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			if IsMillable(profile, bag, slot) then
				local link = GetContainerItemLink(bag, slot)
				local name = GetItemInfo(link) or "?"
				return bag, slot, link, name
			end
		end
	end
	return nil
end

local millButton          = nil
local millUpdatePending   = false
local millLastTarget      = nil

local function ApplyMillMacrotext(bag, slot)
	if not millButton then return end
	local name = cachedMillName or "Milling"
	if bag and slot then
		millButton:SetAttribute("macrotext",
			"/cast " .. name .. "\n/use " .. bag .. " " .. slot)
	else
		millButton:SetAttribute("macrotext", "")
	end
end

local function UpdateMillButton()
	if not millButton then return end
	if _G.AutoDelete_IsOneKeyLocked and _G.AutoDelete_IsOneKeyLocked("mill") then
		if InCombatLockdown and InCombatLockdown() then
			millUpdatePending = true
			return
		end
		ApplyMillMacrotext(nil, nil)
		return
	end
	local profile = cachedProfile
	if not profile or not profile.millEnabled or not CharacterCanMill() then
		-- Cheap idempotent short-circuit (see UpdateOpenButton for rationale).
		if millLastTarget == nil and not millUpdatePending then return end
		millLastTarget = nil
		if InCombatLockdown and InCombatLockdown() then
			millUpdatePending = true
		else
			ApplyMillMacrotext(nil, nil)
		end
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		millUpdatePending = true
		return
	end
	-- v3.20 Keep-list override (see UpdateDisenchantButton for the pattern).
	local _om = _G.AutoDelete_KeepOverrideTargets and _G.AutoDelete_KeepOverrideTargets.mill
	if _om then
		local _oLink = GetContainerItemLink(_om.bag, _om.slot)
		local _oId = _oLink and GetItemIDFromLink(_oLink) or nil
		if _oId == _om.id then
			local _oName = GetItemInfo(_oLink)
			millLastTarget = { bag = _om.bag, slot = _om.slot, link = _oLink, name = _oName }
			ApplyMillMacrotext(_om.bag, _om.slot)
			local panel = _G.AutoDeleteOptionsPanel
			if panel and panel.IsShown and panel:IsShown() and panel._refreshMillStatus then
				panel:_refreshMillStatus()
			end
			return
		end
		_G.AutoDelete_KeepOverrideTargets.mill = nil
	end
	local bag, slot, link, name = FindMillTarget(profile)
	if bag and slot then
		millLastTarget = { bag = bag, slot = slot, link = link, name = name }
	else
		millLastTarget = nil
	end
	ApplyMillMacrotext(bag, slot)
	local panel = _G.AutoDeleteOptionsPanel
	if panel and panel.IsShown and panel:IsShown() and panel._refreshMillStatus then
		panel:_refreshMillStatus()
	end
end

local function GetMillStatus()
	local profile = cachedProfile
	if not profile or not profile.millEnabled then
		return "Disabled", 0.55, 0.55, 0.55
	end
	if not CharacterCanMill() then
		return "Requires Inscription", 1.0, 0.3, 0.3
	end
	local lockLeft = _G.AutoDelete_GetOneKeyLockRemaining and _G.AutoDelete_GetOneKeyLockRemaining("mill") or 0
	if lockLeft > 0 then
		return string.format("Waiting %.1fs", lockLeft), 1.0, 0.82, 0.0
	end
	if millLastTarget and millLastTarget.link then
		return "Next: " .. millLastTarget.link, 0.7, 0.85, 1.0
	end
	return "No millable herbs in bags", 0.55, 0.55, 0.55
end

function _G.AutoDelete_GetMillLastTarget() return millLastTarget end
function _G.AutoDelete_SetMillLastTarget(target) millLastTarget = target end
function _G.AutoDelete_GetCachedMillName() return cachedMillName end

local function EnsureMillButton()
	if millButton then return millButton end
	millButton = CreateFrame("Button", "AutoDeleteMillButton", UIParent,
		"SecureActionButtonTemplate")
	millButton:Hide()
	millButton:RegisterForClicks("AnyUp")
	millButton:SetAttribute("type", "macro")
	millButton:SetAttribute("macrotext", "")
	millButton:HookScript("PreClick", function()
		if _G.AutoDelete_OnOneKeyPreClick then _G.AutoDelete_OnOneKeyPreClick("mill") end
	end)
	millButton:HookScript("PostClick", function()
		if _G.AutoDelete_OnOneKeyPostClick then _G.AutoDelete_OnOneKeyPostClick("mill") end
	end)
	return millButton
end

local function FlushDeferredMillUpdate()
	if not millUpdatePending then return end
	millUpdatePending = false
	UpdateMillButton()
end

_G.AutoDelete_EnsureMillButton        = EnsureMillButton
_G.AutoDelete_UpdateMillButton        = UpdateMillButton
_G.AutoDelete_FlushDeferredMillUpdate = FlushDeferredMillUpdate
_G.AutoDelete_GetMillStatus           = GetMillStatus
_G.AutoDelete_RefreshMillKnown        = RefreshMillKnown
_G.AutoDelete_IsMillable              = IsMillable

end  -- end of One-Key Mill `do` block

-- ============================================================================
-- One-Key Prospect
-- ============================================================================
-- Identical architecture to One-Key Mill, but for Jewelcrafting's
-- Prospecting cast on stacks of 5+ ore. Profession spell ID 31252.

do

local PROSPECT_SPELL_ID = 31252
local cachedProspectName  = nil
local cachedProspectKnown = false

local function RefreshProspectKnown()
	cachedProspectName = cachedProspectName or GetSpellInfo(PROSPECT_SPELL_ID)
	if not cachedProspectName then cachedProspectKnown = false; return end
	local i = 1
	while true do
		local name = GetSpellName(i, BOOKTYPE_SPELL)
		if not name then break end
		if name == cachedProspectName then cachedProspectKnown = true; return end
		i = i + 1
	end
	cachedProspectKnown = false
end

local function CharacterCanProspect() return cachedProspectKnown end
function _G.AutoDelete_CanProspect() return cachedProspectKnown end

-- IgnoringKeep on _G for the local-cap reason.
function _G.AutoDelete_IsProspectable_IgnoringKeep(profile, bag, slot)
	local link = GetContainerItemLink(bag, slot)
	if not link then return false end
	local id = GetItemIDFromLink(link)
	if not id then return false end
	if IsQuestItem and IsQuestItem(bag, slot) then return false end
	local _, count = GetContainerItemInfo(bag, slot)
	if not count or count < 5 then return false end
	local name, _, _, _, _, itemType, itemSubType = GetItemInfo(link)
	if not name then return false end
	if itemType ~= "Trade Goods" then return false end
	-- "Metal & Stone" is the localized enUS string for the ore subtype.
	-- NOTE: enUS-only by design. PE is English. For a non-English port,
	-- use numeric item subclass IDs (Trade Goods Metal & Stone = LE_ITEM_TRADE_GOODS_METAL_STONE).
	if itemSubType ~= "Metal & Stone" then return false end
	return true
end

local function IsProspectable(profile, bag, slot)
	if not _G.AutoDelete_IsProspectable_IgnoringKeep(profile, bag, slot) then return false end
	local link = GetContainerItemLink(bag, slot)
	local id = GetItemIDFromLink(link)
	local name = GetItemInfo(link)
	if IsWhitelisted(profile, id, name) then return false end
	return true
end

local function FindProspectTarget(profile)
	if not profile or not profile.prospectEnabled then return nil end
	if not CharacterCanProspect() then return nil end
	if _G.AutoDelete_SpikeDebug then
		local _sc = _G.AutoDelete_SpikeCounters
		local _ss = _G.AutoDelete_SpikeSession
		_sc.find = (_sc.find or 0) + 1
		_ss.find = (_ss.find or 0) + 1
	end
	for bag = 0, NUM_BAG_SLOTS do
		local slots = GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			if IsProspectable(profile, bag, slot) then
				local link = GetContainerItemLink(bag, slot)
				local name = GetItemInfo(link) or "?"
				return bag, slot, link, name
			end
		end
	end
	return nil
end

local prospectButton          = nil
local prospectUpdatePending   = false
local prospectLastTarget      = nil

local function ApplyProspectMacrotext(bag, slot)
	if not prospectButton then return end
	local name = cachedProspectName or "Prospecting"
	if bag and slot then
		prospectButton:SetAttribute("macrotext",
			"/cast " .. name .. "\n/use " .. bag .. " " .. slot)
	else
		prospectButton:SetAttribute("macrotext", "")
	end
end

local function UpdateProspectButton()
	if not prospectButton then return end
	if _G.AutoDelete_IsOneKeyLocked and _G.AutoDelete_IsOneKeyLocked("prospect") then
		if InCombatLockdown and InCombatLockdown() then
			prospectUpdatePending = true
			return
		end
		ApplyProspectMacrotext(nil, nil)
		return
	end
	local profile = cachedProfile
	if not profile or not profile.prospectEnabled or not CharacterCanProspect() then
		-- Cheap idempotent short-circuit (see UpdateOpenButton for rationale).
		if prospectLastTarget == nil and not prospectUpdatePending then return end
		prospectLastTarget = nil
		if InCombatLockdown and InCombatLockdown() then
			prospectUpdatePending = true
		else
			ApplyProspectMacrotext(nil, nil)
		end
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		prospectUpdatePending = true
		return
	end
	-- v3.20 Keep-list override (see UpdateDisenchantButton for the pattern).
	local _op = _G.AutoDelete_KeepOverrideTargets and _G.AutoDelete_KeepOverrideTargets.prospect
	if _op then
		local _oLink = GetContainerItemLink(_op.bag, _op.slot)
		local _oId = _oLink and GetItemIDFromLink(_oLink) or nil
		if _oId == _op.id then
			local _oName = GetItemInfo(_oLink)
			prospectLastTarget = { bag = _op.bag, slot = _op.slot, link = _oLink, name = _oName }
			ApplyProspectMacrotext(_op.bag, _op.slot)
			local panel = _G.AutoDeleteOptionsPanel
			if panel and panel.IsShown and panel:IsShown() and panel._refreshProspectStatus then
				panel:_refreshProspectStatus()
			end
			return
		end
		_G.AutoDelete_KeepOverrideTargets.prospect = nil
	end
	local bag, slot, link, name = FindProspectTarget(profile)
	if bag and slot then
		prospectLastTarget = { bag = bag, slot = slot, link = link, name = name }
	else
		prospectLastTarget = nil
	end
	ApplyProspectMacrotext(bag, slot)
	local panel = _G.AutoDeleteOptionsPanel
	if panel and panel.IsShown and panel:IsShown() and panel._refreshProspectStatus then
		panel:_refreshProspectStatus()
	end
end

local function GetProspectStatus()
	local profile = cachedProfile
	if not profile or not profile.prospectEnabled then
		return "Disabled", 0.55, 0.55, 0.55
	end
	if not CharacterCanProspect() then
		return "Requires Jewelcrafting", 1.0, 0.3, 0.3
	end
	local lockLeft = _G.AutoDelete_GetOneKeyLockRemaining and _G.AutoDelete_GetOneKeyLockRemaining("prospect") or 0
	if lockLeft > 0 then
		return string.format("Waiting %.1fs", lockLeft), 1.0, 0.82, 0.0
	end
	if prospectLastTarget and prospectLastTarget.link then
		return "Next: " .. prospectLastTarget.link, 0.7, 0.85, 1.0
	end
	return "No prospectable ore in bags", 0.55, 0.55, 0.55
end

function _G.AutoDelete_GetProspectLastTarget() return prospectLastTarget end
function _G.AutoDelete_SetProspectLastTarget(target) prospectLastTarget = target end
function _G.AutoDelete_GetCachedProspectName() return cachedProspectName end

local function EnsureProspectButton()
	if prospectButton then return prospectButton end
	prospectButton = CreateFrame("Button", "AutoDeleteProspectButton", UIParent,
		"SecureActionButtonTemplate")
	prospectButton:Hide()
	prospectButton:RegisterForClicks("AnyUp")
	prospectButton:SetAttribute("type", "macro")
	prospectButton:SetAttribute("macrotext", "")
	prospectButton:HookScript("PreClick", function()
		if _G.AutoDelete_OnOneKeyPreClick then _G.AutoDelete_OnOneKeyPreClick("prospect") end
	end)
	prospectButton:HookScript("PostClick", function()
		if _G.AutoDelete_OnOneKeyPostClick then _G.AutoDelete_OnOneKeyPostClick("prospect") end
	end)
	return prospectButton
end

local function FlushDeferredProspectUpdate()
	if not prospectUpdatePending then return end
	prospectUpdatePending = false
	UpdateProspectButton()
end

_G.AutoDelete_EnsureProspectButton        = EnsureProspectButton
_G.AutoDelete_UpdateProspectButton        = UpdateProspectButton
_G.AutoDelete_FlushDeferredProspectUpdate = FlushDeferredProspectUpdate
_G.AutoDelete_GetProspectStatus           = GetProspectStatus
_G.AutoDelete_RefreshProspectKnown        = RefreshProspectKnown
_G.AutoDelete_IsProspectable              = IsProspectable

end  -- end of One-Key Prospect `do` block

-- ============================================================================
-- One-Key Disenchant
-- ============================================================================
-- A SecureActionButton whose `macrotext` attribute is rewritten by addon code
-- between key presses to point at the next disenchantable BoP item in bags.
-- The user assigns a key in Key Bindings -> AutoDelete; pressing the key fires
-- `/cast Disenchant` followed by `/use <bag> <slot>` from a hardware-event path,
-- which is the only way to cast Disenchant on a bag item without tripping
-- 3.3.5a's protected-function gate.
--
-- Combat safety: SetAttribute on a secure button is forbidden in combat (taint),
-- so updates are queued during combat and flushed on PLAYER_REGEN_ENABLED.
-- The user can still press the button mid-combat; it just casts whatever target
-- was wired before combat started.
--
-- Eligibility (IsDisenchantable):
--   - Character knows the Disenchant spell (spellbook scan)
--   - Item is Armor (class 2) or Weapon (class 1) per GetItemInfo
--   - Quality is Uncommon (2), or Rare (3) if disenchantRare toggle is on
--   - Item is Soulbound (tooltip scan)
--   - Item is NOT on the Keep list, NOT a quest item

-- Spell ID 13262 = Disenchant. Cached localized name resolved on first use
-- so the spellbook scan is locale-correct without hardcoding "Disenchant".
local DISENCHANT_SPELL_ID = 13262
local cachedDisenchantName = nil
local cachedDisenchantKnown = false

-- Walks the player's spellbook looking for the Disenchant spell. Cached
-- result is read by every UI refresh and every bag scan, so the cost of
-- the walk is paid only when SPELLS_CHANGED fires.
local function RefreshDisenchantKnown()
	cachedDisenchantName = cachedDisenchantName or GetSpellInfo(DISENCHANT_SPELL_ID)
	if not cachedDisenchantName then
		cachedDisenchantKnown = false
		return
	end
	-- BOOKTYPE_SPELL is "spell"; iterate until GetSpellName returns nil.
	local i = 1
	while true do
		local name = GetSpellName(i, BOOKTYPE_SPELL)
		if not name then break end
		if name == cachedDisenchantName then
			cachedDisenchantKnown = true
			return
		end
		i = i + 1
	end
	cachedDisenchantKnown = false
end

-- Public-ish accessors (used by the Options UI refresh code and the scan).
local function CharacterCanDisenchant() return cachedDisenchantKnown end

-- iLvl floors for Disenchant. Items below the floor for their quality
-- cannot be disenchanted on the live 3.3.5a client; targeting them just
-- wastes a keypress. Numbers are conservative (Blizzard's published values).
-- These are used when the profile's disenchantIlvlMin is 0 (the default,
-- meaning "use the mechanical floor"); a non-zero profile value overrides
-- the per-quality default with a single global floor.
local DE_UNCOMMON_FLOOR = 5
local DE_RARE_FLOOR     = 55
local DE_EPIC_FLOOR     = 95
-- Upper bounds left open; the spell handles "above max" by refusing to cast.

-- Returns true if (bag, slot) holds an item that the disenchant macro
-- should target, given the current profile. Caller is responsible for
-- the disenchantEnabled gate and the CharacterCanDisenchant check.
--
-- v3.20: split into a Keep-ignoring inner predicate + a wrapper that
-- adds the Keep check, so the override popup can detect Keep-blocked
-- items in a single bag walk. See AutoDelete_IsOpenable_IgnoringKeep above
-- for the design rationale and the FindDisenchantTargetWithKeep two-pass
-- function below for how this is consumed.
--
-- Exposed on _G to dodge Lua 5.1's 200-local cap (wiki §13.1).
function _G.AutoDelete_IsDisenchantable_IgnoringKeep(profile, bag, slot)
	local link = GetContainerItemLink(bag, slot)
	if not link then return false end
	local id = GetItemIDFromLink(link)
	if not id then return false end
	-- Quest items are never targets (consistent with every other auto-rule).
	if IsQuestItem and IsQuestItem(bag, slot) then return false end
	local name, _, quality, ilvl, _, itemType = GetItemInfo(link)
	if not name then return false end
	-- Armor or Weapon. 3.3.5a's GetItemInfo returns the 6th value as the
	-- localized itemType string, not a numeric classId (the numeric class
	-- was added in later expansions and is unreliable on base 3.3.5a).
	-- TODO: non-English locales need a translation table; for enUS this
	-- matches the live game strings exactly.
	if itemType ~= "Armor" and itemType ~= "Weapon" then return false end

	-- Quality gate. Each tier has its own toggle and its own mechanical
	-- iLvl floor; the profile's disenchantIlvlMin overrides the floor when
	-- set, disenchantIlvlMax adds an optional ceiling. Both are zero by
	-- default ("no override / no cap").
	ilvl = ilvl or 0
	local effectiveFloor, effectiveCeiling
	if quality == 2 then
		if not profile.disenchantUncommon then return false end
		effectiveFloor = DE_UNCOMMON_FLOOR
	elseif quality == 3 then
		if not profile.disenchantRare then return false end
		effectiveFloor = DE_RARE_FLOOR
	elseif quality == 4 then
		if not profile.disenchantEpic then return false end
		effectiveFloor = DE_EPIC_FLOOR
	else
		return false
	end
	-- Profile-level overrides. Non-zero values replace the per-quality floor
	-- or impose a ceiling; zero leaves the default behavior intact.
	local floorOverride = tonumber(profile.disenchantIlvlMin) or 0
	if floorOverride > 0 then effectiveFloor = floorOverride end
	local ceilingOverride = tonumber(profile.disenchantIlvlMax) or 0
	if ceilingOverride > 0 then effectiveCeiling = ceilingOverride end
	if ilvl < effectiveFloor then return false end
	if effectiveCeiling and ilvl > effectiveCeiling then return false end

	-- Bind-state gate. An item in the player's bags is in exactly one of
	-- three states for our purposes:
	--   1) Soulbound (BoP or bound-BoE)         -> route through disenchantBoP
	--   2) BoE not yet bound                    -> route through disenchantBoE
	--   3) Anything else (e.g. account-bound stash items, unbound non-BoE)
	--                                            -> not a disenchant target
	-- The two tooltip scans answer (1) and (2) respectively; we accept the
	-- item if its category is enabled in the profile.
	if IsSoulbound(bag, slot) then
		if not profile.disenchantBoP then return false end
	elseif IsBindOnEquip(bag, slot) then
		if not profile.disenchantBoE then return false end
	else
		return false
	end
	return true
end

-- Wrapper: full disenchant eligibility INCLUDING Keep-list filter. Matches
-- the pre-v3.20 IsDisenchantable behavior. External callers (Process Bags
-- panel, etc.) hit this path; the override-aware Find function below uses
-- AutoDelete_IsDisenchantable_IgnoringKeep + an explicit Keep check so it
-- can detect the blocked-by-Keep case for the popup.
local function IsDisenchantable(profile, bag, slot, singleAffixPlan, keepIDs, keepNames, keepOneIDs, keepStackIDs)
	if not _G.AutoDelete_IsDisenchantable_IgnoringKeep(profile, bag, slot) then return false end
	local link = GetContainerItemLink(bag, slot)
	local slotPlan = singleAffixPlan and singleAffixPlan.slots[bag .. ":" .. slot]
	if _G.AutoDelete_IsDestructiveRuleProtected
		and _G.AutoDelete_IsDestructiveRuleProtected(profile, bag, slot, link, "disenchant", slotPlan, keepIDs, keepNames, keepOneIDs, keepStackIDs) then
		return false
	end
	return true
end

-- Scans bags for the next disenchant target. Returns (bag, slot, link, name)
-- or nil. Walks bag/slot in ascending order and returns the FIRST eligible
-- item, matching FindMillTarget / FindProspectTarget / FindNextOpenable.
-- v3.20: switched from "lowest iLvl wins" to bag-slot order per user
-- feedback (2026-05-23). The old lowest-iLvl heuristic was meant to clear
-- trash first, but it surprised users who expected the keybind to consume
-- the item they were looking at (i.e. the topmost eligible item in their
-- bag UI. Bag-slot order is consistent with the other three one-key
-- actions and matches what the player sees in their bags.
local function FindDisenchantTarget(profile)
	if not profile or not profile.disenchantEnabled then return nil end
	if not CharacterCanDisenchant() then return nil end
	if _G.AutoDelete_SpikeDebug then
		local _sc = _G.AutoDelete_SpikeCounters
		local _ss = _G.AutoDelete_SpikeSession
		_sc.find = (_sc.find or 0) + 1
		_ss.find = (_ss.find or 0) + 1
	end
	local _p = AutoDelete_PerfBegin("FindDisenchantTarget")
	local keepNames, keepIDs = BuildWantedSets(profile.whitelistText, "keep-list")
	local keepOneIDs = select(2, BuildWantedSets(profile.keepOneText, "keepone-list"))
	local keepStackIDs = select(2, BuildWantedSets(profile.keepStackText, "keepstack-list"))
	local singleAffixPlan = _G.AutoDelete_BuildSingleAffixPlan(profile, keepIDs, keepNames)
	for bag = 0, NUM_BAG_SLOTS do
		local count = GetContainerNumSlots(bag) or 0
		for slot = 1, count do
			if IsDisenchantable(profile, bag, slot, singleAffixPlan, keepIDs, keepNames, keepOneIDs, keepStackIDs) then
				local link = GetContainerItemLink(bag, slot)
				local name = GetItemInfo(link) or "?"
				AutoDelete_PerfEnd("FindDisenchantTarget", _p)
				return bag, slot, link, name
			end
		end
	end
	AutoDelete_PerfEnd("FindDisenchantTarget", _p)
	return nil
end

-- Created at PLAYER_LOGIN below. Public for the OnEnter tooltip in Options.
local disenchantButton = nil
local disenchantUpdatePending = false   -- true if we deferred a combat update
local disenchantLastTarget = nil        -- table: {bag, slot, link, name} or nil

-- Writes the macrotext attribute. MUST be out of combat (caller's job to
-- check). Empty macrotext on no-target so the keypress no-ops cleanly rather
-- than firing a stale `/use` against the wrong bag slot after the user looted
-- something into the previously targeted position.
local function ApplyDisenchantMacrotext(bag, slot)
	if not disenchantButton then return end
	local name = cachedDisenchantName or "Disenchant"
	if bag and slot then
		disenchantButton:SetAttribute(
			"macrotext",
			"/cast " .. name .. "\n/use " .. bag .. " " .. slot
		)
	else
		disenchantButton:SetAttribute("macrotext", "")
	end
end

-- Rescans bags and wires the button. Combat-safe: defers if in combat,
-- flushes on PLAYER_REGEN_ENABLED. Cheap when the feature is off (single
-- bool check, no scan).
local function UpdateDisenchantButton()
	if not disenchantButton then return end
	if _G.AutoDelete_IsOneKeyLocked and _G.AutoDelete_IsOneKeyLocked("disenchant") then
		if InCombatLockdown and InCombatLockdown() then
			disenchantUpdatePending = true
			return
		end
		ApplyDisenchantMacrotext(nil, nil)
		return
	end
	local profile = cachedProfile
	if not profile or not profile.disenchantEnabled or not CharacterCanDisenchant() then
		-- Cheap idempotent short-circuit (see UpdateOpenButton for rationale).
		if disenchantLastTarget == nil and not disenchantUpdatePending then return end
		disenchantLastTarget = nil
		if InCombatLockdown and InCombatLockdown() then
			disenchantUpdatePending = true
		else
			ApplyDisenchantMacrotext(nil, nil)
		end
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		disenchantUpdatePending = true
		return
	end
	-- v3.20: honor active Keep-list override before the normal scan.
	-- The popup's "Do it anyway" stashed { bag, slot, id }; we re-validate
	-- by reading the slot's current item id (the user could have moved or
	-- consumed the item between popup-accept and now). On match, arm to
	-- that slot. On mismatch, clear and fall through to the normal Find.
	local _od = _G.AutoDelete_KeepOverrideTargets and _G.AutoDelete_KeepOverrideTargets.disenchant
	if _od then
		local _oLink = GetContainerItemLink(_od.bag, _od.slot)
		local _oId = _oLink and GetItemIDFromLink(_oLink) or nil
		if _oId == _od.id then
			local _oName = GetItemInfo(_oLink)
			if _G.AutoDelete_IsDisenchantable_IgnoringKeep
				and _G.AutoDelete_IsDisenchantable_IgnoringKeep(profile, _od.bag, _od.slot) then
				disenchantLastTarget = {
					bag = _od.bag,
					slot = _od.slot,
					link = _oLink,
					name = _oName,
					keepOverride = true,
				}
				ApplyDisenchantMacrotext(_od.bag, _od.slot)
				local panel = _G.AutoDeleteOptionsPanel
				if panel and panel.IsShown and panel:IsShown() and panel._refreshDisenchantStatus then
					panel:_refreshDisenchantStatus()
				end
				return
			end
		end
		_G.AutoDelete_KeepOverrideTargets.disenchant = nil
	end
	local bag, slot, link, name = FindDisenchantTarget(profile)
	if bag and slot then
		disenchantLastTarget = { bag = bag, slot = slot, link = link, name = name }
	else
		disenchantLastTarget = nil
	end
	ApplyDisenchantMacrotext(bag, slot)
	-- If the options panel is open, push the new "Next: ..." text to its
	-- status line. Single-direction call (addon -> UI); the panel does not
	-- need to know about us. Defensive: skip if the panel hasn't built yet
	-- or doesn't expose the refresher.
	local panel = _G.AutoDeleteOptionsPanel
	if panel and panel.IsShown and panel:IsShown() and panel._refreshDisenchantStatus then
		panel:_refreshDisenchantStatus()
	end
end

-- ============================================================================
-- v3.20: Keep-list Override Popup + Action Chat Notifier
-- ============================================================================
-- Two related additions:
--
-- A) Keep-list override popup. When a Keep-listed item passes every OTHER
--    eligibility check for DE / Mill / Prospect / Open, the addon used to
--    silently skip it. v3.20 raises a StaticPopup with three choices:
--      * Do it anyway   -- sets an override target the matching Update*Button
--                          uses INSTEAD of its normal Find* result, lasts until
--                          the slot empties or the user moves the item
--      * Skip this item -- per-character persistent memory so the popup
--                          never re-asks about this (action, itemId) pair
--      * Remove from Keep -- drops the item from profile.whitelistText AND
--                          clears any stale Skip memory, so future re-adds
--                          re-prompt cleanly
--    Triggered once per BAG_UPDATE_DELAYED, suppressed if a popup is already
--    open or the item is already permanently skipped.
--
-- B) Action chat notifier. Hooks UNIT_SPELLCAST_SUCCEEDED to print
--    "[AutoDelete] Disenchanted [link]" / Milled / Prospected after the
--    spell fires successfully. Open uses /use, not a spell, so it's
--    detected separately via slot-change on BAG_UPDATE_DELAYED.
--
-- All new code lives on _G to keep the main chunk under Lua 5.1's 200-local
-- cap (wiki §13.1). Cross-file accessors expose the per-action *LastTarget
-- upvalues via closures so the chat printer can resolve them by action name.

-- (A1) Accessor closures for the *LastTarget upvalues. Each closes over the
-- file-local var so the chat printer can read the most-recently-armed
-- target without us hoisting those vars to globals.
function _G.AutoDelete_GetDisenchantLastTarget() return disenchantLastTarget end
function _G.AutoDelete_SetDisenchantLastTarget(target) disenchantLastTarget = target end
function _G.AutoDelete_GetCachedDisenchantName() return cachedDisenchantName end

-- (A2) SavedVariables migration. AutoDeleteStatsDB is per-character; we add
-- a keepSkip table whose subtables hold "permanently skipped" itemIds per
-- action. Idempotent: safe to call on every PLAYER_LOGIN.
function _G.AutoDelete_EnsureKeepSkipDB()
	local sv = _G.AutoDeleteStatsDB
	if not sv then return end
	sv.keepSkip = sv.keepSkip or {}
	sv.keepSkip.disenchant = sv.keepSkip.disenchant or {}
	sv.keepSkip.mill       = sv.keepSkip.mill       or {}
	sv.keepSkip.prospect   = sv.keepSkip.prospect   or {}
	sv.keepSkip.open       = sv.keepSkip.open       or {}
end

function _G.AutoDelete_IsKeepSkipped(action, itemId)
	local sv = _G.AutoDeleteStatsDB
	if not sv or not sv.keepSkip or not sv.keepSkip[action] then return false end
	return sv.keepSkip[action][itemId] == true
end

function _G.AutoDelete_MarkKeepSkipped(action, itemId)
	local sv = _G.AutoDeleteStatsDB
	if not sv or not action or not itemId then return end
	sv.keepSkip = sv.keepSkip or {}
	sv.keepSkip[action] = sv.keepSkip[action] or {}
	sv.keepSkip[action][itemId] = true
end

function _G.AutoDelete_ClearKeepSkip(action, itemId)
	local sv = _G.AutoDeleteStatsDB
	if not sv or not sv.keepSkip or not sv.keepSkip[action] then return end
	sv.keepSkip[action][itemId] = nil
end

-- (A3) Active overrides set by popup OnAccept. Keyed by action name. Each
-- entry is { bag, slot, id }; the matching Update*Button consults it before
-- running its normal Find* scan.
_G.AutoDelete_KeepOverrideTargets = _G.AutoDelete_KeepOverrideTargets or {}

-- (A4) Generic two-pass bag walker. Calls predicateIgnoringKeep for every
-- slot; partitions matches into Keep-blocked vs unblocked; returns the best
-- of each set per sortByIlvl. The parameter is retained for forward
-- compatibility, but as of v3.20 (2026-05-23) all four actions pass
-- sortByIlvl=false (bag-slot order, top-down) so the popup matches what
-- the player sees in their bag UI. Both returns may be nil.
function _G.AutoDelete_WalkBagsTwoPass(profile, predicateIgnoringKeep, sortByIlvl)
	if not profile or type(predicateIgnoringKeep) ~= "function" then return nil, nil end
	local bestNon, bestKeep = nil, nil
	local bestNonKey, bestKeepKey = math.huge, math.huge
	for bag = 0, NUM_BAG_SLOTS do
		local slots = GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			if predicateIgnoringKeep(profile, bag, slot) then
				local link = GetContainerItemLink(bag, slot)
				local name, _, _, ilvl = GetItemInfo(link)
				local id = GetItemIDFromLink(link)
				ilvl = ilvl or 0
				local sortKey = sortByIlvl and ilvl or (bag * 100 + slot)
				local rec = { bag = bag, slot = slot, link = link, name = name, id = id, ilvl = ilvl }
				if IsWhitelisted(profile, id, name) then
					if sortKey < bestKeepKey then
						bestKeep, bestKeepKey = rec, sortKey
					end
				else
					if sortKey < bestNonKey then
						bestNon, bestNonKey = rec, sortKey
					end
				end
			end
		end
	end
	return bestNon, bestKeep
end

-- (A5) StaticPopupDialog registration. Three buttons; button1's label is
-- per-action (set in OnShow via the data field passed at Show time).
-- The text uses %s for the item link (StaticPopup_Show formats it).
--
-- KEEP_OVERRIDE_VERBS on _G (not a local) to avoid bumping the main
-- chunk's local count over Lua 5.1's 200 cap.
_G.AutoDelete_KeepOverrideVerbs = {
	disenchant = "Disenchant",
	mill       = "Mill",
	prospect   = "Prospect",
	open       = "Open",
}

-- Popup body is built per-call by ShowKeepOverridePopup so the action verb
-- ("Disenchant" / "Mill" / "Prospect" / "Open") and the item link both
-- weave through the explanation. text=%s here just acts as the slot
-- StaticPopup_Show fills with that pre-formatted string.
--
-- Button labels (2026-05-23 spec): button1 is the per-action verb only
-- (no "anyway" suffix); button2 = "Ignore"; button3 = "Unprotect".
-- Visual order on 3.3.5a's StaticPopup row is button1, button3, button2 ->
-- Disenchant / Unprotect / Ignore, matching the user-supplied spec.
StaticPopupDialogs["AUTODELETE_KEEP_OVERRIDE"] = {
	text = "%s",
	button1 = "Disenchant",
	button2 = "Ignore",
	button3 = "Remove",
	OnShow = function(self)
		-- Per-action verb on button1 (overrides the default "Disenchant"
		-- placeholder above). data is set right after Show by our
		-- ShowKeepOverridePopup helper.
		if self.data and self.data.action and _G.AutoDelete_KeepOverrideVerbs[self.data.action] then
			if self.button1 and self.button1.SetText then
				self.button1:SetText(_G.AutoDelete_KeepOverrideVerbs[self.data.action])
			end
		end
	end,
	OnAccept = function(self)
		local d = self.data
		if not d then return end
		_G.AutoDelete_KeepOverrideTargets[d.action] = { bag = d.bag, slot = d.slot, id = d.id }
		-- Re-arm the relevant secure button so the user's next keypress
		-- targets the override. Each Update* now consults the override
		-- table before falling through to its normal Find*.
		if d.action == "disenchant" and _G.AutoDelete_UpdateDisenchantButton then
			_G.AutoDelete_UpdateDisenchantButton()
		elseif d.action == "mill" and _G.AutoDelete_UpdateMillButton then
			_G.AutoDelete_UpdateMillButton()
		elseif d.action == "prospect" and _G.AutoDelete_UpdateProspectButton then
			_G.AutoDelete_UpdateProspectButton()
		elseif d.action == "open" and _G.AutoDelete_UpdateOpenButton then
			_G.AutoDelete_UpdateOpenButton()
		end
	end,
	OnCancel = function(self)
		local d = self.data
		if not d then return end
		_G.AutoDelete_MarkKeepSkipped(d.action, d.id)
		print("|cffff8000[AutoDelete]|r Ignoring " .. (d.link or "item") ..
			" for " .. (_G.AutoDelete_KeepOverrideVerbs[d.action] or d.action) .. ".")
	end,
	OnAlt = function(self)
		local d = self.data
		if not d then return end
		local profile = _G.AutoDelete_GetCachedProfile and _G.AutoDelete_GetCachedProfile()
		if not profile then return end
		-- Drop "item:<id>\n" (or trailing without newline) from whitelistText.
		local id = d.id
		local txt = profile.whitelistText or ""
		txt = txt:gsub("item:" .. id .. "\r?\n?", "")
		profile.whitelistText = txt
		-- Clear any leftover skip memory for this item across all four
		-- actions so re-adding to Keep later re-prompts cleanly.
		_G.AutoDelete_ClearKeepSkip("disenchant", id)
		_G.AutoDelete_ClearKeepSkip("mill",       id)
		_G.AutoDelete_ClearKeepSkip("prospect",   id)
		_G.AutoDelete_ClearKeepSkip("open",       id)
		if _G.AutoDelete_RefreshCachedProfile then _G.AutoDelete_RefreshCachedProfile() end
		print("|cffff8000[AutoDelete]|r Removed " .. (d.link or "item") ..
			" from your Keep list.")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- (A6) ShowKeepOverridePopup. Suppress if already shown OR if the item is
-- in skip memory. Otherwise build the verbose body (explains WHY the
-- popup appeared and WHAT each button does in plain language so a new
-- player isn't confused) and show.
function _G.AutoDelete_ShowKeepOverridePopup(action, rec)
	if not rec or not rec.id then return end
	if _G.AutoDelete_IsKeepSkipped(action, rec.id) then return end
	-- One popup at a time across all four actions to avoid stacking.
	if StaticPopup_Visible and StaticPopup_Visible("AUTODELETE_KEEP_OVERRIDE") then return end
	local verb = _G.AutoDelete_KeepOverrideVerbs[action] or action
	local link = rec.link or rec.name or "this item"
	-- 2026-05-23 spec: title on its own line (legendary orange), then two
	-- short sentences explaining WHAT is happening and WHY this popup
	-- appeared, then a per-button cheat-sheet so the user knows what each
	-- choice does without guessing.
	--
	--   |cffff8000Auto-Disenchant Warning|r
	--
	--   AutoDelete wants to Disenchant <link>.
	--   It's on your Keep list, so AutoDelete is asking first.
	--
	--   Disenchant = Disenchant this one item now.
	--   Remove = Take this item off your Keep list.
	--   Ignore = Never ask about this item again.
	local body = string.format(
		"|cffff8000Auto-%s Warning|r\n\n" ..
		"AutoDelete wants to %s %s.\n" ..
		"It's on your Keep list, so AutoDelete is asking first.\n\n" ..
		"%s = %s this one item now.\n" ..
		"Remove = Take this item off your Keep list.\n" ..
		"Ignore = Never ask about this item again.",
		verb, verb, link, verb, verb)
	local dlg = StaticPopup_Show("AUTODELETE_KEEP_OVERRIDE", body)
	if dlg then
		dlg.data = { action = action, bag = rec.bag, slot = rec.slot,
			link = rec.link, name = rec.name, id = rec.id }
		-- Force-call OnShow so the button1 label updates immediately. Some
		-- 3.3.5a clients fire OnShow before .data is attached; this re-runs
		-- it after attachment.
		if dlg.OnShow then dlg:OnShow() end
	end
end

function _G.AutoDelete_OnOneKeyPreClick(action)
	local hasTarget = false
	local target = nil
	if action == "disenchant" and _G.AutoDelete_GetDisenchantLastTarget then
		target = _G.AutoDelete_GetDisenchantLastTarget()
		hasTarget = target ~= nil
	elseif action == "mill" and _G.AutoDelete_GetMillLastTarget then
		target = _G.AutoDelete_GetMillLastTarget()
		hasTarget = target ~= nil
	elseif action == "prospect" and _G.AutoDelete_GetProspectLastTarget then
		target = _G.AutoDelete_GetProspectLastTarget()
		hasTarget = target ~= nil
	elseif action == "open" and _G.AutoDelete_GetOpenLastTarget then
		target = _G.AutoDelete_GetOpenLastTarget()
		hasTarget = target ~= nil
	end
	if hasTarget and _G.AutoDelete_IsOneKeyTargetAllowed and not _G.AutoDelete_IsOneKeyTargetAllowed(action, target) then
		if _G.AutoDelete_ClearOneKeyTarget then _G.AutoDelete_ClearOneKeyTarget(action) end
		print("|cffff8000[AutoDelete]|r Keep list blocked that one-key target.")
		hasTarget = false
	end
	if hasTarget then return end
	if _G.AutoDelete_CheckKeepOverrideForAction then
		_G.AutoDelete_CheckKeepOverrideForAction(action)
	end
end

-- (A7) Hotkey-triggered check. If the user presses a one-key action and no
-- normal target is staged, check whether the next possible target is blocked
-- only by Keep. This must not run from BAG_UPDATE / Process Bags refreshes:
-- eligible preview items should never spam popups. The popup appears only from
-- the action hotkey path, then the user can choose the action and press again.
function _G.AutoDelete_CheckKeepOverrideForAction(action)
	if InCombatLockdown and InCombatLockdown() then return end
	-- (Fix F, 2026-05-23) Skip while our own DeleteItems / SellItems batch
	-- is mid-flight. AutoDelete_SelfBagUpdateUntil is set by DeleteItems
	-- when it starts a batch; running the keep-check inside that window
	-- means we're re-walking bags after every PickupContainerItem call.
	if GetTime() < (_G.AutoDelete_SelfBagUpdateUntil or 0) then return end
	local now = GetTime()
	if now < (_G.AutoDelete_LastKeepOverrideHotkeyAt or 0) + 0.5 then
		return
	end
	_G.AutoDelete_LastKeepOverrideHotkeyAt = now

	local profile = _G.AutoDelete_GetCachedProfile and _G.AutoDelete_GetCachedProfile()
	if not profile then return end
	-- (Fix B, 2026-05-23) Empty Keep list -> nothing can ever be blocked.
	-- Skip every bag walk. Most users have at least one Keep item but the
	-- short-circuit is essentially free when the list isn't empty (just an
	-- empty-string check) and saves the entire 4-walk cost when it is.
	local whitelistText = profile.whitelistText
	if not whitelistText or whitelistText == "" then return end

	if action == "disenchant" and profile.disenchantEnabled and CharacterCanDisenchant() then
		local normal, blocked = _G.AutoDelete_WalkBagsTwoPass(profile,
			_G.AutoDelete_IsDisenchantable_IgnoringKeep, false)
		if blocked and not normal then _G.AutoDelete_ShowKeepOverridePopup("disenchant", blocked) end
	elseif action == "mill" and profile.millEnabled and _G.AutoDelete_CanMill and _G.AutoDelete_CanMill() then
		local normal, blocked = _G.AutoDelete_WalkBagsTwoPass(profile,
			_G.AutoDelete_IsMillable_IgnoringKeep, false)
		if blocked and not normal then _G.AutoDelete_ShowKeepOverridePopup("mill", blocked) end
	elseif action == "prospect" and profile.prospectEnabled and _G.AutoDelete_CanProspect and _G.AutoDelete_CanProspect() then
		local normal, blocked = _G.AutoDelete_WalkBagsTwoPass(profile,
			_G.AutoDelete_IsProspectable_IgnoringKeep, false)
		if blocked and not normal then _G.AutoDelete_ShowKeepOverridePopup("prospect", blocked) end
	elseif action == "open" and profile.autoOpenEnabled then
		local normal, blocked = _G.AutoDelete_WalkBagsTwoPass(profile,
			_G.AutoDelete_IsOpenable_IgnoringKeep, false)
		if blocked and not normal then _G.AutoDelete_ShowKeepOverridePopup("open", blocked) end
	end
end

function _G.AutoDelete_CheckKeepOverrides()
	-- Retained as a compatibility no-op. Keep override popups are now hotkey
	-- triggered only; bag refresh paths must not open them.
end

-- (B) Action chat notifier. Hooks UNIT_SPELLCAST_SUCCEEDED via the existing
-- scanner OnEvent (event registration + dispatch case added separately).
-- Matches the cached localized spell names captured at PLAYER_LOGIN.
function _G.AutoDelete_OnSpellCastSucceeded(spellName)
	if not spellName then return end
	local lastTarget, verb, action = nil, nil, nil
	if _G.AutoDelete_GetCachedDisenchantName and spellName == (_G.AutoDelete_GetCachedDisenchantName() or "Disenchant") then
		verb = "Disenchanted"
		action = "disenchant"
	elseif _G.AutoDelete_GetCachedMillName and spellName == (_G.AutoDelete_GetCachedMillName() or "Milling") then
		verb = "Milled"
		action = "mill"
	elseif _G.AutoDelete_GetCachedProspectName and spellName == (_G.AutoDelete_GetCachedProspectName() or "Prospecting") then
		verb = "Prospected"
		action = "prospect"
	end
	local pending = action and _G.AutoDelete_OneKeyPendingTargets and _G.AutoDelete_OneKeyPendingTargets[action] or nil
	if pending and (pending.untilAt or 0) >= GetTime() then
		lastTarget = pending.target
	elseif action and _G.AutoDelete_GetOneKeyLastTarget then
		lastTarget = _G.AutoDelete_GetOneKeyLastTarget(action)
	end
	if verb and lastTarget and lastTarget.link then
		print("|cffff8000[AutoDelete]|r " .. verb .. " " .. lastTarget.link)
		if _G.AutoDelete_RecordProcessAction then
			_G.AutoDelete_RecordProcessAction({
				action = action,
				verb = verb,
				link = lastTarget.link,
				name = lastTarget.name,
				bag = lastTarget.bag,
				slot = lastTarget.slot,
			})
		end
		-- Clear any active override now that the action fired. The
		-- BAG_UPDATE that follows will re-arm the secure button to whatever
		-- comes next (or nothing if no eligible items remain).
		if _G.AutoDelete_KeepOverrideTargets then
			if verb == "Disenchanted" then _G.AutoDelete_KeepOverrideTargets.disenchant = nil
			elseif verb == "Milled"    then _G.AutoDelete_KeepOverrideTargets.mill       = nil
			elseif verb == "Prospected" then _G.AutoDelete_KeepOverrideTargets.prospect  = nil
			end
		end
	end
	if action and _G.AutoDelete_OneKeyPendingTargets then
		_G.AutoDelete_OneKeyPendingTargets[action] = nil
	end
end

-- Open uses /use, not a cast spell -- no UNIT_SPELLCAST_SUCCEEDED. Detect
-- via slot-content change on BAG_UPDATE_DELAYED: if the slot we last armed
-- now holds a different link (or nothing), the open happened.
function _G.AutoDelete_CheckOpenSlotChange()
	if not openLastTarget then return end
	local t = openLastTarget
	if not t.bag or not t.slot or not t.link then return end
	local nowLink = GetContainerItemLink(t.bag, t.slot)
	if nowLink ~= t.link then
		-- The slot we armed now holds something else (or is empty). Print.
		print("|cffff8000[AutoDelete]|r Opened " .. t.link)
		if _G.AutoDelete_RecordProcessAction then
			_G.AutoDelete_RecordProcessAction({
				action = "open",
				verb = "Opened",
				link = t.link,
				name = t.name,
				bag = t.bag,
				slot = t.slot,
			})
		end
		-- Clear the cached target so we don't re-print on the next bag
		-- update; UpdateOpenButton will repopulate it on its rescan.
		openLastTarget = nil
		if _G.AutoDelete_KeepOverrideTargets then
			_G.AutoDelete_KeepOverrideTargets.open = nil
		end
	end
end

-- Status string for the Options UI. Returns short text + a color triple.
-- Pure presentation helper; safe to call any time.
local function GetDisenchantStatus()
	local profile = cachedProfile
	if not profile or not profile.disenchantEnabled then
		return "Disabled", 0.55, 0.55, 0.55
	end
	if not CharacterCanDisenchant() then
		return "Requires Enchanting", 1.0, 0.3, 0.3
	end
	local lockLeft = _G.AutoDelete_GetOneKeyLockRemaining and _G.AutoDelete_GetOneKeyLockRemaining("disenchant") or 0
	if lockLeft > 0 then
		return string.format("Waiting %.1fs", lockLeft), 1.0, 0.82, 0.0
	end
	if disenchantLastTarget and disenchantLastTarget.link then
		return "Next: " .. disenchantLastTarget.link, 0.7, 0.85, 1.0
	end
	return "No eligible items in bags", 0.55, 0.55, 0.55
end

-- Export the accessors the Options UI needs. Single global namespace,
-- matches the pattern used by _G.AutoDelete_RefreshCachedProfile.
_G.AutoDelete_GetDisenchantStatus    = GetDisenchantStatus
_G.AutoDelete_UpdateDisenchantButton = UpdateDisenchantButton
_G.AutoDelete_IsDisenchantable       = IsDisenchantable

-- (No BINDING_HEADER / BINDING_NAME globals here. Earlier dev iterations
-- registered the disenchant button via Bindings.xml so it appeared under
-- the Blizzard Key Bindings menu. We replaced that with the panel's
-- in-panel key-capture row, which calls SetBinding directly and saves
-- via SaveBindings(GetCurrentBindingSet()). Result: addon stays at two
-- files, binding still persists across sessions, and users never have
-- to leave our settings panel to assign a key.)

-- ============================================================================
-- Process Bags
-- ============================================================================
-- Aggregates the four secure-action predicates (Open, Disenchant, Mill,
-- Prospect) into a single bag walk so the Process Bags panel can render
-- one row per actionable item. Action precedence is gear-first (disenchant)
-- then crafting (mill, prospect) then container (open) -- in practice
-- each item satisfies at most one predicate so order rarely matters.
--
-- Ignored items are stored per-character in AutoDeleteStatsDB.processIgnored
-- as {[itemId] = true}. Stats DB is the right home because:
--   (1) it's already declared SavedVariablesPerCharacter in the TOC, and
--   (2) ignore decisions are personal to that character ("never disenchant
--       this transmog piece I keep on my mage"), not a profile preference
--       that should follow when copying a profile to an alt.

local PROCESS_ACTIONS = {
	delete     = { label = "Delete",   color = {0.95, 0.30, 0.30, 1} },
	sell       = { label = "Sell",     color = {0.30, 0.60, 0.95, 1} },
	disenchant = { label = "DE",       color = {0.55, 0.45, 0.85, 1} },
	mill       = { label = "Mill",     color = {0.45, 0.85, 0.55, 1} },
	prospect   = { label = "Prospect", color = {0.85, 0.65, 0.30, 1} },
	open       = { label = "Open",     color = {0.45, 0.75, 0.95, 1} },
	kept       = { label = "Kept",     color = {0.55, 0.55, 0.55, 1} },
}

local function GetProcessIgnoredTable()
	_G.AutoDeleteStatsDB = _G.AutoDeleteStatsDB or {}
	_G.AutoDeleteStatsDB.processIgnored = _G.AutoDeleteStatsDB.processIgnored or {}
	return _G.AutoDeleteStatsDB.processIgnored
end

local function IsProcessIgnored(itemId)
	if not itemId then return false end
	return GetProcessIgnoredTable()[itemId] == true
end

local function SetProcessIgnored(itemId, ignored)
	if not itemId then return end
	local t = GetProcessIgnoredTable()
	if ignored then t[itemId] = true else t[itemId] = nil end
end

local function ClearProcessIgnored()
	local t = GetProcessIgnoredTable()
	for k in pairs(t) do t[k] = nil end
end

function _G.AutoDelete_EvaluateProcessEntry(profile, bag, slot, link, id, ignored, ruleCtx)
	local name, _, itemQuality, ilvl, _, itemClass, itemSubType, _, equipSlot, _, vendorPrice = GetItemInfo(link)
	local isQuestItem = (itemClass == "Quest")
	local isDeleteGearItem = equipSlot and equipSlot ~= "" and equipSlot ~= "INVTYPE_BAG"
	local isSellGearItem = false
	local isWeaponSlot = false
	if equipSlot and GEAR_SLOTS[equipSlot] then
		if WEAPON_SLOTS[equipSlot] then
			isSellGearItem = true
			isWeaponSlot = true
		elseif itemClass == "Armor" or itemClass == "Weapon" then
			isSellGearItem = true
		end
	end
	local deleteNames, deleteIDs
	local sellNames, sellIDs
	local keepNames, keepIDs
	local keepOneIDs
	local keepStackIDs
	local singleAffixPlan
	if ruleCtx then
		deleteNames, deleteIDs = ruleCtx.deleteNames, ruleCtx.deleteIDs
		sellNames, sellIDs = ruleCtx.sellNames, ruleCtx.sellIDs
		keepNames, keepIDs = ruleCtx.keepNames, ruleCtx.keepIDs
		keepOneIDs = ruleCtx.keepOneIDs
		keepStackIDs = ruleCtx.keepStackIDs
		singleAffixPlan = ruleCtx.singleAffixPlan
	else
		deleteNames, deleteIDs = BuildWantedSets(profile.listText, "delete-list")
		sellNames, sellIDs = BuildWantedSets(profile.sellListText, "sell-list")
		keepNames, keepIDs = BuildWantedSets(profile.whitelistText, "keep-list")
		keepOneIDs = select(2, BuildWantedSets(profile.keepOneText, "keepone-list"))
		keepStackIDs = select(2, BuildWantedSets(profile.keepStackText, "keepstack-list"))
		singleAffixPlan = _G.AutoDelete_BuildSingleAffixPlan(profile, keepIDs, keepNames)
	end
	local onKeep = _G.AutoDelete_IsWhitelistedFast(keepIDs, keepNames, id, name)
	local onKeepOne = id and keepOneIDs and keepOneIDs[id]
	local onKeepStack = id and keepStackIDs and keepStackIDs[id]
	local onSell = (id and sellIDs[id]) or (name and sellNames[Normalize(name)])
	local missingAffixBlocked, missingAffixState = _G.AutoDelete_IsMissingAffixHardStop(profile, bag, slot, link)
	local missingAffixReason = "Missing affix hard stop"
	if missingAffixState == "unknown" then
		missingAffixReason = missingAffixReason .. " (ownership unknown)"
	end

	if onKeepOne then
		local _, count = GetContainerItemInfo(bag, slot)
		local seen = ruleCtx and ruleCtx.keepOneSeenUnits and (ruleCtx.keepOneSeenUnits[id] or 0) or 0
		if onKeep then
			return "kept", "Keep list blocked KeepOne", "KeepOne", name
		elseif missingAffixBlocked then
			return "kept", missingAffixReason .. " blocked KeepOne", "KeepOne", name
		elseif IsAffixProtected(profile, bag, slot, link, "delete") then
			return "kept", "Affix Protection blocked KeepOne", "KeepOne", name
		elseif seen >= 1 or (count or 1) > 1 then
			if ruleCtx and ruleCtx.keepOneSeenUnits then ruleCtx.keepOneSeenUnits[id] = 1 end
			return "delete", "KeepOne extra unit", "KeepOne", name
		else
			if ruleCtx and ruleCtx.keepOneSeenUnits then ruleCtx.keepOneSeenUnits[id] = seen + (count or 1) end
			return "kept", "KeepOne kept final unit", "KeepOne", name
		end
	end

	if onKeepStack then
		if onKeep then
			return "kept", "Keep list blocked KeepStack", "KeepStack", name
		elseif missingAffixBlocked then
			return "kept", missingAffixReason .. " blocked KeepStack", "KeepStack", name
		elseif IsAffixProtected(profile, bag, slot, link, "delete") then
			return "kept", "Affix Protection blocked KeepStack", "KeepStack", name
		end
		local stackCount, keepBag, keepSlot = _G.AutoDelete_GetKeepStackSlotChoice(id)
		if stackCount > 1 and (bag ~= keepBag or slot ~= keepSlot) then
			return "delete", "KeepStack extra stack", "KeepStack", name
		end
		return "kept", "KeepStack kept one stack", "KeepStack", name
	end

	local singleAffixSlot = singleAffixPlan and singleAffixPlan.slots[bag .. ":" .. slot]
	if singleAffixSlot then
		missingAffixBlocked, missingAffixState = _G.AutoDelete_IsMissingAffixHardStop(profile, bag, slot, link, singleAffixSlot)
		missingAffixReason = "Missing affix hard stop"
		if missingAffixState == "unknown" then
			missingAffixReason = missingAffixReason .. " (ownership unknown)"
		end
	end
	if singleAffixSlot and not singleAffixSlot.extra then
		return "kept", "KeepOne Missing Affix kept one missing-affix item", "KeepOne Missing Affix", name
	end

	local deleteRule = nil
	if id and deleteIDs[id] then
		deleteRule = "Delete list"
	elseif name and deleteNames[Normalize(name)] then
		deleteRule = "Delete list"
	elseif not isQuestItem and itemQuality == 0 and profile.qualityActionJunk == "delete"
		and not IsCosmeticSlot(link) then
		deleteRule = "Auto Actions: Junk delete"
	elseif not isQuestItem and itemQuality == 1 and profile.qualityActionCommon == "delete"
		and isDeleteGearItem and not IsCosmeticSlot(link) then
		deleteRule = "Auto Actions: Common gear delete"
	elseif not isQuestItem and itemQuality == 2 and profile.qualityActionGreens == "delete"
		and isDeleteGearItem and not IsCosmeticSlot(link) then
		deleteRule = "Auto Actions: Green gear delete"
	end
	if deleteRule then
		if onKeep then
			return "kept", "Keep list blocked delete", deleteRule, name
		elseif missingAffixBlocked then
			return "kept", missingAffixReason .. " blocked delete", deleteRule, name
		elseif IsAffixProtected(profile, bag, slot, link, "delete", singleAffixSlot) then
			return "kept", "Affix Protection blocked delete", deleteRule, name
		elseif _G.AutoDelete_IsRecipeDeleteProtected(profile, itemClass, itemSubType, deleteRule) then
			return "kept", "Sell Known Recipes blocked delete", deleteRule, name
		else
			return "delete", "Would delete", deleteRule, name
		end
	end

	local sellRule = nil
	local recipeProtectReason = nil
	local recipeProtectRule = nil
	if vendorPrice and vendorPrice > 0 then
		local recipeAction, recipeReason, recipeRule =
			_G.AutoDelete_GetKnownRecipeSellDecision(profile, bag, slot, link, itemClass, itemSubType, itemQuality, isQuestItem, onSell)
		if recipeAction == "sell" then
			sellRule = recipeRule
		elseif recipeAction == "protect" then
			recipeProtectReason = recipeReason
			recipeProtectRule = recipeRule
		elseif onSell then
			sellRule = "Sell list"
		elseif not isQuestItem and itemQuality == 0 and profile.qualityActionJunk == "sell" then
			sellRule = "Auto Actions: Junk sell"
		elseif not isQuestItem and itemQuality == 1 and isSellGearItem
			and profile.qualityActionCommon == "sell" then
			sellRule = "Auto Actions: Common gear sell"
		elseif not isQuestItem and itemQuality == 2 and isSellGearItem
			and profile.qualityActionGreens == "sell" then
			sellRule = "Auto Actions: Green gear sell"
		elseif not isQuestItem and isSellGearItem and (itemQuality == 3 or itemQuality == 4) then
			local isBoE = IsBindOnEquip(bag, slot)
			local rarityIsRare = (itemQuality == 3)
			local rarityIsEpic = (itemQuality == 4)
			local function InRange(min, max)
				return ilvl and ilvl >= (min or 1) and ilvl <= (max or 199)
			end
			if isBoE and isWeaponSlot and profile.boeWeaponsEnabled
				and ((rarityIsRare and profile.boeWeaponsRare) or (rarityIsEpic and profile.boeWeaponsEpic))
				and InRange(profile.boeWeaponsIlvlMin, profile.boeWeaponsIlvlMax) then
				sellRule = "Sell Filters: BoE Weapons"
			elseif (not isBoE) and profile.bopEnabled
				and ((rarityIsRare and profile.bopRare) or (rarityIsEpic and profile.bopEpic))
				and InRange(profile.bopIlvlMin, profile.bopIlvlMax) then
				sellRule = "Sell Filters: BoP"
			elseif isBoE and (not isWeaponSlot) and profile.boeArmorEnabled
				and ((rarityIsRare and profile.boeArmorRare) or (rarityIsEpic and profile.boeArmorEpic))
				and InRange(profile.boeArmorIlvlMin, profile.boeArmorIlvlMax) then
				sellRule = "Sell Filters: BoE Armor"
			end
		end
	end
	if recipeProtectReason then
		return "kept", recipeProtectReason, recipeProtectRule, name
	end
	if sellRule then
		if onKeep then
			return "kept", "Keep list blocked sell", sellRule, name
		elseif missingAffixBlocked then
			return "kept", missingAffixReason .. " blocked sell", sellRule, name
		elseif IsAffixProtected(profile, bag, slot, link, "sell", singleAffixSlot) then
			return "kept", "Affix Protection blocked sell", sellRule, name
		else
			return "sell", "Would sell at vendor", sellRule, name
		end
	end

	if not ignored then
		local isDisenchantable = _G.AutoDelete_IsDisenchantable
		local isDisenchantableIgnoringKeep = _G.AutoDelete_IsDisenchantable_IgnoringKeep
		local isMillable       = _G.AutoDelete_IsMillable
		local isProspectable   = _G.AutoDelete_IsProspectable
		local isOpenable       = _G.AutoDelete_IsOpenable
		if isDisenchantableIgnoringKeep and isDisenchantableIgnoringKeep(profile, bag, slot) then
			local deProtected, deProtectReason = false, nil
			if _G.AutoDelete_IsDestructiveRuleProtected then
				deProtected, deProtectReason = _G.AutoDelete_IsDestructiveRuleProtected(
					profile, bag, slot, link, "disenchant", singleAffixSlot,
					keepIDs, keepNames, keepOneIDs, keepStackIDs)
			end
			if deProtected then
				local reasonText = (deProtectReason == "keep-blocked" and "Keep list blocked disenchant")
					or (deProtectReason == "keepone-blocked" and "KeepOne blocked disenchant")
					or (deProtectReason == "keepstack-blocked" and "KeepStack blocked disenchant")
					or (deProtectReason == "single-affix-kept" and "KeepOne Missing Affix blocked disenchant")
					or (deProtectReason == "missing-affix-blocked" and "Missing affix hard stop blocked disenchant")
					or (deProtectReason == "missing-affix-unknown" and "Missing affix hard stop blocked disenchant (ownership unknown)")
					or "Affix Protection blocked disenchant"
				return "kept", reasonText, "One-Key Disenchant", name
			end
		end
		if isDisenchantable and isDisenchantable(profile, bag, slot, singleAffixPlan, keepIDs, keepNames, keepOneIDs, keepStackIDs) then
			return "disenchant", "Eligible for disenchant", "One-Key Disenchant", name, true
		elseif isMillable and isMillable(profile, bag, slot) then
			return "mill", "Eligible for milling", "One-Key Mill", name, true
		elseif isProspectable and isProspectable(profile, bag, slot) then
			return "prospect", "Eligible for prospecting", "One-Key Prospect", name, true
		elseif isOpenable and isOpenable(profile, bag, slot) then
			return "open", "Eligible to open", "One-Key Open", name, true
		end
	end

	if onKeep then
		return "kept", "Keep list", "Keep list", name
	elseif ignored then
		return "kept", "Ignored for Process Bags", "Process ignore", name
	elseif isQuestItem then
		return "kept", "Quest item protected", "Quest protection", name
	end
	return "kept", "No rule matched", "No matching rule", name
end

-- Walks bags once, returns a list of actionable items. Each entry:
--   { bag, slot, itemId, link, name, action, count, variantNames }
-- action is one of the keys in PROCESS_ACTIONS. Returned rows are deduped by
-- action + itemId because PE affix names can differ while the base item ID is
-- the same. The first matching slot is used for arming; after that item is
-- processed, a refresh can surface the next matching copy.
local function ProcessScan(profile)
	local results = {}
	if not profile then return results end
	local ignored = GetProcessIgnoredTable()
	local seen = {}
	local deleteNames, deleteIDs = BuildWantedSets(profile.listText, "delete-list")
	local sellNames, sellIDs = BuildWantedSets(profile.sellListText, "sell-list")
	local keepNames, keepIDs = BuildWantedSets(profile.whitelistText, "keep-list")
	local keepOneIDs = select(2, BuildWantedSets(profile.keepOneText, "keepone-list"))
	local keepStackIDs = select(2, BuildWantedSets(profile.keepStackText, "keepstack-list"))
	local ruleCtx = {
		deleteNames = deleteNames,
		deleteIDs = deleteIDs,
		sellNames = sellNames,
		sellIDs = sellIDs,
		keepNames = keepNames,
		keepIDs = keepIDs,
		keepOneIDs = keepOneIDs,
		keepStackIDs = keepStackIDs,
		keepOneSeenUnits = {},
	}
	ruleCtx.singleAffixPlan = _G.AutoDelete_BuildSingleAffixPlan(profile, keepIDs, keepNames)

	for bag = 0, NUM_BAG_SLOTS do
		local slots = GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local id = GetItemIDFromLink(link)
				if id then
					local action, reason, sourceRule, name, processAction =
						_G.AutoDelete_EvaluateProcessEntry(profile, bag, slot, link, id, ignored[id], ruleCtx)
					if action then
						local key = action .. ":" .. tostring(id)
						if action == "kept" then key = key .. ":" .. tostring(reason) .. ":" .. tostring(sourceRule) end
						local existing = seen[key]
						if existing then
							existing.count = (existing.count or 1) + 1
							if name ~= "?" and Normalize(name) ~= Normalize(existing.name) then
								existing.variantNames = true
							end
						else
							local entry = {
							bag    = bag,
							slot   = slot,
							itemId = id,
							link   = link,
							name   = name or "?",
							action = action,
							reason = reason,
							sourceRule = sourceRule,
							processAction = processAction,
							count  = 1,
							}
							seen[key] = entry
							table.insert(results, entry)
						end
					end
				end
			end
		end
	end
	return results
end

-- Returns row counts plus copy counts. `total` is visible rows after grouping;
-- `copies` is actual matching bag slots represented by those rows.
-- Used by the Tools Card 1 launcher's status line.
local function ProcessScanCounts(profile)
	local counts = { total = 0, copies = 0, delete = 0, sell = 0, disenchant = 0, mill = 0, prospect = 0, open = 0, kept = 0 }
	for _, entry in ipairs(ProcessScan(profile)) do
		counts.total = counts.total + 1
		counts.copies = counts.copies + (entry.count or 1)
		counts[entry.action] = (counts[entry.action] or 0) + 1
	end
	return counts
end

-- Arming: writes the macrotext for a single action's secure button to
-- point at the chosen (bag, slot). Same hardware-event-required pattern;
-- the user still presses the bound key to fire. Returns true if the arm
-- succeeded (false if in combat -- caller can decide to surface a
-- "armed will apply post-combat" message, but we don't queue here).
local function ProcessArm(action, bag, slot)
	if InCombatLockdown and InCombatLockdown() then return false end
	if _G.AutoDelete_IsOneKeyLocked and _G.AutoDelete_IsOneKeyLocked(action) then
		return false, "locked"
	end
	local btnName
	if     action == "disenchant" then btnName = "AutoDeleteDisenchantButton"
	elseif action == "mill"       then btnName = "AutoDeleteMillButton"
	elseif action == "prospect"   then btnName = "AutoDeleteProspectButton"
	elseif action == "open"       then btnName = "AutoDeleteOpenButton"
	else return false end
	local btn = _G[btnName]
	if not btn then return false end
	local link = (bag and slot) and GetContainerItemLink(bag, slot) or nil
	local name = link and GetItemInfo(link) or nil
	if bag and slot then
		local db = GetDB()
		local profile = select(1, GetActiveProfile(db))
		local id = link and GetItemIDFromLink(link) or nil
		local currentAction, currentReason, _, _, processAction
		if profile and link then
			local deleteNames, deleteIDs = BuildWantedSets(profile.listText, "delete-list")
			local sellNames, sellIDs = BuildWantedSets(profile.sellListText, "sell-list")
			local keepNames, keepIDs = BuildWantedSets(profile.whitelistText, "keep-list")
			local keepOneIDs = select(2, BuildWantedSets(profile.keepOneText, "keepone-list"))
			local keepStackIDs = select(2, BuildWantedSets(profile.keepStackText, "keepstack-list"))
			local ruleCtx = {
				deleteNames = deleteNames,
				deleteIDs = deleteIDs,
				sellNames = sellNames,
				sellIDs = sellIDs,
				keepNames = keepNames,
				keepIDs = keepIDs,
				keepOneIDs = keepOneIDs,
				keepStackIDs = keepStackIDs,
				keepOneSeenUnits = {},
				singleAffixPlan = _G.AutoDelete_BuildSingleAffixPlan(profile, keepIDs, keepNames),
			}
			currentAction, currentReason, _, _, processAction =
				_G.AutoDelete_EvaluateProcessEntry(profile, bag, slot, link, id, IsProcessIgnored(id), ruleCtx)
		end
		if currentAction ~= action or not processAction then
			return false, currentReason or "blocked"
		end
	end
	if bag and slot then
		btn:SetAttribute("macrotext", "/use " .. bag .. " " .. slot)
		-- Disenchant / Mill / Prospect need the spell cast first. Detect
		-- those by name and prepend /cast <spell> so the keypress fires
		-- the correct two-step.
		if action == "disenchant" then
			btn:SetAttribute("macrotext", "/cast " .. (GetSpellInfo(13262) or "Disenchant") ..
				"\n/use " .. bag .. " " .. slot)
		elseif action == "mill" then
			btn:SetAttribute("macrotext", "/cast " .. (GetSpellInfo(51005) or "Milling") ..
				"\n/use " .. bag .. " " .. slot)
		elseif action == "prospect" then
			btn:SetAttribute("macrotext", "/cast " .. (GetSpellInfo(31252) or "Prospecting") ..
				"\n/use " .. bag .. " " .. slot)
		end
		if _G.AutoDelete_SetOneKeyLastTarget then
			_G.AutoDelete_SetOneKeyLastTarget(action, {
				bag = bag,
				slot = slot,
				link = link,
				name = name,
			})
		end
	else
		btn:SetAttribute("macrotext", "")
		if _G.AutoDelete_SetOneKeyLastTarget then
			_G.AutoDelete_SetOneKeyLastTarget(action, nil)
		end
	end
	return true
end

_G.AutoDelete_ProcessScan         = ProcessScan
_G.AutoDelete_ProcessScanCounts   = ProcessScanCounts
_G.AutoDelete_ProcessArm          = ProcessArm
_G.AutoDelete_IsProcessIgnored    = IsProcessIgnored
_G.AutoDelete_SetProcessIgnored   = SetProcessIgnored
_G.AutoDelete_ClearProcessIgnored = ClearProcessIgnored
_G.AutoDelete_PROCESS_ACTIONS     = PROCESS_ACTIONS

-- ============================================================================
-- Decision inspector, quick item menu, and diagnostic report
-- ============================================================================

function _G.AutoDelete_FindBagSlotForItem(itemId, itemName)
	local needle = itemName and Normalize(itemName) or nil
	for bag = 0, NUM_BAG_SLOTS do
		local slots = GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local link = GetContainerItemLink(bag, slot)
			if link then
				local id = GetItemIDFromLink(link)
				if itemId and id == itemId then return bag, slot, link end
				if needle then
					local name = GetItemInfo(link)
					if name and Normalize(name) == needle then return bag, slot, link end
				end
			end
		end
	end
	return nil, nil, nil
end

function _G.AutoDelete_ResolveItemReference(text)
	text = Trim(text or "")
	if text == "" and GetCursorInfo then
		local cursorType, itemId, itemLink = GetCursorInfo()
		if cursorType == "item" then
			local id = (type(itemId) == "number") and itemId or GetItemIDFromLink(itemLink)
			local name = id and GetItemInfo(id) or nil
			return id, itemLink, name
		end
	end
	local id = tonumber(text:match("Hitem:(%d+)") or text:match("item:(%d+)") or text:match("^(%d+)$"))
	if id then
		local name, link = GetItemInfo(id)
		return id, link or ("item:" .. id), name or ("item:" .. id)
	end
	local clean = text:gsub("^%[(.+)%]$", "%1")
	clean = Trim(clean)
	if clean == "" then return nil, nil, nil end
	local name, link = GetItemInfo(clean)
	if link then
		return GetItemIDFromLink(link), link, name
	end
	return nil, nil, clean
end

function _G.AutoDelete_BuildWhyReport(itemId, itemLink, itemName, bag, slot)
	local db = GetDB()
	local profile = GetActiveProfile(db)
	local lines = {}
	if not itemLink and itemId then itemLink = "item:" .. itemId end
	if (not bag or not slot) and (itemId or itemName) then
		bag, slot, itemLink = _G.AutoDelete_FindBagSlotForItem(itemId, itemName)
	end
	itemName = itemName or (itemLink and GetItemInfo(itemLink)) or (itemId and ("item:" .. itemId)) or "Unknown item"
	itemId = itemId or GetItemIDFromLink(itemLink)
	table.insert(lines, "AutoDelete decision report")
	table.insert(lines, "Item: " .. tostring(itemName) .. (itemId and (" (item:" .. itemId .. ")") or ""))
	if bag and slot then
		table.insert(lines, "Bag slot: " .. bag .. "." .. slot)
	else
		table.insert(lines, "Bag slot: not currently found in bags")
	end
	table.insert(lines, "")

	local deleteNames, deleteIDs = BuildWantedSets(profile.listText, "delete-list")
	local sellNames, sellIDs = BuildWantedSets(profile.sellListText, "sell-list")
	local keepNames, keepIDs = BuildWantedSets(profile.whitelistText, "keep-list")
	local keepOneIDs = select(2, BuildWantedSets(profile.keepOneText, "keepone-list"))
	local keepStackIDs = select(2, BuildWantedSets(profile.keepStackText, "keepstack-list"))
	local onKeep = _G.AutoDelete_IsWhitelistedFast(keepIDs, keepNames, itemId, itemName)
	local onDelete = (itemId and deleteIDs[itemId]) or (itemName and deleteNames[Normalize(itemName)])
	local onSell = (itemId and sellIDs[itemId]) or (itemName and sellNames[Normalize(itemName)])
	local onKeepOne = itemId and keepOneIDs[itemId]
	local onKeepStack = itemId and keepStackIDs[itemId]
	local singleAffixPlan = _G.AutoDelete_BuildSingleAffixPlan(profile, keepIDs, keepNames)
	local singleAffixSlot = (bag and slot and singleAffixPlan) and singleAffixPlan.slots[bag .. ":" .. slot] or nil

	table.insert(lines, "List rules:")
	table.insert(lines, "  Keep list: " .. (onKeep and "yes - protects item" or "no"))
	table.insert(lines, "  Delete list: " .. (onDelete and "yes" or "no"))
	table.insert(lines, "  Sell list: " .. (onSell and "yes" or "no"))
	table.insert(lines, "  KeepOne list: " .. (onKeepOne and "yes - keep one unit" or "no"))
	table.insert(lines, "  KeepStack list: " .. (onKeepStack and "yes - keep one stack" or "no"))
	table.insert(lines, "  KeepOne Missing Affix: " .. ((profile.keepSingleMissingAffix and singleAffixSlot)
		and (singleAffixSlot.extra and "duplicate extra follows cleanup rules" or "protected missing-affix item")
		or "no"))

	table.insert(lines, "")
	table.insert(lines, "Runtime gates:")
	table.insert(lines, "  AutoDelete enabled: " .. (profile.enabled and "yes" or "no - auto cleanup is disabled"))
	table.insert(lines, "  Cursor busy: " .. ((CursorHasItem and CursorHasItem()) and "yes - delete queue waits" or "no"))
	table.insert(lines, "  Delete queue: " .. tostring(#((_G.AutoDelete_DeleteQueue or {}).items or {})) .. " pending")

	local name, quality, ilvl, itemClass, itemSubType, maxStack, equipSlot, vendorPrice = nil, nil, nil, nil, nil, nil, nil, nil
	if itemLink then
		local info = { GetItemInfo(itemLink) }
		name = info[1]
		quality = info[3]
		ilvl = info[4]
		itemClass = info[6]
		itemSubType = info[7]
		maxStack = info[8]
		equipSlot = info[9]
		vendorPrice = info[11]
	end
	local isQuestItem = (itemClass == "Quest")
	local isRecipeLike = _G.AutoDelete_IsRecipeLikeItem(itemClass, itemSubType)
	local recipeKnowledgeState = nil
	local recipeQualityEnabled = nil
	if profile.knownRecipeSellEnabled and isRecipeLike and bag and slot and itemLink then
		recipeKnowledgeState = _G.AutoDelete_GetRecipeKnowledgeState(bag, slot, itemLink)
		recipeQualityEnabled = _G.AutoDelete_IsKnownRecipeQualityEnabled(profile, quality)
	end
	local isDeleteGearItem = equipSlot and equipSlot ~= "" and equipSlot ~= "INVTYPE_BAG"
	local isSellGearItem = false
	local isWeaponSlot = false
	if equipSlot and GEAR_SLOTS[equipSlot] then
		if WEAPON_SLOTS[equipSlot] then
			isSellGearItem = true
			isWeaponSlot = true
		elseif itemClass == "Armor" or itemClass == "Weapon" then
			isSellGearItem = true
		end
	end
	local isCosmetic = itemLink and IsCosmeticSlot(itemLink)
	local missingAffixBlocked, missingAffixState = false, nil
	if bag and slot and itemLink then
		missingAffixBlocked, missingAffixState = _G.AutoDelete_IsMissingAffixHardStop(profile, bag, slot, itemLink, singleAffixSlot)
	end
	local missingAffixWhyText = "missing affix hard stop"
	if missingAffixState == "unknown" then
		missingAffixWhyText = missingAffixWhyText .. " (ownership unknown)"
	end
	local function InItemLevelRange(minIlvl, maxIlvl)
		return ilvl and ilvl >= (minIlvl or 1) and ilvl <= (maxIlvl or 199)
	end
	local function RarityEnabled(rareFlag, epicFlag)
		return (quality == 3 and rareFlag) or (quality == 4 and epicFlag)
	end
	table.insert(lines, "")
	table.insert(lines, "Item facts:")
	table.insert(lines, "  Quality: " .. tostring(quality))
	table.insert(lines, "  iLvl: " .. tostring(ilvl))
	table.insert(lines, "  Class: " .. tostring(itemClass))
	table.insert(lines, "  Subtype: " .. tostring(itemSubType))
	table.insert(lines, "  Recipe-like: " .. tostring(isRecipeLike))
	if recipeKnowledgeState then
		table.insert(lines, "  Recipe knowledge: " .. tostring(recipeKnowledgeState))
	end
	table.insert(lines, "  Equip slot: " .. tostring(equipSlot))
	table.insert(lines, "  Sell gear slot: " .. tostring(isSellGearItem))
	table.insert(lines, "  Weapon slot: " .. tostring(isWeaponSlot))
	table.insert(lines, "  Max stack: " .. tostring(maxStack))
	table.insert(lines, "  Vendor price: " .. tostring(vendorPrice))
	if isRecipeLike then
		table.insert(lines, "")
		table.insert(lines, "Recipe diagnostics:")
		table.insert(lines, "  Sell Known Recipes: " .. (profile.knownRecipeSellEnabled and "on" or "off"))
		table.insert(lines, "  Knowledge state: " .. tostring(recipeKnowledgeState or "not scanned"))
		table.insert(lines, "  Quality toggle: " .. tostring(_G.AutoDelete_GetRecipeQualityLabel(quality))
			.. (recipeQualityEnabled == nil and " (not checked)" or (recipeQualityEnabled and " on" or " off")))
		table.insert(lines, "  Explicit Sell list: " .. (onSell and "yes - sells before recipe protection" or "no"))
		table.insert(lines, "  Explicit Delete list: " .. (onDelete and "yes - deletes before automatic recipe protection" or "no"))
	end

	table.insert(lines, "")
	table.insert(lines, "Delete decision:")
	if not profile.enabled then
		table.insert(lines, "  Final: no auto-delete. AutoDelete is disabled.")
	elseif onKeep then
		table.insert(lines, "  Final: keep. Keep list wins before Delete or auto-delete.")
	elseif onKeepOne then
		local total = itemId and _G.AutoDelete_CountBagUnitsByItemId(itemId) or 0
		if missingAffixBlocked then
			table.insert(lines, "  Final: keep. " .. missingAffixWhyText .. " blocks KeepOne.")
		elseif bag and slot and itemLink and IsAffixProtected(profile, bag, slot, itemLink, "delete", singleAffixSlot) then
			table.insert(lines, "  Final: keep. Affix protection blocks KeepOne.")
		elseif total > 1 then
			table.insert(lines, "  Final: delete extra unit(s). KeepOne leaves one unit.")
		else
			table.insert(lines, "  Final: keep. KeepOne already has one unit left.")
		end
	elseif onKeepStack then
		local stackCount, keepBag, keepSlot = itemId and _G.AutoDelete_GetKeepStackSlotChoice(itemId) or 0
		if missingAffixBlocked then
			table.insert(lines, "  Final: keep. " .. missingAffixWhyText .. " blocks KeepStack.")
		elseif bag and slot and itemLink and IsAffixProtected(profile, bag, slot, itemLink, "delete", singleAffixSlot) then
			table.insert(lines, "  Final: keep. Affix protection blocks KeepStack.")
		elseif stackCount > 1 and bag and slot and (bag ~= keepBag or slot ~= keepSlot) then
			table.insert(lines, "  Final: delete extra stack. KeepStack leaves one stack.")
		else
			table.insert(lines, "  Final: keep. KeepStack already has one stack left.")
		end
	elseif singleAffixSlot and not singleAffixSlot.extra then
		table.insert(lines, "  Final: keep. KeepOne Missing Affix kept one missing-affix item.")
	elseif missingAffixBlocked then
		table.insert(lines, "  Final: keep. " .. missingAffixWhyText .. " blocks delete.")
	elseif bag and slot and itemLink and IsAffixProtected(profile, bag, slot, itemLink, "delete", singleAffixSlot) then
		table.insert(lines, "  Final: keep. Affix protection blocks delete.")
	elseif onDelete then
		table.insert(lines, "  Final: delete. Explicit Delete list entry matches.")
	elseif _G.AutoDelete_IsRecipeDeleteProtected(profile, itemClass, itemSubType, "auto") then
		table.insert(lines, "  Final: keep. Sell Known Recipes keeps recipe items out of automatic delete rules.")
	elseif isQuestItem then
		table.insert(lines, "  Final: keep. Quest item blocks auto-delete.")
	elseif quality == 0 and profile.qualityActionJunk == "delete" and not isCosmetic then
		table.insert(lines, "  Final: delete. Junk auto action is Delete.")
	elseif quality == 1 and profile.qualityActionCommon == "delete" and isDeleteGearItem and not isCosmetic then
		table.insert(lines, "  Final: delete. Common gear auto action is Delete.")
	elseif quality == 2 and profile.qualityActionGreens == "delete" and isDeleteGearItem and not isCosmetic then
		table.insert(lines, "  Final: delete. Green gear auto action is Delete.")
	else
		table.insert(lines, "  Final: keep. No delete rule matched.")
	end

	table.insert(lines, "")
	table.insert(lines, "Sell decision:")
	if not profile.enabled then
		table.insert(lines, "  Final: no auto-sell. AutoDelete is disabled.")
	elseif onKeep then
		table.insert(lines, "  Final: keep. Keep list wins before Sell or auto-sell.")
	elseif missingAffixBlocked then
		table.insert(lines, "  Final: keep. " .. missingAffixWhyText .. " blocks sell.")
	elseif bag and slot and itemLink and IsAffixProtected(profile, bag, slot, itemLink, "sell", singleAffixSlot) then
		table.insert(lines, "  Final: keep. Affix protection blocks sell.")
	elseif profile.knownRecipeSellEnabled and isRecipeLike then
		local recipeAction, recipeReason, recipeRule =
			_G.AutoDelete_GetKnownRecipeSellDecision(profile, bag, slot, itemLink, itemClass, itemSubType, quality, isQuestItem, onSell)
		if recipeAction == "sell" and recipeRule == "Sell list" then
			table.insert(lines, "  Final: sell at vendor. Explicit Sell list entry matches.")
		elseif recipeAction == "sell" then
			table.insert(lines, "  Final: sell at vendor. Sell Known Recipes rule matched.")
		else
			table.insert(lines, "  Final: keep. " .. tostring(recipeReason) .. ".")
		end
	elseif onSell then
		table.insert(lines, "  Final: sell at vendor. Explicit Sell list entry matches.")
	elseif isQuestItem then
		table.insert(lines, "  Final: keep. Quest item blocks auto-sell.")
	elseif quality == 0 and profile.qualityActionJunk == "sell" then
		table.insert(lines, "  Final: sell at vendor. Junk auto action is Sell.")
	elseif quality == 1 and profile.qualityActionCommon == "sell" and isSellGearItem then
		table.insert(lines, "  Final: sell at vendor. Common gear auto action is Sell.")
	elseif quality == 2 and profile.qualityActionGreens == "sell" and isSellGearItem then
		table.insert(lines, "  Final: sell at vendor. Green gear auto action is Sell.")
	elseif (quality == 3 or quality == 4) and isSellGearItem then
		if not bag or not slot then
			table.insert(lines, "  Final: keep for current scan. Rare/Epic sell categories require a bag slot to read BoE/BoP state.")
		else
			local isBoE = IsBindOnEquip(bag, slot)
			if isBoE and isWeaponSlot and profile.boeWeaponsEnabled
				and RarityEnabled(profile.boeWeaponsRare, profile.boeWeaponsEpic)
				and InItemLevelRange(profile.boeWeaponsIlvlMin, profile.boeWeaponsIlvlMax) then
				table.insert(lines, "  Final: sell at vendor. BoE Weapons rule matched.")
			elseif (not isBoE) and profile.bopEnabled
				and RarityEnabled(profile.bopRare, profile.bopEpic)
				and InItemLevelRange(profile.bopIlvlMin, profile.bopIlvlMax) then
				table.insert(lines, "  Final: sell at vendor. BoP rule matched.")
			elseif isBoE and (not isWeaponSlot) and profile.boeArmorEnabled
				and RarityEnabled(profile.boeArmorRare, profile.boeArmorEpic)
				and InItemLevelRange(profile.boeArmorIlvlMin, profile.boeArmorIlvlMax) then
				table.insert(lines, "  Final: sell at vendor. BoE Armor rule matched.")
			else
				table.insert(lines, "  Final: keep. No Rare/Epic sell category matched.")
			end
		end
	else
		table.insert(lines, "  Final: keep. No sell rule matched.")
	end

	table.insert(lines, "")
	table.insert(lines, "Disenchant decision:")
	if not profile.disenchantEnabled then
		table.insert(lines, "  Final: keep. One-Key Disenchant is off.")
	elseif not bag or not slot or not itemLink then
		table.insert(lines, "  Final: keep. Item must be in a bag slot for One-Key Disenchant.")
	elseif not _G.AutoDelete_IsDisenchantable_IgnoringKeep
		or not _G.AutoDelete_IsDisenchantable_IgnoringKeep(profile, bag, slot) then
		table.insert(lines, "  Final: keep. DE filters do not match this item.")
	else
		local deProtected, deProtectReason = false, nil
		if _G.AutoDelete_IsDestructiveRuleProtected then
			deProtected, deProtectReason = _G.AutoDelete_IsDestructiveRuleProtected(
				profile, bag, slot, itemLink, "disenchant", singleAffixSlot,
				keepIDs, keepNames, keepOneIDs, keepStackIDs)
		end
		if deProtected then
			local deText = (deProtectReason == "keep-blocked" and "Keep list blocks disenchant.")
				or (deProtectReason == "keepone-blocked" and "KeepOne blocks disenchant.")
				or (deProtectReason == "keepstack-blocked" and "KeepStack blocks disenchant.")
				or (deProtectReason == "single-affix-kept" and "KeepOne Missing Affix blocks disenchant.")
				or (deProtectReason == "missing-affix-blocked" and "Missing affix hard stop blocks disenchant.")
				or (deProtectReason == "missing-affix-unknown" and "Missing affix hard stop blocks disenchant because ownership is unknown.")
				or "Affix protection blocks disenchant."
			table.insert(lines, "  Final: keep. " .. deText)
		else
			table.insert(lines, "  Final: disenchant. DE filters matched and no protection rule blocked it.")
		end
	end

	table.insert(lines, "")
	table.insert(lines, "Affix dot:")
	if not bag or not slot or not itemLink then
		table.insert(lines, "  Unknown. Item must be in a bag slot to scan tooltip markers.")
	else
		local tier = ClassifyAffixByLink(itemLink, bag, slot, nil)
		if not tier then
			table.insert(lines, "  Hidden. No @affix@ marker found.")
		elseif cachedProfile and cachedProfile.showAffixDot == false then
			table.insert(lines, "  Hidden. Show affix dot is off.")
		else
			local affixDisplayName = _G.AutoDelete_GetAffixDisplayName
				and _G.AutoDelete_GetAffixDisplayName(itemLink, bag, slot, itemName)
				or itemName
			local owned = AutoDelete_IsAffixOwnedByItemName(affixDisplayName)
			local affixKey = _G.AutoDelete_GetAffixKeyForItemName
				and _G.AutoDelete_GetAffixKeyForItemName(affixDisplayName)
				or nil
			local dotLevel, dotColor = _G.AutoDelete_DecideDot(itemLink, bag, slot, nil)
			table.insert(lines, "  Tier: " .. tostring(tier))
			if affixDisplayName and affixDisplayName ~= itemName then
				table.insert(lines, "  Tooltip name: " .. tostring(affixDisplayName))
			end
			table.insert(lines, "  Affix key: " .. tostring(affixKey or "not matched"))
			table.insert(lines, "  PE ownership: " .. (owned == nil and "unknown" or (owned and "owned" or "missing")))
			if not dotLevel then
				table.insert(lines, "  Dot: hidden because Show/Keep Missing Affix is on and the affix is owned.")
			elseif owned == false then
				table.insert(lines, "  Dot: " .. _G.AutoDelete_GetMissingAffixColorLabel(cachedProfile) .. " because the affix is missing or unlearned.")
			else
				table.insert(lines, "  Dot: tier color.")
			end
		end
	end

	table.insert(lines, "")
	table.insert(lines, "Process Bags:")
	if itemId and IsProcessIgnored(itemId) then
		table.insert(lines, "  Ignored on this character.")
	else
		local found = false
		if bag and slot then
			for _, entry in ipairs(ProcessScan(profile)) do
				if entry.bag == bag and entry.slot == slot then
					local meta = PROCESS_ACTIONS[entry.action]
					table.insert(lines, "  Row action: " .. (meta and meta.label or entry.action))
					if entry.reason then table.insert(lines, "  Reason: " .. tostring(entry.reason)) end
					if entry.sourceRule then table.insert(lines, "  Source rule: " .. tostring(entry.sourceRule)) end
					if not profile.enabled and (entry.action == "delete" or entry.action == "sell") then
						table.insert(lines, "  Runtime: preview only while AutoDelete is disabled.")
					end
					if (entry.count or 1) > 1 then
						table.insert(lines, "  Grouped copies: " .. tostring(entry.count) .. " share this item ID.")
					end
					found = true
					break
				end
			end
		end
		if not found and itemId then
			for _, entry in ipairs(ProcessScan(profile)) do
				if entry.itemId == itemId then
					local meta = PROCESS_ACTIONS[entry.action]
					table.insert(lines, "  Row action: " .. (meta and meta.label or entry.action) .. " (grouped by item ID).")
					if entry.reason then table.insert(lines, "  Reason: " .. tostring(entry.reason)) end
					if entry.sourceRule then table.insert(lines, "  Source rule: " .. tostring(entry.sourceRule)) end
					if not profile.enabled and (entry.action == "delete" or entry.action == "sell") then
						table.insert(lines, "  Runtime: preview only while AutoDelete is disabled.")
					end
					if (entry.count or 1) > 1 then
						table.insert(lines, "  Grouped copies: " .. tostring(entry.count) .. " share this item ID.")
					end
					found = true
					break
				end
			end
		end
		if not found then table.insert(lines, "  No current process action matched.") end
	end

	return table.concat(lines, "\n")
end

function _G.AutoDelete_ShowWhy(itemRef)
	local id, link, name = _G.AutoDelete_ResolveItemReference(itemRef)
	if not id and not name then
		print("|cffff8000[AutoDelete]|r Right-click a Process Bags row, then choose Why?")
		return
	end
	local text = _G.AutoDelete_BuildWhyReport(id, link, name)
	if _G.AutoDelete_ShowReportWindow then
		_G.AutoDelete_ShowReportWindow(text)
	else
		print("|cffff8000[AutoDelete]|r " .. text:gsub("\n", "\n|cffff8000[AutoDelete]|r "))
	end
end

function _G.AutoDelete_BuildDiagnosticReport()
	local db = GetDB()
	local profile, profileKey, charKey = GetActiveProfile(db)
	local c = ProcessScanCounts(profile)
	local function CountEntries(listText)
		local n = 0
		for line in string.gmatch(listText or "", "[^\r\n]+") do
			if Trim(line) ~= "" then n = n + 1 end
		end
		return n
	end
	local function CountTable(t)
		local n = 0
		if t then for _ in pairs(t) do n = n + 1 end end
		return n
	end
	local ignored = 0
	for _ in pairs(GetProcessIgnoredTable()) do ignored = ignored + 1 end
	local owned = 0
	for _ in pairs(_G.AutoDelete_OwnedAffixes or {}) do owned = owned + 1 end
	local decisionCount = #(((_G.AutoDelete_DecisionHistory or {}).entries) or {})
	local version = (GetAddOnMetadata and GetAddOnMetadata("AutoDelete", "Version")) or "Unknown"
	local lines = {
		"AutoDelete diagnostic report",
		"Version: " .. tostring(version),
		"Character: " .. tostring(charKey),
		"Profile: " .. tostring(profileKey),
		"Enabled: " .. tostring(profile.enabled),
		"Scan interval: " .. tostring(profile.scanInterval),
		"",
		"Lists:",
		"  Delete: " .. CountEntries(profile.listText),
		"  Sell: " .. CountEntries(profile.sellListText),
		"  Keep: " .. CountEntries(profile.whitelistText),
		"  KeepOne: " .. CountEntries(profile.keepOneText),
		"  KeepStack: " .. CountEntries(profile.keepStackText),
		"",
		"Auto actions:",
		"  Junk: " .. tostring(profile.qualityActionJunk),
		"  ElvUI junk coin hidden: " .. tostring(_G.AutoDelete_ElvUIJunkIconState and _G.AutoDelete_ElvUIJunkIconState.active or false),
		"  Common: " .. tostring(profile.qualityActionCommon),
		"  Greens: " .. tostring(profile.qualityActionGreens),
		"",
		"Recipe filters:",
		"  Sell Known Recipes: " .. tostring(profile.knownRecipeSellEnabled),
		"  White: " .. tostring(profile.knownRecipeSellCommon)
			.. "   Green: " .. tostring(profile.knownRecipeSellUncommon)
			.. "   Blue: " .. tostring(profile.knownRecipeSellRare)
			.. "   Purple: " .. tostring(profile.knownRecipeSellEpic),
		"  Tooltip cache entries: " .. CountTable(_G.AutoDelete_TooltipCache and _G.AutoDelete_TooltipCache.recipeKnown),
		"",
		"Affix:",
		"  Show dot: " .. tostring(profile.showAffixDot),
		"  Show/Keep Missing Affix: " .. tostring(profile.affixCollectionMode),
		"  KeepOne Missing Affix: " .. tostring(profile.keepSingleMissingAffix),
		"  Missing affix color: " .. _G.AutoDelete_GetMissingAffixColorLabel(profile),
		"  Protect tiers: I=" .. tostring(profile.protectAffixTier1)
			.. " II=" .. tostring(profile.protectAffixTier2)
			.. " III=" .. tostring(profile.protectAffixTier3)
			.. " IV=" .. tostring(profile.protectAffixTier4)
			.. " V=" .. tostring(profile.protectAffixTier5),
		"  Learned affixes mirrored: " .. owned,
		"",
		"Process Bags:",
		"  Rows: " .. c.total,
		"  Copies: " .. (c.copies or c.total),
		"  Delete: " .. c.delete,
		"  Sell: " .. c.sell,
		"  DE: " .. c.disenchant,
		"  Mill: " .. c.mill,
		"  Prospect: " .. c.prospect,
		"  Open: " .. c.open,
		"  Kept: " .. c.kept,
		"  Ignored: " .. ignored,
		"",
		"Diagnostics:",
		"  Perf enabled: " .. tostring(_G.AutoDelete_PerfEnabled),
		"  Spike debug: " .. tostring(_G.AutoDelete_SpikeDebug),
		"  ElvUI hook disabled: " .. tostring(_G.AutoDelete_ElvUIHookDisabled),
		"  Decision history entries: " .. tostring(decisionCount),
	}
	return table.concat(lines, "\n")
end

function _G.AutoDelete_ShowDiagnosticReport()
	local text = _G.AutoDelete_BuildDiagnosticReport()
	if _G.AutoDelete_ShowReportWindow then
		_G.AutoDelete_ShowReportWindow(text)
	else
		print("|cffff8000[AutoDelete]|r Report window unavailable. Use /del help after the UI loads.")
	end
end

function _G.AutoDelete_ClearProcessDebugCache()
	local cache = _G.AutoDelete_TooltipCache
	if cache then
		cache.affix = {}
		cache.affixName = {}
		cache.soulbound = {}
		cache.boe = {}
		cache.locked = {}
	end
end

function _G.AutoDelete_GetProcessTooltipLines(bag, slot, maxLines)
	local lines = {}
	if not bag or not slot then return lines end
	boeTip:Hide()
	boeTip:SetOwner(boeTipOwner, "ANCHOR_NONE")
	boeTip:ClearLines()
	boeTip:SetBagItem(bag, slot)
	boeTip:Show()
	local n = boeTip:NumLines()
	local limit = math.min(n, maxLines or 8)
	for i = 1, limit do
		local leftFS = _G["AutoDelete_BoETipTextLeft" .. i]
		local rightFS = _G["AutoDelete_BoETipTextRight" .. i]
		local leftText = leftFS and leftFS:GetText() or ""
		local rightText = rightFS and rightFS:GetText() or ""
		if leftText ~= "" or rightText ~= "" then
			if rightText ~= "" then
				table.insert(lines, "    tt" .. i .. ": " .. leftText .. " || " .. rightText)
			else
				table.insert(lines, "    tt" .. i .. ": " .. leftText)
			end
		end
	end
	if n > limit then
		table.insert(lines, "    tooltip lines truncated: " .. tostring(n - limit))
	end
	boeTip:Hide()
	return lines
end

function _G.AutoDelete_BuildProcessDebugReport()
	local db = GetDB()
	local profile, profileKey, charKey = GetActiveProfile(db)
	local counts = ProcessScanCounts(profile)
	local ignoredCount = 0
	for _ in pairs(GetProcessIgnoredTable()) do ignoredCount = ignoredCount + 1 end
	local function yes(value) return value and "yes" or "no" end
	local function cacheCount(t)
		local n = 0
		if t then for _ in pairs(t) do n = n + 1 end end
		return n
	end
	local function statusText(fn)
		if not fn then return "unknown" end
		local text = fn()
		return tostring(text)
	end
	local version = (GetAddOnMetadata and GetAddOnMetadata("AutoDelete", "Version")) or "Unknown"
	local lines = {
		"AutoDelete Process Bags diagnostic",
		"Version: " .. tostring(version),
		"Character: " .. tostring(charKey),
		"Profile: " .. tostring(profileKey),
		"Enabled: " .. tostring(profile and profile.enabled),
		"",
		"One-key settings:",
		"  Disenchant enabled: " .. tostring(profile and profile.disenchantEnabled) .. "   spell known: " .. yes(CharacterCanDisenchant()),
		"  Mill enabled: " .. tostring(profile and profile.millEnabled) .. "   spell known: " .. yes(_G.AutoDelete_CanMill and _G.AutoDelete_CanMill()),
		"  Prospect enabled: " .. tostring(profile and profile.prospectEnabled) .. "   spell known: " .. yes(_G.AutoDelete_CanProspect and _G.AutoDelete_CanProspect()),
		"  Open enabled: " .. tostring(profile and profile.autoOpenEnabled),
		"",
		"One-key status:",
		"  Disenchant: " .. statusText(_G.AutoDelete_GetDisenchantStatus),
		"  Mill: " .. statusText(_G.AutoDelete_GetMillStatus),
		"  Prospect: " .. statusText(_G.AutoDelete_GetProspectStatus),
		"  Open: " .. statusText(_G.AutoDelete_GetOpenStatus),
		"",
		"Process summary:",
		"  Rows: " .. tostring(counts.total) .. "   copies: " .. tostring(counts.copies or counts.total),
		"  Delete: " .. tostring(counts.delete) .. "   Sell: " .. tostring(counts.sell) .. "   DE: " .. tostring(counts.disenchant),
		"  Mill: " .. tostring(counts.mill) .. "   Prospect: " .. tostring(counts.prospect) .. "   Open: " .. tostring(counts.open) .. "   Kept: " .. tostring(counts.kept),
		"  Ignored item IDs: " .. tostring(ignoredCount),
		"",
		"Tooltip cache:",
		"  BoE: " .. cacheCount(_G.AutoDelete_TooltipCache and _G.AutoDelete_TooltipCache.boe)
			.. "   Soulbound: " .. cacheCount(_G.AutoDelete_TooltipCache and _G.AutoDelete_TooltipCache.soulbound)
			.. "   Affix: " .. cacheCount(_G.AutoDelete_TooltipCache and _G.AutoDelete_TooltipCache.affix)
			.. "   Affix names: " .. cacheCount(_G.AutoDelete_TooltipCache and _G.AutoDelete_TooltipCache.affixName)
			.. "   Recipes: " .. cacheCount(_G.AutoDelete_TooltipCache and _G.AutoDelete_TooltipCache.recipeKnown),
		"",
		"Bag slots:",
	}
	local deleteNames, deleteIDs = BuildWantedSets(profile.listText, "delete-list")
	local sellNames, sellIDs = BuildWantedSets(profile.sellListText, "sell-list")
	local keepNames, keepIDs = BuildWantedSets(profile.whitelistText, "keep-list")
	local keepOneIDs = select(2, BuildWantedSets(profile.keepOneText, "keepone-list"))
	local keepStackIDs = select(2, BuildWantedSets(profile.keepStackText, "keepstack-list"))
	local singleAffixPlan = _G.AutoDelete_BuildSingleAffixPlan(profile, keepIDs, keepNames)
	local ruleCtx = {
		deleteNames = deleteNames,
		deleteIDs = deleteIDs,
		sellNames = sellNames,
		sellIDs = sellIDs,
		keepNames = keepNames,
		keepIDs = keepIDs,
		keepOneIDs = keepOneIDs,
		keepStackIDs = keepStackIDs,
		keepOneSeenUnits = {},
		singleAffixPlan = singleAffixPlan,
	}
	local foundAny = false
	for bag = 0, NUM_BAG_SLOTS do
		local slots = GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			local link = GetContainerItemLink(bag, slot)
			if link then
				foundAny = true
				local id = GetItemIDFromLink(link)
				local info = { GetItemInfo(link) }
				local name = info[1] or "?"
				local quality = info[3]
				local ilvl = info[4]
				local itemClass = info[6]
				local itemSubType = info[7]
				local maxStack = info[8]
				local equipSlot = info[9]
				local vendorPrice = info[11]
				local _, count, locked = GetContainerItemInfo(bag, slot)
				local ignored = id and IsProcessIgnored(id)
				local action, reason, sourceRule, _, processAction =
					_G.AutoDelete_EvaluateProcessEntry(profile, bag, slot, link, id, ignored, ruleCtx)
				local deRaw = _G.AutoDelete_IsDisenchantable_IgnoringKeep
					and _G.AutoDelete_IsDisenchantable_IgnoringKeep(profile, bag, slot)
				local singleAffixSlot = singleAffixPlan and singleAffixPlan.slots[bag .. ":" .. slot]
				local deProtected, deProtectReason = false, nil
				if _G.AutoDelete_IsDestructiveRuleProtected then
					deProtected, deProtectReason = _G.AutoDelete_IsDestructiveRuleProtected(
						profile, bag, slot, link, "disenchant", singleAffixSlot,
						keepIDs, keepNames, keepOneIDs, keepStackIDs)
				end
				local millRaw = _G.AutoDelete_IsMillable_IgnoringKeep
					and _G.AutoDelete_IsMillable_IgnoringKeep(profile, bag, slot)
				local prospectRaw = _G.AutoDelete_IsProspectable_IgnoringKeep
					and _G.AutoDelete_IsProspectable_IgnoringKeep(profile, bag, slot)
				local openRaw = _G.AutoDelete_IsOpenable_IgnoringKeep
					and _G.AutoDelete_IsOpenable_IgnoringKeep(profile, bag, slot)
				local boe = IsBindOnEquip(bag, slot)
				local soulbound = IsSoulbound(bag, slot)
				local affix = ClassifyAffixByLink(link, bag, slot, nil)
				local missingBlocked, missingState = _G.AutoDelete_IsMissingAffixHardStop(profile, bag, slot, link, singleAffixSlot)
				table.insert(lines, string.format(
					"  b%d s%d item:%s x%s %s",
					bag, slot, tostring(id), tostring(count or 1), tostring(link or name)
				))
				table.insert(lines, string.format(
					"    facts: quality=%s ilvl=%s class=%s sub=%s equip=%s maxStack=%s vendor=%s slotLocked=%s",
					tostring(quality), tostring(ilvl), tostring(itemClass), tostring(itemSubType),
					tostring(equipSlot), tostring(maxStack), tostring(vendorPrice), tostring(locked)
				))
				table.insert(lines, string.format(
					"    tooltip: soulbound=%s boe=%s affixTier=%s missingBlocked=%s missingState=%s",
					yes(soulbound), yes(boe), tostring(affix), yes(missingBlocked), tostring(missingState)
				))
				if _G.AutoDelete_IsRecipeLikeItem(itemClass, itemSubType) then
					table.insert(lines, string.format(
						"    recipe: enabled=%s state=%s quality=%s qualityToggle=%s",
						yes(profile.knownRecipeSellEnabled),
						tostring(profile.knownRecipeSellEnabled and _G.AutoDelete_GetRecipeKnowledgeState(bag, slot, link) or "not scanned"),
						tostring(_G.AutoDelete_GetRecipeQualityLabel(quality)),
						yes(_G.AutoDelete_IsKnownRecipeQualityEnabled(profile, quality))
					))
				end
				table.insert(lines, string.format(
					"    process: action=%s processAction=%s reason=%s source=%s ignored=%s",
					tostring(action), tostring(processAction), tostring(reason), tostring(sourceRule), yes(ignored)
				))
				table.insert(lines, string.format(
					"    gates: deRaw=%s deProtected=%s deProtectReason=%s millRaw=%s prospectRaw=%s openRaw=%s",
					yes(deRaw), yes(deProtected), tostring(deProtectReason), yes(millRaw), yes(prospectRaw), yes(openRaw)
				))
				for _, ttLine in ipairs(_G.AutoDelete_GetProcessTooltipLines(bag, slot, 6)) do
					table.insert(lines, ttLine)
				end
			end
		end
	end
	if not foundAny then
		table.insert(lines, "  No bag items found.")
	end
	return table.concat(lines, "\n")
end

function _G.AutoDelete_ShowProcessDebugReport()
	local text = _G.AutoDelete_BuildProcessDebugReport()
	if _G.AutoDelete_ShowReportWindow then
		_G.AutoDelete_ShowReportWindow(text, "Process Bags Diagnostic")
	else
		print("|cffff8000[AutoDelete]|r Process Bags diagnostic is ready, but the report window is unavailable.")
	end
end

_G.AutoDelete_ProcessActionHistory = _G.AutoDelete_ProcessActionHistory or {
	cap = 80,
	entries = {},
}

function _G.AutoDelete_RecordProcessAction(data)
	if not data or not data.action then return end
	local hist = _G.AutoDelete_ProcessActionHistory
	hist.entries = hist.entries or {}
	table.insert(hist.entries, 1, {
		time = GetTime(),
		action = data.action,
		verb = data.verb,
		link = data.link,
		name = data.name,
		bag = data.bag,
		slot = data.slot,
	})
	while #hist.entries > (hist.cap or 80) do
		table.remove(hist.entries)
	end
end

function _G.AutoDelete_ClearProcessActionHistory(action)
	local hist = _G.AutoDelete_ProcessActionHistory
	hist.entries = hist.entries or {}
	for i = #hist.entries, 1, -1 do
		if not action or hist.entries[i].action == action then
			table.remove(hist.entries, i)
		end
	end
end

function _G.AutoDelete_BuildProcessActionHistoryReport(action)
	local hist = _G.AutoDelete_ProcessActionHistory or {}
	local now = GetTime()
	local title = action == "disenchant" and "AutoDelete Disenchant history"
		or "AutoDelete Process Bags action history"
	local lines = {
		title,
		"Session only. Clears on reload.",
		"",
	}
	local shown = 0
	for _, entry in ipairs(hist.entries or {}) do
		if not action or entry.action == action then
			shown = shown + 1
			local item = entry.link or entry.name or "unknown item"
			local where = (entry.bag and entry.slot) and (" b" .. entry.bag .. " s" .. entry.slot) or ""
			table.insert(lines, string.format(
				"%d. %s  %s%s",
				shown,
				_G.AutoDelete_FormatDecisionHistoryAgo(entry, now),
				tostring(entry.verb or entry.action) .. " " .. tostring(item),
				where
			))
		end
	end
	if shown == 0 then
		if action == "disenchant" then
			table.insert(lines, "No Disenchant actions recorded this session.")
		else
			table.insert(lines, "No Process Bags actions recorded this session.")
		end
	end
	return table.concat(lines, "\n")
end

function _G.AutoDelete_ShowDEHistory()
	local text = _G.AutoDelete_BuildProcessActionHistoryReport("disenchant")
	if _G.AutoDelete_ShowReportWindow then
		_G.AutoDelete_ShowReportWindow(text, "Disenchant History")
	else
		print("|cffff8000[AutoDelete]|r Disenchant history is ready, but the report window is unavailable.")
	end
end

function _G.AutoDelete_ShowItemQuickMenu(data, owner)
	if not data then return end
	local C_MENU_BG = { 5 / 255, 5 / 255, 5 / 255, 1 }
	local C_MENU_BORDER = { 0.30, 0.30, 0.30, 1 }
	local C_MENU_ROW = { 11 / 255, 11 / 255, 11 / 255, 1 }
	local C_MENU_ROW_HOVER = { 20 / 255, 45 / 255, 70 / 255, 1 }
	local C_MENU_ROW_BORDER = { 0.25, 0.25, 0.25, 1 }
	local C_MENU_ROW_BORDER_HOVER = { 0.40, 0.40, 0.40, 1 }
	local C_MENU_TEXT = { 0.85, 0.85, 0.85, 1 }
	local C_MENU_TEXT_HOVER = { 1, 1, 1, 1 }
	local link = data.link or data.itemLink
	local id = data.itemId or GetItemIDFromLink(link)
	local name = data.name or (link and GetItemInfo(link)) or (id and GetItemInfo(id))
	if not id then return end
	local isProcessRow = data.processAction == true
	local stackCount
	if data.bag and data.slot then
		local _, count = GetContainerItemInfo(data.bag, data.slot)
		stackCount = count
	end
	local maxStack = select(8, GetItemInfo(link or ("item:" .. id)))
	local isStackable = ((tonumber(maxStack) or 1) > 1) or ((tonumber(stackCount) or 1) > 1)
	local frame = _G.AutoDelete_QuickMenuFrame
	if not frame then
		frame = CreateFrame("Frame", "AutoDeleteQuickMenu", UIParent)
		frame:SetFrameStrata("FULLSCREEN_DIALOG")
		frame:SetFrameLevel(200)
		frame:EnableMouse(true)
		frame:SetClampedToScreen(true)
		frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		frame:SetBackdropColor(unpack(C_MENU_BG))
		frame:SetBackdropBorderColor(unpack(C_MENU_BORDER))
		frame:Hide()
		_G.AutoDelete_RegisterSpecialFrame("AutoDeleteQuickMenu")
		frame._items = {}
		frame:SetScript("OnHide", function(self) if self._closer then self._closer:Hide() end end)

		local closer = CreateFrame("Button", nil, UIParent)
		closer:SetAllPoints(UIParent)
		closer:SetFrameStrata("FULLSCREEN_DIALOG")
		closer:SetFrameLevel(199)
		closer:RegisterForClicks("AnyDown")
		closer:SetScript("OnClick", function() frame:Hide() end)
		closer:Hide()
		frame._closer = closer
		_G.AutoDelete_QuickMenuFrame = frame
	end

	local actions = {
		{ label = "Keep", func = function()
			if AddItemToList("whitelistText", id) then
				if _G.AutoDelete_RefreshCachedProfile then _G.AutoDelete_RefreshCachedProfile() end
				if _G.AutoDelete_RefreshProcessPanel then _G.AutoDelete_RefreshProcessPanel() end
			end
		end },
		{ label = "Sell", func = function()
			if AddItemToList("sellListText", id) then
				if _G.AutoDelete_RefreshCachedProfile then _G.AutoDelete_RefreshCachedProfile() end
				if _G.AutoDelete_RefreshProcessPanel then _G.AutoDelete_RefreshProcessPanel() end
			end
		end },
		{ label = "Delete", func = function()
			if AddItemToList("listText", id) then
				if _G.AutoDelete_RefreshCachedProfile then _G.AutoDelete_RefreshCachedProfile() end
				if _G.AutoDelete_RefreshProcessPanel then _G.AutoDelete_RefreshProcessPanel() end
			end
		end },
		{ label = "KeepOne", func = function()
			if AddItemToList("keepOneText", id) then
				if _G.AutoDelete_RefreshCachedProfile then _G.AutoDelete_RefreshCachedProfile() end
				if _G.AutoDelete_RefreshProcessPanel then _G.AutoDelete_RefreshProcessPanel() end
			end
		end },
		{ label = "Remove", func = function()
			local removedCount, removedLabels = 0, ""
			if _G.AutoDelete_RemoveItemFromAllLists then
				removedCount, removedLabels = _G.AutoDelete_RemoveItemFromAllLists(id)
			end
			if removedCount > 0 then
				if _G.AutoDelete_RefreshCachedProfile then _G.AutoDelete_RefreshCachedProfile() end
				if _G.AutoDelete_RefreshProcessPanel then _G.AutoDelete_RefreshProcessPanel() end
				if _G.AutoDeleteOptionsPanel and _G.AutoDeleteOptionsPanel.Refresh then
					_G.AutoDeleteOptionsPanel:Refresh()
				end
				print("|cffff8000[AutoDelete]|r Removed " .. (link or name or ("item:" .. id))
					.. " from all lists (" .. removedLabels .. ").")
			else
				print("|cffff8000[AutoDelete]|r " .. (link or name or ("item:" .. id)) .. " is not on any list.")
			end
		end },
	}
	if isStackable then
		table.insert(actions, 5, { label = "KeepStack", func = function()
			if AddItemToList("keepStackText", id) then
				if _G.AutoDelete_RefreshCachedProfile then _G.AutoDelete_RefreshCachedProfile() end
				if _G.AutoDelete_RefreshProcessPanel then _G.AutoDelete_RefreshProcessPanel() end
			end
		end })
	end
	if isProcessRow then
		actions[#actions + 1] = { label = "Ignore for Process", func = function()
			SetProcessIgnored(id, true)
			if _G.AutoDelete_RefreshProcessPanel then _G.AutoDelete_RefreshProcessPanel() end
			print("|cffff8000[AutoDelete]|r Ignoring " .. (link or name or ("item:" .. id)) .. " in Process Bags.")
		end }
	end
	actions[#actions + 1] = { label = "Why?", func = function()
		local text = _G.AutoDelete_BuildWhyReport(id, link, name, data.bag, data.slot)
		if _G.AutoDelete_ShowReportWindow then _G.AutoDelete_ShowReportWindow(text) else print(text) end
	end }

	for _, btn in ipairs(frame._items) do btn:Hide() end
	frame._items = {}

	local rowH = 22
	local W = 160
	frame:SetSize(W, rowH * #actions + 4)
	frame:ClearAllPoints()
	local mx, my = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (mx / scale) - 8, (my / scale) + 2)

	local menuLevel = frame:GetFrameLevel()
	for i, action in ipairs(actions) do
		local btn = CreateFrame("Button", nil, frame)
		btn:SetSize(W - 4, rowH)
		btn:SetPoint("TOPLEFT", 2, -2 - (i - 1) * rowH)
		btn:SetFrameLevel(menuLevel + 1)
		btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		btn:SetBackdropColor(unpack(C_MENU_ROW))
		btn:SetBackdropBorderColor(unpack(C_MENU_ROW_BORDER))

		local txt = btn:CreateFontString(nil, "OVERLAY")
		txt:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
		txt:SetTextColor(unpack(C_MENU_TEXT))
		txt:SetJustifyH("LEFT")
		txt:SetPoint("LEFT", 8, 0)
		txt:SetPoint("RIGHT", -8, 0)
		txt:SetText(action.label)

		btn:SetScript("OnEnter", function()
			btn:SetBackdropColor(unpack(C_MENU_ROW_HOVER))
			btn:SetBackdropBorderColor(unpack(C_MENU_ROW_BORDER_HOVER))
			txt:SetTextColor(unpack(C_MENU_TEXT_HOVER))
		end)
		btn:SetScript("OnLeave", function()
			btn:SetBackdropColor(unpack(C_MENU_ROW))
			btn:SetBackdropBorderColor(unpack(C_MENU_ROW_BORDER))
			txt:SetTextColor(unpack(C_MENU_TEXT))
		end)
		btn:SetScript("OnClick", function()
			frame:Hide()
			action.func()
		end)
		frame._items[#frame._items + 1] = btn
	end

	frame:Show()
	frame._closer:Show()
end

local scanner = CreateFrame("Frame")
-- Expose to _G so _G.AutoDelete_SetSpikeDebug (which lives in the spike
-- helper block at the top of the file, before scanner exists) can find
-- this frame at toggle time for LOOT_* event register/unregister.
_G.AutoDelete_ScannerFrame = scanner
scanner:RegisterEvent("ADDON_LOADED")
scanner:RegisterEvent("PLAYER_LOGIN")
scanner:RegisterEvent("BAG_UPDATE")
scanner:RegisterEvent("BAG_UPDATE_DELAYED")
scanner:RegisterEvent("MERCHANT_SHOW")
scanner:RegisterEvent("MERCHANT_CLOSED")
scanner:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
scanner:RegisterEvent("PLAYER_REGEN_ENABLED")    -- flush deferred disenchant updates
scanner:RegisterEvent("SPELLS_CHANGED")          -- re-check Disenchant known status
scanner:RegisterEvent("UNIT_SPELLCAST_START")
scanner:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED") -- v3.20: chat notify after DE / Mill / Prospect

-- Note on BAG_UPDATE handling: v3.20 briefly tried event bracketing
-- (LOOT_OPENED/CLOSED + merchant flags) to coalesce BAG_UPDATE bursts.
-- That design was wrong for this workload: pet AOE loot concentrated
-- 30+ items' worth of cold-cache tooltip scans into one frame at
-- LOOT_CLOSED (visible stutter), and vendor sell starved the
-- scanRequested->next-batch loop because BAG_UPDATE no longer set
-- the flag (sell hung between batches waiting for the periodic tick).
-- The inline path below distributes the same total work across the
-- natural frame boundaries between events, which is what makes
-- looting and selling feel snappy. Tooltip cache, idempotent button
-- short-circuits, and bag-space cooldown stay -- those were real
-- wins without the latency cost.

-- ============================================================================
-- Welcome Popup
-- ============================================================================
-- A first-run / persistent setup popup. Shown at PLAYER_LOGIN unless the user
-- has dismissed it via "Don't show again". Walks the user through:
--   1. Notice that all settings default to off.
--   2. Optional: create a "/target Goblin Merchant" macro (Account or Char).
--   3. Optional: walk through binding "Interact With Target" in Esc menu.
-- After all steps, opens the main settings panel.

local function ShowWelcomePopup()
	if _G.AutoDelete_WelcomePopup then
		_G.AutoDelete_WelcomePopup:Show()
		return
	end

	local FONT = "Fonts\\FRIZQT__.TTF"
	local WHITE8 = "Interface\\Buttons\\WHITE8x8"

	-- Canonical design tokens (mirrored from Options.lua's local C_* constants
	-- because this file can't see those locals). Keep these values in sync
	-- with Options.lua if the design system ever shifts. Documented in
	-- the local AGENTS.md PE-integration / design table.
	local C_BG       = { 5/255,  5/255,  5/255, 1 }     -- #050505 panel bg
	local C_BORDER   = { 0.16, 0.16, 0.16, 1 }          -- #2a2a2a outer border
	local C_TITLEBAR = { 16/255, 16/255, 16/255, 1 }    -- #101010 title bar bg
	local C_TITLE    = { 1.00, 0.50, 0.00, 1 }          -- #ff8000 legendary orange
	local C_DIM      = { 0.45, 0.45, 0.45, 1 }          -- #737373 dim text
	local C = {
		TEXT = { 0.85, 0.85, 0.85, 1 },
		TEXT_BRIGHT = { 0.90, 0.90, 0.90, 1 },
		TEXT_MUTED = { 0.75, 0.75, 0.75, 1 },
		TEXT_SUBTLE = { 0.55, 0.55, 0.55, 1 },
		CLOSE_HOVER = { 1.00, 0.30, 0.30, 1 },
		BUTTON_BG = { 0.10, 0.10, 0.10, 1 },
		BUTTON_HOVER = { 0.18, 0.18, 0.18, 1 },
		BUTTON_BORDER = { 0.30, 0.30, 0.30, 1 },
		BUTTON_BORDER_HOVER = { 1.00, 0.50, 0.00, 0.85 },
		CHECK_BG = { 0.10, 0.10, 0.10, 1 },
		CHECK_BORDER = { 0.40, 0.40, 0.40, 1 },
		RADIO_ON = { 1.00, 0.50, 0.00, 1 },
		RADIO_OFF = { 0.25, 0.25, 0.25, 1 },
		SUCCESS = { 0.20, 0.85, 0.20, 1 },
		WARNING = { 1.00, 0.82, 0.00, 1 },
		ERROR = { 1.00, 0.30, 0.30, 1 },
		DIVIDER = { 0.18, 0.18, 0.18, 1 },
		WARN_BG = { 0.18, 0.04, 0.04, 1 },
		WARN_BORDER = { 0.85, 0.15, 0.15, 1 },
		FOOTER_BG = { 5 / 255, 5 / 255, 5 / 255, 1 },
	}

	-- Outer frame. Audit fix 2026-05-20: dropped the legendary-orange border
	-- (and the borderless orange-tint title bar) that made this popup read
	-- as a different window family from the main settings panel and the
	-- Process Bags / Import Conflicts windows. Now uses the canonical chrome:
	-- dark body, dark gray border, dark title bar, orange title text, dim
	-- close X that turns red on hover.
	local f = CreateFrame("Frame", "AutoDelete_WelcomePopup", UIParent)
	f:SetSize(440, 658)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetFrameLevel(100)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetBackdrop({
		bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1,
	})
	f:SetBackdropColor(unpack(C_BG))
	f:SetBackdropBorderColor(unpack(C_BORDER))
	_G.AutoDelete_RegisterSpecialFrame("AutoDelete_WelcomePopup")

	-- Title bar -- dark bg + dark border, matching the main settings panel.
	local titleBar = CreateFrame("Frame", nil, f)
	titleBar:SetPoint("TOPLEFT", 1, -1)
	titleBar:SetPoint("TOPRIGHT", -1, -1)
	titleBar:SetHeight(28)
	titleBar:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
	titleBar:SetBackdropColor(unpack(C_TITLEBAR))
	titleBar:SetBackdropBorderColor(unpack(C_BORDER))

	local title = titleBar:CreateFontString(nil, "OVERLAY")
	title:SetFont(FONT, 14, "OUTLINE")
	title:SetPoint("LEFT", 12, 0)
	title:SetTextColor(unpack(C_TITLE))
	title:SetText("Welcome to AutoDelete")

	-- Close X -- dim by default, red on hover, matches the main panel exactly.
	local closeBtn = CreateFrame("Button", nil, titleBar)
	closeBtn:SetSize(24, 24)
	closeBtn:SetPoint("RIGHT", -4, 0)
	local closeText = closeBtn:CreateFontString(nil, "OVERLAY")
	closeText:SetFont(FONT, 16, "OUTLINE")
	closeText:SetPoint("CENTER", 0, 1)
	closeText:SetTextColor(unpack(C_DIM))
	closeText:SetText("x")
	closeBtn:SetScript("OnEnter", function() closeText:SetTextColor(unpack(C.CLOSE_HOVER)) end)
	closeBtn:SetScript("OnLeave", function() closeText:SetTextColor(unpack(C_DIM)) end)
	closeBtn:SetScript("OnClick", function() f:Hide() end)

	-- Intro text
	local intro = f:CreateFontString(nil, "OVERLAY")
	intro:SetFont(FONT, 12)
	intro:SetPoint("TOPLEFT", 16, -42)
	intro:SetPoint("TOPRIGHT", -16, -42)
	intro:SetJustifyH("LEFT")
	intro:SetWordWrap(true)
	intro:SetTextColor(unpack(C.TEXT_BRIGHT))
	intro:SetText("All AutoDelete settings start |cffff8000OFF|r by default. Open the settings panel after this dialog to enable features and configure your Delete, Sell, Keep, KeepOne, and KeepStack lists.")
	intro:SetHeight(50)

	-- Section: Macro creation
	local macroLabel = f:CreateFontString(nil, "OVERLAY")
	macroLabel:SetFont(FONT, 12, "OUTLINE")
	macroLabel:SetPoint("TOPLEFT", 16, -106)
	macroLabel:SetTextColor(unpack(C.WARNING))
	macroLabel:SetText("Create a Goblin Merchant macro?")

	local macroDesc = f:CreateFontString(nil, "OVERLAY")
	macroDesc:SetFont(FONT, 11)
	macroDesc:SetPoint("TOPLEFT", 16, -124)
	macroDesc:SetPoint("TOPRIGHT", -16, -124)
	macroDesc:SetJustifyH("LEFT")
	macroDesc:SetWordWrap(true)
	macroDesc:SetTextColor(unpack(C.TEXT_MUTED))
	macroDesc:SetText("Quick way to target your summoned Goblin Merchant. After creation, drag it to a hotbar from |cffffd700/macro|r.")
	macroDesc:SetHeight(28)

	-- Macro scope selection (only used if Yes is clicked)
	local macroScope = "char"  -- default
	local accBox, charBox

	local function MakeRadio(parent, label, x, y, getValue, setValue)
		local btn = CreateFrame("Button", nil, parent)
		btn:SetSize(160, 18)
		btn:SetPoint("TOPLEFT", x, y)

		local dot = btn:CreateTexture(nil, "ARTWORK")
		dot:SetTexture(WHITE8)
		dot:SetSize(10, 10)
		dot:SetPoint("LEFT", 2, 0)
		dot:SetVertexColor(unpack(C.RADIO_OFF))

		local txt = btn:CreateFontString(nil, "OVERLAY")
		txt:SetFont(FONT, 11)
		txt:SetPoint("LEFT", 18, 0)
		txt:SetTextColor(unpack(C.TEXT))
		txt:SetText(label)

		btn._dot = dot
		btn._update = function()
			if getValue() then
				dot:SetVertexColor(unpack(C.RADIO_ON))
			else
				dot:SetVertexColor(unpack(C.RADIO_OFF))
			end
		end
		btn:SetScript("OnClick", function()
			setValue()
			if accBox then accBox._update() end
			if charBox then charBox._update() end
		end)
		btn._update()
		return btn
	end

	charBox = MakeRadio(f, "Per-character macro", 32, -156,
		function() return macroScope == "char" end,
		function() macroScope = "char" end)
	accBox = MakeRadio(f, "Account-wide macro", 200, -156,
		function() return macroScope == "account" end,
		function() macroScope = "account" end)

	-- Yes/No buttons for the macro section
	local function MakeButton(parent, label, w)
		local btn = CreateFrame("Button", nil, parent)
		btn:SetSize(w or 80, 24)
		btn:SetBackdrop({
			bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1,
		})
		btn:SetBackdropColor(unpack(C.BUTTON_BG))
		btn:SetBackdropBorderColor(unpack(C.BUTTON_BORDER))
		local txt = btn:CreateFontString(nil, "OVERLAY")
		txt:SetFont(FONT, 11, "OUTLINE")
		txt:SetPoint("CENTER")
		txt:SetTextColor(unpack(C.TEXT_BRIGHT))
		txt:SetText(label)
		btn:SetScript("OnEnter", function(self)
			self:SetBackdropColor(unpack(C.BUTTON_HOVER))
			self:SetBackdropBorderColor(unpack(C.BUTTON_BORDER_HOVER))
		end)
		btn:SetScript("OnLeave", function(self)
			self:SetBackdropColor(unpack(C.BUTTON_BG))
			self:SetBackdropBorderColor(unpack(C.BUTTON_BORDER))
		end)
		return btn, txt
	end

	local macroYes, macroYesTxt = MakeButton(f, "Create Macro", 110)
	macroYes:SetPoint("TOPLEFT", 16, -180)

	-- Macro feedback label (shown after click). Anchored BELOW the buttons
	-- so the text never overlaps them even when it wraps to two lines.
	local macroResult = f:CreateFontString(nil, "OVERLAY")
	macroResult:SetFont(FONT, 10)
	macroResult:SetPoint("TOPLEFT", macroYes, "BOTTOMLEFT", 0, -4)
	macroResult:SetPoint("RIGHT", f, "RIGHT", -16, 0)
	macroResult:SetJustifyH("LEFT")
	macroResult:SetWordWrap(true)
	macroResult:SetTextColor(unpack(C.SUCCESS))
	macroResult:SetText("")

	macroYes:SetScript("OnClick", function()
		local perChar = (macroScope == "char")
		-- 3.3.5 expects an iconIndex (number) into the GetMacroIcons() table,
		-- not a string name. Walk the table looking for our icon.
		local body = "/target Goblin Merchant"
		local existing = GetMacroIndexByName("AutoDelete-Goblin")
		if existing and existing > 0 then
			macroResult:SetTextColor(unpack(C.WARNING))
			macroResult:SetText("Macro 'AutoDelete-Goblin' already exists. Open |cffffd700/macro|r and drag it to your action bar.")
			return
		end

		-- Resolve icon name to icon index. The Goblin Merchant pet uses the
		-- Pack Hobgoblin racial icon. GetMacroIcons() returns names without
		-- the path prefix, in upper or mixed case depending on client.
		-- We compare case-insensitively to be safe.
		local iconIdx = 1
		local wantedLower = "ability_racial_packhobgoblin"
		if GetMacroIcons then
			local icons = GetMacroIcons()
			if type(icons) == "table" then
				for i, name in ipairs(icons) do
					if name and string.lower(name) == wantedLower then
						iconIdx = i
						break
					end
				end
			end
		end

		local ok, idx = pcall(CreateMacro, "AutoDelete-Goblin", iconIdx, body, perChar)
		if ok and idx and idx > 0 then
			macroResult:SetTextColor(unpack(C.SUCCESS))
			macroResult:SetText("Created macro 'AutoDelete-Goblin'. Open |cffffd700/macro|r and drag it to your action bar.")
		else
			macroResult:SetTextColor(unpack(C.ERROR))
			local err = (not ok) and tostring(idx) or "unknown"
			macroResult:SetText("Could not create the macro. Error: " .. err)
		end
	end)

	-- Section: Keybind walkthrough
	local kbLabel = f:CreateFontString(nil, "OVERLAY")
	kbLabel:SetFont(FONT, 12, "OUTLINE")
	kbLabel:SetPoint("TOPLEFT", 16, -226)
	kbLabel:SetTextColor(unpack(C.WARNING))
	kbLabel:SetText("Bind Interact With Target?")

	local kbDesc = f:CreateFontString(nil, "OVERLAY")
	kbDesc:SetFont(FONT, 11)
	kbDesc:SetPoint("TOPLEFT", 16, -244)
	kbDesc:SetPoint("TOPRIGHT", -16, -244)
	kbDesc:SetJustifyH("LEFT")
	kbDesc:SetWordWrap(true)
	kbDesc:SetTextColor(unpack(C.TEXT_MUTED))
	kbDesc:SetText("Once the merchant is targeted, this keybind opens the vendor window. Look under |cffffd700Targeting Functions|r > |cffffd700Interact With Target|r.")
	kbDesc:SetHeight(32)

	local kbYes, _ = MakeButton(f, "Open Keybinds", 110)
	kbYes:SetPoint("TOPLEFT", 16, -290)
	kbYes:SetScript("OnClick", function()
		-- Open Blizzard's keybinding panel.
		if KeyBindingFrame_LoadUI then KeyBindingFrame_LoadUI() end
		if KeyBindingFrame then
			KeyBindingFrame:Show()
		elseif ShowUIPanel then
			ShowUIPanel(KeyBindingFrame)
		end
		-- Scroll to the INTERACTTARGET binding. The keybind UI is a faux
		-- scroll frame backed by the GetBinding(i) iteration. We walk the
		-- list, find the row index for "INTERACTTARGET", set the scroll
		-- offset to put it near the top, then refresh the visible rows.
		local KBF = _G.KeyBindingFrame
		if not KBF or not GetNumBindings then return end

		local targetIdx
		for i = 1, GetNumBindings() do
			local action = GetBinding(i)
			if action == "INTERACTTARGET" then
				targetIdx = i
				break
			end
		end
		if not targetIdx then return end

		-- KeyBindingFrameScrollFrame uses FauxScrollFrame: KEYBINDINGS_PER_PAGE
		-- rows are visible, scroll offset is in rows. Set it so target row
		-- sits near the top (offset = targetIdx - 1, clamped).
		local SF = _G.KeyBindingFrameScrollFrame
		if SF and FauxScrollFrame_OnVerticalScroll and KeyBindingFrame_Update then
			local KEYS_PER_PAGE = (_G.KEY_BINDINGS_DISPLAYED or 19)
			local maxOffset = math.max(0, GetNumBindings() - KEYS_PER_PAGE)
			local offset = math.max(0, math.min(targetIdx - 2, maxOffset))
			-- Each row is 16px tall in 3.3.5's keybind frame.
			FauxScrollFrame_OnVerticalScroll(SF, offset * 16, 16, KeyBindingFrame_Update)
		end
	end)

	-- Divider above the 'How it works' section so the eye separates it from
	-- the macro/keybind walkthrough above.
	local divider = f:CreateTexture(nil, "ARTWORK")
	divider:SetTexture(WHITE8)
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", 16, -334)
	divider:SetPoint("TOPRIGHT", -16, -334)
	divider:SetVertexColor(unpack(C.DIVIDER))

	-- Section: How it works (simple explanation of the 3-list system).
	local hiwLabel = f:CreateFontString(nil, "OVERLAY")
	hiwLabel:SetFont(FONT, 12, "OUTLINE")
	hiwLabel:SetPoint("TOPLEFT", 16, -344)
	hiwLabel:SetTextColor(unpack(C.WARNING))
	hiwLabel:SetText("How it works")

	local hiwBody = f:CreateFontString(nil, "OVERLAY")
	hiwBody:SetFont(FONT, 11)
	hiwBody:SetPoint("TOPLEFT", 16, -362)
	hiwBody:SetPoint("TOPRIGHT", -16, -362)
	hiwBody:SetJustifyH("LEFT")
	hiwBody:SetWordWrap(true)
	hiwBody:SetTextColor(unpack(C.TEXT))
	hiwBody:SetText(
		"AutoDelete uses five item lists. Drop an item onto the icons next to your bag, or open the panel and use the tabs.\n" ..
		"|cffff5050Delete|r: items are destroyed on next scan.\n" ..
		"|cffffd700Sell|r: items are sold the next time you open a vendor.\n" ..
		"|cff80c0ffKeep|r: items are protected and never auto-sold or auto-deleted.\n" ..
		"|cffff5050KeepOne|r: extra units are deleted until one unit remains.\n" ..
		"|cffff5050KeepStack|r: extra stacks are deleted until one stack remains.\n\n" ..
		"|cff66ddffSell filters|r (on the Sell tab, BoE Armor / BoP / BoE Weapons): vendor-only auto-sell rules. " ..
		"Match by quality and item level, no per-item entry needed."
	)
	hiwBody:SetHeight(125)

	-- Auto-Add Equipped opt-in checkbox. Sits between 'How it works' and the
	-- warning callout. Toggling this on writes the setting to the active
	-- profile AND immediately runs the one-time sync of currently equipped
	-- items into Keep, mirroring the General-tab toggle's behavior. Default
	-- is ON (matches the profile default), so new users are protected without
	-- having to know about the feature.
	-- Read initial state from the profile so the popup reflects current setting
	-- if the user has already toggled it elsewhere.
	local aaeChecked = true
	do
		_G.AutoDeleteDB = _G.AutoDeleteDB or {}
		local db = _G.AutoDeleteDB
		if db.profiles and db.chars then
			local charKey = (UnitName("player") or "Default") .. "-" .. (GetRealmName() or "")
			local profileKey = db.chars[charKey] or charKey
			local p = db.profiles[profileKey]
			if p and p.autoAddEquipped ~= nil then
				aaeChecked = (p.autoAddEquipped == true)
			end
		end
	end
	local aaeCheck = CreateFrame("Button", nil, f)
	aaeCheck:SetSize(14, 14)
	aaeCheck:SetPoint("TOPLEFT", 16, -482)
	aaeCheck:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
	aaeCheck:SetBackdropColor(unpack(C.CHECK_BG))
	aaeCheck:SetBackdropBorderColor(unpack(C.CHECK_BORDER))

	local aaeMark = aaeCheck:CreateTexture(nil, "OVERLAY")
	aaeMark:SetTexture("Interface\\AddOns\\AutoDelete\\textures\\checkmark.tga")
	aaeMark:SetSize(12, 12)
	aaeMark:SetPoint("CENTER")
	if aaeChecked then aaeMark:Show() else aaeMark:Hide() end

	local aaeLabel = f:CreateFontString(nil, "OVERLAY")
	aaeLabel:SetFont(FONT, 11)
	aaeLabel:SetPoint("LEFT", aaeCheck, "RIGHT", 6, 0)
	aaeLabel:SetTextColor(unpack(C.TEXT))
	aaeLabel:SetText("Auto-Add Equipped Items to Keep")

	local aaeDesc = f:CreateFontString(nil, "OVERLAY")
	aaeDesc:SetFont(FONT, 10)
	aaeDesc:SetPoint("TOPLEFT", aaeCheck, "BOTTOMLEFT", 0, -2)
	aaeDesc:SetPoint("RIGHT", f, "RIGHT", -16, 0)
	aaeDesc:SetJustifyH("LEFT")
	aaeDesc:SetWordWrap(true)
	aaeDesc:SetTextColor(unpack(C.TEXT_SUBTLE))
	aaeDesc:SetText("Adds your currently equipped items to Keep, plus anything you equip later. Recommended.")

	-- Click handler writes to profile and (if enabling) runs the sync.
	local function ToggleAutoAddEquipped()
		aaeChecked = not aaeChecked
		if aaeChecked then aaeMark:Show() else aaeMark:Hide() end
		_G.AutoDeleteDB = _G.AutoDeleteDB or {}
		local db = _G.AutoDeleteDB
		if db.profiles and db.chars then
			local charKey = (UnitName("player") or "Default") .. "-" .. (GetRealmName() or "")
			local profileKey = db.chars[charKey] or charKey
			local p = db.profiles[profileKey]
			if p then
				local wasOff = (p.autoAddEquipped ~= true)
				p.autoAddEquipped = aaeChecked
				if _G.AutoDelete_RefreshCachedProfile then
					_G.AutoDelete_RefreshCachedProfile()
				end
				if aaeChecked and wasOff and _G.AutoDelete_SyncEquippedToKeep then
					_G.AutoDelete_SyncEquippedToKeep()
				end
			end
		end
	end
	aaeCheck:SetScript("OnClick", ToggleAutoAddEquipped)

	-- Make label clickable too
	local aaeLabelBtn = CreateFrame("Button", nil, f)
	aaeLabelBtn:SetPoint("LEFT", aaeCheck, "RIGHT", 0, 0)
	aaeLabelBtn:SetSize(280, 14)
	aaeLabelBtn:SetScript("OnClick", ToggleAutoAddEquipped)

	-- Warning callout: bright red box reminding users to put valuable items
	-- on the Keep list before enabling auto-delete/auto-sell rules. Sits
	-- between 'How it works' and the footer. Backdrop with red border for
	-- visual punch so it can't be missed.
	local warnFrame = CreateFrame("Frame", nil, f)
	warnFrame:SetPoint("TOPLEFT", 16, -522)
	warnFrame:SetPoint("TOPRIGHT", -16, -522)
	warnFrame:SetHeight(84)
	warnFrame:SetBackdrop({
		bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 2,
	})
	warnFrame:SetBackdropColor(unpack(C.WARN_BG))
	warnFrame:SetBackdropBorderColor(unpack(C.WARN_BORDER))

	local warnText = warnFrame:CreateFontString(nil, "OVERLAY")
	warnText:SetFont(FONT, 12, "OUTLINE")
	warnText:SetPoint("TOPLEFT", 10, -8)
	warnText:SetPoint("BOTTOMRIGHT", -10, 8)
	warnText:SetJustifyH("CENTER")
	warnText:SetJustifyV("MIDDLE")
	warnText:SetWordWrap(true)
	warnText:SetTextColor(unpack(C.ERROR))
	warnText:SetText("FAIR WARNING\nTo prevent valuable items from being sold or deleted, ADD THEM TO YOUR KEEP LIST BEFORE YOU TURN AUTODELETE ON.")

	-- Footer bar: darker strip with a divider line on top, separating the
	-- "Don't show again" checkbox + Open Settings button from the body.
	-- Uses absolute positioning anchored to BOTTOMLEFT/BOTTOMRIGHT of the
	-- popup so it stays glued to the bottom regardless of popup height.
	local FOOTER_H = 44
	local footerBar = CreateFrame("Frame", nil, f)
	footerBar:SetPoint("BOTTOMLEFT", 1, 1)
	footerBar:SetPoint("BOTTOMRIGHT", -1, 1)
	footerBar:SetHeight(FOOTER_H)
	footerBar:SetBackdrop({ bgFile = WHITE8 })
	footerBar:SetBackdropColor(unpack(C.FOOTER_BG))

	local footerDivider = f:CreateTexture(nil, "ARTWORK")
	footerDivider:SetTexture(WHITE8)
	footerDivider:SetHeight(1)
	footerDivider:SetPoint("BOTTOMLEFT", 1, FOOTER_H + 1)
	footerDivider:SetPoint("BOTTOMRIGHT", -1, FOOTER_H + 1)
	footerDivider:SetVertexColor(unpack(C.DIVIDER))

	-- Don't-show-again checkbox (left side of footer bar). Parented to
	-- footerBar so it draws on top of the footer's backdrop - children of
	-- a child frame stack above the parent's overlay regions.
	local dontShow = false
	local dsCheck = CreateFrame("Button", nil, footerBar)
	dsCheck:SetSize(14, 14)
	dsCheck:SetPoint("LEFT", footerBar, "LEFT", 16, 0)
	dsCheck:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
	dsCheck:SetBackdropColor(unpack(C.CHECK_BG))
	dsCheck:SetBackdropBorderColor(unpack(C.CHECK_BORDER))

	local dsCheckMark = dsCheck:CreateTexture(nil, "OVERLAY")
	dsCheckMark:SetTexture("Interface\\AddOns\\AutoDelete\\textures\\checkmark.tga")
	dsCheckMark:SetSize(12, 12)
	dsCheckMark:SetPoint("CENTER")
	dsCheckMark:Hide()

	local dsLabel = footerBar:CreateFontString(nil, "OVERLAY")
	dsLabel:SetFont(FONT, 11)
	dsLabel:SetPoint("LEFT", dsCheck, "RIGHT", 6, 0)
	dsLabel:SetTextColor(unpack(C.TEXT))
	dsLabel:SetText("Don't show this again")

	dsCheck:SetScript("OnClick", function()
		dontShow = not dontShow
		if dontShow then dsCheckMark:Show() else dsCheckMark:Hide() end
	end)

	-- Make label clickable too
	local labelBtn = CreateFrame("Button", nil, footerBar)
	labelBtn:SetPoint("LEFT", dsCheck, "RIGHT", 0, 0)
	labelBtn:SetSize(160, 14)
	labelBtn:SetScript("OnClick", function() dsCheck:Click() end)

	local openSettings, _ = MakeButton(footerBar, "Open Settings", 130)
	openSettings:SetPoint("RIGHT", footerBar, "RIGHT", -16, 0)
	openSettings:SetScript("OnClick", function()
		if dontShow then
			_G.AutoDeleteDB = _G.AutoDeleteDB or {}
			_G.AutoDeleteDB.welcomeDismissed = true
		end
		f:Hide()
		local panel = _G.AutoDeleteOptionsPanel
		-- Diagnostics: print why the panel didn't open if anything goes wrong.
		-- Helps users tell us what's happening when "Open Settings" appears
		-- to do nothing.
		if not panel then
			print("|cffff8000[AutoDelete]|r Open Settings: panel not found (Options.lua may not have loaded yet). Try /del to open settings instead.")
			return
		end
		if not panel.IsShown then
			print("|cffff8000[AutoDelete]|r Open Settings: panel object missing IsShown method. Type: " .. type(panel))
			return
		end
		if panel:IsShown() then
			print("|cffff8000[AutoDelete]|r Open Settings: panel already visible (it may be hidden behind another window).")
			return
		end
		panel:Show()
		-- Verify it actually became visible. If something else is blocking
		-- (strata, parent hidden, addon conflict) tell the user.
		if not panel:IsShown() then
			print("|cffff8000[AutoDelete]|r Open Settings: called Show() but panel did not become visible. Try /del - if that also fails, an addon conflict is likely.")
		end
	end)

	-- Hook close (X or Esc) to also persist the dismissal if checked
	f:SetScript("OnHide", function()
		if dontShow then
			_G.AutoDeleteDB = _G.AutoDeleteDB or {}
			_G.AutoDeleteDB.welcomeDismissed = true
		end
	end)
end

-- ============================================================================
-- Event Handler (scanner OnEvent)
-- ============================================================================
-- ADDON_LOADED        -> initialize SavedVariables
-- PLAYER_LOGIN        -> print loaded notice, install MerchantFrame.Hide
--                        wrappers, schedule the post-login ElvUI button
--                        creation + welcome popup (2s delay)
-- BAG_UPDATE          -> request a delete-scan + rewire secure buttons +
--                        refresh process panel + bag-space warning
-- BAG_UPDATE_DELAYED  -> request a delete-scan (Wrath: rarely fires; harmless)
-- MERCHANT_SHOW       -> sample inventory worth, then auto-repair + auto-sell
-- MERCHANT_CLOSED     -> print sell summary, fire after-close summon if armed

scanner:SetScript("OnEvent", function(self, event, arg1, arg2)
	-- v3.20 spike debug: track LOOT_* events when active. These events
	-- are only registered while SpikeDebug is on (see SetSpikeDebug),
	-- so the dispatch cost is zero in the off case.
	if event == "LOOT_OPENED" or event == "LOOT_SLOT_CLEARED" or event == "LOOT_CLOSED" then
		if _G.AutoDelete_SpikeAddLootEvt then _G.AutoDelete_SpikeAddLootEvt(event) end
		return
	end
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		GetDB()
		RefreshCachedProfile()
		return
	end
	if event == "ADDON_LOADED" and tostring(arg1 or ""):lower() == "projectebonhold" then
		AfterDelay(0.2, function()
			if AutoDelete_InstallPEAffixHook then AutoDelete_InstallPEAffixHook() end
			if AutoDelete_RefreshOwnedAffixes then AutoDelete_RefreshOwnedAffixes() end
			if AutoDelete_RequestPELearnedAffixes then
				AutoDelete_RequestPELearnedAffixes("ProjectEbonhold loaded", false)
			end
		end)
		return
	end
	if event == "UNIT_SPELLCAST_START" and arg1 == "player" then
		if _G.AutoDelete_OnOneKeySpellStart then
			_G.AutoDelete_OnOneKeySpellStart(arg2)
		end
		return
	end
	-- v3.20 action chat notifier. UNIT_SPELLCAST_SUCCEEDED on 3.3.5a fires
	-- (unit, spellName, rank, lineID, spellID) -- arg1 is unit, arg2 is
	-- the spell name. We only care about player casts whose name matches
	-- one of the cached localized DE / Mill / Prospect spells.
	if event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
		if _G.AutoDelete_OnSpellCastSucceeded then
			_G.AutoDelete_OnSpellCastSucceeded(arg2)
		end
		return
	end
	if event == "PLAYER_EQUIPMENT_CHANGED" then
		-- Equipping a BoE flips it to Soulbound -- invalidate the soulbound
		-- tooltip cache so any subsequent IsSoulbound() rescans. Cheap: just
		-- replace the sub-table, GC handles the old entries.
		if _G.AutoDelete_TooltipCache then
			_G.AutoDelete_TooltipCache.soulbound = {}
		end
		HandleEquipmentChanged(arg1)
		return
	end
	if event == "PLAYER_LOGIN" then
		RefreshCachedProfile()
		print("|cffff8000[AutoDelete]|r loaded. Type |cff00ff00/del|r to configure.")
		-- Mirror PE's learnedAffixes if PE addon has already populated.
		-- PE's SEND_LEARNED_AFFIXES often arrives later than PLAYER_LOGIN
		-- so the auto-hook below catches subsequent updates, but a login-
		-- time pass catches the case where PE pushed data via a different
		-- path before our addon loaded.
		if AutoDelete_RefreshOwnedAffixes then AutoDelete_RefreshOwnedAffixes() end
		-- Install the PE auto-refresh hook NOW. This is the primary
		-- trigger that keeps our mirror in sync with PE's table without
		-- the user having to re-toggle Show/Keep Missing Affix after every Extract.
		-- See AutoDelete_InstallPEAffixHook for the design rationale.
		-- If PE isn't loaded yet (rare -- both addons should be loaded
		-- by PLAYER_LOGIN), the install is a no-op and the SPELLS_CHANGED
		-- handler will pick up affix updates as a fallback.
		if AutoDelete_InstallPEAffixHook then AutoDelete_InstallPEAffixHook() end
		if AutoDelete_RequestPELearnedAffixes then
			AutoDelete_RequestPELearnedAffixes("PLAYER_LOGIN", false)
		end
		if _G.AutoDelete_InstallBagAltRightHook then _G.AutoDelete_InstallBagAltRightHook() end
		if _G.AutoDelete_CreateMinimapButton then _G.AutoDelete_CreateMinimapButton() end

		-- One-Key Disenchant: create the SecureActionButton once. Name is
		-- referenced by the panel's key-capture row as the CLICK target
		-- ("CLICK AutoDeleteDisenchantButton:LeftButton"). Created here
		-- rather than at file load because SecureActionButtonTemplate is
		-- only safe to instantiate after PLAYER_LOGIN (some private servers
		-- reject earlier creation paths). UIParent is the parent: keeps the
		-- button out of any tainted ancestor chain so the protected call
		-- the macro fires stays secure.
		if not disenchantButton then
			disenchantButton = CreateFrame(
				"Button",
				"AutoDeleteDisenchantButton",
				UIParent,
				"SecureActionButtonTemplate"
			)
			disenchantButton:Hide()  -- invisible; only the bound key matters
			disenchantButton:RegisterForClicks("AnyUp")
			disenchantButton:SetAttribute("type", "macro")
			disenchantButton:SetAttribute("macrotext", "")
			disenchantButton:HookScript("PreClick", function()
				if _G.AutoDelete_OnOneKeyPreClick then _G.AutoDelete_OnOneKeyPreClick("disenchant") end
			end)
			disenchantButton:HookScript("PostClick", function()
				if _G.AutoDelete_OnOneKeyPostClick then _G.AutoDelete_OnOneKeyPostClick("disenchant") end
			end)
		end
		RefreshDisenchantKnown()
		UpdateDisenchantButton()

		-- One-Key Open: create the secure button now (PLAYER_LOGIN is the
		-- earliest safe time for SecureActionButtonTemplate on some private
		-- servers) and stage the first target. The button has no Bindings.xml
		-- entry; the options panel installs a binding via SetBinding when
		-- the user picks a key in the in-panel capture row.
		if _G.AutoDelete_EnsureOpenButton then
			_G.AutoDelete_EnsureOpenButton()
			if _G.AutoDelete_UpdateOpenButton then _G.AutoDelete_UpdateOpenButton() end
		end

		-- One-Key Mill and One-Key Prospect mirror the Open/Disenchant
		-- pattern: create the secure button, refresh the known-spell cache,
		-- stage the first target. Each is a no-op if the user hasn't
		-- toggled the feature on.
		if _G.AutoDelete_EnsureMillButton then
			_G.AutoDelete_EnsureMillButton()
			if _G.AutoDelete_RefreshMillKnown then _G.AutoDelete_RefreshMillKnown() end
			if _G.AutoDelete_UpdateMillButton then _G.AutoDelete_UpdateMillButton() end
		end
		if _G.AutoDelete_EnsureProspectButton then
			_G.AutoDelete_EnsureProspectButton()
			if _G.AutoDelete_RefreshProspectKnown then _G.AutoDelete_RefreshProspectKnown() end
			if _G.AutoDelete_UpdateProspectButton then _G.AutoDelete_UpdateProspectButton() end
		end

		-- v3.20: initialize per-character Keep-skip memory. Lazy and
		-- idempotent; safe to call on every PLAYER_LOGIN regardless of
		-- whether the SV table already has the keepSkip subtree.
		if _G.AutoDelete_EnsureKeepSkipDB then _G.AutoDelete_EnsureKeepSkipDB() end

		-- One-time notice: the v3.02 schema migration moved sell rules into
		-- per-category sections. EnsureProfileFields sets this flag when it
		-- migrates a profile from the old schema.
		if _G._AutoDelete_NeedMigrationNotice then
			_G._AutoDelete_NeedMigrationNotice = nil
			print("|cffff8000[AutoDelete]|r |cffffff00Sell rules updated:|r the old Sell Filters/Conditions split has been replaced with per-category sections (BoE Armor, BoP, BoE Weapons). Your existing settings were migrated. Open |cff00ff00/del|r and review the Sell tab.")
		end

		-- Keep bags open when the vendor closes. Diagnostic trace on PE-ElvUI
		-- showed the call order is:
		--   1. ToggleBackpack fires (Blizzard ContainerFrame_OnHide cascade)
		--   2. B:CloseBags fires (ElvUI closes its bag frames)
		--   3. MerchantFrame:OnHide fires LAST
		--
		-- That means hooking OnHide is too late to set a suppress flag.
		-- We have to wrap MerchantFrame.Hide directly so the flag is set
		-- BEFORE any cascading hide handlers run.
		if MerchantFrame then
			local suppressClose = false

			-- Wrap _G.CloseAllBags
			if _G.CloseAllBags then
				local origCloseAllBags = _G.CloseAllBags
				_G.CloseAllBags = function(...)
					if suppressClose then return end
					return origCloseAllBags(...)
				end
			end

			-- Wrap _G.ToggleBackpack (cascade calls this)
			if _G.ToggleBackpack then
				local origToggleBackpack = _G.ToggleBackpack
				_G.ToggleBackpack = function(...)
					if suppressClose then return end
					return origToggleBackpack(...)
				end
			end

			-- Wrap _G.CloseBackpack just in case
			if _G.CloseBackpack then
				local origCloseBackpack = _G.CloseBackpack
				_G.CloseBackpack = function(...)
					if suppressClose then return end
					return origCloseBackpack(...)
				end
			end

			-- Wrap ElvUI's bag module CloseBags.
			if _G.ElvUI then
				local E = _G.ElvUI[1]
				local B = E and E.GetModule and E:GetModule("Bags", true)
				if B and B.CloseBags then
					local origCB = B.CloseBags
					B.CloseBags = function(self, ...)
						if suppressClose then return end
						return origCB(self, ...)
					end
				end
			end

			-- Pre-hook the Hide method on MerchantFrame. This is the EARLIEST
			-- possible interception point: the user/script calls
			-- MerchantFrame:Hide(), our wrapper sets suppressClose, then
			-- delegates to the real Hide which fires the OnHide cascade.
			-- All bag-close calls in that cascade now see suppressClose=true.
			local origHide = MerchantFrame.Hide
			MerchantFrame.Hide = function(self, ...)
				suppressClose = true
				local result = origHide(self, ...)
				-- Release the flag after the OnHide cascade settles. The
				-- cascade completes in the same frame so anything past 0
				-- works; 0.1s is conservative and means the user's manual
				-- bag toggle keypress arriving immediately after vendor
				-- close still goes through.
				AfterDelay(0.1, function() suppressClose = false end)
				return result
			end
		end

		AfterDelay(2, function()
			CreateElvUIBagButton()
			-- Last-resort compatibility path for ElvUI's replacement bag UI.
			-- Default Blizzard bags use ContainerFrame_Update above.
			InstallElvUIAffixDotHook()
			if _G.AutoDelete_RefreshElvUIJunkIconSuppression then
				_G.AutoDelete_RefreshElvUIJunkIconSuppression(cachedProfile)
			end
			-- Show the welcome popup unless the user clicked
			-- "Don't show this again" on a previous login.
			if not (_G.AutoDeleteDB and _G.AutoDeleteDB.welcomeDismissed) then
				ShowWelcomePopup()
			end
			-- One-shot scan: detect items present on more than one list
			-- (Delete + Sell, Delete + Keep, Sell + Keep). The add-time
			-- conflict check prevents new ones, but imports, manual text
			-- edits, or older saves can leave overlaps. We warn the user
			-- in chat and direct them to /del clean.
			local p = cachedProfile
			if p then
				local function buildKeySet(text)
					local set = {}
					for line in string.gmatch(text or "", "[^\r\n]+") do
						local raw = Trim(line)
						if raw ~= "" then set[raw] = true end
					end
					return set
				end
				local delSet  = buildKeySet(p.listText)
				local sellSet = buildKeySet(p.sellListText)
				local keepSet = buildKeySet(p.whitelistText)
				local keepOneSet = buildKeySet(p.keepOneText)
				local keepStackSet = buildKeySet(p.keepStackText)
				local conflicts = 0
				for k in pairs(delSet)  do if sellSet[k] then conflicts = conflicts + 1 end end
				for k in pairs(delSet)  do if keepSet[k] then conflicts = conflicts + 1 end end
				for k in pairs(delSet)  do if keepOneSet[k] then conflicts = conflicts + 1 end end
				for k in pairs(delSet)  do if keepStackSet[k] then conflicts = conflicts + 1 end end
				for k in pairs(sellSet) do if keepSet[k] then conflicts = conflicts + 1 end end
				for k in pairs(sellSet) do if keepOneSet[k] then conflicts = conflicts + 1 end end
				for k in pairs(sellSet) do if keepStackSet[k] then conflicts = conflicts + 1 end end
				for k in pairs(keepSet) do if keepOneSet[k] then conflicts = conflicts + 1 end end
				for k in pairs(keepSet) do if keepStackSet[k] then conflicts = conflicts + 1 end end
				for k in pairs(keepOneSet) do if keepStackSet[k] then conflicts = conflicts + 1 end end
				if conflicts > 0 then
					print("|cffff4444[AutoDelete]|r Warning: " .. conflicts ..
						" item(s) appear on more than one list. Run |cff00ff00/del clean|r to resolve.")
				end
			end
		end)
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		-- Combat just ended. Flush any deferred secure-button macrotext
		-- updates that were blocked by InCombatLockdown. Each module owns
		-- its own pending flag and FlushDeferred* helper so they stay
		-- independent; both calls are safe no-ops when nothing's queued.
		if disenchantUpdatePending then
			disenchantUpdatePending = false
			UpdateDisenchantButton()
		end
		if _G.AutoDelete_FlushDeferredOpenUpdate then
			_G.AutoDelete_FlushDeferredOpenUpdate()
		end
		if _G.AutoDelete_FlushDeferredMillUpdate then
			_G.AutoDelete_FlushDeferredMillUpdate()
		end
		if _G.AutoDelete_FlushDeferredProspectUpdate then
			_G.AutoDelete_FlushDeferredProspectUpdate()
		end
		return
	end
	if event == "SPELLS_CHANGED" then
		-- Fires on login and any time the spellbook changes (learn a spell,
		-- respec, etc). Re-scan to keep the per-spell known caches honest.
		if _G.AutoDelete_TooltipCache then
			_G.AutoDelete_TooltipCache.recipeKnown = {}
		end
		RefreshDisenchantKnown()
		UpdateDisenchantButton()
		if _G.AutoDelete_RefreshMillKnown then
			_G.AutoDelete_RefreshMillKnown()
			if _G.AutoDelete_UpdateMillButton then _G.AutoDelete_UpdateMillButton() end
		end
		if _G.AutoDelete_RefreshProspectKnown then
			_G.AutoDelete_RefreshProspectKnown()
			if _G.AutoDelete_UpdateProspectButton then _G.AutoDelete_UpdateProspectButton() end
		end
		-- Mirror PE's learnedAffixes so affix-collection mode reflects
		-- any new affixes the player just learned. Cheap rebuild.
		if AutoDelete_RefreshOwnedAffixes then AutoDelete_RefreshOwnedAffixes() end
		return
	end
	if event == "MERCHANT_SHOW" then
		-- Set the auto-open block flag FIRST, before anything else can fire
		-- a BAG_UPDATE. The flag stays true until the post-close grace expires.
		merchantOpen = true
		RefreshCachedProfile()
		sellSessionCount = 0
		sellSessionCopper = 0
		sellDryTicks = 0
		-- Snapshot bags so the UseContainerItem hook can identify what the
		-- player just sold (the slot is empty by the time the hook fires).
		SnapshotAllBags()
		-- Sample inventory worth BEFORE selling (otherwise we'd always sample
		-- post-sell bags, underselling the average).
		SampleInventoryWorth()
		-- Master toggle gate: when AutoDelete is disabled the addon must
		-- not perform ANY action, including auto-repair or auto-sell. Bag
		-- sampling and tracking still run because they're passive.
		if cachedProfile and cachedProfile.enabled then
			-- Repair first (before selling) so durability gold is accounted
			-- for separately from sell revenue in chat output.
			TryAutoRepair()
			SellItems()
		end
		return
	end
	if event == "MERCHANT_CLOSED" then
		-- Defer the unblock so any BAG_UPDATE events fired in the immediate
		-- aftermath of closing the merchant (sell loop tail, manual sells
		-- still being processed by the server) don't trigger auto-open on
		-- the now-just-emptied slot. When the grace expires we also
		-- schedule a single catch-up button + panel refresh -- the
		-- BAG_UPDATE handler skips those during merchant-open to avoid
		-- stalling the sell loop, so the One-Key targets and Process
		-- panel can be stale by the time the user closes the window.
		AfterDelay(MERCHANT_CLOSE_GRACE, function()
			merchantOpen = false
			local catchupAt = GetTime() + 0.15
			scanner.nextButtonRefreshAt = catchupAt
			scanner.nextPanelRefreshAt  = catchupAt
		end)
		local hadSellSession = sellSessionCount > 0
		if hadSellSession then
			print("|cffff8000[AutoDelete]|r Sold " .. sellSessionCount .. " item(s) for " .. FormatMoney(sellSessionCopper))
			sellSessionCount = 0
			sellSessionCopper = 0
			sellDryTicks = 0
		end
		if cachedProfile and cachedProfile.summonScavenger and cachedProfile.summonAfterSell and hadSellSession then
			local combatOk = (not cachedProfile.summonOnlyInCombat) or (UnitAffectingCombat and UnitAffectingCombat("player"))
			if combatOk then
				_G.AutoDelete_ScavengerLastTriggerReason = "after-sell-merchant-closed"
				DelayedSummon(1.5)
			else
				_G.AutoDelete_ScavengerLastTriggerReason = "after-sell-merchant-closed-combat-blocked"
			end
		end
		-- Summon Greedy Scavenger after closing a vendor window.
		-- Gated by summonScavenger (master) AND summonAfterClose (this-moment subflag).
		-- If summonOnlyInCombat is set, the player must be in combat here and
		-- when the delayed summon fires.
		if cachedProfile and cachedProfile.summonScavenger and cachedProfile.summonAfterClose then
			local combatOk = (not cachedProfile.summonOnlyInCombat) or (UnitAffectingCombat and UnitAffectingCombat("player"))
			if combatOk then
				_G.AutoDelete_ScavengerLastTriggerReason = "after-vendor-close"
				DelayedSummon(1.5)
			else
				_G.AutoDelete_ScavengerLastTriggerReason = "after-vendor-close-combat-blocked"
			end
		end
		return
	end
	-- BAG_UPDATE / BAG_UPDATE_DELAYED
	-- Two-tier processing.
	--
	-- INLINE (synchronous, happens here on every BAG_UPDATE):
	--   * RefreshCachedProfile() and RequestScan(): drive the auto-sell
	--     loop. The scanner's OnUpdate sees scanRequested and fires the
	--     next SellItems batch on the next tick -- this is what makes
	--     selling feel continuous instead of hanging between batches.
	--   * Bag-space warning: just a free-slot count + cooldown check.
	--
	-- DO NOT call _G.AutoDelete_RefreshAffixDots() here, ever. That
	-- function exists for the Options-toggle path; it walks visible
	-- Blizzard bag frames AND calls ElvUI's B:UpdateAllBagSlots(),
	-- which is a full-bag-UI rebuild costing >100ms per call. A
	-- previous build invoked it inline on every BAG_UPDATE and it
	-- dropped the client to 1 FPS during 100-item delete bursts (one
	-- full ElvUI bag rebuild per delete). Dot rendering for live bag
	-- changes is already covered by two natural paths: Blizzard's
	-- ContainerFrame_Update hook (UpdateAffixDotForFrame is wired
	-- to it via hooksecurefunc above) and ElvUI's B:UpdateSlot hook
	-- (InstallElvUIAffixDotHook). Neither needs help from BAG_UPDATE.
	--
	-- DEFERRED (~150ms trailing-edge debounce, fires from OnUpdate):
	--   * The four Update*Button calls. Each runs a Find*Target scan that
	--     iterates bag slots until a match is found (v3.20 onward: all four
	--     Find functions short-circuit on the first eligible slot in
	--     bag-slot order; FindDisenchantTarget no longer enumerates every
	--     slot for a lowest-iLvl pick). Cold-cache tooltip scans
	--     (IsSoulbound + IsBindOnEquip per slot for DE) can still cluster
	--     into one frame during loot bursts -- with 5+ BAG_UPDATEs x 4
	--     buttons x ~60 slots x ~2 tooltip ops the early-break is the
	--     mitigation that prevents the 10-20s freezes the v3.19-era
	--     "lowest-iLvl wins" scan produced. The user pressing the
	--     bind key after looting can tolerate a 150ms button-rescan
	--     delay; they can't tolerate the freeze.
	--   * RefreshProcessPanel + the settings-panel process count: also
	--     bag-scanning when the panel is open. Same justification.
	--
	-- SKIPPED during merchant-open:
	--   * Burst-quiescence timestamps. Vendor BAG_UPDATEs are produced by
	--     our own sell loop; treating them like loot/mailbox bursts adds the
	--     1s quiescence wait between sell batches.
	--   * Button + panel deferred refresh.
	--
	--   At a vendor each sell fires a BAG_UPDATE. If we scheduled the
	--   deferred refresh on every one of those, the deferred batch of
	--   button rescans would eventually fire mid-sell and block the
	--   OnUpdate scan loop for ~1s, stalling the next SellItems batch.
	--   Result: visible "hang" between sell batches and the after-sell
	--   summon never firing because sellDryTicks never reaches 2.
	--   Instead, while merchantOpen is true, we leave the deferred
	--   timers alone. MERCHANT_CLOSED's grace callback fires a single
	--   button + panel refresh after the sell session settles, which
	--   catches up the One-Key targets for the now-emptied bags.
	--
	-- The debounce uses GetTime() on the scanner frame as state (no new
	-- file-locals; we're brushing Lua 5.1's 200-cap on the main chunk).
	-- Trailing-edge only: each non-merchant BAG_UPDATE pushes the
	-- deadline out by 150ms; the actual fire happens 150ms after the
	-- LAST BAG_UPDATE.
	local _pBag = AutoDelete_PerfBegin("BAG_UPDATE handler")
	-- v3.20 spike debug: count this frame's BAG_UPDATE / BAG_UPDATE_DELAYED
	-- separately. Cheap when spike debug is off (one global lookup).
	if _G.AutoDelete_SpikeDebug then
		local c = _G.AutoDelete_SpikeCounters
		local sess = _G.AutoDelete_SpikeSession
		if event == "BAG_UPDATE_DELAYED" then
			c.bagUpdDel    = (c.bagUpdDel or 0) + 1
			sess.bagUpdDel = (sess.bagUpdDel or 0) + 1
		else
			c.bagUpd       = (c.bagUpd or 0) + 1
			sess.bagUpd    = (sess.bagUpd or 0) + 1
		end
	end
	-- v3.20 bench harness: refresh quiet timer + transition armed->active.
	-- Cheap no-op when bench is idle.
	if _G.AutoDelete_BenchOnBagUpdate then _G.AutoDelete_BenchOnBagUpdate(GetTime()) end
	RefreshCachedProfile()
	RequestScan()
	local now = GetTime()
	-- Burst-quiescence timestamp: the scanner OnUpdate uses this to
	-- defer DeleteItems while BAG_UPDATEs are still arriving (scav AOE
	-- loot, mailbox take-all, quest chain rewards). See scanner OnUpdate
	-- below for the consumer. Stashed on the scanner frame so we don't
	-- add a file-local (Lua 5.1's 200-cap is tight on the main chunk).
	--
	-- Suppress self-updates: DeleteItems opens a 0.5s window before
	-- doing its own deletes. BAG_UPDATEs that arrive inside that
	-- window are almost certainly from our own deletes -- treating
	-- them as "external burst extending" would re-trigger a fresh
	-- 1s wait after every delete batch, adding 1s × N batches to
	-- the clearing time. Skip the timestamp update for those.
	if not merchantOpen and now >= (_G.AutoDelete_SelfBagUpdateUntil or 0) then
		scanner.lastBagUpdateAt = now
	end
	if not merchantOpen then
		scanner.nextButtonRefreshAt = now + 0.15
		scanner.nextPanelRefreshAt  = now + 0.15
	end
	-- (Bag-space chat warning removed v3.20. The Goblin Merchant appearing
	-- IS the visual "bags filling up" signal; the chat print was redundant
	-- and spammed once per cooldown window while bags hovered around the
	-- threshold. The threshold field 'bagSpaceWarnThreshold' is now used
	-- only by the Goblin summon trigger -- see GetGoblinBagThreshold.)
	AutoDelete_PerfEnd("BAG_UPDATE handler", _pBag)
end)

scanner:SetScript("OnUpdate", function(self, elapsed)
	local now = GetTime()
	-- v3.20 SPIKE DEBUG (off by default): if the previous frame ran
	-- long, snapshot the counters that accumulated during it into the
	-- ring buffer (rate-limited chat dump). Then reset for this frame's
	-- accumulators. MUST be first so the counters reflect a clean
	-- per-frame window. Cheap when off: single global hash lookup.
	if _G.AutoDelete_SpikeDebug then
		if elapsed * 1000 > _G.AutoDelete_SpikeThresholdMs then
			_G.AutoDelete_SpikeRecord(elapsed)
		end
		_G.AutoDelete_SpikeReset()
	end
	-- v3.20 bench harness: tick the auto-finalize check. Cheap no-op when
	-- bench state is nil (single global lookup + state check + return).
	if _G.AutoDelete_BenchTick then _G.AutoDelete_BenchTick(now) end
	-- Deferred affix-scan queue. Runs every frame but no-ops when the
	-- queue is empty. When non-empty, processes a small batch of cold
	-- tooltip scans (rate-limited to ~60 scans/sec) so they don't all
	-- pile into a single frame during a 100-item loot. Runs BEFORE the
	-- master-toggle gate because the affix dot is a user-facing
	-- feature independent of the master enable.
	AutoDelete_ProcessAffixScanQueue(now)
	-- Deferred button refresh: trailing-edge debounce, fires 150ms after
	-- the last BAG_UPDATE (see BAG_UPDATE handler for rationale). Runs
	-- regardless of the master toggle because the per-feature One-Key
	-- buttons can be enabled independently of the master delete/sell
	-- master. The Update*Button functions self-gate via their own
	-- profile toggles and have idempotent short-circuits when off.
	-- nil-safe: nextButtonRefreshAt starts as nil before the first
	-- BAG_UPDATE schedules it; (nil or 0) > 0 is false, so we wait.
	if (self.nextButtonRefreshAt or 0) > 0 and now >= self.nextButtonRefreshAt then
		self.nextButtonRefreshAt = 0
		local _pBR = AutoDelete_PerfBegin("deferred button refresh (all 4)")
		if UpdateDisenchantButton                then UpdateDisenchantButton() end
		if _G.AutoDelete_UpdateOpenButton        then _G.AutoDelete_UpdateOpenButton() end
		if _G.AutoDelete_UpdateMillButton        then _G.AutoDelete_UpdateMillButton() end
		if _G.AutoDelete_UpdateProspectButton    then _G.AutoDelete_UpdateProspectButton() end
		-- Keep-list override popups are deliberately NOT checked here.
		-- They only appear from the matching one-key hotkey path, otherwise
		-- ordinary bag refreshes and Process Bags previews can spam warnings.
		-- The Open slot-change detector still runs here so the chat notifier
		-- prints "[AutoDelete] Opened [link]" after the user presses Open.
		if _G.AutoDelete_CheckOpenSlotChange  then _G.AutoDelete_CheckOpenSlotChange()  end
		AutoDelete_PerfEnd("deferred button refresh (all 4)", _pBR)
	end
	-- Deferred panel refresh: same debounce. RefreshProcessPanel itself
	-- early-returns when the panel is hidden, so when the Process Bags
	-- window isn't open this is a free check on every tick.
	if (self.nextPanelRefreshAt or 0) > 0 and now >= self.nextPanelRefreshAt then
		self.nextPanelRefreshAt = 0
		local _pPR = AutoDelete_PerfBegin("deferred panel refresh")
		if _G.AutoDelete_RefreshProcessPanel then _G.AutoDelete_RefreshProcessPanel() end
		local optPanel = _G.AutoDeleteOptionsPanel
		if optPanel and optPanel.IsShown and optPanel:IsShown() and optPanel._refreshProcessCount then
			optPanel:_refreshProcessCount()
		end
		AutoDelete_PerfEnd("deferred panel refresh", _pPR)
	end
	if not cachedProfile or not cachedProfile.enabled then
		-- v3.20: master disable wipes the delete queue. Re-enabling
		-- later should NOT resume deleting items queued under prior
		-- conditions -- between disable and re-enable the user may
		-- have changed Keep list, Affix settings, or swapped profile.
		-- A fresh walk after re-enable repopulates the queue under
		-- the new rules. The counter queue-cleared-disable surfaces
		-- this in /del perf report so the user can see when it fired.
		local Q = _G.AutoDelete_DeleteQueue
		if Q and #Q.items > 0 then
			local cleared = #Q.items
			for i = cleared, 1, -1 do Q.items[i] = nil end
			AutoDelete_PerfCount("DeleteItems/queue-cleared-disable", cleared)
			if _G.AutoDelete_DebugSell then
				print(string.format(
					"|cffff8000[AutoDelete DEBUG]|r queue CLEARED on disable: %d entries dropped",
					cleared
				))
			end
		end
		return
	end
	-- v3.20: drain the throttled delete queue. One item per DELAY (90ms)
	-- interval; cheap no-op when the queue is empty or the throttle hasn't
	-- elapsed. Placed AFTER the master-enable gate so disabling the addon
	-- mid-burst stops further deletes AND clears the queue (see above) so
	-- re-enabling does a fresh walk under current settings.
	if _G.AutoDelete_DrainDeleteQueue then
		_G.AutoDelete_DrainDeleteQueue(now)
	end
	if now >= nextPeriodicAt then
		nextPeriodicAt = now + periodicInterval
		scanRequested = true
	end
	if scanRequested and now >= nextScanAt then
		-- Burst-quiescence gate. While external BAG_UPDATEs are still
		-- arriving (anything in the last BAG_QUIESCENCE_S window), defer
		-- the scan so the per-item walk runs on a settled bag. Source-
		-- agnostic: works for player loot, scav AOE loot, mailbox take-
		-- all, quest reward chain.
		--
		-- Tuned 2026-05-22 after user feedback ("first burst still bad,
		-- Scav loot bursts last ~1-2s"):
		--
		--   BAG_QUIESCENCE_S=1.0 -- match user's stated preference of
		--     "wait 1 second after items hit the bag." 300ms was too
		--     short to detect a still-ongoing burst.
		--
		--   BAG_QUIESCENCE_MAX_S=5.0 -- previous cap of 1s was firing
		--     scans MID-BURST on multi-second scav loots (the
		--     defer-cap timer kicked in before the burst finished).
		--     Raised to 5s so the cap is only an anti-starvation
		--     safeguard for the truly pathological "constant trickle"
		--     case, not a regular fire path.
		--
		-- Our own deletes don't extend the wait -- see the
		-- _G.AutoDelete_SelfBagUpdateUntil suppression in the
		-- BAG_UPDATE handler and DeleteItems prologue. Without that,
		-- the deletes' own BAG_UPDATEs would re-trigger the 1s wait
		-- after every batch of 5 (turning a 1.5s clearing into a 7s
		-- crawl).
		local BAG_QUIESCENCE_S     = 1.0   -- wait this long after last EXTERNAL BAG_UPDATE
		local BAG_QUIESCENCE_MAX_S = 5.0   -- anti-starvation cap on total defer
		local lastBagAt    = self.lastBagUpdateAt or 0
		local deferStarted = self.quiescenceFirstDeferredAt or 0
		local stillBursting = (now - lastBagAt) < BAG_QUIESCENCE_S
		local hitDeferCap   = deferStarted > 0
			and (now - deferStarted) >= BAG_QUIESCENCE_MAX_S

		if stillBursting and not hitDeferCap then
			-- Defer; mark the start of this defer window if we just
			-- entered it. Don't touch nextScanAt -- we want to check
			-- again on the very next OnUpdate frame, not push a full
			-- scanInterval forward.
			if deferStarted == 0 then
				self.quiescenceFirstDeferredAt = now
			end
		else
			self.quiescenceFirstDeferredAt = 0
			scanRequested = false
			-- Minimum 0.25 s (was 0.5 s). Paired with the lowered
			-- DELETE_BATCH_SIZE (30 -> 5) so loot-burst deletes spread
			-- across multiple short scans instead of one big chug. Net
			-- throughput stays roughly the same (~20 items/sec) but no
			-- single scan tick exceeds one frame.
			local interval = (cachedProfile.scanInterval and cachedProfile.scanInterval >= 0.25) and cachedProfile.scanInterval or 0.25
			-- Vendor selling should stay responsive even when the normal bag
			-- scan setting is slower. The sell batch is already capped, so this
			-- only tightens the gap between merchant sell passes.
			if MerchantFrame and MerchantFrame:IsShown() and interval > 0.35 then
				interval = 0.35
			end
			nextScanAt = now + interval
			DeleteItems()
			if MerchantFrame and MerchantFrame:IsShown() then SellItems(true) end
		end
	end
end)

-- ============================================================================
-- Companion Watcher
-- ============================================================================
-- Three behaviors layered on the Summon Scavenger feature:
--   (1) Mount-aware: dismiss the active companion when the player mounts. On
--       dismount, re-summon the scavenger only if summonScavenger is still
--       enabled AND at least one scav sub-toggle (afterSell/afterClose) is on.
--   (2) Stuck detection (summoned-flag only, 3.3.5 has no distance API):
--       if the last pet we summoned stops being marked 'summoned' unexpectedly
--       (e.g. died, despawned), re-summon it. Applies to BOTH Scavenger and
--       Goblin Merchant while they're the active tracked companion.
--   (3) Bag-full auto-summon: when bags hit 0 free slots AND the feature
--       toggle is on, summon Goblin Merchant. Fires once per fill edge; only
--       re-arms after the user frees a slot or the watcher is reset.
--
-- All three features short-circuit if the Summon Scavenger master toggle is
-- off, so they never run unexpectedly for users who opt out.

-- Which companion we're currently tracking for stuck detection.
-- Values: "scavenger" | "merchant" | nil (none)
local activeTracked       = nil

-- Mount state we last saw, so we detect edges (mounting / dismounting).
local lastMountState      = nil

-- If the player was on a companion when they mounted, we store which one here
-- so we know what to re-summon on dismount.
local dismissedDueToMount = nil

-- True when bags are nearly full (free slots <= BAGS_NEAR_FULL_THRESHOLD).
-- Flips back to false once free slots rise above the threshold, which re-arms
-- the trigger.
local bagsFullArmed       = true   -- true = next 'near full' will fire
local bagsFullSince       = nil    -- GetTime() when bags first became near-full; reset when a slot frees
-- v3.20 queue-aware Goblin defer: snapshot of #_G.AutoDelete_DeleteQueue.items
-- at the moment bagsFullSince started accumulating. While the queue keeps
-- SHRINKING from this snapshot the drain is winning and we re-arm the timer
-- (no Goblin yet). If the queue plateaus or grows (loot rate >= drain rate),
-- the timer accumulates normally and Goblin fires after BAGS_FULL_DELAY.
-- Lives on _G (not a file-local) because the main chunk is already at
-- Lua 5.1's 200-local cap; adding a file-local here triggers the
-- "main function has more than 200 local variables" compile error.
_G.AutoDelete_BagsFullQueueAtStart = _G.AutoDelete_BagsFullQueueAtStart or nil

function _G.AutoDelete_RearmGoblinAfterBackoff(reason)
	bagsFullArmed = true
	bagsFullSince = nil
	_G.AutoDelete_BagsFullQueueAtStart = nil
	_G.AutoDelete_GoblinLastDeferReason = "rearmed-after-" .. tostring(reason or "failure")
end

-- Bag-full auto-summon threshold fallback. The Goblin Merchant fires when
-- free slots drop to or below this value. Default 3 so the merchant arrives
-- before bags are completely full, leaving room for additional drops while
-- vendoring. The actual threshold is now user-configurable via the Tools
-- tab (profile.goblinMerchantBagThreshold); this constant only acts as a
-- safety fallback when the profile field is missing or non-numeric.
local BAGS_NEAR_FULL_THRESHOLD = 3

-- Per-profile read of the bag-space threshold. One value drives both the
-- chat warning AND the Goblin Merchant summon trigger. Returns the user-
-- configured value if set, otherwise BAGS_NEAR_FULL_THRESHOLD.
local function GetGoblinBagThreshold(p)
	return tonumber(p and p.bagSpaceWarnThreshold) or BAGS_NEAR_FULL_THRESHOLD
end

-- (bagSpaceLastWarnAt is declared near the top of the file as a
-- forward-accessible local so the BAG_UPDATE handler captures it as an
-- upvalue. Do NOT re-declare here with `local`; that would shadow the
-- top-of-file local and break the cooldown-gated chat warning.)

-- Bag-full auto-summon debounce window. Bags must stay at or below the
-- threshold continuously for this many seconds before the Goblin Merchant is
-- summoned. Prevents transient fills (loot a stack that auto-merges with an
-- existing stack a moment later) from triggering a stray summon.
--
-- Tuned three times:
--   v3.17: 3.0 -> 1.5 (faster merchant pop when bags genuinely stuck full)
--   v3.20: 1.5 -> 2.0 (give the delete scanner time to clear loot bursts
--          before the merchant fires)
--   v3.20: 2.0 -> 3.5 (queue-throttled deletes changed throughput from
--          ~16 items/sec to ~9 items/sec, so the 2.0 s window only
--          absorbed ~18 items. Current drain is ~11 items/sec, and 3.5 s still
--          comfortably absorbs a typical burst before the anti-starvation cap.
--          PLUS the bag-full check now defers when the delete
--          queue is actively shrinking -- see _G.AutoDelete_BagsFullQueueAtStart logic
--          in the auto-summon block below. The shrink-defer is the
--          primary mechanism; this absolute cap is the anti-starvation
--          backstop for when loot rate genuinely exceeds drain rate.)
local BAGS_FULL_DELAY = 3.5

-- ============================================================================
-- User-dismiss vs leash classification (timing-based)
-- ============================================================================
-- Problem: when our pet's `summoned` flag flips to false, we can't tell from
-- the API whether the user right-clicked the portrait to dismiss it, or
-- whether it fell behind / despawned / died. Naively re-summoning every time
-- ignores user intent (they dismissed for a reason).
--
-- Approach: timing. When WE summon the pet, record GetTime() in
-- lastSummonAt. If the pet flips to "not summoned" within USER_DISMISS_WINDOW
-- of that summon, classify as "user dismissed" - they clicked it off
-- intentionally, fast and deliberate. Suppress restore for USER_DISMISS_GRACE.
-- A real range-leash takes seconds to minutes of travel before the server
-- despawns the pet, so the timing distinguishes cleanly.
--
-- We deliberately use summon/despawn timing rather than speed-at-transition;
-- stationary casts can otherwise be misclassified as user dismisses.
local lastSummonAt        = 0
local userDismissUntil    = 0
local USER_DISMISS_WINDOW = 5.0    -- seconds after our summon during which "gone" = user dismissed
local USER_DISMISS_GRACE  = 30.0   -- seconds to suppress restore after a user dismiss

-- COMPANION_UPDATE event debounce. The event can fire multiple times in quick
-- succession during a state transition; we only want to process the latest.
local lastCompanionUpdate = 0
local COMPANION_DEBOUNCE  = 0.5

-- ============================================================================
-- Loot-event-based stuck detection
-- ============================================================================
-- The CRITTER `summoned` flag is unreliable on PE for "pet fell behind" -
-- the API claims summoned even when the pet is geographically lost. And
-- 3.3.5 has no UnitPosition API to measure player distance from a summon
-- point. So we detect the actual symptom rather than any proxy for it:
--
--   "The scavenger has stopped doing its job."
--
-- The scavenger's job is to pick up gray items and money near the player
-- after kills. Every successful pickup, the scav says one of its monster
-- chat lines (the spam suppressed by hideGreedySpam). We track the latest
-- timestamp of any scav monster chat line. We also track when the player
-- last looted a corpse via LOOT_CLOSED.
--
-- Stuck-detection rule: if the player has looted at least
-- LOOT_STUCK_PLAYER_MIN corpses within LOOT_STUCK_WINDOW seconds AND the
-- scavenger hasn't said anything in the same window, the scav is
-- geographically lost. Re-summon.
--
-- This detects the actual symptom rather than guessing via position or
-- speed. Bonus: it costs almost nothing - we already filter every scav
-- chat line, so the timestamp update is one assignment per existing event.
local lastScavLootChatAt    = 0
-- Ring buffer of player loot timestamps (GetTime() values). Automatically
-- pruned in OnUpdate to entries within LOOT_STUCK_WINDOW (60s). Cleared on
-- scavenger re-summon. Maximum realistic size: ~10-15 entries (looting every
-- 4-6s for a full minute). No manual bounding needed.
local LOOT_STUCK_WINDOW     = 60   -- seconds: window over which we evaluate
local LOOT_STUCK_PLAYER_MIN = 2    -- min player loots in the window before we judge
local recentPlayerLootTimes = {}

-- Simple periodic ticker: checks mount state changes and companion summoned
-- flag every ~1s. Not tied to scanInterval because the scanner is gated on
-- cachedProfile.enabled; this watcher must also run when Master is off but
-- scavenger features are used (rare, but correct).
local companionWatcher = CreateFrame("Frame")
local watchAccum = 0
local WATCH_INTERVAL = 1.0

local function IsPlayerMountedOrFlying()
	if IsFlying and IsFlying() then return true end
	if IsMounted and IsMounted() then return true end
	return false
end

-- Assigned (not `local function`) because the name was forward-declared
-- above DeleteItems so the BAG_UPDATE handler can capture it as an upvalue.
ComputeTotalFreeSlots = function()
	local free = 0
	for bag = 0, 4 do
		local f = GetContainerNumFreeSlots and GetContainerNumFreeSlots(bag) or 0
		if f then free = free + f end
	end
	return free
end

local function AnyScavSubToggleOn(p)
	if not p then return false end
	return (p.summonAfterSell or p.summonAfterClose) and true or false
end

function _G.AutoDelete_IsAnyOtherCompanionUp(currentName)
	local n = GetNumCompanions("CRITTER")
	for i = 1, n do
		local _, cName, _, _, summoned = GetCompanionInfo("CRITTER", i)
		if (summoned == 1 or summoned == true) and cName then
			local lower = string.lower(cName)
			if not string.find(lower, currentName) then
				return true
			end
		end
	end
	return false
end

function _G.AutoDelete_HandleTrackedCompanionGone(p, combatOk, now, allowSwapSuppression)
	if activeTracked == "scavenger" then
		local _, isUp = FindCompanionById(SCAVENGER_CREATURE_ID, "greedy scavenger")
		if isUp then return end
		if allowSwapSuppression and _G.AutoDelete_IsAnyOtherCompanionUp("greedy scavenger") then
			activeTracked = nil
		elseif (now - lastSummonAt) < USER_DISMISS_WINDOW then
			userDismissUntil = now + USER_DISMISS_GRACE
			activeTracked = nil
		elseif AnyScavSubToggleOn(p) and combatOk then
			DelayedSummon(0.3)
		else
			activeTracked = nil
		end
		return
	end

	if activeTracked == "merchant" then
		local _, isUp = FindCompanionById(MERCHANT_CREATURE_ID, "goblin merchant")
		if isUp then return end
		if allowSwapSuppression and _G.AutoDelete_IsAnyOtherCompanionUp("goblin merchant") then
			activeTracked = nil
		elseif (now - lastSummonAt) < USER_DISMISS_WINDOW then
			userDismissUntil = now + USER_DISMISS_GRACE
			activeTracked = nil
		elseif p.summonMerchantWhenBagsFull and ComputeTotalFreeSlots() <= GetGoblinBagThreshold(p) and combatOk then
			if _G.AutoDelete_GoblinAutoBackoffActive and _G.AutoDelete_GoblinAutoBackoffActive() then
				_G.AutoDelete_GoblinLastDeferReason = "summon-backoff"
				activeTracked = nil
				bagsFullArmed = true
			else
				SummonGoblinMerchant()
				bagsFullArmed = false
			end
			bagsFullSince = nil
			_G.AutoDelete_BagsFullQueueAtStart = nil
		else
			activeTracked = nil
			if p.summonMerchantWhenBagsFull and ComputeTotalFreeSlots() <= GetGoblinBagThreshold(p) then
				bagsFullArmed = true
				bagsFullSince = nil
				_G.AutoDelete_BagsFullQueueAtStart = nil
			end
		end
	end
end

companionWatcher:SetScript("OnUpdate", function(_, elapsed)
	watchAccum = watchAccum + elapsed
	if watchAccum < WATCH_INTERVAL then return end
	watchAccum = 0

	local p = cachedProfile
	if not p then return end

	-- Master toggle gate: AutoDelete must not summon, dismiss, or re-summon
	-- pets when disabled. The companion-tracking features all require both
	-- the master toggle AND the per-feature toggle to be on.
	if not p.enabled then return end

	-- Master gate: all three features require summonScavenger enabled.
	if not p.summonScavenger then
		return
	end

	-- Combat gate. When summonOnlyInCombat is enabled, ALL automatic summon
	-- paths (mount/dismount restore, stuck-detection re-summon, bag-full
	-- merchant trigger) only fire while the player is in combat. Manual
	-- /del commands and after-sell/after-close summons (handled in their
	-- own code paths) check this flag separately.
	local combatOk = (not p.summonOnlyInCombat) or (UnitAffectingCombat and UnitAffectingCombat("player"))

	-- (0) Loot-based stuck detection (only for scavenger; merchant doesn't loot).
	-- We don't run this every tick - only when there's something to evaluate.
	-- The check is cheap: walk the ring buffer to count recent loots, compare
	-- to the scav's last chat timestamp.
	if activeTracked == "scavenger" and combatOk and not IsPlayerMountedOrFlying() then
		local nowLoot = GetTime()

		-- Prune in place to avoid per-tick table churn while farming.
		local writeIdx = 1
		for readIdx = 1, #recentPlayerLootTimes do
			local t = recentPlayerLootTimes[readIdx]
			if (nowLoot - t) <= LOOT_STUCK_WINDOW then
				recentPlayerLootTimes[writeIdx] = t
				writeIdx = writeIdx + 1
			end
		end
		for i = #recentPlayerLootTimes, writeIdx, -1 do
			recentPlayerLootTimes[i] = nil
		end

		-- If we've had enough player loots in the window AND the scav
		-- hasn't said anything since the OLDEST of those loots, the scav is
		-- almost certainly geographically lost.
		if #recentPlayerLootTimes >= LOOT_STUCK_PLAYER_MIN then
			local oldestLoot = recentPlayerLootTimes[1]
			if lastScavLootChatAt < oldestLoot then
				-- Re-summon. The summon helper handles state updates.
				if DismissCompanion then DismissCompanion("CRITTER") end
				AfterDelay(0.4, function() SummonGreedyScavenger(true) end)
				-- Clear the ring so we don't immediately re-fire.
				recentPlayerLootTimes = {}
			end
		end
	end

	-- (1) Mount-aware dismiss / re-summon.
	local nowMounted = IsPlayerMountedOrFlying()
	if lastMountState == nil then lastMountState = nowMounted end
	if nowMounted ~= lastMountState then
		lastMountState = nowMounted
		if nowMounted then
			-- Mounting. Dismiss whichever pet we were tracking, and remember
			-- so dismount can restore it (scav only - merchant gets summoned
			-- via bag-full trigger, not mount flow).
			local scavIdx, scavUp = FindCompanionByName("greedy scavenger")
			local merchIdx, merchUp = FindCompanionByName("goblin merchant")
			if scavUp or merchUp then
				if DismissCompanion then DismissCompanion("CRITTER") end
				dismissedDueToMount = scavUp and "scavenger" or nil
				-- If only merchant was up, we don't auto-revive it on dismount.
			end
		else
			-- Dismounting. Re-summon scavenger if we dismissed it AND the user
			-- still has the master toggle on AND a sub-toggle that would use
			-- it AND the combat gate (if enabled) is satisfied.
			if dismissedDueToMount == "scavenger" and AnyScavSubToggleOn(p) and combatOk then
				DelayedSummon(1.5)
				activeTracked = "scavenger"
			end
			dismissedDueToMount = nil
		end
	end

	-- Don't run stuck-detection or bag-full while mounted. WoW dismisses pets
	-- on mount natively and we just dismissed ours above.
	if nowMounted then return end

	-- Respect user-dismiss grace window. If the reactive event handler (or
	-- the previous polling tick) classified a recent transition as a user
	-- dismiss, skip the stuck-detection block so we don't re-summon over
	-- their intent.
	local pollNow = GetTime()
	local inUserDismissGrace = pollNow < userDismissUntil

	if activeTracked and not inUserDismissGrace then
		-- Polling path guards user intent: if the user swapped to another pet,
		-- stop tracking and do not force a re-summon.
		_G.AutoDelete_HandleTrackedCompanionGone(p, combatOk, pollNow, true)
	end

	-- (3) Bag-full auto-summon. See BAGS_FULL_DELAY above for debounce.
	--
	-- The 1.5s debounce IS the "give AutoDelete a chance to clear"
	-- gate: if AutoDelete frees slots in time, bags rise above
	-- threshold and the "above threshold" branch below resets the
	-- timer; no summon fires. If AutoDelete CAN'T keep up (e.g. scav
	-- is looting faster than the delete scan can clear, so bags
	-- oscillate around or stay below threshold for 1.5s straight),
	-- the timer accumulates and the summon fires -- which is correct
	-- (more loot coming in than auto-delete can handle, user needs
	-- the Goblin).
	--
	-- An earlier build added an AutoDelete_HasPendingDeleteItems gate
	-- here that reset bagsFullSince whenever any delete-eligible item
	-- was in bags. That broke the scav-looting-faster-than-deletes
	-- case: with pending deletes always present during a sustained
	-- loot burst, the timer never accumulated and Goblin never
	-- summoned. Removed.
	--
-- v3.20 queue-aware re-add: with queue-throttled deletes (current drain is
-- ~11 items/sec vs old ~16/sec) the raw timer-based debounce could
	-- fire Goblin BEFORE the drain finished a moderate burst. Fix is
	-- a SHRINKING-QUEUE gate (not a "pending-exists" gate, which had
	-- the old bug): snapshot queue length when bagsFullSince starts;
	-- if the queue length is currently SMALLER than the snapshot, the
	-- drain is winning and we re-arm the timer with the new (smaller)
	-- snapshot. If the queue plateaus or grows (loot rate >= drain
	-- rate), the timer accumulates normally and Goblin fires after
	-- BAGS_FULL_DELAY. Edge cases:
	--   - Queue empty AND free still under threshold: snapshot starts
	--     at 0, current is 0, no shrink possible, timer accumulates,
	--     Goblin fires. Correct (nothing left to auto-delete).
	--   - Loot rate > drain rate: queue grows past snapshot, no
	--     shrink, timer accumulates. Goblin fires. Correct.
	--   - Drain catches up before timer hits cap: queue shrinks each
	--     tick, timer keeps resetting, eventually free rises past
	--     threshold and the else-branch fires the FULL reset (re-arm).
	if p.summonMerchantWhenBagsFull then
		local free = ComputeTotalFreeSlots()
		local qLen = #_G.AutoDelete_DeleteQueue.items
		local threshold = GetGoblinBagThreshold(p)
		local now = GetTime()

		if free > threshold then
			-- Bags above threshold: full reset. Drain caught up OR loot
			-- stopped on its own.
			bagsFullSince = nil
			_G.AutoDelete_BagsFullQueueAtStart = nil
			_G.AutoDelete_BagsBelowAt = 0
			bagsFullArmed = true
			if _G.AutoDelete_PendingScavengerAfterBags and AnyScavSubToggleOn(p) and combatOk then
				_G.AutoDelete_PendingScavengerAfterBags = false
				_G.AutoDelete_ScavengerLastTriggerReason = "bags-no-longer-full"
				DelayedSummon(1.0)
			end
		elseif (not bagsFullArmed)
			and combatOk
			and not (_G.AutoDelete_GoblinConfirmPending or false)
			and not (_G.AutoDelete_GoblinAutoBackoffActive and _G.AutoDelete_GoblinAutoBackoffActive()) then
			-- If a prior Merchant summon attempt failed or was dropped while
			-- bags stayed full, the normal above-threshold reset never happens.
			-- Re-arm once backoff ends so full bags can trigger Merchant again.
			bagsFullArmed = true
			bagsFullSince = nil
			_G.AutoDelete_BagsFullQueueAtStart = nil
			_G.AutoDelete_GoblinLastDeferReason = "rearmed-still-full"
		elseif bagsFullArmed and combatOk then
			-- Bags below threshold. Record WHEN they first dropped (used
			-- to compare against LastDeleteWalkAt to detect "has pipeline
			-- scanned since bags filled?").
			if (_G.AutoDelete_BagsBelowAt or 0) == 0 then
				_G.AutoDelete_BagsBelowAt = now
			end
			local bagsBelowAt = _G.AutoDelete_BagsBelowAt
			local lastDrain   = _G.AutoDelete_LastDrainPopAt or 0
			local lastEnq     = _G.AutoDelete_LastEnqueueAt or 0
			local lastWalk    = _G.AutoDelete_LastDeleteWalkAt or 0
			local lastWalkEnq = _G.AutoDelete_LastDeleteWalkEnqueued or 0
			local recency     = _G.AutoDelete_GoblinRecencyS or 2.0

			-- "Pipeline is busy" = anything in queue, OR drain/enqueue
			-- happened within the last `recency` seconds. Captures the
			-- case where queue just emptied but more loot is coming.
			local pipelineBusy = (qLen > 0)
				or (lastDrain > 0 and (now - lastDrain) < recency)
				or (lastEnq   > 0 and (now - lastEnq)   < recency)
			-- "Walk happened since bags went below" = AutoDelete has had
			-- at least one chance to scan since this near-full started.
			local walkSinceBelow = (lastWalk >= bagsBelowAt)
			-- "Last walk found nothing" = scanned bags, enqueued zero
			-- candidates. Goblin must be allowed to fire here, otherwise
			-- it would wait forever on full bags of non-deletable items.
			local foundNothingLastWalk = walkSinceBelow and lastWalkEnq == 0

			if pipelineBusy then
				-- State 2: pipeline actively working. Use queue-shrink
				-- timer (preserved from prior implementation).
				if not bagsFullSince then
					bagsFullSince = now
					_G.AutoDelete_BagsFullQueueAtStart = qLen
				elseif _G.AutoDelete_BagsFullQueueAtStart
					and qLen > 0
					and qLen < _G.AutoDelete_BagsFullQueueAtStart then
					-- Queue shrunk: drain is winning, reset + re-snapshot.
					bagsFullSince = now
					_G.AutoDelete_BagsFullQueueAtStart = qLen
					_G.AutoDelete_GoblinLastDeferReason = "pipeline-busy-shrinking"
				elseif (now - bagsFullSince) >= BAGS_FULL_DELAY then
					-- Queue stopped shrinking for the full delay window
					-- = loot rate > drain rate. Fire.
					if _G.AutoDelete_GoblinAutoBackoffActive and _G.AutoDelete_GoblinAutoBackoffActive() then
						_G.AutoDelete_GoblinLastDeferReason = "summon-backoff"
					else
						bagsFullArmed = false
						bagsFullSince = nil
						_G.AutoDelete_BagsFullQueueAtStart = nil
						_G.AutoDelete_BagsBelowAt = 0
						_G.AutoDelete_GoblinLastFireAt = now
						_G.AutoDelete_GoblinLastFireReason = "queue-stopped-shrinking"
						SummonGoblinMerchant()
					end
				else
					_G.AutoDelete_GoblinLastDeferReason = "pipeline-busy-waiting"
				end
			elseif not walkSinceBelow then
				-- State 1: pipeline has NOT scanned yet since bags went
				-- below threshold (sustained loot storm preventing
				-- DeleteItems from running). Defer. DO NOT start timer.
				bagsFullSince = nil
				_G.AutoDelete_BagsFullQueueAtStart = nil
				_G.AutoDelete_GoblinLastDeferReason = "no-walk-yet"
			elseif foundNothingLastWalk then
				-- State 3: pipeline scanned, found NO deletable items.
				-- Start timer immediately; Goblin is the right answer.
				if not bagsFullSince then
					bagsFullSince = now
					_G.AutoDelete_BagsFullQueueAtStart = qLen
				elseif (now - bagsFullSince) >= BAGS_FULL_DELAY then
					if _G.AutoDelete_GoblinAutoBackoffActive and _G.AutoDelete_GoblinAutoBackoffActive() then
						_G.AutoDelete_GoblinLastDeferReason = "summon-backoff"
					else
						bagsFullArmed = false
						bagsFullSince = nil
						_G.AutoDelete_BagsFullQueueAtStart = nil
						_G.AutoDelete_BagsBelowAt = 0
						_G.AutoDelete_GoblinLastFireAt = now
						_G.AutoDelete_GoblinLastFireReason = "no-deletable-candidates"
						SummonGoblinMerchant()
					end
				else
					_G.AutoDelete_GoblinLastDeferReason = "found-nothing-waiting"
				end
			else
				-- Transitional state: walked, enqueued items, but the
				-- recency windows for drain/enqueue have elapsed AND
				-- queue is empty (everything drained). Bags are still
				-- below threshold so more loot must have arrived after
				-- our last activity but didn't trigger a fresh walk yet.
				-- Treat as "no walk yet for the NEW state": defer.
				bagsFullSince = nil
				_G.AutoDelete_BagsFullQueueAtStart = nil
				_G.AutoDelete_GoblinLastDeferReason = "transitional-no-recent-activity"
			end
		end
	end
end)

-- Exposed so SummonGreedyScavenger / SummonGoblinMerchant can mark the
-- active tracked pet without tight coupling. Set via the helpers below.
function _G.AutoDelete_SetActiveTrackedPet(which)
	activeTracked = which
end

-- Read-only accessor used by /del pos debug command.
function _G.AutoDelete_GetActiveTrackedPet() return activeTracked end

-- Exposed so the Summon helpers can record the moment of summon. Used by
-- the user-dismiss-vs-leash classifier: if the pet goes "not summoned"
-- within USER_DISMISS_WINDOW of this timestamp, treat as user dismiss.
function _G.AutoDelete_RecordSummonAt(t)
	lastSummonAt = t or GetTime()
end

-- Exposed so the GreedyChatFilter can record the scavenger's "alive and
-- looting" timestamp without forward-referencing the local variable.
function _G.AutoDelete_RecordScavLootChat(t)
	lastScavLootChatAt = t or GetTime()
end

function _G.AutoDelete_GetScavLootChatAt() return lastScavLootChatAt end

-- ============================================================================
-- Reactive companion event handler
-- ============================================================================
-- COMPANION_UPDATE fires when companion state changes (summon, dismiss, list
-- update). It's faster than the 1s polling tick - typically reacts within a
-- single frame. The polling tick is kept as a safety net in case
-- COMPANION_UPDATE doesn't fire reliably for range-based despawns on this
-- server build.
--
-- Logic:
--   1. Debounce against event storms (multiple fires within COMPANION_DEBOUNCE)
--   2. If we have an active tracked pet AND it's now "not summoned":
--      a. Within USER_DISMISS_WINDOW of our last summon -> user dismissed,
--         set userDismissUntil to suppress restore for USER_DISMISS_GRACE
--      b. Outside that window -> leash/despawn/death, re-summon (subject to
--         combat gate, master toggle, and the same checks as the polling tick)
local companionEventFrame = CreateFrame("Frame")
companionEventFrame:RegisterEvent("COMPANION_UPDATE")
companionEventFrame:RegisterEvent("LOOT_CLOSED")
companionEventFrame:SetScript("OnEvent", function(_, event)
	-- LOOT_CLOSED: player finished looting a corpse. Push the timestamp so
	-- the loot-based stuck detector can correlate against scav chat lines.
	if event == "LOOT_CLOSED" then
		table.insert(recentPlayerLootTimes, GetTime())
		return
	end

	if event ~= "COMPANION_UPDATE" then return end

	-- Debounce: COMPANION_UPDATE can fire several times for a single state
	-- change. Process at most once per COMPANION_DEBOUNCE seconds.
	local now = GetTime()
	if (now - lastCompanionUpdate) < COMPANION_DEBOUNCE then return end
	lastCompanionUpdate = now

	local p = cachedProfile
	if not p or not p.enabled or not p.summonScavenger then return end

	-- AUTO-ATTACH: if the user just summoned a scav or merchant via the
	-- portrait/macro and we have no active tracked pet, attach. Without this
	-- the entire stuck-detection pipeline silently does nothing for
	-- user-initiated summons.
	if not activeTracked then
		local _, scavUp = FindCompanionById(SCAVENGER_CREATURE_ID, "greedy scavenger")
		local _, merchUp = FindCompanionById(MERCHANT_CREATURE_ID, "goblin merchant")
		if scavUp then
			activeTracked = "scavenger"
			lastSummonAt = now   -- treat as if we just summoned
		elseif merchUp then
			activeTracked = "merchant"
			lastSummonAt = now
		end
	end

	if not activeTracked then return end

	-- Combat gate (when summonOnlyInCombat is on, all auto-summons require
	-- the player to be in combat).
	local combatOk = (not p.summonOnlyInCombat) or (UnitAffectingCombat and UnitAffectingCombat("player"))

	-- Suppress while mounted - WoW handles companion despawn natively.
	if IsPlayerMountedOrFlying() then return end

	-- Suppress if we recently classified a user dismiss.
	if now < userDismissUntil then return end

	-- Event path favors fast response and shares the same classification and
	-- re-summon logic as polling, without swap-suppression checks.
	_G.AutoDelete_HandleTrackedCompanionGone(p, combatOk, now, false)
end)

-- ============================================================================
-- Slash Commands
-- ============================================================================
-- /del               -> toggle the options panel
-- /del clean         -> dedupe and resolve item-list conflicts (see ResolveEntryKey
--                       below for the matching rules)
-- /del sell          -> force a sell pass at the current vendor (NOT gated
--                       by master Enable; manual override)
-- /del setup         -> reopen the welcome popup (clears welcomeDismissed)
-- /autodelete        -> alias for /del

-- ----------------------------------------------------------------------------
-- /del clean - remove duplicate entries and item-list conflicts
-- ============================================================================
-- Rules:
--   * Within a single list: keep first occurrence, remove subsequent duplicates
--   * Keep wins over Delete, Sell, KeepOne, and KeepStack
--   * Across Delete + Sell + KeepOne + KeepStack: if an item appears on more
--     than one, remove it
--     (reported so the user can re-add to their preferred list)
--
-- Identity resolution: entries are either "item:N" or a plain name.
--   * "item:N" → resolved via GetItemInfo to normalized name key
--   * plain name → lower-cased and trimmed as the key
--   * Unresolvable "item:N" falls back to "id:N" so it still matches itself

local function ResolveEntryKey(rawLine)
	local entry = Trim(rawLine or "")
	if entry == "" then return nil, nil, nil end
	-- Strip comments
	entry = string.gsub(entry, "%s*#.*$", "")
	entry = Trim(entry)
	if entry == "" then return nil, nil, nil end

	local id = tonumber(string.match(entry, "^item:(%d+)"))
	if id then
		local name = GetItemInfo("item:" .. id)
		if name and name ~= "" then
			return "name:" .. string.lower(name), name, Trim(rawLine or "")
		end
		return "id:" .. id, "item:" .. id, Trim(rawLine or "")
	end
	return "name:" .. string.lower(entry), entry, Trim(rawLine or "")
end

function _G.AutoDelete_BuildListAuditReport(prefixLines)
	local db = GetDB()
	local profile, profileKey, charKey = GetActiveProfile(db)
	local listDefs = {
		{ field = "listText", label = "Delete" },
		{ field = "sellListText", label = "Sell" },
		{ field = "whitelistText", label = "Keep" },
		{ field = "keepOneText", label = "KeepOne" },
		{ field = "keepStackText", label = "KeepStack" },
	}
	local entries, byKey, byName = {}, {}, {}
	local totals = { Delete = 0, Sell = 0, Keep = 0, KeepOne = 0, KeepStack = 0 }
	local safeLinkOrNumberFixes, duplicateFixes, nameOnlyCount, uncachedIdCount = 0, 0, 0, 0

	local function AddToBucket(t, key, entry)
		if not key or key == "" then return end
		local bucket = t[key]
		if not bucket then
			bucket = { entries = {}, lists = {}, ids = {} }
			t[key] = bucket
		end
		table.insert(bucket.entries, entry)
		bucket.lists[entry.listLabel] = true
		if entry.id then bucket.ids[entry.id] = true end
	end

	local function ParseLine(rawLine, listLabel)
		local original = Trim(rawLine or "")
		if original == "" then return nil end
		local hasComment = string.find(original, "#", 1, true) ~= nil
		local stripped = string.gsub(original, "%s*#.*$", "")
		stripped = Trim(stripped)
		if stripped == "" then return nil end

		local linkId = tonumber(string.match(stripped, "Hitem:(%d+)"))
		local itemId = linkId or tonumber(string.match(stripped, "^item:(%d+)")) or tonumber(string.match(stripped, "^(%d+)$"))
		if itemId then
			local name = GetItemInfo("item:" .. itemId)
			if not name then
				GetItemInfo("item:" .. itemId)
				uncachedIdCount = uncachedIdCount + 1
			end
			local entry = {
				listLabel = listLabel,
				raw = original,
				kind = "id",
				id = itemId,
				name = name,
				display = name or ("item:" .. itemId),
				key = "id:" .. itemId,
				nameKey = name and Normalize(name) or nil,
				canCanonicalize = (not hasComment) and ((linkId ~= nil) or (string.match(stripped, "^%d+$") ~= nil)),
			}
			if entry.canCanonicalize then safeLinkOrNumberFixes = safeLinkOrNumberFixes + 1 end
			return entry
		end

		nameOnlyCount = nameOnlyCount + 1
		return {
			listLabel = listLabel,
			raw = original,
			kind = "name",
			display = stripped,
			key = "name:" .. Normalize(stripped),
			nameKey = Normalize(stripped),
		}
	end

	for _, def in ipairs(listDefs) do
		local seenInList = {}
		for line in string.gmatch(profile[def.field] or "", "[^\r\n]+") do
			local entry = ParseLine(line, def.label)
			if entry then
				totals[def.label] = totals[def.label] + 1
				table.insert(entries, entry)
				if seenInList[entry.key] then duplicateFixes = duplicateFixes + 1 end
				seenInList[entry.key] = true
				AddToBucket(byKey, entry.key, entry)
				if entry.nameKey then AddToBucket(byName, entry.nameKey, entry) end
			end
		end
	end

	local function CountLists(bucket)
		local n = 0
		for _ in pairs(bucket.lists or {}) do n = n + 1 end
		return n
	end

	local function CountIds(bucket)
		local n = 0
		for _ in pairs(bucket.ids or {}) do n = n + 1 end
		return n
	end

	local exactConflicts, sameNameMultiId, nameMixWarnings = {}, {}, {}
	for key, bucket in pairs(byKey) do
		if CountLists(bucket) > 1 then table.insert(exactConflicts, { key = key, bucket = bucket }) end
	end
	for nameKey, bucket in pairs(byName) do
		local ids = CountIds(bucket)
		local hasNameOnly, hasId = false, false
		for _, entry in ipairs(bucket.entries) do
			if entry.kind == "name" then hasNameOnly = true else hasId = true end
		end
		if ids > 1 then table.insert(sameNameMultiId, { key = nameKey, bucket = bucket }) end
		if hasNameOnly and hasId then table.insert(nameMixWarnings, { key = nameKey, bucket = bucket }) end
	end

	table.sort(exactConflicts, function(a, b) return a.key < b.key end)
	table.sort(sameNameMultiId, function(a, b) return a.key < b.key end)
	table.sort(nameMixWarnings, function(a, b) return a.key < b.key end)

	local function EntryLabel(entry)
		local idText = entry.id and ("item:" .. entry.id) or "name-only"
		return string.format("%s: %s (%s)", entry.listLabel, entry.display or "Unknown", idText)
	end

	local function AddEntries(lines, bucket, limit)
		local count = 0
		for _, entry in ipairs(bucket.entries or {}) do
			count = count + 1
			if count <= limit then table.insert(lines, "  " .. EntryLabel(entry)) end
		end
		if count > limit then table.insert(lines, "  ... " .. tostring(count - limit) .. " more") end
	end

	local lines = {}
	if prefixLines then
		for _, line in ipairs(prefixLines) do table.insert(lines, line) end
		table.insert(lines, "")
	end
	table.insert(lines, "AutoDelete list audit")
	table.insert(lines, "Character: " .. tostring(charKey))
	table.insert(lines, "Profile: " .. tostring(profileKey))
	table.insert(lines, "")
	table.insert(lines, "Counts:")
	table.insert(lines, "  Delete: " .. tostring(totals.Delete))
	table.insert(lines, "  Sell: " .. tostring(totals.Sell))
	table.insert(lines, "  Keep: " .. tostring(totals.Keep))
	table.insert(lines, "  KeepOne: " .. tostring(totals.KeepOne))
	table.insert(lines, "  KeepStack: " .. tostring(totals.KeepStack))
	table.insert(lines, "")
	table.insert(lines, "Safe fixes available:")
	table.insert(lines, "  Duplicate lines in the same list: " .. tostring(duplicateFixes))
	table.insert(lines, "  Full item links or plain numeric IDs to normalize: " .. tostring(safeLinkOrNumberFixes))
	table.insert(lines, "")
	table.insert(lines, "Needs review:")
	table.insert(lines, "  Exact cross-list conflicts: " .. tostring(#exactConflicts))
	table.insert(lines, "  Same cached name with multiple item IDs: " .. tostring(#sameNameMultiId))
	table.insert(lines, "  Name-only mixed with item-ID entries: " .. tostring(#nameMixWarnings))
	table.insert(lines, "  Name-only entries: " .. tostring(nameOnlyCount))
	table.insert(lines, "  Uncached item IDs: " .. tostring(uncachedIdCount))
	table.insert(lines, "")
	table.insert(lines, "Safe fix command:")
	table.insert(lines, "  /del audit fix")
	table.insert(lines, "")
	table.insert(lines, "Review rule:")
	table.insert(lines, "  AutoDelete does not guess when names can map to multiple item IDs.")
	table.insert(lines, "  Heroic and non-heroic same-name cases must be reviewed by item ID.")

	if #exactConflicts > 0 then
		table.insert(lines, "")
		table.insert(lines, "Exact cross-list conflicts:")
		for _, item in ipairs(exactConflicts) do AddEntries(lines, item.bucket, 6) end
	end
	if #sameNameMultiId > 0 then
		table.insert(lines, "")
		table.insert(lines, "Same cached name with multiple item IDs:")
		for _, item in ipairs(sameNameMultiId) do AddEntries(lines, item.bucket, 8) end
	end
	if #nameMixWarnings > 0 then
		table.insert(lines, "")
		table.insert(lines, "Name-only mixed with item-ID entries:")
		for _, item in ipairs(nameMixWarnings) do AddEntries(lines, item.bucket, 8) end
	end
	if nameOnlyCount > 0 then
		table.insert(lines, "")
		table.insert(lines, "Name-only entries:")
		local shown = 0
		for _, entry in ipairs(entries) do
			if entry.kind == "name" then
				shown = shown + 1
				if shown <= 30 then table.insert(lines, "  " .. EntryLabel(entry)) end
			end
		end
		if shown > 30 then table.insert(lines, "  ... " .. tostring(shown - 30) .. " more") end
	end
	if uncachedIdCount > 0 then
		table.insert(lines, "")
		table.insert(lines, "Uncached item IDs:")
		local shown = 0
		for _, entry in ipairs(entries) do
			if entry.kind == "id" and not entry.name then
				shown = shown + 1
				if shown <= 30 then table.insert(lines, "  " .. EntryLabel(entry)) end
			end
		end
		if shown > 30 then table.insert(lines, "  ... " .. tostring(shown - 30) .. " more") end
	end
	if duplicateFixes == 0 and safeLinkOrNumberFixes == 0 and #exactConflicts == 0
		and #sameNameMultiId == 0 and #nameMixWarnings == 0 and nameOnlyCount == 0
		and uncachedIdCount == 0 then
		table.insert(lines, "")
		table.insert(lines, "No list issues found.")
	end
	return table.concat(lines, "\n")
end

function _G.AutoDelete_FixSafeListAuditIssues()
	local db = GetDB()
	local profile = GetActiveProfile(db)
	local listDefs = {
		{ field = "listText", label = "Delete" },
		{ field = "sellListText", label = "Sell" },
		{ field = "whitelistText", label = "Keep" },
		{ field = "keepOneText", label = "KeepOne" },
		{ field = "keepStackText", label = "KeepStack" },
	}
	local removedDupes, normalizedRefs = 0, 0

	local function ParseFixKey(line)
		local original = Trim(line or "")
		if original == "" then return nil, nil, false end
		local hasComment = string.find(original, "#", 1, true) ~= nil
		local stripped = string.gsub(original, "%s*#.*$", "")
		stripped = Trim(stripped)
		if stripped == "" then return nil, original, false end
		local linkId = tonumber(string.match(stripped, "Hitem:(%d+)"))
		local itemId = linkId or tonumber(string.match(stripped, "^item:(%d+)")) or tonumber(string.match(stripped, "^(%d+)$"))
		if itemId then
			local shouldNormalize = (not hasComment) and ((linkId ~= nil) or (string.match(stripped, "^%d+$") ~= nil))
			return "id:" .. itemId, shouldNormalize and ("item:" .. itemId) or original, shouldNormalize
		end
		return "name:" .. Normalize(stripped), original, false
	end

	for _, def in ipairs(listDefs) do
		local seen, rebuilt = {}, {}
		for line in string.gmatch(profile[def.field] or "", "[^\r\n]+") do
			local key, outLine, didNormalize = ParseFixKey(line)
			if key then
				if seen[key] then
					removedDupes = removedDupes + 1
				else
					seen[key] = true
					if didNormalize then normalizedRefs = normalizedRefs + 1 end
					table.insert(rebuilt, outLine)
				end
			elseif Trim(line) ~= "" then
				table.insert(rebuilt, Trim(line))
			end
		end
		profile[def.field] = table.concat(rebuilt, "\n")
		if #rebuilt > 0 then profile[def.field] = profile[def.field] .. "\n" end
	end

	RefreshCachedProfile()
	local panel = _G.AutoDeleteOptionsPanel
	if panel and panel._built and panel:IsVisible() then panel:Refresh() end

	return removedDupes, normalizedRefs
end

function _G.AutoDelete_ShowListAudit()
	local text = _G.AutoDelete_BuildListAuditReport()
	if _G.AutoDelete_ShowReportWindow then
		_G.AutoDelete_ShowReportWindow(text, "List Audit")
	else
		print("|cffff8000[AutoDelete]|r " .. text:gsub("\n", "\n|cffff8000[AutoDelete]|r "))
	end
end

function _G.AutoDelete_RunListAuditSafeFix()
	local removedDupes, normalizedRefs = _G.AutoDelete_FixSafeListAuditIssues()
	local prefix = {
		"Safe list audit fixes applied.",
		"Duplicate lines removed: " .. tostring(removedDupes),
		"References normalized: " .. tostring(normalizedRefs),
	}
	local text = _G.AutoDelete_BuildListAuditReport(prefix)
	if _G.AutoDelete_ShowReportWindow then
		_G.AutoDelete_ShowReportWindow(text, "List Audit")
	else
		print("|cffff8000[AutoDelete]|r " .. text:gsub("\n", "\n|cffff8000[AutoDelete]|r "))
	end
end

local function CleanLists()
	local db = GetDB()
	local profile = GetActiveProfile(db)

	local function Parse(listText)
		local entries = {}
		for line in string.gmatch(listText or "", "[^\r\n]+") do
			local key, display, raw = ResolveEntryKey(line)
			if key then
				table.insert(entries, { key = key, display = display, raw = raw })
			end
		end
		return entries
	end

	local delEntries  = Parse(profile.listText)
	local sellEntries = Parse(profile.sellListText)
	local keepEntries = Parse(profile.whitelistText)
	local keepOneEntries = Parse(profile.keepOneText)
	local keepStackEntries = Parse(profile.keepStackText)

	-- 1. Dedupe within each list (first occurrence wins)
	local function DedupeWithin(entries)
		local seen, kept, dupes = {}, {}, {}
		for _, e in ipairs(entries) do
			if not seen[e.key] then
				seen[e.key] = true
				table.insert(kept, e)
			else
				table.insert(dupes, e.display)
			end
		end
		return kept, dupes
	end

	local keptDel,  internalDelDupes  = DedupeWithin(delEntries)
	local keptSell, internalSellDupes = DedupeWithin(sellEntries)
	local keptKeep, internalKeepDupes = DedupeWithin(keepEntries)
	local keptKeepOne, internalKeepOneDupes = DedupeWithin(keepOneEntries)
	local keptKeepStack, internalKeepStackDupes = DedupeWithin(keepStackEntries)

	-- 2a. Keep overrides Delete/Sell. Items on Keep AND Delete/Sell get
	-- removed from Delete/Sell (matches runtime semantics: Keep always wins).
	local keepKeys = {}
	for _, e in ipairs(keptKeep) do keepKeys[e.key] = true end

	local keepBlockedFromDel, keepBlockedFromSell, keepBlockedFromKeepOne, keepBlockedFromKeepStack = {}, {}, {}, {}
	local afterKeepDel, afterKeepSell, afterKeepOne, afterKeepStack = {}, {}, {}, {}
	for _, e in ipairs(keptDel) do
		if keepKeys[e.key] then
			table.insert(keepBlockedFromDel, e.display)
		else
			table.insert(afterKeepDel, e)
		end
	end
	for _, e in ipairs(keptSell) do
		if keepKeys[e.key] then
			table.insert(keepBlockedFromSell, e.display)
		else
			table.insert(afterKeepSell, e)
		end
	end
	for _, e in ipairs(keptKeepOne) do
		if keepKeys[e.key] then
			table.insert(keepBlockedFromKeepOne, e.display)
		else
			table.insert(afterKeepOne, e)
		end
	end
	for _, e in ipairs(keptKeepStack) do
		if keepKeys[e.key] then
			table.insert(keepBlockedFromKeepStack, e.display)
		else
			table.insert(afterKeepStack, e)
		end
	end

	-- 2b. Find Delete + Sell + KeepOne + KeepStack overlap. All get removed
	-- (no winner; user re-adds to their preferred list manually).
	local sellKeys = {}
	for _, e in ipairs(afterKeepSell) do sellKeys[e.key] = true end
	local keepOneKeys = {}
	for _, e in ipairs(afterKeepOne) do keepOneKeys[e.key] = true end
	local keepStackKeys = {}
	for _, e in ipairs(afterKeepStack) do keepStackKeys[e.key] = true end
	local delKeys = {}
	for _, e in ipairs(afterKeepDel) do delKeys[e.key] = true end

	local crossDupes, finalDel, finalSell, finalKeepOne, finalKeepStack = {}, {}, {}, {}, {}
	local crossKeys = {}
	for _, e in ipairs(afterKeepDel) do
		if sellKeys[e.key] or keepOneKeys[e.key] or keepStackKeys[e.key] then
			crossKeys[e.key] = true
			table.insert(crossDupes, e.display)
		else
			table.insert(finalDel, e.raw)
		end
	end
	for _, e in ipairs(afterKeepSell) do
		if delKeys[e.key] or keepOneKeys[e.key] or keepStackKeys[e.key] then
			if not crossKeys[e.key] then
				crossKeys[e.key] = true
				table.insert(crossDupes, e.display)
			end
		elseif not crossKeys[e.key] then
			table.insert(finalSell, e.raw)
		end
	end
	for _, e in ipairs(afterKeepOne) do
		if delKeys[e.key] or sellKeys[e.key] or keepStackKeys[e.key] then
			if not crossKeys[e.key] then
				crossKeys[e.key] = true
				table.insert(crossDupes, e.display)
			end
		elseif not crossKeys[e.key] then
			table.insert(finalKeepOne, e.raw)
		end
	end
	for _, e in ipairs(afterKeepStack) do
		if delKeys[e.key] or sellKeys[e.key] or keepOneKeys[e.key] then
			if not crossKeys[e.key] then
				crossKeys[e.key] = true
				table.insert(crossDupes, e.display)
			end
		elseif not crossKeys[e.key] then
			table.insert(finalKeepStack, e.raw)
		end
	end

	local finalKeep = {}
	for _, e in ipairs(keptKeep) do table.insert(finalKeep, e.raw) end

	-- Rewrite list text (preserve trailing newline if there were entries)
	profile.listText = table.concat(finalDel, "\n")
	if #finalDel > 0 then profile.listText = profile.listText .. "\n" end
	profile.sellListText = table.concat(finalSell, "\n")
	if #finalSell > 0 then profile.sellListText = profile.sellListText .. "\n" end
	profile.whitelistText = table.concat(finalKeep, "\n")
	if #finalKeep > 0 then profile.whitelistText = profile.whitelistText .. "\n" end
	profile.keepOneText = table.concat(finalKeepOne, "\n")
	if #finalKeepOne > 0 then profile.keepOneText = profile.keepOneText .. "\n" end
	profile.keepStackText = table.concat(finalKeepStack, "\n")
	if #finalKeepStack > 0 then profile.keepStackText = profile.keepStackText .. "\n" end

	RefreshCachedProfile()

	-- Report
	print("|cffff8000[AutoDelete]|r Clean complete.")
	if #internalDelDupes > 0 then
		print("  |cff999999Removed " .. #internalDelDupes .. " internal duplicate(s) in Delete list:|r " .. table.concat(internalDelDupes, ", "))
	end
	if #internalSellDupes > 0 then
		print("  |cff999999Removed " .. #internalSellDupes .. " internal duplicate(s) in Sell list:|r " .. table.concat(internalSellDupes, ", "))
	end
	if #internalKeepDupes > 0 then
		print("  |cff999999Removed " .. #internalKeepDupes .. " internal duplicate(s) in Keep list:|r " .. table.concat(internalKeepDupes, ", "))
	end
	if #internalKeepOneDupes > 0 then
		print("  |cff999999Removed " .. #internalKeepOneDupes .. " internal duplicate(s) in KeepOne list:|r " .. table.concat(internalKeepOneDupes, ", "))
	end
	if #internalKeepStackDupes > 0 then
		print("  |cff999999Removed " .. #internalKeepStackDupes .. " internal duplicate(s) in KeepStack list:|r " .. table.concat(internalKeepStackDupes, ", "))
	end
	if #keepBlockedFromDel > 0 then
		print("|cff80c0ff  Removed from Delete (already on Keep, Keep wins):|r " .. table.concat(keepBlockedFromDel, ", "))
	end
	if #keepBlockedFromSell > 0 then
		print("|cff80c0ff  Removed from Sell (already on Keep, Keep wins):|r " .. table.concat(keepBlockedFromSell, ", "))
	end
	if #keepBlockedFromKeepOne > 0 then
		print("|cff80c0ff  Removed from KeepOne (already on Keep, Keep wins):|r " .. table.concat(keepBlockedFromKeepOne, ", "))
	end
	if #keepBlockedFromKeepStack > 0 then
		print("|cff80c0ff  Removed from KeepStack (already on Keep, Keep wins):|r " .. table.concat(keepBlockedFromKeepStack, ", "))
	end
	if #crossDupes > 0 then
		print("|cffff4444  Removed cross-list conflict(s) from Delete / Sell / KeepOne / KeepStack:|r " .. table.concat(crossDupes, ", "))
		print("  |cffaaaaaaRe-add these manually to your preferred list.|r")
	end
	if #internalDelDupes == 0 and #internalSellDupes == 0 and #internalKeepDupes == 0
		and #internalKeepOneDupes == 0 and #internalKeepStackDupes == 0
		and #keepBlockedFromDel == 0 and #keepBlockedFromSell == 0
		and #keepBlockedFromKeepOne == 0 and #keepBlockedFromKeepStack == 0
		and #crossDupes == 0 then
		print("  |cff999999No duplicates found.|r")
	end

	-- Refresh UI if open
	local panel = _G.AutoDeleteOptionsPanel
	if panel and panel._built and panel:IsVisible() then
		panel:Refresh()
	end
end

-- ============================================================================
-- Profile Import - merge item lists from another character's profile
-- ============================================================================
-- The list keys in a profile, with their display labels. Order matters for the
-- popup list buttons.
local IMPORT_LIST_KEYS = { "listText", "sellListText", "whitelistText", "keepOneText", "keepStackText" }
local IMPORT_LIST_DISPLAY = {
	listText       = "Delete",
	sellListText   = "Sell",
	whitelistText  = "Keep",
	keepOneText    = "KeepOne",
	keepStackText  = "KeepStack",
}
local IMPORT_DISPLAY_TO_KEY = {
	Delete = "listText",
	Sell   = "sellListText",
	Keep   = "whitelistText",
	KeepOne = "keepOneText",
	KeepStack = "keepStackText",
}

-- Walk a list text and build a map: canonicalKey → rawLine.
-- First occurrence wins (matches the dedupe behavior of /del clean).
local function BuildKeyMap(listText)
	local map = {}
	for line in string.gmatch(listText or "", "[^\r\n]+") do
		local key, _, raw = ResolveEntryKey(line)
		if key and not map[key] then
			map[key] = raw
		end
	end
	return map
end

-- Remove all lines matching a given canonical key from a list text.
-- Returns the rewritten text.
local function RemoveEntriesWithKey(listText, keyToRemove)
	local out = {}
	for line in string.gmatch(listText or "", "[^\r\n]+") do
		local k = ResolveEntryKey(line)
		if k ~= keyToRemove then
			table.insert(out, Trim(line))
		end
	end
	local rebuilt = table.concat(out, "\n")
	if #out > 0 then rebuilt = rebuilt .. "\n" end
	return rebuilt
end

-- Append a single raw entry to a list text (idempotent-ish: appends if the
-- canonical key isn't already present).
local function AppendEntry(listText, rawEntry)
	local key = ResolveEntryKey(rawEntry)
	if not key then return listText or "" end
	local existing = BuildKeyMap(listText)
	if existing[key] then return listText or "" end  -- already present
	local base = listText or ""
	if base ~= "" and not string.match(base, "\n$") then base = base .. "\n" end
	return base .. Trim(rawEntry) .. "\n"
end

-- PreviewImport: detects what would change if we imported the source profile's
-- item lists into the current character's profile. Makes NO changes.
-- Returns:
--   {
--     additions = { {key, display, raw, targetList, targetListDisplay}, ... }
--     conflicts = { {key, display, raw, sourceList, sourceListDisplay,
--                    currentList, currentListDisplay}, ... }
--   }
-- Returns nil, reason on error.
local function PreviewImport(sourceCharKey)
	if not sourceCharKey or sourceCharKey == "" then
		return nil, "no source selected"
	end
	local db = GetDB()
	local sourceProfile = db.profiles and db.profiles[sourceCharKey]
	if not sourceProfile then return nil, "source profile not found" end
	local currentProfile = GetActiveProfile(db)
	if sourceCharKey == GetCharKey() then
		return nil, "source is the current character"
	end

	-- Build canonical-key maps for each of the current character's lists,
	-- so we can look up "is this item somewhere in my current profile?"
	local currentMaps = {}
	for _, lk in ipairs(IMPORT_LIST_KEYS) do
		currentMaps[lk] = BuildKeyMap(currentProfile[lk])
	end
	-- Reverse map: key → which list it's on (if any) in the current profile
	local currentKeyList = {}
	for _, lk in ipairs(IMPORT_LIST_KEYS) do
		for k in pairs(currentMaps[lk]) do
			currentKeyList[k] = lk
		end
	end

	local additions, conflicts = {}, {}
	local seenInThisImport = {}  -- guard against dupes across source's own lists

	for _, srcListKey in ipairs(IMPORT_LIST_KEYS) do
		local srcText = sourceProfile[srcListKey]
		for line in string.gmatch(srcText or "", "[^\r\n]+") do
			local key, display, raw = ResolveEntryKey(line)
			if key and not seenInThisImport[key] then
				seenInThisImport[key] = true
				local curList = currentKeyList[key]
				if not curList then
					-- Not in current at all → addition
					table.insert(additions, {
						key = key, display = display, raw = raw,
						targetList = srcListKey,
						targetListDisplay = IMPORT_LIST_DISPLAY[srcListKey],
					})
				elseif curList ~= srcListKey then
					-- In current on a DIFFERENT list → conflict
					table.insert(conflicts, {
						key = key, display = display, raw = raw,
						sourceList = srcListKey,
						sourceListDisplay = IMPORT_LIST_DISPLAY[srcListKey],
						currentList = curList,
						currentListDisplay = IMPORT_LIST_DISPLAY[curList],
					})
				end
				-- else: same list on both → skip (no duplicate, no change)
			end
		end
	end

	return { additions = additions, conflicts = conflicts }
end

-- ApplyImport: performs the merge. resolutions is a table keyed by canonical
-- key → chosen list display name ("Delete"/"Sell"/"Keep"). Keys not present
-- in resolutions default to the source's list (i.e., "take source").
local function ApplyImport(sourceCharKey, resolutions)
	local preview, reason = PreviewImport(sourceCharKey)
	if not preview then return false, reason end

	local db = GetDB()
	local profile = GetActiveProfile(db)
	resolutions = resolutions or {}

	local addedByList = { Delete = 0, Sell = 0, Keep = 0, KeepOne = 0, KeepStack = 0 }
	local movedByList = { Delete = 0, Sell = 0, Keep = 0, KeepOne = 0, KeepStack = 0 }

	-- Apply additions (no conflict, always add to source's list).
	for _, add in ipairs(preview.additions) do
		profile[add.targetList] = AppendEntry(profile[add.targetList], add.raw)
		addedByList[add.targetListDisplay] = (addedByList[add.targetListDisplay] or 0) + 1
	end

	-- Apply conflict resolutions.
	for _, c in ipairs(preview.conflicts) do
		local chosen = resolutions[c.key] or c.sourceListDisplay
		if chosen ~= c.currentListDisplay then
			-- Remove from current location, add to chosen.
			profile[c.currentList] = RemoveEntriesWithKey(profile[c.currentList], c.key)
			local chosenKey = IMPORT_DISPLAY_TO_KEY[chosen]
			if chosenKey then
				profile[chosenKey] = AppendEntry(profile[chosenKey], c.raw)
				movedByList[chosen] = (movedByList[chosen] or 0) + 1
			end
		end
		-- else: keep where it is, no change
	end

	if RefreshCachedProfile then RefreshCachedProfile() end

	-- Summary report
	print(string.format("|cffff8000[AutoDelete]|r Import from %s complete.", sourceCharKey))
	local addParts = {}
	for _, lbl in ipairs({"Delete","Sell","Keep","KeepOne","KeepStack"}) do
		if addedByList[lbl] > 0 then table.insert(addParts, addedByList[lbl] .. " to " .. lbl) end
	end
	if #addParts > 0 then
		print("  |cff999999Added:|r " .. table.concat(addParts, ", "))
	end
	local moveParts = {}
	for _, lbl in ipairs({"Delete","Sell","Keep","KeepOne","KeepStack"}) do
		if movedByList[lbl] > 0 then table.insert(moveParts, movedByList[lbl] .. " to " .. lbl) end
	end
	if #moveParts > 0 then
		print("  |cff999999Moved via conflict resolution:|r " .. table.concat(moveParts, ", "))
	end
	if #addParts == 0 and #moveParts == 0 then
		print("  |cff999999No changes needed. Lists already match.|r")
	end

	-- Refresh UI if open
	local panel = _G.AutoDeleteOptionsPanel
	if panel and panel._built and panel:IsVisible() then
		panel:Refresh()
	end
	return true
end

-- Expose import API alongside existing profile helpers.
_G.AutoDelete_Profiles.PreviewImport = PreviewImport
_G.AutoDelete_Profiles.ApplyImport = ApplyImport

-- ============================================================================
-- Modifier-click handlers (shift = search fill, Alt+Right = item quick menu)
-- ============================================================================
-- Shift-click and Alt+Right-click do different things:
--
--   SHIFT-CLICK is the search-box-fill shortcut. When our settings panel is
--   visible, shift-clicking an item link (chat, bag, anywhere) fills the
--   panel's search box with the item name. We do NOT intercept any default
--   shift-click behavior (stack split, AH search, link-insert-into-chat,
--   bank/guild bank moves). Just observe the click via hooksecurefunc and
--   update the search box. Returns nothing, eats nothing.
--
--   ALT+RIGHT-CLICK opens AutoDelete's quick item menu. Real bag items use
--   Blizzard's modified-click function, never per-button bag slot OnClick
--   wrappers and never UseContainerItem. The guard is deliberately narrow:
--   pure Alt+Right only, valid bag/slot only, otherwise call Blizzard's
--   original handler.
--
-- Why this split: shift-click is heavily overloaded by Blizzard. Every new
-- context we discover (stack split, AH, bank, ...) is another suppress case.
-- Alt+Right-click on item links still uses HandleModifiedItemClick /
-- ChatEdit_InsertLink. Bag-slot OnClick handlers stay untouched.

-- Shared skip-frame check used by both shift and Alt+Right paths. Returns true if
-- we should bail (some context is open that uses modifier-click for its own
-- purposes). Shift's search-fill is non-destructive, so technically it's
-- safe to run anywhere - we still skip in these contexts to keep the
-- behavior of both modifiers consistent and predictable.
local function ShouldSkipContext(allowVendor)
	local skipFrames = {
		{ frame = AuctionFrame,    name = "Auction House" },
		{ frame = BankFrame,       name = "Bank" },
		{ frame = GuildBankFrame,  name = "Guild Bank" },
		{ frame = TradeSkillFrame, name = "Tradeskill" },
		{ frame = CraftFrame,      name = "Craft" },
	}
	if not allowVendor then
		skipFrames[#skipFrames + 1] = { frame = MerchantFrame, name = "Vendor" }
	end
	for _, f in ipairs(skipFrames) do
		if f.frame and f.frame:IsShown() then
			if _G.AutoDelete_DebugSell then
				print("|cffff8000[AutoDelete DEBUG]|r " .. f.name .. " open, skipping")
			end
			return true
		end
	end
	return false
end

-- ----------------------------------------------------------------------------
-- SHIFT-CLICK: search-box fill only. Non-destructive, runs alongside default.
-- ----------------------------------------------------------------------------
local function HandleShiftClickFill(link)
	if not link then return end
	local panel = _G.AutoDeleteOptionsPanel
	if not panel or not panel._built or not panel:IsVisible() then return end
	if ShouldSkipContext() then return end
	local name = GetItemInfo(link)
	if not name or name == "" then return end
	if panel._searchBox and panel._searchBox.SetText then
		panel._searchBox:SetText(name)
		panel._searchBox:SetCursorPosition(#name)
		if panel._searchPlaceholder then panel._searchPlaceholder:Hide() end
		panel._filterText = name
		if panel.Refresh then panel:Refresh() end
	end
end

-- ----------------------------------------------------------------------------
-- ALT+RIGHT-CLICK: quick item menu.
-- ----------------------------------------------------------------------------
local lastHandledItemId = nil
local lastHandledAt = 0

function _G.AutoDelete_IsAltRightClick()
	if not IsAltKeyDown() then return false end
	if not IsMouseButtonDown then return false end
	return IsMouseButtonDown("RightButton")
end

function _G.AutoDelete_ResolveBagSlotFromModifiedClickButton(buttonFrame)
	if not buttonFrame then return nil, nil end
	local bag, slot

	if buttonFrame.GetBagID then
		local ok, value = pcall(buttonFrame.GetBagID, buttonFrame)
		if ok then bag = value end
	end
	if buttonFrame.GetID then
		local ok, value = pcall(buttonFrame.GetID, buttonFrame)
		if ok then slot = value end
	end

	if bag == nil and buttonFrame.GetParent then
		local parent = buttonFrame:GetParent()
		if parent and parent.GetID then
			local ok, value = pcall(parent.GetID, parent)
			if ok then bag = value end
		end
	end

	bag = bag or buttonFrame.bagID or buttonFrame.BagID or buttonFrame.bag or buttonFrame.Bag
	slot = slot or buttonFrame.slotID or buttonFrame.SlotID or buttonFrame.slot or buttonFrame.Slot
	if type(bag) ~= "number" or type(slot) ~= "number" then return nil, nil end
	if bag < 0 or bag > NUM_BAG_SLOTS or slot < 1 then return nil, nil end
	return bag, slot
end

function _G.AutoDelete_ShouldConsumeBagAltRight(buttonFrame, mouseButton)
	if mouseButton ~= "RightButton" then return false end
	if not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return false end
	if ShouldSkipContext(true) then return false end
	if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then return false end
	if GetCursorInfo and GetCursorInfo() then return false end
	if not _G.AutoDelete_ShowItemQuickMenu then return false end

	local bag, slot = _G.AutoDelete_ResolveBagSlotFromModifiedClickButton(buttonFrame)
	if not bag or not slot then return false end
	local link = GetContainerItemLink(bag, slot)
	if not link then return false end
	local itemId = GetItemIDFromLink(link)
	if not itemId then return false end
	return true, bag, slot, link, itemId
end

function _G.AutoDelete_OpenBagAltRightMenu(buttonFrame, mouseButton)
	local consume, bag, slot, link, itemId = _G.AutoDelete_ShouldConsumeBagAltRight(buttonFrame, mouseButton)
	if not consume then return false end
	if _G.AutoDelete_DebugSell then
		print("|cffff8000[AutoDelete DEBUG]|r Alt+Right menu via ContainerFrameItemButton_OnModifiedClick. link=" .. tostring(link))
	end
	_G.AutoDelete_ShowItemQuickMenu({ itemId = itemId, link = link, bag = bag, slot = slot })
	return true
end

-- Returns true if the click was consumed (for ChatEdit_InsertLink to know
-- whether to suppress its default chat-insert behavior).
local function HandleAltRightClickMenu(link, source, bag, slot)
	if not link then return false end
	if _G.AutoDelete_DebugSell then
		print("|cffff8000[AutoDelete DEBUG]|r Alt+Right menu via " .. source .. ". link=" .. tostring(link))
	end

	local itemId = GetItemIDFromLink(link)
	if _G.AutoDelete_DebugSell then
		print("|cffff8000[AutoDelete DEBUG]|r extracted itemId=" .. tostring(itemId))
	end
	if not itemId then return false end

	if ShouldSkipContext(true) then return false end

	-- Dedupe: a single modified click in chat can fire both ChatEdit_InsertLink
	-- and HandleModifiedItemClick. Suppress the second menu open inside 0.5s.
	local now = GetTime()
	if lastHandledItemId == itemId and (now - lastHandledAt) < 0.5 then
		if _G.AutoDelete_DebugSell then
			print("|cffff8000[AutoDelete DEBUG]|r duplicate within window, skipping")
		end
		-- Consume duplicates too. Alt+Right is AutoDelete-owned in this addon,
		-- and a second path should never fall through to normal item use.
		return true
	end
	lastHandledItemId = itemId
	lastHandledAt = now

	-- If an editbox is focused, don't insert text or add to Keep - let the
	-- default behavior take precedence. (Alt-click has no default behavior
	-- but a focused editbox usually means the user is mid-type, so we bail
	-- to be safe.)
	local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
	if focus then return false end

	if _G.AutoDelete_ShowItemQuickMenu then
		_G.AutoDelete_ShowItemQuickMenu({ itemId = itemId, link = link, bag = bag, slot = slot })
	end
	return true   -- eat the chat-link insert if that's how we got here
end

-- ----------------------------------------------------------------------------
-- Hook installation
-- ----------------------------------------------------------------------------
-- Real bag items: replace the global modified-click dispatcher with a tiny
-- wrapper so pure Alt+Right can be consumed before Blizzard falls through to
-- normal item use. All other clicks call the original dispatcher.
function _G.AutoDelete_InstallBagAltRightHook()
	if _G.AutoDelete_BagAltRightHookInstalled then return true end
	if type(ContainerFrameItemButton_OnModifiedClick) ~= "function" then return false end
	_G.AutoDelete_Original_ContainerFrameItemButton_OnModifiedClick = ContainerFrameItemButton_OnModifiedClick
	ContainerFrameItemButton_OnModifiedClick = function(self, button)
		if _G.AutoDelete_OpenBagAltRightMenu(self, button) then return end
		return _G.AutoDelete_Original_ContainerFrameItemButton_OnModifiedClick(self, button)
	end
	_G.AutoDelete_BagAltRightHookInstalled = true
	return true
end
_G.AutoDelete_InstallBagAltRightHook()

-- Shift-click (search fill) is hooked via hooksecurefunc on
-- HandleModifiedItemClick. We also hook ChatEdit_InsertLink to catch the
-- chat-link path. Both are read-only observations for Shift; Alt+Right on
-- chat links is consumed only when AutoDelete opens the quick menu.
hooksecurefunc("HandleModifiedItemClick", function(link)
	if IsShiftKeyDown() then HandleShiftClickFill(link) end
	if _G.AutoDelete_IsAltRightClick() then HandleAltRightClickMenu(link, "HandleModifiedItemClick") end
end)

-- Alt+Right-click on a chat hyperlink: ChatEdit_InsertLink is the function called
-- when the user holds a modifier and clicks a chat link. We intercept on
-- Alt+Right to suppress the default behavior (insert link text into chat editbox)
-- when we're consuming the click for the quick item menu. Shift-click on chat links
-- still goes through to the default (insert into chat) - we DO call the
-- search-fill path on shift but never consume the click.
_G.AutoDelete_Original_ChatEdit_InsertLink = ChatEdit_InsertLink
ChatEdit_InsertLink = function(link)
	-- Shift-click: just observe, never consume.
	if IsShiftKeyDown() then
		HandleShiftClickFill(link)
		return _G.AutoDelete_Original_ChatEdit_InsertLink(link)
	end
	-- Alt+Right-click: try to consume.
	if _G.AutoDelete_IsAltRightClick() and HandleAltRightClickMenu(link, "ChatEdit_InsertLink") then
		return true
	end
	return _G.AutoDelete_Original_ChatEdit_InsertLink(link)
end

function _G.AutoDelete_ShowOptionsPanel()
	local panel = _G.AutoDeleteOptionsPanel
	if not panel then
		print("|cffff8000[AutoDelete]|r Settings panel is not ready yet. Try again in a moment.")
		return
	end
	panel:Show()
end

function _G.AutoDelete_ToggleOptionsPanel()
	local panel = _G.AutoDeleteOptionsPanel
	if not panel then
		print("|cffff8000[AutoDelete]|r Settings panel is not ready yet. Try again in a moment.")
		return
	end
	if panel:IsShown() then
		panel:Hide()
	else
		panel:Show()
	end
end

function _G.AutoDelete_RunSlashCommand(command)
	if SlashCmdList and SlashCmdList["AUTODELETE"] then
		SlashCmdList["AUTODELETE"](command or "")
	end
end

function _G.AutoDelete_ShowMinimapMenu(anchor)
	if not EasyMenu then
		print("|cffff8000[AutoDelete]|r Minimap menu is not available on this client.")
		return
	end
	if not _G.AutoDelete_MinimapMenuFrame then
		_G.AutoDelete_MinimapMenuFrame = CreateFrame("Frame", "AutoDeleteMinimapMenu", UIParent, "UIDropDownMenuTemplate")
		_G.AutoDelete_RegisterSpecialFrame("AutoDeleteMinimapMenu")
	end

	local settingsLabel = "Open Settings"
	local panel = _G.AutoDeleteOptionsPanel
	if panel and panel.IsShown and panel:IsShown() then settingsLabel = "Close Settings" end

	local function run(command)
		return function() _G.AutoDelete_RunSlashCommand(command) end
	end

	local menu = {
		{ text = "AutoDelete", isTitle = true, notCheckable = true },
		{ text = settingsLabel, notCheckable = true, func = function() _G.AutoDelete_ToggleOptionsPanel() end },
		{ text = "Process Bags", notCheckable = true, func = run("process") },
		{ text = "Affix List", notCheckable = true, func = run("affix") },
		{ text = "Decision History", notCheckable = true, func = run("history") },
		{ text = "List Audit", notCheckable = true, func = run("audit") },
		{ text = "Settings Report", notCheckable = true, func = run("report") },
		{
			text = "Diagnostics",
			hasArrow = true,
			notCheckable = true,
			menuList = {
				{ text = "Process Debug", notCheckable = true, func = run("processdebug") },
				{ text = "Disenchant History", notCheckable = true, func = run("de history") },
				{ text = "Goblin Report", notCheckable = true, func = run("goblin") },
				{ text = "Scavenger Report", notCheckable = true, func = run("scav") },
			},
		},
	}

	EasyMenu(menu, _G.AutoDelete_MinimapMenuFrame, anchor or "cursor", 0, 0, "MENU", 2)
end

function _G.AutoDelete_SetMinimapButtonPosition(angle)
	if not _G.AutoDelete_MinimapButton or not Minimap then return end
	_G.AutoDeleteDB = _G.AutoDeleteDB or {}
	angle = tonumber(angle) or tonumber(_G.AutoDeleteDB.minimapAngle) or 225
	_G.AutoDeleteDB.minimapAngle = angle

	local radius = 80
	local radians = math.rad(angle)
	_G.AutoDelete_MinimapButton:ClearAllPoints()
	_G.AutoDelete_MinimapButton:SetPoint(
		"CENTER",
		Minimap,
		"CENTER",
		math.cos(radians) * radius,
		math.sin(radians) * radius
	)
end

function _G.AutoDelete_UpdateMinimapButtonDrag()
	if not _G.AutoDelete_MinimapButton or not Minimap then return end
	local minX, minY = Minimap:GetCenter()
	local curX, curY = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale() or 1
	if not minX or not minY or not curX or not curY or scale == 0 then return end

	curX = curX / scale
	curY = curY / scale
	local atan2 = math.atan2 or math.atan
	local angle = math.deg(atan2(curY - minY, curX - minX))
	_G.AutoDelete_SetMinimapButtonPosition(angle)
end

function _G.AutoDelete_CreateMinimapButton()
	if _G.AutoDelete_MinimapButton or not Minimap then return end

	local button = CreateFrame("Button", "AutoDeleteMinimapButton", Minimap)
	button:SetSize(30, 30)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	button:SetBackdropColor(5/255, 5/255, 5/255, 1)
	button:SetBackdropBorderColor(1, 0.5, 0, 1)

	local label = button:CreateFontString(nil, "OVERLAY")
	label:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
	label:SetText("AD")
	label:SetTextColor(1, 0.5, 0, 1)
	label:SetPoint("CENTER", 0, 0)
	button._label = label

	button:SetScript("OnEnter", function(self)
		self:SetBackdropColor(16/255, 16/255, 16/255, 1)
		self:SetBackdropBorderColor(1, 0.65, 0.15, 1)
		if self._label then self._label:SetTextColor(1, 0.65, 0.15, 1) end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("AutoDelete", 1, 0.5, 0)
		GameTooltip:AddLine("Left-click: open/close settings", 0.85, 0.85, 0.85)
		GameTooltip:AddLine("Right-click: quick menu", 0.85, 0.85, 0.85)
		GameTooltip:AddLine("Drag: move button", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		self:SetBackdropColor(5/255, 5/255, 5/255, 1)
		self:SetBackdropBorderColor(1, 0.5, 0, 1)
		if self._label then self._label:SetTextColor(1, 0.5, 0, 1) end
		GameTooltip:Hide()
	end)
	button:SetScript("OnClick", function(self, mouseButton)
		if self._justDragged then
			return
		end
		if mouseButton == "RightButton" then
			_G.AutoDelete_ShowMinimapMenu(self)
		else
			_G.AutoDelete_ToggleOptionsPanel()
		end
	end)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", _G.AutoDelete_UpdateMinimapButtonDrag)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		_G.AutoDelete_UpdateMinimapButtonDrag()
		self._justDragged = true
		AfterDelay(0.05, function()
			if self then self._justDragged = nil end
		end)
	end)

	_G.AutoDelete_MinimapButton = button
	_G.AutoDelete_SetMinimapButtonPosition((_G.AutoDeleteDB and _G.AutoDeleteDB.minimapAngle) or 225)
end

SLASH_AUTODELETE1 = "/del"
SLASH_AUTODELETE2 = "/autodelete"
SlashCmdList["AUTODELETE"] = function(msg)
	local rawArg = Trim(msg or "")
	local arg = string.lower(rawArg)
	if arg == "clean" then
		CleanLists()
		return
	end
	if arg == "audit" or arg == "audit lists" then
		if _G.AutoDelete_ShowListAudit then _G.AutoDelete_ShowListAudit() end
		return
	end
	if arg == "audit fix" or arg == "audit lists fix" then
		if _G.AutoDelete_RunListAuditSafeFix then _G.AutoDelete_RunListAuditSafeFix() end
		return
	end
	if arg == "sell" then
		SellItems()
		return
	end
	if arg == "setup" then
		-- Re-open the welcome popup. Clears the dismissed flag so the user
		-- can see it again from this point forward unless they re-check
		-- "Don't show this again" inside the popup.
		_G.AutoDeleteDB = _G.AutoDeleteDB or {}
		_G.AutoDeleteDB.welcomeDismissed = false
		ShowWelcomePopup()
		return
	end
	if arg == "process" then
		-- Toggle the Process Bags standalone panel. Same effect as clicking
		-- the "Open Panel" button on Tools tab Card 1.
		if _G.AutoDelete_ToggleProcessPanel then
			_G.AutoDelete_ToggleProcessPanel()
		end
		return
	end
	if arg == "report" then
		if _G.AutoDelete_ShowDiagnosticReport then _G.AutoDelete_ShowDiagnosticReport() end
		return
	end
	if arg == "processdebug" then
		if _G.AutoDelete_ShowProcessDebugReport then _G.AutoDelete_ShowProcessDebugReport() end
		return
	end
	if arg == "processdebug clear" then
		if _G.AutoDelete_ClearProcessDebugCache then _G.AutoDelete_ClearProcessDebugCache() end
		if _G.AutoDelete_RefreshProcessPanel then _G.AutoDelete_RefreshProcessPanel() end
		print("|cffff8000[AutoDelete]|r Process Bags diagnostic caches cleared.")
		return
	end
	if arg == "de history" then
		if _G.AutoDelete_ShowDEHistory then _G.AutoDelete_ShowDEHistory() end
		return
	end
	if arg == "de history clear" then
		if _G.AutoDelete_ClearProcessActionHistory then
			_G.AutoDelete_ClearProcessActionHistory("disenchant")
		end
		print("|cffff8000[AutoDelete]|r Disenchant history cleared for this session.")
		return
	end
	if arg == "history" then
		if _G.AutoDelete_ShowDecisionHistory then _G.AutoDelete_ShowDecisionHistory() end
		return
	end
	if arg == "history clear" then
		if _G.AutoDelete_ClearDecisionHistory then _G.AutoDelete_ClearDecisionHistory() end
		print("|cffff8000[AutoDelete]|r decision history cleared for this session.")
		return
	end
	if arg == "debug" then
		-- Toggle the sell-decision debug trace. When on, every item that
		-- sells via the auto-rules prints its inputs (id, quality, ilvl,
		-- equipSlot, itemClass, isWeaponSlot, bind status, sellReason).
		_G.AutoDelete_DebugSell = not _G.AutoDelete_DebugSell
		if _G.AutoDelete_DebugSell then
			print("|cffff8000[AutoDelete]|r sell debug |cff00ff00ON|r - every auto-sell will now print its decision inputs.")
		else
			print("|cffff8000[AutoDelete]|r sell debug |cffff5555OFF|r.")
		end
		return
	end
	if arg == "perf" then
		AutoDelete_PerfToggle()
		return
	end
	if arg == "perf report" then
		AutoDelete_PerfReport()
		return
	end
	if arg == "perf reset" then
		AutoDelete_PerfReset()
		return
	end
	-- v3.20 frame-level spike debug. /del spike [on|off|<ms>|report|clear]
	-- with no arg, prints current state. See _G.AutoDelete_SetSpikeDebug
	-- and AutoDelete_SpikeRecord for the underlying mechanism.
	if arg == "spike" then
		print(string.format(
			"|cffff8000[AutoDelete SPIKE]|r state=%s threshold=%dms ring=%d/%d cooldown=%.1fs",
			_G.AutoDelete_SpikeDebug and "|cff00ff00ON|r" or "|cffff5555OFF|r",
			_G.AutoDelete_SpikeThresholdMs,
			(function() local n = 0 for _ in pairs(_G.AutoDelete_SpikeRing) do n = n + 1 end return n end)(),
			_G.AutoDelete_SpikeRingCap,
			_G.AutoDelete_SpikeChatCooldown
		))
		print("  /del spike on | off | <ms> | report | chat | clear")
		return
	end
	if arg == "spike on" then
		_G.AutoDelete_SetSpikeDebug(true)
		return
	end
	if arg == "spike off" then
		_G.AutoDelete_SetSpikeDebug(false)
		return
	end
	if arg == "spike report" then
		_G.AutoDelete_SpikeReport()
		return
	end
	if arg == "spike chat" then
		_G.AutoDelete_SpikeReportChat()
		return
	end
	if arg == "spike clear" then
		_G.AutoDelete_SpikeClear()
		return
	end
	-- v3.20 ElvUI hook A/B gate (diagnostic only -- not exposed in the
	-- options panel). When OFF, AutoDelete's ElvUI bag-dot work is
	-- skipped at the top of the UpdateSlot hook; ElvUI itself still
	-- runs as normal. Use to isolate whether our per-slot work is
	-- amplifying pickup stutter during loot bursts.
	if arg == "elvuihook" then
		print(string.format(
			"|cffff8000[AutoDelete]|r ElvUI bag hook is %s. /del elvuihook on | off",
			_G.AutoDelete_ElvUIHookDisabled and "|cffff5555OFF (skipping AutoDelete work)|r"
				or "|cff00ff00ON|r"
		))
		return
	end
	if arg == "elvuihook on" then
		_G.AutoDelete_ElvUIHookDisabled = false
		print("|cffff8000[AutoDelete]|r ElvUI bag hook |cff00ff00ON|r -- affix dots will draw on ElvUI bag slots.")
		-- Trigger a full refresh so dots reappear on currently-visible
		-- ElvUI bag slots without the user needing to open/close bags.
		if _G.AutoDelete_RefreshAffixDots then _G.AutoDelete_RefreshAffixDots() end
		return
	end
	if arg == "elvuihook off" then
		_G.AutoDelete_ElvUIHookDisabled = true
		print("|cffff8000[AutoDelete]|r ElvUI bag hook |cffff5555OFF|r -- AutoDelete will skip ALL per-slot work in ElvUI's UpdateSlot. Affix dots will NOT update on ElvUI bags until you turn this back on. Diagnostic use only.")
		return
	end
	-- v3.20 /del goblin: live diagnostic for the bag-full auto-summon
	-- gate. Prints what state the Goblin defer logic last saw so the
	-- user can see WHY Goblin did or didn't fire.
	if arg == "goblin" then
		local now = GetTime()
		local lines = {
			"AutoDelete Goblin Merchant diagnostic",
			"debugBuild=goblin-priority-v3-2026-05-30"
		}
		local p = cachedProfile
		table.insert(lines, string.format("freeSlots=%s   threshold=%s   armed=%s   since=%s",
			tostring(ComputeTotalFreeSlots and ComputeTotalFreeSlots() or "unknown"),
			tostring(GetGoblinBagThreshold and GetGoblinBagThreshold(p) or "unknown"),
			tostring(bagsFullArmed),
			bagsFullSince and string.format("%.1fs ago", now - bagsFullSince) or "inactive"
		))
		table.insert(lines, string.format("bagsBelowAt=%.1fs ago   lastDeleteWalk=%.1fs ago (enqueued=%d)",
			((_G.AutoDelete_BagsBelowAt or 0) == 0) and -1 or (now - _G.AutoDelete_BagsBelowAt),
			((_G.AutoDelete_LastDeleteWalkAt or 0) == 0) and -1 or (now - _G.AutoDelete_LastDeleteWalkAt),
			_G.AutoDelete_LastDeleteWalkEnqueued or 0
		))
		table.insert(lines, string.format("lastDrainPop=%.1fs ago   lastEnqueue=%.1fs ago   queueLen=%d",
			((_G.AutoDelete_LastDrainPopAt or 0) == 0) and -1 or (now - _G.AutoDelete_LastDrainPopAt),
			((_G.AutoDelete_LastEnqueueAt or 0) == 0) and -1 or (now - _G.AutoDelete_LastEnqueueAt),
			#((_G.AutoDelete_DeleteQueue or {}).items or {})
		))
		table.insert(lines, string.format("lastFireReason=%s   lastDeferReason=%s",
			tostring(_G.AutoDelete_GoblinLastFireReason or "none"),
			tostring(_G.AutoDelete_GoblinLastDeferReason or "none")
		))
		table.insert(lines, string.format("lastSummonResult=%s   attempt=%s   confirmPending=%s",
			tostring(_G.AutoDelete_GoblinLastSummonResult or "none"),
			tostring(_G.AutoDelete_GoblinLastSummonAttempt or "none"),
			tostring(_G.AutoDelete_GoblinConfirmPending or false)
		))
		table.insert(lines, string.format("autoBackoff=%s   backoffLeft=%s",
			tostring(_G.AutoDelete_GoblinAutoBackoffActive and _G.AutoDelete_GoblinAutoBackoffActive() or false),
			(now < (_G.AutoDelete_GoblinAutoBackoffUntil or 0))
				and string.format("%.1fs", (_G.AutoDelete_GoblinAutoBackoffUntil or 0) - now)
				or "inactive"
		))
		table.insert(lines, string.format("lastFireAt=%s",
			((_G.AutoDelete_GoblinLastFireAt or 0) == 0)
				and "never (this session)"
				or string.format("%.1fs ago", now - _G.AutoDelete_GoblinLastFireAt)
		))
		table.insert(lines, "Negative \"ago\" values = event hasn't happened this session.")
		if _G.AutoDelete_ShowReportWindow then
			_G.AutoDelete_ShowReportWindow(table.concat(lines, "\n"), "Goblin Summon Diagnostic")
		else
			print("|cffff8000[AutoDelete]|r Goblin diagnostic is ready, but the report window is unavailable.")
		end
		return
	end
	-- v3.20 /del bench: auto-arming benchmark harness. One macro, hit it
	-- to start. Auto-finalizes 5s after bag activity stops. See the
	-- "Bench harness" block above for the state machine + save semantics.
	if arg == "bench" then
		_G.AutoDelete_BenchToggle()
		return
	end
	-- Explicit subcommands for deterministic macro binding (vs smart toggle).
	if arg == "bench start" then
		local B = _G.AutoDelete_Bench
		if B and B.state then
			print(string.format(
				"|cffff8000[AutoDelete BENCH]|r already %s ('%s'). Use /del bench stop or /del bench cancel.",
				B.state, tostring(B.name)
			))
		else
			_G.AutoDelete_BenchArm()
		end
		return
	end
	if arg == "bench stop" then
		local B = _G.AutoDelete_Bench
		if not B or not B.state then
			print("|cffff8000[AutoDelete BENCH]|r not active. /del bench start to begin.")
		elseif B.state == "armed" then
			print("|cffff8000[AutoDelete BENCH]|r still armed (no activity captured). Use /del bench cancel to abort, or wait for loot to start it.")
		else
			print("|cffff8000[AutoDelete BENCH]|r force-finalizing '" .. tostring(B.name) .. "' (manual stop).")
			_G.AutoDelete_BenchFinalize()
		end
		return
	end
	if arg == "bench cancel" then
		local B = _G.AutoDelete_Bench
		if not B or not B.state then
			print("|cffff8000[AutoDelete BENCH]|r not active. Nothing to cancel.")
		else
			print("|cffff8000[AutoDelete BENCH]|r |cffff5555CANCELED|r '" .. tostring(B.name) .. "' -- no data saved.")
			B.state = nil
			B.name = nil
			B.armedAt = 0
			B.startedAt = 0
			B.lastBagUpdateAt = 0
			B.configSnap = nil
		end
		return
	end
	if arg == "bench list" then
		_G.AutoDelete_BenchList()
		return
	end
	if arg == "bench compare" then
		_G.AutoDelete_BenchCompare(nil, nil)  -- auto-pick last two
		return
	end
	do
		local a, b = arg:match("^bench%s+compare%s+(%S+)%s+(%S+)$")
		if a then
			_G.AutoDelete_BenchCompare(a, b)
			return
		end
		local single = arg:match("^bench%s+show%s+(%S+)$")
		if single then
			_G.AutoDelete_ShowBenchReport(single)
			return
		end
		local delName = arg:match("^bench%s+delete%s+(%S+)$")
		if delName then
			_G.AutoDelete_BenchDelete(delName)
			return
		end
		-- /del bench <name>  -> arm with explicit name (if not a subcommand above)
		local explicit = arg:match("^bench%s+(%S+)$")
		if explicit and explicit ~= "list" and explicit ~= "compare"
			and explicit ~= "show" and explicit ~= "delete" then
			_G.AutoDelete_BenchArm(explicit)
			return
		end
	end
	do
		local ms = arg:match("^spike%s+(%d+)$")
		if ms then
			local n = tonumber(ms)
			if n and n >= 5 and n <= 500 then
				_G.AutoDelete_SpikeThresholdMs = n
				print(string.format("|cffff8000[AutoDelete SPIKE]|r threshold set to %dms.", n))
			else
				print("|cffff8000[AutoDelete SPIKE]|r threshold must be between 5 and 500 ms.")
			end
			return
		end
	end
	if arg == "affix" then
		if _G.AutoDelete_ScanLearnedAffixes then
			_G.AutoDelete_ScanLearnedAffixes()
		else
			print("|cffff8000[AutoDelete]|r Learned Affixes window not available. Try again in a moment.")
		end
		return
	end
	if arg == "scav" or arg == "pet" or arg == "pos" then
		-- Diagnostic: dump Greedy Scavenger summon and stuck-detection state.
		-- `/del scav` is the clear command; `/del pet` and `/del pos` remain
		-- aliases for older diagnostics/macros.
		local p = cachedProfile
		local now = GetTime()
		local idx, scavUp, cId = FindCompanionById(SCAVENGER_CREATURE_ID, "greedy scavenger")
		if cId then SCAVENGER_CREATURE_ID = cId end
		local inCombat = (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false
		local mounted = IsPlayerMountedOrFlying()
		local combatAllowed = (_G.AutoDelete_ScavengerCombatAllowed and _G.AutoDelete_ScavengerCombatAllowed(p)) and true or false
		local lines = {
			"AutoDelete Greedy Scavenger diagnostic",
			"debugBuild=scav-priority-v3-2026-05-30"
		}

		if _G.AutoDelete_GetActiveTrackedPet then
			table.insert(lines, "activeTracked=" .. tostring(_G.AutoDelete_GetActiveTrackedPet())
				.. "  summonPending=" .. tostring(summonPending))
		end

		table.insert(lines, "companionFound=" .. tostring(idx ~= nil)
			.. "  summoned=" .. tostring(scavUp)
			.. "  creatureId=" .. tostring(SCAVENGER_CREATURE_ID or "unknown"))

		table.insert(lines, "inCombat=" .. tostring(inCombat)
			.. "  mounted=" .. tostring(mounted)
			.. "  combatAllowed=" .. tostring(combatAllowed))

		if p then
			table.insert(lines, "enabled=" .. tostring(p.enabled)
				.. "  summonScavenger=" .. tostring(p.summonScavenger)
				.. "  onlyCombat=" .. tostring(p.summonOnlyInCombat))
			table.insert(lines, "afterSell=" .. tostring(p.summonAfterSell)
				.. "  afterVendorClose=" .. tostring(p.summonAfterClose)
				.. "  hideSpam=" .. tostring(p.hideGreedySpam))
		end

		table.insert(lines, string.format("lastScavCall=%s   lastSummonAt=%s",
			((lastSummonCallAt.scavenger or 0) == 0) and "never"
				or string.format("%.1fs ago", now - lastSummonCallAt.scavenger),
			(lastSummonAt == 0) and "never" or string.format("%.1fs ago", now - lastSummonAt)
		))
		table.insert(lines, "scavResult=" .. tostring(_G.AutoDelete_ScavengerLastSummonResult)
			.. "  attempt=" .. tostring(_G.AutoDelete_ScavengerLastSummonAttempt)
			.. "  confirmPending=" .. tostring(_G.AutoDelete_ScavengerConfirmPending))
		table.insert(lines, "triggerReason=" .. tostring(_G.AutoDelete_ScavengerLastTriggerReason))
		table.insert(lines, "summonOwner=" .. tostring(_G.AutoDelete_CompanionSummonOwner)
			.. "  ownerUntil=" .. tostring(_G.AutoDelete_CompanionSummonOwnerUntil)
			.. "  pendingAfterCompanion=" .. tostring(_G.AutoDelete_PendingScavengerAfterCompanion)
			.. "  pendingAfterBags=" .. tostring(_G.AutoDelete_PendingScavengerAfterBags))
		table.insert(lines, string.format("userDismissGrace=%s   lastCompanionUpdate=%s",
			(userDismissUntil > now) and string.format("%.1fs left", userDismissUntil - now) or "inactive",
			(lastCompanionUpdate == 0) and "never" or string.format("%.1fs ago", now - lastCompanionUpdate)
		))
		table.insert(lines, "lastMountState=" .. tostring(lastMountState)
			.. "  dismissedDueToMount=" .. tostring(dismissedDueToMount))

		if _G.AutoDelete_GetScavLootChatAt then
			local lastChat = _G.AutoDelete_GetScavLootChatAt() or 0
			if lastChat > 0 then
				table.insert(lines, string.format("lastScavLootChat=%.1fs ago", now - lastChat))
			else
				table.insert(lines, "lastScavLootChat=never")
			end
		end

		-- Count recent player loots inside the window.
		local windowCount = 0
		local oldestInWindow = nil
		if recentPlayerLootTimes then
			for _, t in ipairs(recentPlayerLootTimes) do
				if (now - t) <= LOOT_STUCK_WINDOW then
					windowCount = windowCount + 1
					if not oldestInWindow then oldestInWindow = t end
				end
			end
		end
		table.insert(lines, string.format("playerLootsInWindow=%d/%d over %ds",
			windowCount, LOOT_STUCK_PLAYER_MIN, LOOT_STUCK_WINDOW))
		if oldestInWindow then
			table.insert(lines, string.format("oldestPlayerLoot=%.1fs ago", now - oldestInWindow))
		end

		local stuckEval = activeTracked == "scavenger"
			and combatAllowed
			and not mounted
			and windowCount >= LOOT_STUCK_PLAYER_MIN
		local lastChat = (_G.AutoDelete_GetScavLootChatAt and _G.AutoDelete_GetScavLootChatAt()) or 0
		local wouldResummon = stuckEval and oldestInWindow and lastChat < oldestInWindow
		table.insert(lines, "stuckEvalReady=" .. tostring(stuckEval)
			.. "  wouldResummonNow=" .. tostring(wouldResummon))
		table.insert(lines, string.format("legacy: player loots in last %ds: %d (need %d to evaluate)",
			LOOT_STUCK_WINDOW, windowCount, LOOT_STUCK_PLAYER_MIN))
		if oldestInWindow then
			table.insert(lines, string.format("legacy: oldest player loot in window: %.1fs ago", now - oldestInWindow))
		end
		if _G.AutoDelete_ShowReportWindow then
			_G.AutoDelete_ShowReportWindow(table.concat(lines, "\n"), "Scavenger Summon Diagnostic")
		else
			print("|cffff8000[AutoDelete]|r Scavenger diagnostic is ready, but the report window is unavailable.")
		end
		return
	end
	if arg == "help" or arg == "?" or arg == "commands" then
		-- List every /del subcommand with a one-line description so the
		-- player doesn't have to grep source or remember diagnostic
		-- commands like `/del perf` when they need them. Grouped by
		-- purpose: panel/action, then mode toggles, then diagnostics.
		-- Color scheme: orange brand prefix, green command name, default
		-- text for the description. Keep each line short enough that the
		-- default chat frame width doesn't wrap (~80 visible chars).
		local function row(cmd, desc)
			print("  |cff00ff00" .. cmd .. "|r  -- " .. desc)
		end
		print("|cffff8000[AutoDelete]|r commands:")
		row("/del",              "open / close the settings panel")
		row("/del help",         "show this list (also: /del ? or /del commands)")
		print(" ")
		row("/del clean",        "remove duplicate or conflicting item-list entries")
		row("/del sell",         "run a sell pass at the open vendor right now")
		row("/del process",      "toggle the Process Bags window (DE / Mill / Prospect / Open)")
		row("/del report",       "open a copyable diagnostic report, including recipe filters")
		row("/del processdebug", "open a Process Bags gate-by-gate diagnostic, including recipes")
		row("/del de history",   "open recent One-Key Disenchant actions")
		row("/del history",      "open recent sell / delete / keep decisions, including recipes")
		row("/del audit",        "open a copyable item list audit")
		row("/del setup",        "re-open the first-time setup / welcome popup")
		print(" ")
		row("/del affix",        "open the Learned / Unlearned affix list")
		print(" ")
		row("/del perf",         "toggle perf instrumentation -- USE THIS TO DIAGNOSE LAG")
		row("/del perf report",  "print perf stats collected since `/del perf` turned on")
		row("/del perf reset",   "clear perf stats and start counting from zero")
		row("/del debug",        "toggle the per-item auto-sell decision trace")
		row("/del goblin",       "open Goblin Merchant summon report")
		row("/del scav",         "open Scavenger summon / stuck-detection report")
		row("/del pet",          "alias for /del scav (also: /del pos)")
		print("|cffff8000[AutoDelete]|r lag diagnosis: run |cff00ff00/del perf|r before the next loot burst,")
		print("|cffff8000           |r let it run for a few seconds, then |cff00ff00/del perf report|r.")
		return
	end
	_G.AutoDelete_ToggleOptionsPanel()
end
