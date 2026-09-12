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
	shades = {},
	dimmed = {},
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

-- What to do about the countdown on the bar the player is on. The game draws one of its own
-- there when Settings > Interface > Action Bar Timers is on, at a size of its own that no add-on
-- can change -- so "draw ours as well" would mean two numbers on one icon.
--
--   addon   ours, and the game's own number faded out of the way. The default: it is the only
--           one of the three where the text size setting always does something.
--   both    ours and the game's, side by side.
--   game    the front bar is left to the game. The other weapon set still gets ours, because the
--           game never draws a number there at all.
--
-- The old names for these (auto / always / never) are migrated in Account().
addon.TIMER_MODES = { "addon", "both", "game" }

function addon:Text()
	return self:Account().text
end

function addon:BackBar()
	return self:Account().backBar
end

-- Where a size is kept. The other weapon set's row has its own pair of keys, and an unset one
-- means "whatever the bar you are on uses" -- the same shape as a position that has not been
-- moved yet. So the row follows the front bar until the player gives it a size of its own, and
-- an upgrade from a build that had one size for both changes nothing on screen.
local function SizeKey(which, isBack)
	if isBack then
		return "back" .. which:sub(1, 1):upper() .. which:sub(2) .. "Size"
	end
	return which .. "Size"
end

addon.SizeKey = SizeKey

function addon:TextSize(which, isBack)
	local text = self:Text()
	if isBack then
		local own = text[SizeKey(which, true)]
		if type(own) == "number" then
			return addon.Clamp(Round(own), self.MIN_TEXT_SIZE, self.MAX_TEXT_SIZE)
		end
	end
	local size = text[SizeKey(which, false)]
	if type(size) ~= "number" then
		return which == "timer" and self.DEFAULT_TIMER_SIZE or self.DEFAULT_COUNT_SIZE
	end
	return addon.Clamp(Round(size), self.MIN_TEXT_SIZE, self.MAX_TEXT_SIZE)
end

function addon:SetTextSize(which, value, isBack)
	self:Text()[SizeKey(which, isBack)] = addon.Clamp(Round(value), self.MIN_TEXT_SIZE, self.MAX_TEXT_SIZE)
end

-- True once the row has been given a size of its own.
function addon:TextSizeIsOwn(which)
	return type(self:Text()[SizeKey(which, true)]) == "number"
end

-- Back to following the bar you are on.
function addon:ClearBackTextSize(which)
	self:Text()[SizeKey(which, true)] = nil
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
function addon:TimerMode()
	local mode = self:Text().timerMode
	for _, known in ipairs(self.TIMER_MODES) do
		if mode == known then
			return mode
		end
	end
	return "addon"
end

function addon:ShowsTimerOn(isBackBar)
	if not self:Account().enabled then
		return false
	end
	-- The game never writes a number on the set you are not on, so that one is always ours.
	if isBackBar then
		return true
	end
	return self:TimerMode() ~= "game"
end

-- True while the game's own number on the front bar should be got out of the way, because ours is
-- going on the same spot.
--
-- Deliberately not conditional on GameShowsBarTimers(): fading a label the game is not drawing
-- anything on costs nothing, and reading that setting is the one part of this that can quietly
-- come back wrong -- which shows up as two numbers on one icon, which is what it was meant to
-- prevent. The setting is still read, for status to print.
function addon:DimsGameTimer()
	return self:ShowsTimerOn(false) and self:TimerMode() == "addon"
end

function addon:ShowsCount()
	return self:Account().enabled and self:Text().showCounts ~= false
end

function addon:BackBarEnabled()
	if not (self:Account().enabled and self:BackBar().enabled ~= false) then
		return false
	end
	-- Welded to one bar -- the Oakensoul Ring and anything like it, or a character that has not
	-- earned the second set yet. A row showing a set that cannot be swapped to is a row of
	-- nothing useful, so it goes on its own rather than by a setting.
	if self.WeaponSwapAvailable and not self:WeaponSwapAvailable() then
		return false
	end
	return true
end

