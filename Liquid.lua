-- PBS_CONSOLE_HUD_CUSTOMIZER is nil if Main.lua bailed out early (e.g. already loaded).
if not PBS_CONSOLE_HUD_CUSTOMIZER then
	return
end

local addon = PBS_CONSOLE_HUD_CUSTOMIZER
local Round = addon.Round
local Clamp = addon.Clamp

-- ---------------------------------------------------------------------------------------
-- The liquid look
--
-- A second style for the three attribute bars: the bar still reads as an ESO bar, but what is
-- in it looks like something poured rather than painted -- darker towards the bottom, light
-- drifting across it, and a bright line at the surface where the fill ends.
--
-- Drawn *over* the client's own fill rather than instead of it. That is the whole design
-- decision, and it is what keeps everything else working: the damage shield overlays, the
-- armour and possession modules and the warners are all controls the attribute visualiser hangs
-- on those same bar controls, and a style that hid the client's bars would take them with it.
-- Ours is one child of each bar control, so it inherits the bar's alpha (the game's own fade out
-- of combat), its hidden state, and any scale this add-on has put on the bar.
--
-- Every texture is one the bar has already loaded (attributeBar_dynamic_fill_gloss and its
-- leading edge) or one the generic progress bars use, so the look adds nothing to the 100 MB
-- pool console add-ons share. There is no new art in this add-on at all.
--
-- The one thing that has to be worked out here is how much of the bar is full, because the
-- overlay has to stop where the fill stops. ESO does not clip a child to its parent, so each
-- piece is given the width it should show and the texture coordinates to match.
-- ---------------------------------------------------------------------------------------

local liquid = {
	overlays = {},
}
addon.liquid = liquid

addon.BAR_STYLES = { "standard", "liquid" }

-- 20 a second. The bands drift slowly on purpose -- a fast shimmer on a health bar reads as a
-- warning, which is the game's job, not this add-on's.
local UPDATE_INTERVAL_MS = 50

-- One band's travel in milliseconds, and how wide it is. Two of them, at different speeds, is
-- what stops the movement from looking like a single sliding object.
local BANDS = {
	{ name = "Band1", periodMs = 5200, width = 48, alpha = 0.25 },
	{ name = "Band2", periodMs = 8300, width = 80, alpha = 0.18 },
}

local SURFACE_WIDTH = 11
local SURFACE_PERIOD_MS = 2600

-- Which bar control belongs to which attribute, and which way it fills. The two halves of the
-- health bar each hold half the value, so the fraction is the same for both -- the client
-- divides by two in ZO_PlayerAttributeBar:UpdateStatusBar.
--
-- A bar with barAlignment REVERSE in the XML fills towards its left, so the surface is on the
-- left and the overlay hangs off the right edge; a normal one is the mirror of that.
liquid.bars = {
	{
		key = "health",
		power = "health",
		controls = {
			{ name = "ZO_PlayerAttributeHealthBarLeft", reverse = true },
			{ name = "ZO_PlayerAttributeHealthBarRight", reverse = false },
		},
	},
	{
		key = "magicka",
		power = "magicka",
		controls = { { name = "ZO_PlayerAttributeMagickaBar", reverse = true } },
	},
	{
		key = "stamina",
		power = "stamina",
		controls = { { name = "ZO_PlayerAttributeStaminaBar", reverse = false } },
	},
}

-- ---------------------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------------------

function addon:BarStyle()
	local style = self:Account().style
	for _, known in ipairs(self.BAR_STYLES) do
		if style == known then
			return style
		end
	end
	return "standard"
end

function addon:SetBarStyle(style)
	for _, known in ipairs(self.BAR_STYLES) do
		if style == known then
			self:Account().style = style
			return true
		end
	end
	return false
end

addon.MIN_LIQUID = 0
addon.MAX_LIQUID = 200
addon.DEFAULT_LIQUID = 100

-- How strongly the whole effect is drawn, as a percentage of the sizes chosen above.
function addon:LiquidStrength()
	local value = self:Account().liquidStrength
	if type(value) ~= "number" then
		return self.DEFAULT_LIQUID
	end
	return Clamp(Round(value), self.MIN_LIQUID, self.MAX_LIQUID)
end

function addon:SetLiquidStrength(value)
	self:Account().liquidStrength = Clamp(Round(value), self.MIN_LIQUID, self.MAX_LIQUID)
