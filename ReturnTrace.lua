-- PBS_CONSOLE_HUD_CUSTOMIZER is nil if Main.lua bailed out early (e.g. already loaded).
if not PBS_CONSOLE_HUD_CUSTOMIZER then
	return
end

local addon = PBS_CONSOLE_HUD_CUSTOMIZER

-- ---------------------------------------------------------------------------------------
-- What happens to the attribute bars as they come back from a menu
--
-- A measurement, like Trace.lua. Two fixes for a flicker on the way back from a menu (1.27.3 and
-- 1.27.4) were reasoned out from the client's source and still left "a slight flicker", so this
-- records what really happens rather than a third guess (FINDINGS 64).
--
-- From the moment the bars' fragment starts to show, for 700 ms, every frame: whether the group, each
-- bar, its frame and background, and this add-on's own drawing are shown or hidden, how solid they
-- are, and what this add-on wrote. Only what changes is kept, with the time since the start, so a
-- flicker -- something that goes and comes back, or changes after the bars are already showing --
-- shows up as a line or two in "/pbhud plain trace".
--
-- It runs only in that window. Its lines are kept in a fixed set of tables, so it makes no garbage
-- beyond the text of what changed.
-- ---------------------------------------------------------------------------------------

local trace = {
	lines = {},
	count = 0,
	values = {},
	writes = {},
}
addon.returnTrace = trace

local WINDOW_MS = 700
local MAX_LINES = 48

local Round = addon.Round

local function Now()
	return GetFrameTimeMilliseconds and GetFrameTimeMilliseconds() or 0
end

local function Lookup(name)
	local control = _G[name]
	if type(control) ~= "table" and type(control) ~= "userdata" then
		return nil
	end
	return control
end

function trace:Add(text)
	if self.count >= MAX_LINES then
		self.truncated = true
		return
	end
	self.count = self.count + 1
	self.lines[self.count] = string.format("+%3d %s", Round(Now() - (self.started or Now())), text)
end

