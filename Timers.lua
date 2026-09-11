-- PBS_CONSOLE_HUD_CUSTOMIZER is nil if Main.lua bailed out early (e.g. already loaded).
if not PBS_CONSOLE_HUD_CUSTOMIZER then
	return
end

local addon = PBS_CONSOLE_HUD_CUSTOMIZER

-- ---------------------------------------------------------------------------------------
-- The back bar, and the text on the icons
--
-- Two things are drawn on the skill bar:
--
--   the back bar   a row of the *other* weapon set's abilities, above the game's own bar. The
--                  game has a back row of its own (ZO_ActionBarTimer, the "back row" and
--                  "action bar timers" settings), but it only appears for the one slot whose
--                  effect is still running, and only while it is running. This one is always
--                  there, so both sets can be read at a glance.
--   the text       how long is left on each ability's effect, and how many targets are under
--                  it, on both bars.
--
-- Where the numbers come from:
--
--   GetActionSlotEffectTimeRemaining(slot, hotbarCategory)   -- ms, and it answers for the bar
--   GetActionSlotEffectDuration(slot, hotbarCategory)        --   you are NOT on as well
--   GetActionSlotEffectStackCount(slot, hotbarCategory)
--
-- These are the client's own, added with the action bar timers (actionbar.lua,
-- HandleSlotEffectUpdated), and they are the whole countdown: no guessing which effect came
-- from which cast, which is what makes an add-on like Action Duration Reminder two thousand
-- lines long. The one thing they do not answer is how many targets an effect is on, and there
-- is no API that does, so that part is counted here from EVENT_EFFECT_CHANGED -- see
-- "Counting targets".
--
-- Nothing of the client's is hooked or called. The labels and the back row are controls of our
-- own, built from the templates in Controls.xml and parented to the button they belong to, so
-- the action bar's own fragment fades and hides them with the bar.
-- ---------------------------------------------------------------------------------------

local timers = {
	back = {},
	labels = {},
}
addon.timers = timers

-- ACTION_BAR_FIRST_NORMAL_SLOT_INDEX is 2 and ACTION_BAR_SLOTS_PER_PAGE is 6, so the abilities
-- are slots 3 to 7 and the ultimate is 8. Read from the globals where they are there, so a
-- client that renumbers them is followed rather than guessed at.
local FIRST_SLOT = (ACTION_BAR_FIRST_NORMAL_SLOT_INDEX or 2) + 1
local LAST_SLOT = (ACTION_BAR_ULTIMATE_SLOT_INDEX or 7) + 1

local UPDATE_INTERVAL_MS = 100
local PRUNE_INTERVAL_MS = 3000

-- Below this the game does not show a timer of its own either (actionbar.lua,
-- MINIMUM_ACTION_BAR_TIMER_DISPLAYED_TIME_MS): a number that flashes up for half a second as an
-- ability is cast is noise.
local MINIMUM_SHOWN_MS = 1000

-- How many effects are remembered for the target count. Six abilities on each bar, a handful of
-- targets each; the cap is what stops a long fight in a crowd from growing the table for ever.
local MAX_TRACKED_EFFECTS = 96

local TIMER_COLOUR = { 0.86, 0.85, 0.13 }
local COUNT_COLOUR = { 1, 1, 1 }

local Round = addon.Round

-- ---------------------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------------------

addon.MIN_TEXT_SIZE = 12
addon.MAX_TEXT_SIZE = 48
addon.DEFAULT_TIMER_SIZE = 27
addon.DEFAULT_COUNT_SIZE = 22

-- auto: only while the game is not already drawing its own numbers on the bar.
addon.TIMER_MODES = { "auto", "always", "never" }

function addon:Text()
	return self:Account().text
end

function addon:BackBar()
	return self:Account().backBar
end

function addon:TextSize(which)
	local text = self:Text()
	local size = text[which .. "Size"]
	local fallback = which == "timer" and self.DEFAULT_TIMER_SIZE or self.DEFAULT_COUNT_SIZE
	if type(size) ~= "number" then
		return fallback
	end
	return addon.Clamp(Round(size), self.MIN_TEXT_SIZE, self.MAX_TEXT_SIZE)
end

function addon:SetTextSize(which, value)
	self:Text()[which .. "Size"] = addon.Clamp(Round(value), self.MIN_TEXT_SIZE, self.MAX_TEXT_SIZE)