end

function addon:LiquidWanted()
	return self:Account().enabled and self:BarStyle() == "liquid" and self:LiquidStrength() > 0
end

-- ---------------------------------------------------------------------------------------
-- The controls
-- ---------------------------------------------------------------------------------------

local function BarControl(name)
	local control = _G[name]
	if type(control) ~= "table" and type(control) ~= "userdata" then
		return nil
	end
	if type(control.GetDimensions) ~= "function" then
		return nil
	end
	return control
end

function liquid:Overlay(entry)
	local existing = self.overlays[entry.name]
	if existing then
		return existing
	end
	local bar = BarControl(entry.name)
	if not bar or not addon.timers then
		return nil
	end
	-- Built the same way as the skill bar's controls, and with the same fallback if the XML
	-- never loaded.
	local control = addon.timers:Build("PBsConsoleHudCustomizerLiquid", bar, "PBsConsoleHudCustomizerLiquid", entry.name)
	if not control then
		return nil
	end
	local overlay = {
		control = control,
		bar = bar,
		reverse = entry.reverse,
		depth = control.Depth or control:GetNamedChild("Depth"),
		surface = control.Surface or control:GetNamedChild("Surface"),
		bands = {},
	}
	for index, band in ipairs(BANDS) do
		overlay.bands[index] = control[band.name] or control:GetNamedChild(band.name)
	end
	self.overlays[entry.name] = overlay
	self:AnchorOverlay(overlay)
	return overlay
end

-- The overlay hangs off the edge the fill grows from, so setting its width is the same as
-- clipping it to the fill.
function liquid:AnchorOverlay(overlay)
	local control = overlay.control
	local bar = overlay.bar
	control:ClearAnchors()
	if overlay.reverse then
		control:SetAnchor(TOPRIGHT, bar, TOPRIGHT, 0, 0)
		control:SetAnchor(BOTTOMRIGHT, bar, BOTTOMRIGHT, 0, 0)
	else
		control:SetAnchor(TOPLEFT, bar, TOPLEFT, 0, 0)
		control:SetAnchor(BOTTOMLEFT, bar, BOTTOMLEFT, 0, 0)
	end
end

function liquid:HideAll()
	for _, overlay in pairs(self.overlays) do
		overlay.control:SetHidden(true)
	end
end

-- ---------------------------------------------------------------------------------------
-- How full the bar is
-- ---------------------------------------------------------------------------------------

local POWER_TYPES = {}

local function PowerType(key)
	local cached = POWER_TYPES[key]
	if cached ~= nil then
		return cached
	end
	local value = _G["COMBAT_MECHANIC_FLAGS_" .. key:upper()]
	POWER_TYPES[key] = value or false
	return POWER_TYPES[key]
end

-- Read rather than followed by event: one call per bar per tick is cheaper than keeping a copy
-- of the client's own bookkeeping in step, and it can never drift out of it.
function liquid:Fraction(bar)
	local powerType = PowerType(bar.power)
	if not powerType or type(GetUnitPower) ~= "function" then
		return nil
	end
	local ok, current, _, effectiveMax = pcall(GetUnitPower, "player", powerType)
	if not ok or type(current) ~= "number" or type(effectiveMax) ~= "number" or effectiveMax <= 0 then
		return nil
	end
	return Clamp(current / effectiveMax, 0, 1)
end

-- ---------------------------------------------------------------------------------------
-- The drawing
-- ---------------------------------------------------------------------------------------