-- Something that is either on or off: recorded each time it flips.
function trace:Flag(key, value)
	value = value and true or false
	local old = self.values[key]
	if old ~= value then
		if old ~= nil then
			self:Add(string.format("%s %s", key, value and "on" or "off"))
		elseif self.initial then
			self.initial[#self.initial + 1] = string.format("%s %s", key, value and "on" or "off")
		end
		self.values[key] = value
	end
end

-- A number that animates: recorded only when it moves a quarter of the way, or reverses, so a fade
-- in is two or three lines and a dip and recovery stands out.
function trace:Level(key, value)
	if type(value) ~= "number" then
		return
	end
	local old = self.values[key]
	local direction = self.values[key .. "~"]
	if old == nil then
		self.values[key] = value
		if self.initial then
			self.initial[#self.initial + 1] = string.format("%s %.2f", key, value)
		end
		return
	end
	local moved = value - old
	local reversed = direction and moved ~= 0 and (moved > 0) ~= direction
	if math.abs(moved) >= 0.25 or (reversed and math.abs(moved) >= 0.05) or (value ~= old and (value == 0 or value == 1)) then
		self:Add(string.format("%s %.2f%s", key, value, reversed and " (back)" or ""))
		self.values[key] = value
		if moved ~= 0 then
			self.values[key .. "~"] = moved > 0
		end
	end
end

local function Shown(control)
	if not control or type(control.IsHidden) ~= "function" then
		return nil
	end
	local ok, hidden = pcall(control.IsHidden, control)
	return ok and not hidden or nil
end

local function Alpha(control)
	if not control or type(control.GetAlpha) ~= "function" then
		return nil
	end
	local ok, alpha = pcall(control.GetAlpha, control)
	return ok and alpha or nil
end

function trace:Sample()
	local plain = addon.plain
	local group = Lookup("ZO_PlayerAttribute")
	self:Flag("group shown", Shown(group))
	self:Level("group alpha", Alpha(group))
	if plain then
		self:Flag("held back", plain.holding)
		self:Flag("drawing", plain.running)
		for _, bar in ipairs(plain.bars) do
			local key = bar.key
			local container = Lookup(bar.container)
			self:Flag(key .. " shown", Shown(container))
			self:Level(key .. " alpha", Alpha(container))
			self:Flag(key .. " frame", Shown(Lookup(bar.container .. "FrameCenter")))
			self:Flag(key .. " background", Shown(Lookup(bar.container .. "BgContainer")))
			local first = bar.controls[1]
			self:Level(key .. " fill alpha", Alpha(Lookup(first.name)))
			local group = plain.effectGroups and plain.effectGroups[first.name]
			if group then
				self:Flag(key .. " effect", Shown(group.control))
				-- How much of the effect is drawn, in steps, so it vanishing or jumping shows.
				local pieces = group.painter.used or 0
				local step = pieces == 0 and 0 or (pieces < 10 and 1 or 2)
				local old = self.values[key .. " pieces"]
				if old ~= step then
					if old ~= nil then
						self:Add(string.format("%s effect pieces %d", key, pieces))
					end
					self.values[key .. " pieces"] = step
				end
			end
			local overlay = plain.overlays and plain.overlays[first.name]
			if overlay then
				self:Flag(key .. " rectangle", Shown(overlay.control))
			end
		end
	end
end

-- A write by this add-on inside the window: the first of each kind, and how many there were.
function trace:Wrote(what)
	if not self.started then
		return
	end
	local seen = self.writes[what]
	if not seen then
		self.writes[what] = 1
		self:Add("wrote " .. tostring(what))
	else
		self.writes[what] = seen + 1
	end
end

function trace:Event(text)
	if self.started then
		self:Add(text)
	end
end

function trace:Begin(reason)
	if not EVENT_MANAGER or type(EVENT_MANAGER.RegisterForUpdate) ~= "function" then
		return
	end
	self:Finish()
	for index = self.count, 1, -1 do
		self.lines[index] = nil
	end
	self.count, self.truncated = 0, false
	for key in pairs(self.values) do
		self.values[key] = nil
	end
	for key in pairs(self.writes) do
		self.writes[key] = nil
	end
	self.started = Now()
	self.style = addon:BarStyle()
	self.returns = (self.returns or 0) + 1
	self:Add(reason)
	-- What everything was at the start, on as few lines as will do.
	self.initial = {}
	self:Sample()
	local initial = self.initial
	self.initial = nil
	for first = 1, #initial, 6 do
		self:Add("at start: " .. table.concat(initial, ", ", first, math.min(#initial, first + 5)))
	end
	-- Every frame for the window, then off.
	EVENT_MANAGER:RegisterForUpdate(addon.name .. "ReturnTrace", 0, function()
		if Now() - trace.started > WINDOW_MS then
			trace:Finish()
		else
			trace:Sample()
		end
	end)
	self.running = true
end

function trace:Finish()
	if not self.running then
		return
	end
	EVENT_MANAGER:UnregisterForUpdate(addon.name .. "ReturnTrace")
	self.running = false
	self.started = nil
end

function trace:Print()
	local Line = addon.Line
	if self.count == 0 then
		Line("|cFF69B4%s|r -- nothing recorded yet. Open a menu, close it, and run this again.", addon.title)
		return
	end
	Line("|cFF69B4%s|r -- the bars coming back from a menu (return %d, style %s), ms from the start:",
		addon.title, self.returns or 0, tostring(self.style))
	for index = 1, self.count do
		Line("  %s", self.lines[index])
	end
	if self.truncated then
		Line("  ... and more, not kept")
	end
	local counts = {}
	for what, n in pairs(self.writes) do
		counts[#counts + 1] = string.format("%s x%d", what, n)
	end
	if #counts > 0 then
		table.sort(counts)
		Line("  writes in the window: %s", table.concat(counts, ", "))
	end
end