end

-- Whether the game is drawing its own countdown and stack count on the bar. Its setting is
-- SETTING_TYPE_UI / UI_SETTING_SHOW_ACTION_BAR_TIMERS, which an add-on can read but not write.
function addon:GameShowsBarTimers()
	if type(GetSetting_Bool) ~= "function" or not SETTING_TYPE_UI or not UI_SETTING_SHOW_ACTION_BAR_TIMERS then
		return false
	end
	local ok, value = pcall(GetSetting_Bool, SETTING_TYPE_UI, UI_SETTING_SHOW_ACTION_BAR_TIMERS)
	return ok and value == true
end

-- The game only ever draws its numbers on the bar you are on, so "auto" is about the front bar
-- alone: the back bar's numbers are always ours to draw.
function addon:ShowsTimerOn(isBackBar)
	if not self:Account().enabled then
		return false
	end
	local mode = self:Text().timerMode
	if mode == "never" then
		return false
	end
	if isBackBar then
		return true
	end
	if mode == "always" then
		return true
	end
	return not self:GameShowsBarTimers()
end

function addon:ShowsCount()
	return self:Account().enabled and self:Text().showCounts ~= false
end

function addon:BackBarEnabled()
	return self:Account().enabled and self:BackBar().enabled ~= false
end

-- ---------------------------------------------------------------------------------------
-- Counting targets
--
-- There is no API for "how many things are under this ability's effect", so the effects the
-- player applies are counted as they are reported: EVENT_EFFECT_CHANGED, filtered to the ones
-- the player is the source of, one entry per effect name with the units under it.
--
-- Matched to a slot by name, with the ability id as a second chance. That is a heuristic, and an
-- honest one: an effect usually carries the name of the ability that applied it, but a morph
-- that renames what it applies (or applies several) will not line up. The countdown does not
-- depend on it -- that comes from the client -- so at worst a target count is missing, never
-- wrong about the time.
-- ---------------------------------------------------------------------------------------

local effects = {}
local effectCount = 0
local idKeys = {}