-- ---------------------------------------------------------------------------------------
-- The shade over the icon
--
-- A Cooldown control of the add-on's own, given the ability's own icon and started with
-- CD_TYPE_VERTICAL_REVEAL. The engine then darkens the icon and wipes that darkness down it as
-- the time runs out: no work per frame here, and the sweep is exactly as long as the effect
-- because the client is the one counting.
--
-- Which way the sweep runs is the difference between CD_TIME_TYPE_TIME_UNTIL and
-- CD_TIME_TYPE_TIME_REMAINING -- one counts towards the end, the other away from it. The setting
-- is a direction rather than a time type for that reason: if a client build ever runs it the
-- other way, the player flips it and it is right again, with no round trip to a console.
-- ---------------------------------------------------------------------------------------

addon.SHADE_DIRECTIONS = { "down", "up" }

function addon:Shade()
	return self:Account().shade
end

function addon:ShadeEnabled()
	return self:Account().enabled and self:Shade().enabled ~= false
end

function addon:ShadeDarkness()
	local value = self:Shade().darkness
	if type(value) ~= "number" then
		return 60
	end
	return addon.Clamp(Round(value), 0, 100)
end

function addon:SetShadeDarkness(value)
	self:Shade().darkness = addon.Clamp(Round(value), 0, 100)
end

function addon:ShadeDirection()
	local direction = self:Shade().direction
	return direction == "up" and "up" or "down"
end

function addon:ShadeTimeType()
	-- "down" is the shade leaving the top of the icon first, which is what the effect running
	-- out should look like.
	if self:ShadeDirection() == "up" then
		return CD_TIME_TYPE_TIME_REMAINING
	end
	return CD_TIME_TYPE_TIME_UNTIL
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
local iconKeys = {}

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

-- An icon path, as a key. GetSlotTexture and the icon an effect reports are the same art, but
-- not always spelt the same way: one may carry a leading slash, and case is not to be trusted.
local function IconKey(path)
	if type(path) ~= "string" or path == "" then
		return nil
	end
	return (path:lower():gsub("^/", ""))
end

timers.IconKey = IconKey

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

function timers:Track(key, abilityId, icon, unitKey, endMs, now)
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
	if icon then
		iconKeys[icon] = key
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
function timers:OnEffectChanged(_, changeType, _, effectName, unitTag, beginTime, endTime, _, iconName, _, _, _, _, _, unitId, abilityId)
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
	self:Track(key, abilityId, IconKey(iconName), unitKey, endMs, now)
end

-- How many units are under this effect right now, and what it was matched by.
--
-- Three chances, because an effect does not have to carry the name of the ability that applied
-- it: the name, the ability id, and the icon. The icon is the one that catches a morph whose
-- effect is called something else -- the art is nearly always the ability's own.
function timers:CountFor(key, abilityId, icon, now)
	local entry, matchedBy = key and effects[key] or nil, "name"
	if not entry and type(abilityId) == "number" then
		local byId = idKeys[abilityId]
		entry = byId and effects[byId] or nil
		matchedBy = "id"
	end
	if not entry and icon then
		local byIcon = iconKeys[icon]
		entry = byIcon and effects[byIcon] or nil
		matchedBy = "icon"
	end
	if not entry then
		return 0, nil
	end
	local count = 0
	for unitKey, endMs in pairs(entry.units) do
		if endMs == 0 or endMs > now then
			count = count + 1
		else
			entry.units[unitKey] = nil
		end
	end
	return count, matchedBy
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
	iconKeys = {}
	effectCount = 0
end

-- ---------------------------------------------------------------------------------------
-- The controls
-- ---------------------------------------------------------------------------------------

local function Font(size)
	return string.format("$(GAMEPAD_BOLD_FONT)|%d|thick-outline", size)
end

-- ---------------------------------------------------------------------------------------
-- Building a control
--
-- From Controls.xml where the template is there, and from plain controls where it is not. The
-- fallback exists because the alternative is a silent nothing on a machine that costs a whole
-- session to test: a manifest that did not pick the XML up, or a client that would not parse it,
-- would otherwise leave no text and no row and no way to tell from the HUD. status says which of
-- the two was used.
-- ---------------------------------------------------------------------------------------

