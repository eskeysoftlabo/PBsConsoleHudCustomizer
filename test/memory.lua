-- How much garbage the add-on makes per update, and whether anything it keeps grows.
--
--   lua test/memory.lua
--
-- The harness's stand-in controls build a Lua table on every write; on a console those writes
-- are C calls and allocate nothing. So the stand-ins are replaced here with versions that reuse
-- their tables, and what is left is the add-on's own garbage. Then each style runs a long fight
-- and reports: garbage per update (with the collector stopped), memory kept after a full collect,
-- and how many controls exist -- controls are never freed by the client, so that number must stop
-- growing once every piece a style needs has been built.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/") or ".")
ADDON_DIR = HERE .. "/.."
dofile(HERE .. "/harness.lua")

-- ---- allocation-free stand-ins ----
local Control = getmetatable(MakeControl("probe", GuiRoot, "control")).__index
local function Slot(t, i)
	local v = t[i]
	if not v then v = {}; t[i] = v end
	return v
end
function Control:ClearAnchors() self.anchorCount = 0; for i = #self.anchors, 1, -1 do self.anchors[i] = nil end end
function Control:SetAnchor(point, relativeTo, relativePoint, offsetX, offsetY, constrains)
	self.anchorPool = self.anchorPool or {}
	local n = #self.anchors + 1
	local a = Slot(self.anchorPool, n)
	a.point, a.relativeTo, a.relativePoint, a.offsetX, a.offsetY, a.constrains = point, relativeTo, relativePoint or point, offsetX or 0, offsetY or 0, constrains
	self.anchors[n] = a
end
function Control:SetDimensions(w, h) self.width, self.height = w, h end
function Control:SetColor(r, g, b, a)
	local c = self.color or {}; self.color = c
	c[1], c[2], c[3], c[4] = r, g, b, a
end
function Control:SetVertexColors(point, r, g, b, a)
	self.vertices = self.vertices or {}
	local v = Slot(self.vertices, point)
	v[1], v[2], v[3], v[4] = r, g, b, a
end
function Control:SetGradientColors(r, g, b, a, r2, g2, b2, a2)
	local t = self.gradient or {}; self.gradient = t
	t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8] = r, g, b, a, r2, g2, b2, a2
end

function Control:SetCenterColor(r, g, b, a)
	local t = self.centerColor or {}; self.centerColor = t
	t[1], t[2], t[3], t[4] = r, g, b, a
end
function Control:SetEdgeColor(r, g, b, a)
	local t = self.edgeColor or {}; self.edgeColor = t
	t[1], t[2], t[3], t[4] = r, g, b, a
end
local POWER_COLOURS = { [1] = { 0.7, 0.2, 0.2 }, [2] = { 0.2, 0.4, 0.8 }, [4] = { 0.3, 0.6, 0.2 } }
function GetInterfaceColor(colorType, powerType)
	if colorType ~= INTERFACE_COLOR_TYPE_POWER_START then return 1, 1, 1, 1 end
	local c = POWER_COLOURS[powerType]
	if not c then return 1, 1, 1, 1 end
	return c[1], c[2], c[3], 1
end
-- A stand-in's own tables are made the first time it is written to; made up front here, so a
-- pooled piece used for the first time late in a run is not counted as the add-on keeping memory.
local create = WINDOW_MANAGER.CreateControl
WINDOW_MANAGER.CreateControl = function(manager, name, parent, kind)
	local control = create(manager, name, parent, kind)
	control.anchorPool = { {}, {} }
	control.anchors[1], control.anchors[2] = 0, 0
	control.anchors[1], control.anchors[2] = nil, nil
	control.vertices = { [1] = {}, [2] = {}, [4] = {}, [8] = {} }
	control.color, control.gradient, control.centerColor, control.edgeColor = {}, {}, {}, {}
	control.drawLevel, control.anchorCount = 0, 0
	return control
end

BuildAttributeBars()
Fire(EVENT_ADD_ON_LOADED, "PBsConsoleHudCustomizer")
Fire(EVENT_PLAYER_ACTIVATED)
local addon = PBS_CONSOLE_HUD_CUSTOMIZER
addon:Account().enabled = true
FireHud(SCENE_FRAGMENT_SHOWN)