-- One band, travelling from the far end towards the surface, clipped by hand to the part of the
-- bar that is actually full: what is shown is the overlap of the band with [0, fillWidth], and
-- the texture coordinates are the same overlap expressed across the band's own width.
function liquid:PlaceBand(texture, overlay, fillWidth, bandWidth, phase, alpha)
	if not texture then
		return
	end
	local travel = fillWidth + bandWidth
	local left = phase * travel - bandWidth
	local right = left + bandWidth
	local visibleLeft = left < 0 and 0 or left
	local visibleRight = right > fillWidth and fillWidth or right
	local width = visibleRight - visibleLeft
	if width <= 1 then
		texture:SetHidden(true)
		return
	end

	local coordLeft = (visibleLeft - left) / bandWidth
	local coordRight = (visibleRight - left) / bandWidth
	texture:ClearAnchors()
	if overlay.reverse then
		-- Measured from the surface, which is on the left of a bar that fills leftwards.
		texture:SetAnchor(TOPLEFT, overlay.control, TOPLEFT, visibleLeft, 0)
		texture:SetAnchor(BOTTOMLEFT, overlay.control, BOTTOMLEFT, visibleLeft, 0)
	else
		texture:SetAnchor(TOPLEFT, overlay.control, TOPLEFT, visibleLeft, 0)
		texture:SetAnchor(BOTTOMLEFT, overlay.control, BOTTOMLEFT, visibleLeft, 0)
	end
	texture:SetWidth(width)
	texture:SetTextureCoords(coordLeft, coordRight, 0, 1)
	texture:SetAlpha(alpha)
	texture:SetHidden(false)
end

function liquid:UpdateOverlay(overlay, fraction, now, strength)
	local control = overlay.control
	local okWidth, barWidth = pcall(overlay.bar.GetWidth, overlay.bar)
	if not okWidth or type(barWidth) ~= "number" or barWidth <= 0 then
		control:SetHidden(true)
		return
	end

	local fillWidth = barWidth * fraction
	if fillWidth < 2 then
		control:SetHidden(true)
		return
	end
	control:SetHidden(false)
	control:SetWidth(fillWidth)

	if overlay.depth then
		overlay.depth:SetAlpha(0.3 * strength)
	end

	for index, band in ipairs(BANDS) do
		local phase = (now % band.periodMs) / band.periodMs
		self:PlaceBand(overlay.bands[index], overlay, fillWidth, band.width, phase, band.alpha * strength)
	end

	-- The surface: a bright line where the fill ends, breathing a little so it does not read as
	-- part of the frame.
	local surface = overlay.surface
	if surface then
		local pulse = 0.55 + 0.2 * math.sin(now / SURFACE_PERIOD_MS * 2 * math.pi)
		surface:ClearAnchors()
		if overlay.reverse then
			surface:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
			surface:SetAnchor(BOTTOMLEFT, control, BOTTOMLEFT, 0, 0)
			surface:SetTextureCoords(0.6875, 0, 0, 0.53125)
		else
			surface:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
			surface:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, 0, 0)
			surface:SetTextureCoords(0, 0.6875, 0, 0.53125)
		end
		surface:SetWidth(SURFACE_WIDTH)
		surface:SetAlpha(pulse * strength)
		surface:SetHidden(fillWidth <= SURFACE_WIDTH)
	end
end

function liquid:Update()
	local now = GetFrameTimeMilliseconds and GetFrameTimeMilliseconds() or 0
	local strength = addon:LiquidStrength() / 100
	for _, bar in ipairs(self.bars) do
		local fraction = self:Fraction(bar)
		for _, entry in ipairs(bar.controls) do
			local overlay = self:Overlay(entry)
			if overlay then
				if fraction then
					self:UpdateOverlay(overlay, fraction, now, strength)
				else
					overlay.control:SetHidden(true)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------------------
-- The loop
--
-- Only while the HUD is up and the liquid style is the one chosen. Standard is the default, and
-- while it is chosen this file does nothing at all: no controls are built and no update is
-- registered.
-- ---------------------------------------------------------------------------------------

function liquid:Start()
	if self.running or not addon:LiquidWanted() or self.hudShown == false then
		return false
	end
	if not EVENT_MANAGER or type(EVENT_MANAGER.RegisterForUpdate) ~= "function" then
		return false
	end
	EVENT_MANAGER:RegisterForUpdate(addon.name .. "Liquid", UPDATE_INTERVAL_MS, function()
		liquid:Update()
	end)
	self.running = true
	self:Update()
	return true
end

function liquid:Stop()
	if not self.running then
		return false
	end
	EVENT_MANAGER:UnregisterForUpdate(addon.name .. "Liquid")
	self.running = false
	self:HideAll()
	return true
end

function liquid:Refresh()
	if addon:LiquidWanted() and self.hudShown ~= false then
		if self.running then
			self:Update()
		else
			self:Start()
		end
	else
		self:Stop()
	end
end

function liquid:OnHudStateChange(shown)
	self.hudShown = shown and true or false
	if shown then
		self:Refresh()
	else
		self:Stop()
	end
end