local function Normalize(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	-- Gender and article markup ("^F", "^n") is part of the raw string and never part of what a
	-- slot is called.
	local plain = name:gsub("%^%a+", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if plain == "" then
		return nil
	end
	return plain:lower()
end

timers.Normalize = Normalize

local function DropOldest()
	local oldestKey, oldestTime = nil, nil
	for key, entry in pairs(effects) do
		if not oldestTime or entry.touched < oldestTime then
			oldestKey, oldestTime = key, entry.touched
		end
	end
	if oldestKey then
		effects[oldestKey] = nil
		effectCount = effectCount - 1
	end
end

function timers:Track(key, abilityId, unitKey, endMs, now)
	local entry = effects[key]
	if not entry then
		if effectCount >= MAX_TRACKED_EFFECTS then
			DropOldest()
		end
		entry = { units = {} }
		effects[key] = entry
		effectCount = effectCount + 1
	end
	entry.touched = now
	entry.units[unitKey] = endMs
	if type(abilityId) == "number" and abilityId > 0 then
		idKeys[abilityId] = key
	end
end

function timers:Forget(key, unitKey)
	local entry = effects[key]
	if not entry then
		return
	end
	entry.units[unitKey] = nil
	if next(entry.units) == nil then
		effects[key] = nil
		effectCount = effectCount - 1
	end
end

-- EVENT_EFFECT_CHANGED. The signature is the client's, and only a few of its arguments matter
-- here: what the effect is called, which unit it is on, when it ends, and whether it has just
-- gone away.
function timers:OnEffectChanged(_, changeType, _, effectName, unitTag, beginTime, endTime, _, _, _, _, _, _, _, unitId, abilityId)
	-- A group member's copy of a buff is the same effect on the same name; counting those would
	-- turn a self-buff into "12".
	if type(unitTag) == "string" and unitTag:find("group", 1, true) then
		return
	end
	local key = Normalize(effectName)
	if not key then
		return
	end
	local now = GetGameTimeMilliseconds and GetGameTimeMilliseconds() or 0
	local unitKey = (type(unitId) == "number" and unitId ~= 0) and unitId or (unitTag ~= "" and unitTag or "?")

	if changeType == EFFECT_RESULT_FADED then
		self:Forget(key, unitKey)
		return
	end
	-- endTime is in seconds on the game clock, and 0 for something that does not expire.
	local endMs = (type(endTime) == "number" and endTime > 0) and math.floor(endTime * 1000) or 0
	self:Track(key, abilityId, unitKey, endMs, now)
end

-- How many units are under this effect right now.
function timers:CountFor(key, abilityId, now)
	local entry = key and effects[key] or nil
	if not entry and type(abilityId) == "number" then
		local byId = idKeys[abilityId]
		entry = byId and effects[byId] or nil
	end
	if not entry then
		return 0
	end
	local count = 0
	for unitKey, endMs in pairs(entry.units) do
		if endMs == 0 or endMs > now then
			count = count + 1
		else
			entry.units[unitKey] = nil
		end
	end
	return count
end

function timers:Prune(now)
	for key, entry in pairs(effects) do
		local any = false
		for unitKey, endMs in pairs(entry.units) do
			if endMs ~= 0 and endMs <= now then
				entry.units[unitKey] = nil
			else
				any = true
			end
		end
		if not any and now - entry.touched > PRUNE_INTERVAL_MS then
			effects[key] = nil
			effectCount = effectCount - 1
		end
	end
end

function timers:Forget_All()
	effects = {}
	idKeys = {}
	effectCount = 0
end

-- ---------------------------------------------------------------------------------------
-- The controls
-- ---------------------------------------------------------------------------------------

local function Font(size)
	return string.format("$(GAMEPAD_BOLD_FONT)|%d|thick-outline", size)
end

function timers:FrontButton(slot)
	local control = _G["ActionButton" .. slot]
	if type(control) ~= "table" and type(control) ~= "userdata" then
		return nil
	end
	if type(control.SetAnchor) ~= "function" then
		return nil
	end
	return control
end

-- One pair of labels over the game's own button. Parented to the button, so it inherits its
-- hiding, its fading and any scale this add-on has put on the bar.
function timers:Labels(slot)
	local existing = self.labels[slot]
	if existing then
		return existing
	end
	local button = self:FrontButton(slot)
	if not button or type(CreateControlFromVirtual) ~= "function" then
		return nil
	end
	local ok, control = pcall(CreateControlFromVirtual, "PBsConsoleHudCustomizerLabels", button, "PBsConsoleHudCustomizerSlotLabels", slot)
	if not ok or not control then
		return nil
	end
	control:SetAnchor(TOPLEFT, button, TOPLEFT, 0, 0)
	control:SetAnchor(BOTTOMRIGHT, button, BOTTOMRIGHT, 0, 0)
	local pair = {
		control = control,
		timer = control:GetNamedChild("Timer"),
		count = control:GetNamedChild("Count"),
	}
	self.labels[slot] = pair
	self:StyleLabels(pair)
	return pair
end

-- One back bar slot, parented to the button of the same number on the game's bar so it follows
-- it wherever this add-on puts the bar.
function timers:BackSlot(slot)
	local existing = self.back[slot]
	if existing then
		return existing
	end
	local button = self:FrontButton(slot)
	if not button or type(CreateControlFromVirtual) ~= "function" then
		return nil
	end
	local ok, control = pcall(CreateControlFromVirtual, "PBsConsoleHudCustomizerBack", button, "PBsConsoleHudCustomizerBackBarSlot", slot)
	if not ok or not control then
		return nil
	end
	local entry = {
		control = control,
		icon = control:GetNamedChild("Icon"),
		timer = control:GetNamedChild("Timer"),
		count = control:GetNamedChild("Count"),
		button = button,
	}
	self.back[slot] = entry
	self:AnchorBackSlot(entry)
	self:StyleLabels(entry)
	return entry
end

function timers:StyleLabels(pair)
	if pair.timer then
		pair.timer:SetFont(Font(addon:TextSize("timer")))
		pair.timer:SetColor(TIMER_COLOUR[1], TIMER_COLOUR[2], TIMER_COLOUR[3], 1)
	end
	if pair.count then
		pair.count:SetFont(Font(addon:TextSize("count")))
		pair.count:SetColor(COUNT_COLOUR[1], COUNT_COLOUR[2], COUNT_COLOUR[3], 1)
	end
end

function timers:AnchorBackSlot(entry)
	local back = addon:BackBar()
	local gap = type(back.gap) == "number" and back.gap or 4
	local offsetX = type(back.offsetX) == "number" and back.offsetX or 0
	local scale = addon:BackBarScale() / 100
	entry.control:ClearAnchors()
	entry.control:SetAnchor(BOTTOM, entry.button, TOP, offsetX, -gap)
	entry.control:SetScale(scale)
end

function addon:BackBarScale()
	local scale = self:BackBar().scale
	if type(scale) ~= "number" then
		return 100
	end
	return addon.Clamp(Round(scale), self.MIN_SCALE, self.MAX_SCALE)
end

function addon:SetBackBarScale(value)
	self:BackBar().scale = addon.Clamp(Round(value), self.MIN_SCALE, self.MAX_SCALE)
end

-- Re-reads every setting that is baked into a control: the fonts and the back row's place.
function timers:Restyle()
	for _, pair in pairs(self.labels) do
		self:StyleLabels(pair)
	end
	for _, entry in pairs(self.back) do
		self:StyleLabels(entry)
		self:AnchorBackSlot(entry)
	end
end

function timers:HideAll()
	for _, pair in pairs(self.labels) do
		pair.control:SetHidden(true)
	end
	for _, entry in pairs(self.back) do
		entry.control:SetHidden(true)
	end
end

-- ---------------------------------------------------------------------------------------
-- Reading a slot
-- ---------------------------------------------------------------------------------------

local function SlotNumber(fn, slot, hotbar)
	if type(fn) ~= "function" then
		return 0
	end
	local ok, value = pcall(fn, slot, hotbar)
	if ok and type(value) == "number" then
		return value
	end
	return 0
end

local function SlotString(fn, slot, hotbar)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, value = pcall(fn, slot, hotbar)
	if ok and type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

function timers:SlotIsEmpty(slot, hotbar)
	if type(GetSlotType) ~= "function" then
		return false
	end
	local ok, slotType = pcall(GetSlotType, slot, hotbar)
	if not ok then
		return false
	end
	return slotType == (ACTION_TYPE_NOTHING or 0)
end

-- What to write on one slot: the time left, and how many targets are under it.
function timers:SlotText(slot, hotbar, now)
	local remaining = SlotNumber(GetActionSlotEffectTimeRemaining, slot, hotbar)
	local timerText = nil
	if remaining >= MINIMUM_SHOWN_MS then
		timerText = self:FormatTime(remaining)
	end

	local countText = nil
	local key = Normalize(SlotString(GetSlotName, slot, hotbar))
	local abilityId = SlotNumber(GetSlotBoundId, slot, hotbar)
	local count = self:CountFor(key, abilityId, now)
	local minimum = addon:Text().countFromOne and 1 or 2
	if count >= minimum then
		countText = tostring(count)
	end
	return timerText, countText
end

-- Seconds to the end, in the shape the game uses on the bar: a minute or more as whole minutes,
-- the last few seconds with one decimal, everything else as whole seconds.
function timers:FormatTime(ms)
	local seconds = ms / 1000
	if seconds >= 60 then
		return string.format("%dm", math.floor(seconds / 60))
	end
	if addon:Text().decimals ~= false and seconds < 10 then
		return string.format("%.1f", seconds)
	end
	return string.format("%d", math.floor(seconds + 0.5))
end

-- ---------------------------------------------------------------------------------------
-- The update
-- ---------------------------------------------------------------------------------------

function timers:BackHotbar()
	if type(GetActiveHotbarCategory) ~= "function" then
		return nil
	end
	local ok, active = pcall(GetActiveHotbarCategory)
	if not ok then
		return nil
	end
	-- Werewolf, a siege engine, a mount: the bar is not one of the weapon sets, and there is no
	-- other set to show. The game's own back row goes away for the same reason.
	if active == HOTBAR_CATEGORY_PRIMARY then
		return HOTBAR_CATEGORY_BACKUP, active
	end
	if active == HOTBAR_CATEGORY_BACKUP then
		return HOTBAR_CATEGORY_PRIMARY, active
	end
	return nil, active
end

local function SetText(label, text)
	if not label then
		return
	end
	if text then
		label:SetText(text)
		label:SetHidden(false)
	else
		label:SetHidden(true)
	end
end

function timers:Update()
	local now = GetGameTimeMilliseconds and GetGameTimeMilliseconds() or 0
	if now - (self.lastPrune or 0) > PRUNE_INTERVAL_MS then
		self.lastPrune = now
		self:Prune(now)
	end

	local backHotbar, activeHotbar = self:BackHotbar()
	local showTimer = addon:ShowsTimerOn(false)
	local showBackTimer = addon:ShowsTimerOn(true)
	local showCount = addon:ShowsCount()
	local backEnabled = addon:BackBarEnabled() and backHotbar ~= nil
	local showEmpty = addon:BackBar().showEmpty ~= false

	for slot = FIRST_SLOT, LAST_SLOT do
		-- The game's own bar.
		if showTimer or showCount then
			local pair = self:Labels(slot)
			if pair then
				local timerText, countText = self:SlotText(slot, activeHotbar, now)
				pair.control:SetHidden(false)
				SetText(pair.timer, showTimer and timerText or nil)
				SetText(pair.count, showCount and countText or nil)
			end
		elseif self.labels[slot] then
			self.labels[slot].control:SetHidden(true)
		end

		-- The other weapon set.
		if backEnabled then
			local entry = self:BackSlot(slot)
			if entry then
				local empty = self:SlotIsEmpty(slot, backHotbar)
				if empty and not showEmpty then
					entry.control:SetHidden(true)
				else
					local icon = SlotString(GetSlotTexture, slot, backHotbar)
					entry.icon:SetTexture(icon or "")
					entry.icon:SetHidden(icon == nil)
					entry.control:SetHidden(false)
					local timerText, countText = self:SlotText(slot, backHotbar, now)
					SetText(entry.timer, showBackTimer and timerText or nil)
					SetText(entry.count, showCount and countText or nil)
				end
			end
		elseif self.back[slot] then
			self.back[slot].control:SetHidden(true)
		end
	end
end

-- The loop only runs while the HUD is up and there is something to draw: a hundred-millisecond
-- update behind a menu would be work for nothing, and on console every frame of it is billed to
-- the pool every add-on shares.
function timers:Wanted()
	if not addon:Account().enabled then
		return false
	end
	-- Moving a slider in the settings panel calls Refresh, and the HUD is not up there: without
	-- this, a hundred-millisecond loop would run behind every menu the panel is reached through.
	-- It starts out true because the first apply happens on the HUD, before the fragment has had
	-- a state change to report.
	if self.hudShown == false then
		return false
	end
	return addon:ShowsTimerOn(false) or addon:ShowsTimerOn(true) or addon:ShowsCount() or addon:BackBarEnabled()
end

function timers:Start()
	if self.running or not self:Wanted() then
		return false
	end
	if not EVENT_MANAGER or type(EVENT_MANAGER.RegisterForUpdate) ~= "function" then
		return false
	end
	EVENT_MANAGER:RegisterForUpdate(addon.name .. "Timers", UPDATE_INTERVAL_MS, function()
		timers:Update()
	end)
	self.running = true
	self:Update()
	return true
end

function timers:Stop()
	if not self.running then
		return false
	end
	EVENT_MANAGER:UnregisterForUpdate(addon.name .. "Timers")
	self.running = false
	self:HideAll()
	return true
end

-- Called whenever a setting changes, and on every HUD show.
function timers:Refresh()
	self:Restyle()
	if self:Wanted() then
		if self.running then
			self:Update()
		else
			self:Start()
		end
	else
		self:Stop()
	end
end

function timers:OnHudStateChange(shown)
	self.hudShown = shown and true or false
	if shown then
		self:Refresh()
	else
		self:Stop()
	end
end

-- Registered on the add-on's own name, beside everyone else's handler for the same event, with
-- the client's own filter so only what the player applied is counted.
function timers:Register()
	if self.registered or not EVENT_MANAGER then
		return false
	end
	EVENT_MANAGER:RegisterForEvent(addon.name .. "Effects", EVENT_EFFECT_CHANGED, function(...)
		timers:OnEffectChanged(...)
	end)
	if type(EVENT_MANAGER.AddFilterForEvent) == "function" and REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE then
		pcall(EVENT_MANAGER.AddFilterForEvent, EVENT_MANAGER, addon.name .. "Effects", EVENT_EFFECT_CHANGED,
			REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER)
	end
	self.registered = true
	return true
end