local FALLBACK_PARTS = {
	PBsConsoleHudCustomizerSlotLabels = {
		{ name = "Timer", kind = "label", point = "CENTER", relative = "CENTER", x = 0, y = 0 },
		{ name = "Count", kind = "label", point = "TOPLEFT", relative = "TOPLEFT", x = -2, y = -4 },
	},
	PBsConsoleHudCustomizerBackBarSlot = {
		{ name = "BG", kind = "texture", point = "CENTER", relative = "CENTER", x = 0, y = 0,
			file = "EsoUI/Art/ActionBar/Gamepad/gp_backrow_abilityFrame_BLANK.dds",
			width = 52, height = 68, coords = { 0, 0.8125, 0, 1.0625 }, level = 0 },
		{ name = "Icon", kind = "texture", point = "CENTER", relative = "CENTER", x = 0, y = 0,
			width = 44, height = 44, level = 1 },
		{ name = "Overlay", kind = "texture", point = "CENTER", relative = "CENTER", x = 0, y = 0,
			file = "EsoUI/Art/ActionBar/Gamepad/gp_backrow_abilityFrame_overlay.dds",
			width = 52, height = 68, coords = { 0, 0.8125, 0, 1.0625 }, level = 2 },
		{ name = "Shade", kind = "cooldown", point = "CENTER", relative = "CENTER", x = 0, y = 0,
			width = 44, height = 44, level = 2 },
		{ name = "Timer", kind = "label", point = "CENTER", relative = "CENTER", x = 0, y = 0, level = 3 },
		{ name = "Count", kind = "label", point = "TOPLEFT", relative = "TOPLEFT", x = -2, y = -4, level = 3 },
	},
	PBsConsoleHudCustomizerShade = {},
	-- The liquid overlay. Anchors and widths are all set from Lua every tick, so the parts only
	-- need to exist with the right textures on them.
	PBsConsoleHudCustomizerLiquid = {
		{ name = "Depth", kind = "texture", point = "TOPLEFT", relative = "TOPLEFT", x = 0, y = 0, fill = true,
			file = "EsoUI/Art/UnitAttributeVisualizer/attributeBar_dynamic_fill_gloss.dds",
			colour = { 0, 0, 0, 0.45 }, coords = { 0, 1, 0.53125, 0 }, level = 1 },
		{ name = "Band1", kind = "texture", point = "TOPLEFT", relative = "TOPLEFT", x = 0, y = 0,
			file = "EsoUI/Art/Miscellaneous/progressbar_genericFill_gloss.dds",
			colour = { 1, 1, 1, 0.45 }, width = 70, level = 2 },
		{ name = "Band2", kind = "texture", point = "TOPLEFT", relative = "TOPLEFT", x = 0, y = 0,
			file = "EsoUI/Art/Miscellaneous/progressbar_genericFill_gloss.dds",
			colour = { 1, 1, 1, 0.3 }, width = 120, level = 2 },
		{ name = "Surface", kind = "texture", point = "TOPRIGHT", relative = "TOPRIGHT", x = 0, y = 0,
			file = "EsoUI/Art/UnitAttributeVisualizer/attributeBar_dynamic_leadingEdge_gloss.dds",
			colour = { 1, 1, 1, 1 }, width = 14, level = 3 },
	},
}

-- A template whose own control is not a plain one.
local FALLBACK_KIND = { PBsConsoleHudCustomizerShade = "cooldown" }

local function ControlType(kind)
	if kind == "label" then
		return CT_LABEL
	end
	if kind == "cooldown" then
		return CT_COOLDOWN
	end
	if kind == "texture" then
		return CT_TEXTURE
	end
	return CT_CONTROL
end

local FALLBACK_SIZE = { PBsConsoleHudCustomizerBackBarSlot = { 52, 68 } }

