-- Stub of just enough ESO client to exercise PBsConsoleHudCustomizer.
--
-- The parts that matter are the three attribute bar containers: the game's own anchors out of
-- playerattributebars.xml (health on the group's centre, magicka's right edge 237 in from its
-- left, stamina's left edge 237 in from its right), a resolver that turns those anchors into a
-- rectangle the way the client does, and the attribute visualiser's habit of writing 141 / 237 /
-- 323 onto a bar's width as buffs come and go.
local DIR = ADDON_DIR

unpack = unpack or table.unpack

-- ---- string table -------------------------------------------------------------------
local stringValues = {}
local nextId = 1
function ZO_CreateStringId(id, value) if not _G[id] then _G[id] = nextId; nextId = nextId + 1 end; stringValues[_G[id]] = value end
function SafeAddVersion() end
function SafeAddString(id, value) stringValues[id] = value end
function GetString(id) return stringValues[id] or ("<missing " .. tostring(id) .. ">") end
-- ZO_StringFormat's <<1>> substitution, as far as this add-on uses it.
function zo_strformat(format, ...)
	local args = { ... }
	return (tostring(format):gsub("<<(%d)>>", function(n) return tostring(args[tonumber(n)] or "") end))
end

-- ---- chat / misc --------------------------------------------------------------------
Chat = {}
CHAT_ROUTER = { AddSystemMessage = function(_, t) Chat[#Chat + 1] = t; print("[chat] " .. t) end }
function d(t) print("[d] " .. tostring(t)) end
SLASH_COMMANDS = {}
local pendingCallLater = {}
function zo_callLater(fn, ms) pendingCallLater[#pendingCallLater + 1] = fn end
function FlushCallLater() local q = pendingCallLater; pendingCallLater = {}; for _, fn in ipairs(q) do fn() end; return #q end
function PendingCallLater() return #pendingCallLater end

local frameTime = 0
function GetFrameTimeMilliseconds() return frameTime end
function AdvanceFrame(ms) frameTime = frameTime + (ms or 1000) end

function GetAddOnManager()
	return {
		GetNumAddOns = function() return 1 end,
		GetAddOnInfo = function(_, i) return "PBsConsoleHudCustomizer", "|cFF69B4PB\u{2019}s ConsoleHudCustomizer|r 1.10.1" end,
	}
end

-- ---- constants ----------------------------------------------------------------------
TOP, LEFT, BOTTOM, RIGHT, CENTER = 1, 2, 4, 8, 128
TOPLEFT, TOPRIGHT, BOTTOMLEFT, BOTTOMRIGHT = 3, 9, 6, 12
CT_LABEL, CT_TEXTURE, CT_CONTROL, CT_COOLDOWN, CT_BACKDROP = "label", "texture", "control", "cooldown", "backdrop"
INTERFACE_COLOR_TYPE_POWER_START = 1
CD_TYPE_VERTICAL_REVEAL, CD_TYPE_RADIAL = 1, 2
CD_TIME_TYPE_TIME_UNTIL, CD_TIME_TYPE_TIME_REMAINING = 1, 2
COMBAT_MECHANIC_FLAGS_HEALTH, COMBAT_MECHANIC_FLAGS_MAGICKA, COMBAT_MECHANIC_FLAGS_STAMINA = 1, 2, 4
TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, TEXT_ALIGN_BOTTOM = 1, 2, 3
DL_OVERLAY, DT_HIGH, DT_MEDIUM = "overlay", "high", "medium"
SCENE_FRAGMENT_SHOWING, SCENE_FRAGMENT_SHOWN, SCENE_FRAGMENT_HIDING, SCENE_FRAGMENT_HIDDEN = "showing", "shown", "hiding", "hidden"

-- ---- events -------------------------------------------------------------------------
EVENT_ADD_ON_LOADED = "EVENT_ADD_ON_LOADED"
EVENT_PLAYER_ACTIVATED = "EVENT_PLAYER_ACTIVATED"
handlers = {}
EVENT_MANAGER = {
	RegisterForEvent = function(_, name, event, fn) handlers[event] = handlers[event] or {}; handlers[event][name] = fn end,
	UnregisterForEvent = function(_, name, event) if handlers[event] then handlers[event][name] = nil end end,
}
function Fire(event, ...) for _, fn in pairs(handlers[event] or {}) do fn(event, ...) end end

local callbacks = {}
CALLBACK_MANAGER = {
	RegisterCallback = function(_, name, fn) callbacks[name] = callbacks[name] or {}; table.insert(callbacks[name], fn) end,
	-- Like ZO_CallbackObject: the callback gets the arguments, not the event name.
	FireCallbacks = function(_, name, ...) for _, fn in ipairs(callbacks[name] or {}) do fn(...) end end,
}

-- ---- saved variables ----------------------------------------------------------------
SavedStore = {}
local function DeepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = DeepCopy(v) end
	return out
end
ZO_SavedVars = {
	NewAccountWide = function(_, name, version, namespace, defaults)
		SavedStore[name] = SavedStore[name] or {}
		local store = SavedStore[name]
		for k, v in pairs(defaults or {}) do if store[k] == nil then store[k] = DeepCopy(v) end end
		return store
	end,
}

-- ---- controls -----------------------------------------------------------------------
Writes = {}
local function CountWrite(control, what)
	Writes[control.name] = Writes[control.name] or {}
	Writes[control.name][what] = (Writes[control.name][what] or 0) + 1
end
function WriteCount(name, what) return (Writes[name] or {})[what] or 0 end

local rootWidth, rootHeight = 1920, 1080
GuiRoot = { name = "GuiRoot", width = rootWidth, height = rootHeight }
function GuiRoot:GetDimensions() return rootWidth, rootHeight end
function GuiRoot:GetName() return "GuiRoot" end
function GuiRoot:Rect() return 0, 0, rootWidth, rootHeight end
function SetRootSize(w, h) rootWidth, rootHeight = w, h; GuiRoot.width, GuiRoot.height = w, h end

-- Which corner of a rectangle a point names, as fractions of its width and height.
local function Fractions(point)
	if point == CENTER then return 0.5, 0.5 end
	local function has(flag) return math.floor(point / flag) % 2 == 1 end
	local fx = has(LEFT) and 0 or (has(RIGHT) and 1 or 0.5)
	local fy = has(TOP) and 0 or (has(BOTTOM) and 1 or 0.5)
	return fx, fy
end

local Control = {}
Control.__index = Control
function MakeControl(name, parent, kind)
	local c = setmetatable({ name = name, parent = parent or GuiRoot, kind = kind, anchors = {}, width = 0, height = 0, hidden = false, handlers = {}, scale = 1 }, Control)
	return c
end
function Control:GetName() return self.name end
function Control:GetNamedChild(suffix) return (self.namedChildren or {})[suffix] or _G[self.name .. suffix] end
function Control:GetParent() return self.parent end
function Control:ClearAnchors() CountWrite(self, "anchor"); self.anchors = {} end
function Control:SetAnchor(point, relativeTo, relativePoint, offsetX, offsetY, constrains)
	CountWrite(self, "anchor")
	assert(#self.anchors < 2, self.name .. " already has two anchors")
	table.insert(self.anchors, { point = point, relativeTo = relativeTo, relativePoint = relativePoint or point, offsetX = offsetX or 0, offsetY = offsetY or 0, constrains = constrains })
end
function Control:SetAnchorFill(target) self:ClearAnchors(); self:SetAnchor(TOPLEFT, target, TOPLEFT); self:SetAnchor(BOTTOMRIGHT, target, BOTTOMRIGHT) end
function Control:GetAnchor(index)
	local a = self.anchors[index + 1]
	if not a then return false end
	return true, a.point, a.relativeTo, a.relativePoint, a.offsetX, a.offsetY, a.constrains
end
function Control:SetDimensions(w, h) CountWrite(self, "dimensions"); self.width, self.height = w, h end
function Control:GetDimensions() return self.width, self.height end
function Control:SetWidth(w) self.width = w end
function Control:SetHeight(h) self.height = h end
function Control:GetHeight() return self.height end
function Control:SetScale(s) CountWrite(self, "scale"); self.scale = s end
function Control:GetScale() return self.scale end
function Control:SetHidden(h) self.hidden = h end
function Control:IsHidden() return self.hidden end
function Control:SetMouseEnabled() end
function Control:SetDrawLayer(v) self.drawLayer = v end
function Control:SetDrawTier(v) self.drawTier = v end
function Control:SetHandler(name, fn) self.handlers[name] = fn end
function Control:SetColor(r, g, b, a) self.color = { r, g, b, a } end
function Control:SetText(t) self.text = t end
function Control:SetFont(f) self.font = f end
function Control:SetTexture(t) self.texture = t end
function Control:SetAlpha(a) self.alpha = a end
function Control:SetTextureCoords(l, r, t, b) self.coords = { l, r, t, b } end
function Control:GetWidth() return self.width end
-- The Cooldown control: StartCooldown is what the engine animates by itself.
function Control:StartCooldown(remaining, duration, cdType, timeType, leadingEdge)
	CountWrite(self, "cooldown")
	self.cooldown = { remaining = remaining, duration = duration, cdType = cdType, timeType = timeType, leadingEdge = leadingEdge }
end
function Control:SetFillColor(r, g, b, a) self.fillColor = { r, g, b, a } end
function Control:SetVerticalCooldownLeadingEdgeHeight(h) self.edgeHeight = h end
function Control:SetDesaturation(v) self.desaturation = v end
function Control:SetDrawLevel(v) self.drawLevel = v end
function Control:GetDrawLevel() return self.drawLevel or 0 end
function Control:GetDrawTier() return self.drawTier or "medium" end
function Control:SetCenterColor(r, g, b, a) self.centerColor = { r, g, b, a } end
function Control:SetGradientColors(r, g, b, a) self.gradient = { r, g, b, a } end
function Control:SetEdgeColor(r, g, b, a) self.edgeColor = { r, g, b, a } end
function Control:GetAlpha() return self.alpha or 1 end
function Control:GetFontHeight() local size = tonumber((self.font or ""):match("|(%d+)|")) or 0; return math.ceil(size * 1.25) end
function Control:GetText() return self.text end
function Control:SetHorizontalAlignment() end
function Control:SetVerticalAlignment() end
function Control:Tick() if self.handlers.OnUpdate then self.handlers.OnUpdate(self) end end

-- The client's own layout, for the one anchor these controls ever have: the anchor point of
-- this control is put on the named point of the control it is anchored to, plus the offsets.
function Control:Rect()
	local a = self.anchors[1]
	if not a then return 0, 0, self.width, self.height end
	local target = a.relativeTo or self.parent or GuiRoot
	local tLeft, tTop, tWidth, tHeight = target:Rect()
	local rfx, rfy = Fractions(a.relativePoint)
	local refX = tLeft + rfx * tWidth
	local refY = tTop + rfy * tHeight
	local fx, fy = Fractions(a.point)
	return refX + a.offsetX - fx * self.width, refY + a.offsetY - fy * self.height, self.width, self.height
end
function Control:GetLeft() local l = self:Rect(); return l end
function Control:GetRight() local l, _, w = self:Rect(); return l + w end
function Control:GetBottom() local _, t, _, h = self:Rect(); return t + h end
function Control:GetTop() local _, t = self:Rect(); return t end

-- Controls.xml, as far as the add-on reads it back: every template it asks for has an Icon, a
-- Timer and a Count child, looked up with GetNamedChild.
local VIRTUAL_CHILDREN = {
	PBsConsoleHudCustomizerBackBarSlot = { "BG", "Icon", "Overlay", "Shade", "Timer", "Count" },
	PBsConsoleHudCustomizerSlotLabels = { "Timer", "Count" },
	PBsConsoleHudCustomizerShade = {},
	PBsConsoleHudCustomizerPlainBar = { "Track", "Fill", "BorderTop", "BorderBottom", "BorderLeft", "BorderRight" },
}

function CreateControlFromVirtual(name, parent, template, suffix)
	local fullName = name .. tostring(suffix or "")
	assert(not CreatedControls[fullName], "duplicate control name " .. fullName)
	assert(VIRTUAL_CHILDREN[template], "unknown template " .. tostring(template))
	local control = MakeControl(fullName, parent, "control")
	control.template = template
	control.namedChildren = {}
	for _, child in ipairs(VIRTUAL_CHILDREN[template]) do
		control.namedChildren[child] = MakeControl(fullName .. child, control, "control")
	end
	CreatedControls[fullName] = control
	return control
end

CreatedControls = {}
WINDOW_MANAGER = {
	CreateControl = function(_, name, parent, kind)
		assert(not CreatedControls[name], "duplicate control name " .. tostring(name))
		local c = MakeControl(name, parent, kind); CreatedControls[name] = c; return c
	end,
	CreateTopLevelWindow = function(_, name)
		assert(not CreatedControls[name], "duplicate control name " .. tostring(name))
		local c = MakeControl(name, GuiRoot, "toplevel"); CreatedControls[name] = c; return c
	end,
}

-- ---- the player attribute bars ------------------------------------------------------
-- playerattributebars.xml / .lua: the top-level is 64 high, BOTTOM of GuiRoot at -105 (the
-- gamepad template) and as wide as ResizeToFitScreen allows; the three containers are 237 x 23
-- and anchored inside it. ZO_PlayerAttribute_OnInitialized then makes PLAYER_ATTRIBUTE_BARS.
local NORMAL_WIDTH, EXPANDED_WIDTH, SHRUNK_WIDTH = 237, 323, 141

local function MakeBar(name, point, relativeTo, relativePoint, offsetX)
	local control = MakeControl(name, _G.ZO_PlayerAttribute, "control")
	control.width, control.height = NORMAL_WIDTH, 23
	control:SetAnchor(point, relativeTo, relativePoint, offsetX or 0, 0)
	_G[name] = control
	return control
end

function BuildAttributeBars()
	local group = MakeControl("ZO_PlayerAttribute", GuiRoot, "toplevel")
	group.height = 64
	group:SetAnchor(BOTTOM, GuiRoot, BOTTOM, 0, -105)
	_G.ZO_PlayerAttribute = group
	-- ResizeToFitScreen
	local width = rootWidth - 502 * 2
	if width < 1014 then width = 1014 end
	if width > 1600 then width = 1600 end
	group.width = width

	local health = MakeBar("ZO_PlayerAttributeHealth", CENTER, group, CENTER, 0)
	local magicka = MakeBar("ZO_PlayerAttributeMagicka", RIGHT, group, LEFT, 237)
	local stamina = MakeBar("ZO_PlayerAttributeStamina", LEFT, group, RIGHT, -237)

	-- The frame pieces and the background container the plain style hides.
	for _, container in ipairs({ health, magicka, stamina }) do
		local numbers = MakeControl(container.name .. "ResourceNumbers", container, "label")
		_G[container.name .. "ResourceNumbers"] = numbers
		for _, suffix in ipairs({ "FrameLeft", "FrameCenter", "FrameRight", "BgContainer" }) do
			local piece = MakeControl(container.name .. suffix, container, "texture")
			_G[container.name .. suffix] = piece
		end
	end

	-- The status bars inside each container: two halves for health, one each for the others.
	local function MakeFill(name, parent, width)
		local fill = MakeControl(name, parent, "statusbar")
		fill.width, fill.height = width, 17
		fill:SetAnchor(LEFT, parent, LEFT, 7, 0)
		fill.gradient = { 1, 1, 1, 1 }
		local gloss = MakeControl(name .. "Gloss", fill, "statusbar")
		fill.namedChildren = { Gloss = gloss }
		_G[name .. "Gloss"] = gloss
		_G[name] = fill
		return fill
	end
	MakeFill("ZO_PlayerAttributeHealthBarLeft", health, 111)
	MakeFill("ZO_PlayerAttributeHealthBarRight", health, 111)
	MakeFill("ZO_PlayerAttributeMagickaBar", magicka, 224)
	MakeFill("ZO_PlayerAttributeStaminaBar", stamina, 224)

	-- The small companions, anchored to the bar they belong to.
	local siege = MakeControl("ZO_PlayerAttributeSiegeHealth", group, "control")
	siege.width, siege.height = 228, 12
	siege:SetAnchor(TOP, _G.ZO_PlayerAttributeHealth, BOTTOM, 0, -1)
	_G.ZO_PlayerAttributeSiegeHealth = siege

	local werewolf = MakeControl("ZO_PlayerAttributeWerewolf", group, "control")
	werewolf.width, werewolf.height = 228, 12
	werewolf:SetAnchor(TOPRIGHT, _G.ZO_PlayerAttributeMagicka, BOTTOMRIGHT, 0, -1)
	_G.ZO_PlayerAttributeWerewolf = werewolf

	local mount = MakeControl("ZO_PlayerAttributeMountStamina", group, "control")
	mount.width, mount.height = 228, 12
	mount:SetAnchor(TOPLEFT, _G.ZO_PlayerAttributeStamina, BOTTOMLEFT, 0, -1)
	_G.ZO_PlayerAttributeMountStamina = mount

	PLAYER_ATTRIBUTE_BARS = { bars = {} }
	BuildActionBar()
	Writes = {}
	return group
end

-- ---- the action bar -----------------------------------------------------------------
-- actionbar.xml / .lua: ZO_ActionBar1 is 70 high, 606 wide on the gamepad, BOTTOM of GuiRoot at
-- -25 (GAMEPAD_CONSTANTS), and every button is a control named ActionButton<slot> inside it.
ACTION_BAR_FIRST_NORMAL_SLOT_INDEX = 2
ACTION_BAR_SLOTS_PER_PAGE = 6
ACTION_BAR_ULTIMATE_SLOT_INDEX = 7
HOTBAR_CATEGORY_PRIMARY, HOTBAR_CATEGORY_BACKUP = 0, 1
ACTION_TYPE_NOTHING, ACTION_TYPE_ABILITY = 0, 1

-- ApplyStyle's chain, with GAMEPAD_CONSTANTS: the weapon swap marker 61 in from the bar's left
-- (permanently hidden on the gamepad but still taking up room), the five abilities 10 apart from
-- it, the ultimate 65 past the last of them, and the quickslot 5 to the left of the marker.
WEAPON_SWAP_WIDTH = 45

function BuildActionBar()
	local bar = MakeControl("ZO_ActionBar1", GuiRoot, "toplevel")
	bar.width, bar.height = 606, 70
	bar:SetAnchor(BOTTOM, GuiRoot, BOTTOM, 0, -25)
	_G.ZO_ActionBar1 = bar

	local swap = MakeControl("ZO_ActionBar1WeaponSwap", bar, "button")
	swap.width, swap.height = WEAPON_SWAP_WIDTH, 45
	swap:SetAnchor(TOPLEFT, bar, TOPLEFT, 61, 4)
	swap.hidden = true
	_G.ZO_ActionBar1WeaponSwap = swap

	local previous = nil
	for slot = 3, 8 do
		local button = MakeControl("ActionButton" .. slot, bar, "control")
		button.width, button.height = 64, 64
		if slot == 3 then
			button:SetAnchor(LEFT, swap, RIGHT, 10, 0)
		elseif slot == 8 then
			button:SetAnchor(LEFT, previous, RIGHT, 65, 0)
		else
			button:SetAnchor(LEFT, previous, RIGHT, 10, 0)
		end
		local icon = MakeControl("ActionButton" .. slot .. "Icon", button, "texture")
		icon:SetAnchor(CENTER, button, CENTER, 0, 0)
		icon.width, icon.height = 64, 64
		local timerText = MakeControl("ActionButton" .. slot .. "TimerText", button, "label")
		button.namedChildren = { Icon = icon, TimerText = timerText }
		_G["ActionButton" .. slot] = button
		previous = button
	end

	local quickslot = MakeControl("QuickslotButton", bar, "control")
	quickslot.width, quickslot.height = 64, 64
	quickslot:SetAnchor(RIGHT, swap, LEFT, -5, 0)
	_G.QuickslotButton = quickslot

	local companion = MakeControl("CompanionUltimateButton", bar, "control")
	companion.width, companion.height = 70, 70
	companion:SetAnchor(RIGHT, _G.ActionButton3, LEFT, -65, 0)
	companion.hidden = true
	_G.CompanionUltimateButton = companion

	return bar
end

-- A companion is out: the client shows its ultimate button and re-anchors the quickslot past it.
function SetCompanionOut(out)
	_G.CompanionUltimateButton:SetHidden(not out)
	_G.QuickslotButton:ClearAnchors()
	if out then
		_G.QuickslotButton:SetAnchor(RIGHT, _G.CompanionUltimateButton, LEFT, -45, 0)
	else
		_G.QuickslotButton:SetAnchor(RIGHT, _G.ZO_ActionBar1WeaponSwap, LEFT, -5, 0)
	end
end

-- GetActiveWeaponPairInfo's second return is the lock the Oakensoul Ring sets, and the weapon
-- swap is also unearned below GetWeaponSwapUnlockedLevel.
WeaponPairLocked = false
PlayerLevel = 50
function GetActiveWeaponPairInfo() return 1, WeaponPairLocked end
function GetWeaponSwapUnlockedLevel() return 15 end
function GetUnitLevel(unitTag) return PlayerLevel end

-- ZO_UnitVisualizer_ShrinkExpandModule:OnValueChanged -- a buff or debuff on a maximum writes
-- one of three widths onto the container, whatever anyone else has done to it.
function SetBarState(name, state)
	local control = _G[name]
	control:SetWidth(state == "expanded" and EXPANDED_WIDTH or (state == "shrunk" and SHRUNK_WIDTH or NORMAL_WIDTH))
end

function BarRect(name)
	local left, top, width, height = _G[name]:Rect()
	return string.format("%d,%d %dx%d", math.floor(left + 0.5), math.floor(top + 0.5), width, height)
end

function BarCentre(name)
	local left, top, width, height = _G[name]:Rect()
	return math.floor(left + width / 2 - rootWidth / 2 + 0.5), math.floor(rootHeight - (top + height / 2) + 0.5)
end

function BarAnchor(name)
	local a = _G[name].anchors[1]
	if not a then return "none" end
	return string.format("%d->%s %d (%d,%d)", a.point, a.relativeTo and a.relativeTo:GetName() or "nil", a.relativePoint, a.offsetX, a.offsetY)
end

-- The colours ZO_PlayerAttributeBar:RefreshColor puts back on a bar, as ZO_ColorDefs.
local function ColourDef(r, g, b)
	return { UnpackRGBA = function() return r, g, b, 1 end }
end
ZO_POWER_BAR_GRADIENT_COLORS = {
	[1] = { ColourDef(0.6, 0.1, 0.1), ColourDef(0.8, 0.2, 0.2) },
	[2] = { ColourDef(0.1, 0.3, 0.7), ColourDef(0.2, 0.4, 0.8) },
	[4] = { ColourDef(0.2, 0.5, 0.1), ColourDef(0.3, 0.6, 0.2) },
}

function GetInterfaceColor(colorType, powerType)
	if colorType ~= INTERFACE_COLOR_TYPE_POWER_START then return 1, 1, 1, 1 end
	local colours = { [1] = { 0.7, 0.2, 0.2 }, [2] = { 0.2, 0.4, 0.8 }, [4] = { 0.3, 0.6, 0.2 } }
	local c = colours[powerType] or { 1, 1, 1 }
	return c[1], c[2], c[3], 1
end

-- ---- the player's power -------------------------------------------------------------
PlayerPower = { [1] = { 1000, 1000, 1000 }, [2] = { 500, 1000, 1000 }, [4] = { 250, 1000, 1000 } }
function GetUnitPower(unitTag, powerType)
	local power = PlayerPower[powerType]
	if not power then return 0, 0, 0 end
	return power[1], power[2], power[3]
end
function SetPower(powerType, current, max)
	PlayerPower[powerType] = { current, max, max }
end

-- ---- the action slot API ------------------------------------------------------------
-- GetActionSlotEffectTimeRemaining / Duration / StackCount and the slot readers, as the client
-- has them since the action bar timers went in: they answer for either hotbar, which is what
-- makes a countdown on the set you are not on possible at all.
ActiveHotbar = HOTBAR_CATEGORY_PRIMARY
SlotData = {}   -- [hotbar][slot] = { name, icon, id, remaining, duration, stacks }

function GetActiveHotbarCategory() return ActiveHotbar end

local function Slot(slot, hotbar)
	return (SlotData[hotbar] or {})[slot]
end

function SetSlot(hotbar, slot, data)
	SlotData[hotbar] = SlotData[hotbar] or {}
	SlotData[hotbar][slot] = data
end

function SetAllSlots()
	SlotData = {}
	for slot = 3, 8 do
		SetSlot(HOTBAR_CATEGORY_PRIMARY, slot, { name = "Front " .. slot, icon = "front" .. slot .. ".dds", id = 100 + slot })
		SetSlot(HOTBAR_CATEGORY_BACKUP, slot, { name = "Back " .. slot, icon = "back" .. slot .. ".dds", id = 200 + slot })
	end
end

function GetSlotName(slot, hotbar) local s = Slot(slot, hotbar); return s and s.name or "" end
function GetSlotTexture(slot, hotbar) local s = Slot(slot, hotbar); return s and s.icon or "" end
function GetSlotBoundId(slot, hotbar) local s = Slot(slot, hotbar); return s and s.id or 0 end
-- What the game says an ability lasts. FancyActionBar+ works from this rather than from whatever
-- effect happens to be longest, and so does this add-on.
AbilityDurations = {}
function GetAbilityDuration(abilityId) return AbilityDurations[abilityId] or 0 end
function SetAbilityDuration(abilityId, ms) AbilityDurations[abilityId] = ms end
function GetSlotType(slot, hotbar) local s = Slot(slot, hotbar); return s and ACTION_TYPE_ABILITY or ACTION_TYPE_NOTHING end
function GetActionSlotEffectTimeRemaining(slot, hotbar) local s = Slot(slot, hotbar); return s and s.remaining or 0 end
function GetActionSlotEffectDuration(slot, hotbar) local s = Slot(slot, hotbar); return s and s.duration or 0 end
function GetActionSlotEffectStackCount(slot, hotbar) local s = Slot(slot, hotbar); return s and s.stacks or 0 end

SETTING_TYPE_UI, UI_SETTING_SHOW_ACTION_BAR_TIMERS = "ui", "barTimers"
GameBarTimers = false
function GetSetting_Bool(settingType, settingId)
	if settingType == SETTING_TYPE_UI and settingId == UI_SETTING_SHOW_ACTION_BAR_TIMERS then
		return GameBarTimers
	end
	return false
end

-- EVENT_EFFECT_CHANGED, and the update loop.
EVENT_EFFECT_CHANGED = "EVENT_EFFECT_CHANGED"
EVENT_ACTION_SLOT_ABILITY_USED = "EVENT_ACTION_SLOT_ABILITY_USED"
EFFECT_RESULT_GAINED, EFFECT_RESULT_FADED, EFFECT_RESULT_UPDATED = 1, 2, 3
REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE, COMBAT_UNIT_TYPE_PLAYER = "source", 1
COMBAT_UNIT_TYPE_PLAYER_PET = 2
-- Which source each registration is filtered to, so a test can send an effect as a pet.
EventFilters = {}
EVENT_MANAGER.AddFilterForEvent = function(_, name, event, filterType, value)
	EventFilters[name] = value
end
function GetGameTimeMilliseconds() return GetFrameTimeMilliseconds() end

local updates = {}
EVENT_MANAGER.RegisterForUpdate = function(_, name, interval, fn) updates[name] = fn end
EVENT_MANAGER.UnregisterForUpdate = function(_, name) updates[name] = nil end
function RunUpdates() for _, fn in pairs(updates) do fn() end end
function UpdateRegistered(name) return updates[name] ~= nil end

-- The slot the player pressed.
function FireCast(slotNum)
	Fire(EVENT_ACTION_SLOT_ABILITY_USED, slotNum)
end

-- The effect event, in the client's argument order, delivered only to the registrations whose
-- filter matches the source -- which is how the client behaves, and the whole point of the pet
-- registration.
EffectSlotSeed = 0
function FireEffectFrom(source, changeType, effectName, unitTag, endTimeSec, unitId, abilityId, icon, effectSlot, beginTimeSec)
	EffectSlotSeed = EffectSlotSeed + 1
	for name, fn in pairs(handlers[EVENT_EFFECT_CHANGED] or {}) do
		if EventFilters[name] == nil or EventFilters[name] == source then
			fn(EVENT_EFFECT_CHANGED, changeType, effectSlot or EffectSlotSeed, effectName, unitTag,
				beginTimeSec or 0, endTimeSec, 0, icon or "icon.dds", nil, 1, 1, 0, "someone",
				unitId, abilityId, source)
		end
	end
end

function FireEffect(changeType, effectName, unitTag, endTimeSec, unitId, abilityId, icon, effectSlot, beginTimeSec)
	FireEffectFrom(COMBAT_UNIT_TYPE_PLAYER, changeType, effectName, unitTag, endTimeSec, unitId,
		abilityId, icon, effectSlot, beginTimeSec)
end

-- ---- scenes -------------------------------------------------------------------------
local hudCallbacks = {}
HUD_FRAGMENT = { RegisterCallback = function(_, name, fn) table.insert(hudCallbacks, fn) end }
function FireHud(state) for _, fn in ipairs(hudCallbacks) do fn(nil, state) end end
CurrentScene = { name = "gamepad_settings" }
SCENE_MANAGER = { GetCurrentScene = function() return CurrentScene end }

SCENE_SHOWING, SCENE_SHOWN, SCENE_HIDING, SCENE_HIDDEN = "showing", "shown", "hiding", "hidden"
local function MakeScene(name)
	local scene = { name = name, state = SCENE_HIDDEN, callbacks = {} }
	function scene:RegisterCallback(_, fn) table.insert(self.callbacks, fn) end
	function scene:IsShowing() return self.state == SCENE_SHOWN end
	function scene:SetState(state) self.state = state; for _, fn in ipairs(self.callbacks) do fn(nil, state) end end
	return scene
end
MenuScene = CurrentScene

-- ---- LibHarvensAddonSettings --------------------------------------------------------
-- The console copy of the library, as far as selection goes (votan73/ESO,
-- LibHarvensAddonSettings/Main.lua + Console/Settings.lua): the panel scene is only created the
-- first time the main menu opens, and picking an add-on from the list calls Select() -- which
-- fires AddonSelected, *then* sets .selected -- and only after that pushes the panel scene.
-- Select() returns early for the add-on that is already selected.
PanelRows = {}
local panels = {}
LibHarvensAddonSettings = {
	ST_LABEL = "label", ST_SECTION = "section", ST_CHECKBOX = "checkbox", ST_SLIDER = "slider", ST_DROPDOWN = "dropdown", ST_BUTTON = "button",
	AddAddon = function(_, title)
		local panel = { title = title, name = title, updates = 0, selected = false }
		function panel:AddSetting(row) if self == Panel then PanelRows[#PanelRows + 1] = row end end
		function panel:UpdateControls() self.updates = self.updates + 1 end
		function panel:Select()
			if self.selected then return end
			CALLBACK_MANAGER:FireCallbacks("LibHarvensAddonSettings_AddonSelected", self.name, self)
			for _, other in ipairs(panels) do other.selected = false end
			self.selected = true
		end
		table.insert(panels, panel)
		if title:find("ConsoleHudCustomizer", 1, true) then Panel = panel end
		return panel
	end,
}
function OpenMainMenu()
	if not LibHarvensAddonSettings.scene then
		LibHarvensAddonSettings.scene = MakeScene("LibHarvensAddonSettingsScene")
	end
	CurrentScene = MenuScene
end

-- activatedCallback in the library's add-on list.
function OpenPanel(panel)
	OpenMainMenu()
	panel:Select()
	local scene = LibHarvensAddonSettings.scene
	scene:SetState(SCENE_SHOWING)
	CurrentScene = scene
	scene:SetState(SCENE_SHOWN)
end

-- Back out of a panel to the list.
function ClosePanel()
	local scene = LibHarvensAddonSettings.scene
	scene:SetState(SCENE_HIDING)
	CurrentScene = MenuScene
	scene:SetState(SCENE_HIDDEN)
end

function Row(label)
	for _, row in ipairs(PanelRows) do
		if row.label == label then return row end
	end
	error("no row " .. tostring(label))
end

-- ---- load the add-on ----------------------------------------------------------------
dofile(DIR .. "/lang/strings.lua")
dofile(DIR .. "/lang/jp.lua")
dofile(DIR .. "/Main.lua")
dofile(DIR .. "/SkillBar.lua")
dofile(DIR .. "/Timers.lua")
dofile(DIR .. "/Plain.lua")
dofile(DIR .. "/Preview.lua")
dofile(DIR .. "/Settings.lua")

-- Another add-on's panel. Ours is added later, at our EVENT_ADD_ON_LOADED.
OtherPanel = LibHarvensAddonSettings:AddAddon("Someone else's add-on")