local frame = 0
local function Frames(n)
	for _ = 1, n do
		frame = frame + 1
		SetPower(COMBAT_MECHANIC_FLAGS_HEALTH, 500 + math.floor(499 * math.sin(frame / 9)), 1000)
		SetPower(COMBAT_MECHANIC_FLAGS_MAGICKA, 500 + math.floor(499 * math.sin(frame / 13)), 1000)
		SetPower(COMBAT_MECHANIC_FLAGS_STAMINA, 500 + math.floor(499 * math.cos(frame / 11)), 1000)
		AdvanceFrame(50)
		RunUpdates()
	end
end
local function Controls()
	local n = 0
	for _ in pairs(CreatedControls) do n = n + 1 end
	return n
end

if MEMORY_SETUP_ONLY then return end

local results = {}
for _, style in ipairs(arg[1] and { arg[1] } or { "standard", "plain", "rounded", "neo", "liquidflow", "crystal" }) do
	addon:SetBarStyle(style)
	addon:Refresh()
	Frames(2000)
	collectgarbage("collect"); collectgarbage("collect")
	local base, controls = collectgarbage("count"), Controls()
	collectgarbage("stop")
	local before = collectgarbage("count")
	Frames(200)
	local perUpdate = (collectgarbage("count") - before) / 200
	collectgarbage("restart")
	Frames(6000)
	collectgarbage("collect"); collectgarbage("collect")
	-- Kept memory is measured over consecutive windows: a leak keeps growing, a one-time plateau
	-- (a table reaching its working size, a pooled piece's first use) does not. What is reported
	-- is the last window.
	local kept = collectgarbage("count") - base
	for _ = 1, 8 do
		local start = collectgarbage("count")
		Frames(6000)
		collectgarbage("collect"); collectgarbage("collect")
		kept = collectgarbage("count") - start
	end
	results[#results + 1] = { style = style, perUpdate = perUpdate, kept = kept, controls = Controls() - controls }
	print(string.format("%-10s garbage per update %6.2f KB   kept over the last 6000 %+6.1f KB   controls built after warm-up %d",
		style, perUpdate, results[#results].kept, results[#results].controls))
end
-- A long fight: casts landing on a stream of new targets as old ones die. The garbage per cast is
-- the event handlers' and the updates'; what is kept after tens of thousands of targets must not
-- grow with them.
if not arg[1] then
	addon:SetBarStyle("standard")
	addon:Refresh()
	for slot = 3, 8 do
		SetSlot(HOTBAR_CATEGORY_PRIMARY, slot, { name = "Skill" .. slot, icon = "icon" .. slot .. ".dds", id = 1000 + slot, remaining = 0, duration = 0 })
		SetAbilityDuration(1000 + slot, 10000)
	end
	local unit = 0
	local function Fight(n)
		for i = 1, n do
			local slot = 3 + i % 6
			FireCast(slot)
			local now = GetGameTimeMilliseconds()
			for t = 1, 6 do
				if t == 1 then unit = unit + 1 end
				FireEffect(EFFECT_RESULT_GAINED, "Skill" .. slot, "", (now + 10000) / 1000, t == 1 and unit or 100 + t, 1000 + slot, "icon" .. slot .. ".dds")
			end
			if i % 3 == 0 then FireEffect(EFFECT_RESULT_FADED, "Skill" .. slot, "", 0, unit - 3, 1000 + slot, "icon" .. slot .. ".dds") end
			AdvanceFrame(300)
			RunUpdates()
		end
	end
	Fight(2000)
	collectgarbage("collect"); collectgarbage("collect")
	local base = collectgarbage("count")
	collectgarbage("stop")
	local before = collectgarbage("count")
	Fight(200)
	local perCast = (collectgarbage("count") - before) / 200
	collectgarbage("restart")
	local from = unit
	Fight(20000)
	collectgarbage("collect"); collectgarbage("collect")
	print(string.format("a fight   garbage per cast %6.2f KB   kept after 20000 casts on %d new targets %+6.1f KB",
		perCast, unit - from, collectgarbage("count") - base))
end
return results