function timers:BuildFallback(name, parent, template)
	local parts = FALLBACK_PARTS[template]
	if not parts or not WINDOW_MANAGER then
		return nil
	end
	local ok, control = pcall(WINDOW_MANAGER.CreateControl, WINDOW_MANAGER, name, parent,
		ControlType(FALLBACK_KIND[template]))
	if not ok or not control then
		return nil
	end
	local size = FALLBACK_SIZE[template]
	if size then
		control:SetDimensions(size[1], size[2])
	end
	for _, part in ipairs(parts) do
		local child = WINDOW_MANAGER:CreateControl(name .. part.name, control, ControlType(part.kind))
		child:SetAnchor(_G[part.point], control, _G[part.relative], part.x, part.y)
		if part.width then
			child:SetDimensions(part.width, part.height)
		end
		if part.file then
			child:SetTexture(part.file)
		end
		if part.fill then
			child:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, 0, 0)
		end
		if part.coords and type(child.SetTextureCoords) == "function" then
			child:SetTextureCoords(unpack(part.coords))
		end
		if part.colour and type(child.SetColor) == "function" then
			child:SetColor(unpack(part.colour))
		end
		if part.level and type(child.SetDrawLevel) == "function" then
			child:SetDrawLevel(part.level)
		end
		if part.kind == "label" then
			child:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
			child:SetVerticalAlignment(part.name == "Timer" and TEXT_ALIGN_BOTTOM or TEXT_ALIGN_TOP)
		end
		control[part.name] = child
	end
	self.usedFallback = true
	return control
end

-- The template where it loaded, plain controls where it did not.
function timers:Build(name, parent, template, slot)
	if type(CreateControlFromVirtual) == "function" then
		local ok, control = pcall(CreateControlFromVirtual, name, parent, template, slot)
		if ok and control then
			return control, false
		end
		addon.writeErrors = addon.writeErrors or {}
		addon.writeErrors[template] = tostring(control or "no control")
	end
	local control = self:BuildFallback(name .. tostring(slot), parent, template)
	return control, control ~= nil
end

-- The children of a built control, whichever way it was built.
local function Child(control, name)
	if control[name] then
		return control[name]
	end
	if type(control.GetNamedChild) == "function" then
		local ok, child = pcall(control.GetNamedChild, control, name)
		if ok then
			return child
		end
	end
	return nil
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
	local control = self:Build("PBsConsoleHudCustomizerLabels", button, "PBsConsoleHudCustomizerSlotLabels", slot)
	if not control then
		return nil
	end
	-- On the icon rather than on the button: the gamepad icon is 61 inside a 64 button (67 in 70
	-- for the ultimate), so "the middle" and "the corner" mean the icon's, which is what the
	-- player is looking at.
	local icon = Child(button, "Icon") or button
	control:SetAnchor(TOPLEFT, icon, TOPLEFT, 0, 0)
	control:SetAnchor(BOTTOMRIGHT, icon, BOTTOMRIGHT, 0, 0)
	local pair = {
		control = control,
		timer = Child(control, "Timer"),
		count = Child(control, "Count"),
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
	local control = self:Build("PBsConsoleHudCustomizerBack", button, "PBsConsoleHudCustomizerBackBarSlot", slot)
	if not control then
		return nil
	end
	local entry = {
		control = control,
		icon = Child(control, "Icon"),
		timer = Child(control, "Timer"),
		count = Child(control, "Count"),
		shade = Child(control, "Shade"),
		shadeState = {},
		button = button,
		isBack = true,
	}
	self.back[slot] = entry
	self:AnchorBackSlot(entry)
	self:StyleLabels(entry)
	return entry
end

local function ApplyFont(label, size, what)
	if not label then
		return
	end
	local descriptor = Font(size)
	local ok, err = pcall(label.SetFont, label, descriptor)
	if not ok then
		addon.writeErrors = addon.writeErrors or {}
		addon.writeErrors[what .. " font"] = tostring(err)
		return
	end
	-- What the client made of the descriptor. A size that never moves when the slider does is
	-- the one symptom that says the descriptor was not understood, and status prints it.
	if type(label.GetFontHeight) == "function" then
		local okHeight, height = pcall(label.GetFontHeight, label)
		label.pbsHeight = okHeight and height or nil
		-- The label is made as tall as its own text. Left at the client's fixed 25 it would hold
		-- a 48 the way a 25 box holds a 48: not in the middle.
		if okHeight and type(height) == "number" and height > 0 then
			pcall(label.SetHeight, label, height)
		end
	end
	label.pbsDescriptor = descriptor
end

-- One shade over the game's own icon, parented to the button so it fades and hides with the bar.
function timers:Shade(slot)
	local existing = self.shades[slot]
	if existing then
		return existing
	end
	local button = self:FrontButton(slot)
	if not button then
		return nil
	end
	local control = self:Build("PBsConsoleHudCustomizerShade", button, "PBsConsoleHudCustomizerShade", slot)
	if not control then
		return nil
	end
	local icon = Child(button, "Icon") or button
	control:ClearAnchors()
	control:SetAnchor(TOPLEFT, icon, TOPLEFT, 0, 0)
	control:SetAnchor(BOTTOMRIGHT, icon, BOTTOMRIGHT, 0, 0)
	control:SetHidden(true)
	self.shades[slot] = { control = control, state = {} }
	return self.shades[slot]
end

-- Starts the sweep when an effect begins or is refreshed, and takes it away when it ends.
-- Nothing is written in between: the engine runs the reveal itself.
function timers:UpdateShade(entry, slot, hotbar, icon, remaining, duration)
	if not entry or not entry.control then
		return
	end
	local control, state = entry.control, entry.state

	if not addon:ShadeEnabled() or not hotbar or remaining < MINIMUM_SHOWN_MS or duration <= 0 then
		if state.running then
			control:SetHidden(true)
			state.running, state.duration, state.remaining, state.icon = nil, nil, nil, nil
		end
		return
	end

	-- A new cast, a refresh, or a different ability in the slot. A refresh is a jump back up in
	-- what is left; anything smaller is the same sweep carrying on.
	local restart = not state.running
		or state.duration ~= duration
		or state.icon ~= icon
		or remaining > (state.remaining or 0) + 250
	if restart then
		if icon and type(control.SetTexture) == "function" then
			addon:Write("shade", control.SetTexture, control, icon)
		end
		if type(control.SetFillColor) == "function" then
			addon:Write("shade", control.SetFillColor, control, 0, 0, 0, addon:ShadeDarkness() / 100)
		end
		if type(control.SetVerticalCooldownLeadingEdgeHeight) == "function" then
			addon:Write("shade", control.SetVerticalCooldownLeadingEdgeHeight, control,
				addon:Shade().leadingEdge ~= false and 4 or 0)
		end
		local USE_LEADING_EDGE = addon:Shade().leadingEdge ~= false
		local ok = addon:Write("shade", control.StartCooldown, control, remaining, duration,
			CD_TYPE_VERTICAL_REVEAL, addon:ShadeTimeType(), USE_LEADING_EDGE)
		if not ok then
			control:SetHidden(true)
			return
		end
		control:SetHidden(false)
		state.running = true
		state.duration = duration
		state.icon = icon
	end
	state.remaining = remaining
end

function timers:HideShades()
	for _, entry in pairs(self.shades) do
		entry.control:SetHidden(true)
		entry.state.running = nil
	end
	for _, entry in pairs(self.back) do
		if entry.shade then
			entry.shade:SetHidden(true)
			entry.shadeState.running = nil
		end
	end
end

-- The countdown goes exactly where the client puts its own -- CENTER, 4 down
-- (ACTION_BUTTON_TIMER_TEXT_OFFSET_Y_DEFAULT_GAMEPAD) -- so that switching between ours and the
-- game's moves nothing on the icon.
--
-- The one exception is "Both", with the game drawing its number there as well: two numbers on one
-- spot cannot be read, so ours drops to the bottom of the icon out of its way.
function timers:PlaceTimer(pair, centred)
	if not pair or not pair.timer or pair.centred == centred then
		return
	end
	local label = pair.timer
	label:ClearAnchors()
	if centred then
		label:SetAnchor(CENTER, pair.control, CENTER, 0, 0)
	else
		label:SetAnchor(BOTTOM, pair.control, BOTTOM, 0, 6)
	end
	pair.centred = centred
end

function timers:StyleLabels(pair)
	local isBack = pair.isBack == true
	ApplyFont(pair.timer, addon:TextSize("timer", isBack), isBack and "back timer" or "timer")
	if pair.timer then
		pair.timer:SetColor(TIMER_COLOUR[1], TIMER_COLOUR[2], TIMER_COLOUR[3], 1)
	end
	ApplyFont(pair.count, addon:TextSize("count", isBack), isBack and "back count" or "count")
	if pair.count then
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
-- The game's own number on the front bar
--
-- ActionButton<n>TimerText is the client's countdown, written by ActionButton:SetTimer and sized
-- by the client's own template -- an add-on cannot change its size, and the setting that turns it
-- on is private. When this add-on draws its own number on the same icon, the client's is faded
-- out instead: alpha is not something the client writes on that label (SetTimer only ever sets
-- its text and its hidden state), so it stays out of the way without a fight, and goes back to
-- full the moment ours is switched off.
-- ---------------------------------------------------------------------------------------

function timers:GameTimerLabel(slot)
	local button = self:FrontButton(slot)
	if not button or type(button.GetNamedChild) ~= "function" then
		return nil
	end
	local ok, label = pcall(button.GetNamedChild, button, "TimerText")
	if ok and label and type(label.SetAlpha) == "function" then
		return label
	end
	return nil
end

-- What is remembered is the label that was faded, not merely that a slot was: a slot whose
-- button has been rebuilt would otherwise be taken for done and left with the game's number on
-- top of ours for the rest of the session.
function timers:DimGameTimer(slot, dim)
	local label = self:GameTimerLabel(slot)
	if not label then
		return false
	end
	local faded = self.dimmed[slot]
	if dim and faded == label then
		return true
	end
	if not dim and faded == nil then
		return true
	end
	local ok, err = pcall(label.SetAlpha, label, dim and 0 or 1)
	if not ok then
		addon.writeErrors = addon.writeErrors or {}
		addon.writeErrors["game timer"] = tostring(err)
		return false
	end
	-- Anything faded earlier and since replaced is handed back as well.
	if faded and faded ~= label then
		pcall(faded.SetAlpha, faded, 1)
	end
	self.dimmed[slot] = dim and label or nil
	return true
end

function timers:UndimAll()
	for slot, label in pairs(self.dimmed) do
		pcall(label.SetAlpha, label, 1)
		self.dimmed[slot] = nil
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
	local icon = IconKey(SlotString(GetSlotTexture, slot, hotbar))
	local count, matchedBy = self:CountFor(key, abilityId, icon, now)
	local minimum = addon:Text().countFromOne and 1 or 2
	if count >= minimum then
		countText = tostring(count)
	end
	return timerText, countText, count, matchedBy
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
	local dim = addon:DimsGameTimer()
	local shadeEnabled = addon:ShadeEnabled()
	-- "Both" is a choice to have the game's number as well, so ours keeps out of its place
	-- whether or not the game happens to be drawing one at this moment.
	local centredTimer = addon:TimerMode() ~= "both"

	for slot = FIRST_SLOT, LAST_SLOT do
		self:DimGameTimer(slot, dim)

		-- The game's own bar.
		if showTimer or showCount then
			local pair = self:Labels(slot)
			if pair then
				self:PlaceTimer(pair, centredTimer)
				local timerText, countText = self:SlotText(slot, activeHotbar, now)
				pair.control:SetHidden(false)
				SetText(pair.timer, showTimer and timerText or nil)
				SetText(pair.count, showCount and countText or nil)
			end
		elseif self.labels[slot] then
			self.labels[slot].control:SetHidden(true)
		end

		if shadeEnabled then
			self:UpdateShade(self:Shade(slot), slot, activeHotbar,
				SlotString(GetSlotTexture, slot, activeHotbar),
				SlotNumber(GetActionSlotEffectTimeRemaining, slot, activeHotbar),
				SlotNumber(GetActionSlotEffectDuration, slot, activeHotbar))
		elseif self.shades[slot] then
			self:UpdateShade(self.shades[slot], slot, nil, nil, 0, 0)
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
					if entry.shade then
						self:UpdateShade({ control = entry.shade, state = entry.shadeState }, slot,
							shadeEnabled and backHotbar or nil, icon,
							SlotNumber(GetActionSlotEffectTimeRemaining, slot, backHotbar),
							SlotNumber(GetActionSlotEffectDuration, slot, backHotbar))
					end
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
	return addon:ShowsTimerOn(false) or addon:ShowsTimerOn(true) or addon:ShowsCount()
		or addon:BackBarEnabled() or addon:ShadeEnabled()
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
	self:HideShades()
	self:UndimAll()
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

-- ---------------------------------------------------------------------------------------
-- What is really on the bar
--
-- One command that answers the two questions a report of "nothing is showing" raises: were the
-- controls ever built, and is the number this add-on worked out the one on screen.
-- ---------------------------------------------------------------------------------------

function timers:TrackedCount()
	return effectCount
end

function timers:TrackedNames(limit)
	local names = {}
	for key in pairs(effects) do
		names[#names + 1] = key
		if #names >= (limit or 6) then
			break
		end
	end
	return names
end

function timers:PrintSlots()
	local Line = addon.Line
	local now = GetGameTimeMilliseconds and GetGameTimeMilliseconds() or 0
	local backHotbar, activeHotbar = self:BackHotbar()

	Line("|cFF69B4%s|r -- the skill bar, slot by slot", addon.title)
	Line("  loop=%s hud=%s  countdown=%s (front=%s back=%s, the game's own dimmed=%s)",
		tostring(self.running == true), tostring(self.hudShown ~= false), addon:TimerMode(),
		tostring(addon:ShowsTimerOn(false)), tostring(addon:ShowsTimerOn(true)), tostring(addon:DimsGameTimer()))
	if addon.WeaponSwapState then
		local available, why = addon:WeaponSwapState()
		Line("  weapon swap available=%s%s  -> other set row=%s", tostring(available),
			why and (" (" .. why .. ")") or "", tostring(addon:BackBarEnabled()))
	end
	Line("  effects tracked=%d  counts shown from %d target(s)  controls from %s", self:TrackedCount(),
		addon:Text().countFromOne and 1 or 2, self.usedFallback and "plain Lua (Controls.xml did not load)" or "Controls.xml")
	local names = self:TrackedNames(6)
	if #names > 0 then
		Line("  tracked: %s", table.concat(names, " | "))
	end

	for slot = FIRST_SLOT, LAST_SLOT do
		local pair = self.labels[slot]
		local name = SlotString(GetSlotName, slot, activeHotbar) or "-"
		local remaining = SlotNumber(GetActionSlotEffectTimeRemaining, slot, activeHotbar)
		local timerText, countText, count, matchedBy = self:SlotText(slot, activeHotbar, now)
		Line("|cFF69B4  %d|r %s  left=%dms -> %s  targets=%d%s -> %s  label=%s h=%s", slot, name, Round(remaining),
			tostring(timerText), count or 0, matchedBy and (" by " .. matchedBy) or "",
			tostring(countText), pair and (pair.timer:IsHidden() and "hidden" or "shown") or "not built",
			pair and tostring(pair.timer.pbsHeight) or "-")
		if backHotbar then
			local backName = SlotString(GetSlotName, slot, backHotbar) or "-"
			local backRemaining = SlotNumber(GetActionSlotEffectTimeRemaining, slot, backHotbar)
			local backTimer, backCount = self:SlotText(slot, backHotbar, now)
			Line("      other set: %s  left=%dms -> %s  count=%s  row=%s", backName, Round(backRemaining),
				tostring(backTimer), tostring(backCount),
				self.back[slot] and (self.back[slot].control:IsHidden() and "hidden" or "shown") or "not built")
		end
	end
	Line("  a count is matched by name, then ability id, then icon. The name on the left has to")
	Line("  appear in the tracked list above, or the icon has to be the effect's own, for a")
	Line("  number to be written -- and it is only written from %d target(s) up.",
		addon:Text().countFromOne and 1 or 2)
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
