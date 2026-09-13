-- PBS_CONSOLE_HUD_CUSTOMIZER is nil if Main.lua bailed out early (e.g. already loaded).
if not PBS_CONSOLE_HUD_CUSTOMIZER then
	return
end

local addon = PBS_CONSOLE_HUD_CUSTOMIZER
local Round = addon.Round
local Clamp = addon.Clamp

-- ---------------------------------------------------------------------------------------
-- The plain look
--
-- A second style for the three attribute bars: a flat rectangle for the track and a flat
-- rectangle for what is in it, with the game's arrow-shaped frame and background out of the way.
--
-- It replaces the liquid style of 1.3.x, which never drew anything on a PS5. Two things about
-- that one are not repeated here, because either could have been the reason:
--
--   * it was built out of textures and hung on the client's status bar controls, as children of
--     a StatusBar. This one hangs on the container -- the same parent the client's own frame,
--     background and numbers use, so there is no question about whether a child of it draws.
--   * it was drawn with texture files and blend modes. The track uses a backdrop and the fill uses an untextured
--     colour rectangle, so there is no image file to load.
--
-- The client's own controls are all still there and still doing their work. The frame and the
-- background are hidden (one flag each, put back the moment the style changes), and the bar's own
-- fill is simply covered: the overlay is opaque and sits a tier above it. Nothing is unparented,
-- nothing is resized, and the attribute visualiser's shield, armour and possession overlays carry
-- on drawing on top of the bars as they always did.
-- ---------------------------------------------------------------------------------------

local plain = {
	overlays = {},
	hidden = {},
	numbers = {},
	blanked = {},
}
addon.plain = plain

-- Standard is the game's own. The other two are this add-on's, and both are the same flat
-- rectangle: what separates them is the size. Square keeps the game's own size and scales it;
-- MURA-HIGE Style is drawn at a width and a height of the player's choosing.
--
-- The key is still "rounded" because that is what an install has saved: the style was drawn with
-- round ends until 1.10.0, and it earned nobody's affection.
addon.BAR_STYLES = { "standard", "plain", "rounded", "neo", "liquidflow" }

-- Nothing animates, so this only has to keep up with the numbers changing.
local UPDATE_INTERVAL_MS = 100

-- Which bar control belongs to which attribute, which way it fills, and the container it lives
-- in. A bar with barAlignment REVERSE in the XML fills towards its left (magicka, and the left
-- half of the health bar), so its rectangle hangs off the right edge.
--
-- The two halves of the health bar each hold half the value, so the fraction is the same for
-- both: the client divides by two in ZO_PlayerAttributeBar:UpdateStatusBar.
plain.bars = {
	{
		key = "health",
		power = "health",
		container = "ZO_PlayerAttributeHealth",
		controls = {
			{ name = "ZO_PlayerAttributeHealthBarLeft", reverse = true },
			{ name = "ZO_PlayerAttributeHealthBarRight", reverse = false },
		},
	},
	{
		key = "magicka",
		power = "magicka",
		container = "ZO_PlayerAttributeMagicka",
		controls = { { name = "ZO_PlayerAttributeMagickaBar", reverse = true } },
	},
	{
		key = "stamina",
		power = "stamina",
		container = "ZO_PlayerAttributeStamina",
		controls = { { name = "ZO_PlayerAttributeStaminaBar", reverse = false } },
	},
}

-- What the game draws around the fill, and what this style puts away: the three frame pieces
-- (the arrow ends and the middle) and the whole background container.
local DRESSING = { "FrameLeft", "FrameCenter", "FrameRight", "BgContainer" }

-- The label the game writes the current and maximum on, when the player has it switched on under
-- Settings > Interface. It is drawn at the default tier, and the rectangles are at HIGH, so
-- without this it ends up behind them -- which is what came back from the PS5.
--
-- The low-health warner needs no such help: it is layer OVERLAY, tier HIGH, level 500
-- (ZO_PlayerAttributeWarner), which is above anything here.
local NUMBERS = "ResourceNumbers"
local NUMBERS_LEVEL = 10

-- Used only if the client will not say what colour a power is.
local FALLBACK_COLOURS = {
	health = { 0.65, 0.16, 0.16 },
	magicka = { 0.20, 0.38, 0.78 },
	stamina = { 0.27, 0.56, 0.20 },
}

local TRACK_COLOUR = { 0.06, 0.06, 0.06 }

-- The outline. Dark rather than black so it reads as a line drawn round the bar rather than a
-- gap in it.
addon.BORDER_COLOURS = { "black", "white", "silver", "gold", "red", "blue" }
local BORDER_PALETTE = {
	black = { 0, 0, 0 },
	white = { 1, 1, 1 },
	silver = { 0.75, 0.75, 0.75 },
	gold = { 1, 0.84, 0 },
	red = { 0.9, 0.2, 0.2 },
	blue = { 0.25, 0.55, 1 },
}
local BORDER_ALPHA = 0.82

function addon:PlainBorderColour()
	local key = self:Account().plainBorderColour
	return BORDER_PALETTE[key] and key or "black"
end

function addon:SetPlainBorderColour(key)
	if not BORDER_PALETTE[key] then return false end
	self:Account().plainBorderColour = key
	return true
end

-- ---------------------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------------------

function addon:BarStyle()
	local style = self:Account().style
	-- 1.3.x called the second style "liquid".
	if style == "liquid" then
		style = "plain"
		self:Account().style = style
	end
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

addon.MIN_PLAIN_OPACITY = 10
addon.MAX_PLAIN_OPACITY = 100
addon.DEFAULT_PLAIN_OPACITY = 100

function addon:PlainOpacity()
	local value = self:Account().plainOpacity
	if type(value) ~= "number" then
		return self.DEFAULT_PLAIN_OPACITY
	end
	return Clamp(Round(value), self.MIN_PLAIN_OPACITY, self.MAX_PLAIN_OPACITY)
end

function addon:SetPlainOpacity(value)
	self:Account().plainOpacity = Clamp(Round(value), self.MIN_PLAIN_OPACITY, self.MAX_PLAIN_OPACITY)
end

-- Whether this add-on's bars carry an outline of their own. The game's arrow-shaped frame is
-- always put away while one of these styles is on -- a flat rectangle inside an arrow frame is
-- neither one thing nor the other -- so an outline is the only frame on offer, and it is this
-- add-on's to draw.
function addon:PlainBorder()
	return self:Account().plainBorder ~= false
end

function addon:SetPlainBorder(value)
	self:Account().plainBorder = value and true or false
end

-- True while this add-on draws the bars itself, in either of its two shapes.
function addon:PlainWanted()
	if not self:Account().enabled then
		return false
	end
	local style = self:BarStyle()
	return style == "plain" or style == "rounded" or style == "neo" or style == "liquidflow"
end

-- MURA-HIGE Style: the one drawn at a size of its own.
function addon:BarsAreMuraHige()
	return self:BarStyle() == "rounded" or self:BarStyle() == "neo"
end

-- ---------------------------------------------------------------------------------------
-- A size in pixels, for the one style that offers it
--
-- Every other style scales: the bar keeps the shape the game drew and is made bigger or smaller
-- whole, because the width of those controls is not this add-on's (the attribute visualiser
-- writes it as buffs come and go, see FINDINGS §3). MURA-HIGE Style draws the bar itself, so
-- there is nothing to fight: it can be given a width and a height and be exactly that.
--
-- Unset means "as the game draws it", which is what keeps an install that never touches these
-- looking the way it did.
-- ---------------------------------------------------------------------------------------

addon.MIN_BAR_WIDTH, addon.MAX_BAR_WIDTH = 20, 800
addon.MIN_BAR_HEIGHT, addon.MAX_BAR_HEIGHT = 3, 80

-- The gamepad attribute bar: 224 of drawable width inside the 237 container, 17 high.
addon.GAME_BAR_WIDTH, addon.GAME_BAR_HEIGHT = 224, 17

function addon:BarSizeSaved(bar)
	local saved = self:Account().bars[bar.key]
	return saved and saved.width, saved and saved.height
end

-- The size to draw at: what was asked for, else the game's own.
function addon:BarSize(bar)
	local width, height = self:BarSizeSaved(bar)
	local measured = self:Account().measured[bar.key] or {}
	if type(width) ~= "number" then
		width = type(measured.barWidth) == "number" and measured.barWidth or self.GAME_BAR_WIDTH
	end
	if type(height) ~= "number" then
		height = type(measured.barHeight) == "number" and measured.barHeight or self.GAME_BAR_HEIGHT
	end
	return Clamp(Round(width), self.MIN_BAR_WIDTH, self.MAX_BAR_WIDTH),
		Clamp(Round(height), self.MIN_BAR_HEIGHT, self.MAX_BAR_HEIGHT)
end

function addon:SetBarSize(bar, which, value)
	local saved = self:Account().bars[bar.key]
	if which == "width" then
		saved.width = Clamp(Round(value), self.MIN_BAR_WIDTH, self.MAX_BAR_WIDTH)
	else
		saved.height = Clamp(Round(value), self.MIN_BAR_HEIGHT, self.MAX_BAR_HEIGHT)
	end
end

-- True while a bar is drawn at a size rather than scaled. That is the whole of what MURA-HIGE
-- Style is, so it is true for every bar the moment the style is chosen -- not only once a slider
-- has been moved.
--
-- It was the saved values that decided this until 1.10.2, which meant choosing the style changed
-- nothing on screen until a slider was touched, and the sizes looked as though they only applied
-- on the second attempt. Unset values are the game's own size; drawing that at a size of our own
-- looks the same and behaves consistently.
function addon:BarSizeIsOwn(bar)
	return self:BarsAreMuraHige()
end

-- ---------------------------------------------------------------------------------------
-- The controls
-- ---------------------------------------------------------------------------------------

local function Control(name)
	local control = _G[name]
	if type(control) ~= "table" and type(control) ~= "userdata" then
		return nil
	end
	if type(control.GetDimensions) ~= "function" then
		return nil
	end
	return control
end

plain.Control = Control

function plain:PowerColour(bar)
	local powerType = _G["COMBAT_MECHANIC_FLAGS_" .. bar.power:upper()]
	if powerType and type(GetInterfaceColor) == "function" and INTERFACE_COLOR_TYPE_POWER_START then
		local ok, r, g, b = pcall(GetInterfaceColor, INTERFACE_COLOR_TYPE_POWER_START, powerType)
		if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
			return r, g, b
		end
	end
	local fallback = FALLBACK_COLOURS[bar.key] or { 1, 1, 1 }
	return fallback[1], fallback[2], fallback[3]
end

function plain:Overlay(bar, entry)
	local existing = self.overlays[entry.name]
	if existing then
		return existing
	end
	local barControl = Control(entry.name)
	local container = Control(bar.container)
	if not barControl or not container or not addon.timers then
		return nil
	end
	-- Built the same way as the skill bar's controls, with the same fallback if the XML did not
	-- load.
	local control = addon.timers:Build("PBsConsoleHudCustomizerPlain", container, "PBsConsoleHudCustomizerPlainBar", entry.name)
	if not control then
		return nil
	end
	local overlay = {
		control = control,
		bar = barControl,
		reverse = entry.reverse,
		track = control.Track or control:GetNamedChild("Track"),
		fill = control.Fill or control:GetNamedChild("Fill"),
		key = bar.key,
		border = {},
	}
	for _, side in ipairs({ "Top", "Bottom", "Left", "Right" }) do
		overlay.border[side] = control["Border" .. side] or control:GetNamedChild("Border" .. side)
	end
	self.overlays[entry.name] = overlay
	self:AnchorOverlay(overlay, bar)
	self:ColourOverlay(bar, overlay)
	return overlay
end

-- Over the client's own fill, exactly: the whole of the bar control's rectangle.
-- Over the client's own bar, exactly -- or, where a size has been asked for, standing on the
-- edge the bar fills from at that size instead.
function plain:AnchorOverlay(overlay, bar)
	local control, barControl = overlay.control, overlay.bar
	local sized = bar and addon:BarSizeIsOwn(bar)
	control:ClearAnchors()
	if sized then
		-- Held by the edge the fill grows from and level with the bar the game has, which is
		-- where the position sliders put it.
		local point = overlay.reverse and RIGHT or LEFT
		control:SetAnchor(point, barControl, point, 0, 0)
		local width, height = addon:BarSize(bar)
		-- The health bar is two halves that meet in the middle, so each is half of what was
		-- asked for and the pair is the whole.
		if #bar.controls > 1 then
			if addon:BarStyle() == "neo" then
				-- Health's native halves meet here. NEO draws one continuous bar,
				-- centered at that same point, rather than two separate fills.
				control:ClearAnchors()
				control:SetAnchor(CENTER, Control(bar.controls[1].name), RIGHT, 0, 0)
			else
				width = width / 2
			end
		end
		control:SetDimensions(width, height)
		overlay.sizedWidth = width
	else
		overlay.sizedWidth = nil
		control:SetAnchor(TOPLEFT, barControl, TOPLEFT, 0, 0)
		control:SetAnchor(BOTTOMRIGHT, barControl, BOTTOMRIGHT, 0, 0)
	end
end

function plain:ColourOverlay(bar, overlay)
	local alpha = addon:PlainOpacity() / 100
	local r, g, b = self:PowerColour(bar)

	if overlay.track and type(overlay.track.SetCenterColor) == "function" then
		overlay.track:SetCenterColor(TRACK_COLOUR[1], TRACK_COLOUR[2], TRACK_COLOUR[3], alpha)
		if type(overlay.track.SetEdgeColor) == "function" then
			overlay.track:SetEdgeColor(0, 0, 0, 0)
		end
		overlay.track:SetHidden(false)
	end
	if overlay.fill and type(overlay.fill.SetColor) == "function" then
		local fill = overlay.fill
		-- Reset all vertices first so switching back to Square restores a solid fill.
		fill:SetColor(r, g, b, alpha)
		if addon:BarsAreMuraHige() and type(fill.SetVertexColors) == "function"
			and VERTEX_POINTS_TOPLEFT and VERTEX_POINTS_TOPRIGHT
			and VERTEX_POINTS_BOTTOMLEFT and VERTEX_POINTS_BOTTOMRIGHT then
			-- Keep each resource's hue: a small white blend at the top, a darker
			-- version at the bottom. Alpha is constant over the whole fill.
			local topR, topG, topB = r + (1 - r) * 0.2, g + (1 - g) * 0.2, b + (1 - b) * 0.2
			fill:SetVertexColors(VERTEX_POINTS_TOPLEFT, topR, topG, topB, alpha)
			fill:SetVertexColors(VERTEX_POINTS_TOPRIGHT, topR, topG, topB, alpha)
			fill:SetVertexColors(VERTEX_POINTS_BOTTOMLEFT, r * 0.55, g * 0.55, b * 0.55, alpha)
			fill:SetVertexColors(VERTEX_POINTS_BOTTOMRIGHT, r * 0.55, g * 0.55, b * 0.55, alpha)
		end
	end

	local border = addon:PlainBorder()
	local colour = BORDER_PALETTE[addon:PlainBorderColour()]
	for _, piece in pairs(overlay.border or {}) do
		if type(piece.SetCenterColor) == "function" then
			piece:SetCenterColor(colour[1], colour[2], colour[3], BORDER_ALPHA * alpha)
			if type(piece.SetEdgeColor) == "function" then
				piece:SetEdgeColor(0, 0, 0, 0)
			end
		end
		piece:SetHidden(not border)
	end
end

function plain:Restyle()
	for _, bar in ipairs(self.bars) do
		for _, entry in ipairs(bar.controls) do
			local overlay = self.overlays[entry.name]
			if overlay then
				self:AnchorOverlay(overlay, bar)
				self:ColourOverlay(bar, overlay)
			end
		end
	end
end

function plain:HideAll()
	for _, overlay in pairs(self.overlays) do
		overlay.control:SetHidden(true)
	end
end

-- ---------------------------------------------------------------------------------------
-- The game's own frame and background
--
-- Hidden while this style is on, and put back the moment it is not. Only the flag is touched,
-- and only when it is not already what it should be, so there is nothing to undo beyond it.
-- ---------------------------------------------------------------------------------------

function plain:Dress(bar, hide)
	for _, suffix in ipairs(DRESSING) do
		local name = bar.container .. suffix
		local control = Control(name)
		if control and type(control.SetHidden) == "function" then
			local wanted = hide and true or false
			if self.hidden[name] ~= wanted then
				addon:Write("plain dressing", control.SetHidden, control, wanted)
				self.hidden[name] = wanted
			end
		end
	end
end

function plain:DressAll(hide)
	for _, bar in ipairs(self.bars) do
		self:Dress(bar, hide)
	end
end

-- The numbers, lifted over the rectangle while this style is on and put back where the client
-- had them when it is not. Re-asserted on every update rather than remembered as done: the
-- client re-applies its own templates to these controls, and a template carries a draw tier.
addon.RESOURCE_TEXT_ALIGNMENTS = { "left", "right", "center" }

function addon:ResourceTextAlignment()
	local key = self:Account().resourceTextAlignment
	if key == "right" or key == "center" then return key end
	return "left"
end

function addon:SetResourceTextAlignment(key)
	for _, known in ipairs(self.RESOURCE_TEXT_ALIGNMENTS) do
		if key == known then
			self:Account().resourceTextAlignment = key
			return true
		end
	end
	return false
end

-- Anchor the label across the drawn bar, not the client's original 224px bar.
-- Save its alignment and anchors before the first write, and restore on style exit.
function plain:AlignNumbers(bar, enabled)
	local label = Control(bar.container .. NUMBERS)
	if not label then return end
	self.numberLayouts = self.numberLayouts or {}
	local saved = self.numberLayouts[label]
	if not enabled then
		if saved then
			addon:Write("number layout", label.ClearAnchors, label)
			for _, anchor in ipairs(saved.anchors) do
				addon:Write("number layout", label.SetAnchor, label, unpack(anchor))
			end
			addon:Write("number layout", label.SetHorizontalAlignment, label, saved.alignment)
			self.numberLayouts[label] = nil
		end
		return
	end
	local first = self.overlays[bar.controls[1].name]
	local last = self.overlays[bar.controls[#bar.controls].name]
	if addon:BarStyle() == "neo" then last = first end
	if not first or not last then return end
	if not saved then
		if type(label.GetHorizontalAlignment) ~= "function" then return end
		local ok, alignment = pcall(label.GetHorizontalAlignment, label)
		if not ok then return end
		saved = { alignment = alignment, anchors = {} }
		for index = 0, 1 do
			local read, valid, point, target, relative, x, y, constrains = pcall(label.GetAnchor, label, index)
			if not read then return end
			if valid then
				saved.anchors[#saved.anchors + 1] = { point, target, relative, x, y, constrains }
			end
		end
		self.numberLayouts[label] = saved
	end
	local key = addon:ResourceTextAlignment()
	local alignment = key == "right" and TEXT_ALIGN_RIGHT or key == "center" and TEXT_ALIGN_CENTER or TEXT_ALIGN_LEFT
	addon:Write("number layout", label.ClearAnchors, label)
	addon:Write("number layout", label.SetAnchor, label, LEFT, first.control, LEFT, 4, 0)
	addon:Write("number layout", label.SetAnchor, label, RIGHT, last.control, RIGHT, -4, 0)
	addon:Write("number layout", label.SetHorizontalAlignment, label, alignment)
end

function plain:RaiseNumbers(bar, raise)
	if not raise then self:AlignNumbers(bar, false) end
	local control = Control(bar.container .. NUMBERS)
	if not control or type(control.SetDrawTier) ~= "function" or type(control.SetDrawLevel) ~= "function" then
		return false
	end

	if raise then
		if not self.numbers[bar.key] then
			local okTier, tier = pcall(control.GetDrawTier, control)
			local okLevel, level = pcall(control.GetDrawLevel, control)
			self.numbers[bar.key] = {
				tier = okTier and tier or nil,
				level = okLevel and level or nil,
			}
		end
		addon:Write("numbers", control.SetDrawTier, control, DT_HIGH)
		addon:Write("numbers", control.SetDrawLevel, control, NUMBERS_LEVEL)
		return true
	end

	local saved = self.numbers[bar.key]
	if not saved then
		return false
	end
	if saved.tier ~= nil then
		addon:Write("numbers", control.SetDrawTier, control, saved.tier)
	end
	if saved.level ~= nil then
		addon:Write("numbers", control.SetDrawLevel, control, saved.level)
	end
	self.numbers[bar.key] = nil
	return true
end

function plain:RaiseAllNumbers(raise)
	for _, bar in ipairs(self.bars) do
		self:RaiseNumbers(bar, raise)
	end
end

-- ---------------------------------------------------------------------------------------
-- The client's own fill, out of the way
--
-- Only needed for a bar drawn at a size of its own: a rectangle narrower or shorter than the
-- game's leaves the game's fill showing round it. The bar control cannot simply be hidden --
-- the damage shield overlays are its children (powershield.lua anchors them to it *and* parents
-- them to it) and would go with it -- so its colours are taken to nothing instead, and its gloss,
-- which has no children, is hidden.
--
-- Putting it back is the client's own line: ZO_StatusBar_SetGradientColor with
-- ZO_POWER_BAR_GRADIENT_COLORS for that power, which is exactly what ZO_PlayerAttributeBar's
-- RefreshColor does.
-- ---------------------------------------------------------------------------------------

local function Gloss(control)
	if control.gloss then
		return control.gloss
	end
	if type(control.GetNamedChild) == "function" then
		local ok, gloss = pcall(control.GetNamedChild, control, "Gloss")
		if ok then
			return gloss
		end
	end
	return nil
end

function plain:BlankClientBar(bar, overlay, blank)
	local control = overlay.bar
	if type(control.SetGradientColors) ~= "function" then
		return false
	end
	local name = overlay.key .. ":" .. tostring(control.GetName and control:GetName() or "?")
	if (self.blanked[name] == true) == (blank and true or false) then
		return true
	end

	local gloss = Gloss(control)
	if blank then
		addon:Write("bar colour", control.SetGradientColors, control, 0, 0, 0, 0, 0, 0, 0, 0)
		if gloss and type(gloss.SetHidden) == "function" then
			addon:Write("bar colour", gloss.SetHidden, gloss, true)
		end
		self.blanked[name] = true
		return true
	end

	local powerType = _G["COMBAT_MECHANIC_FLAGS_" .. bar.power:upper()]
	local gradient = powerType and ZO_POWER_BAR_GRADIENT_COLORS and ZO_POWER_BAR_GRADIENT_COLORS[powerType]
	if gradient and gradient[1] and gradient[2] then
		local ok, r, g, b, a = pcall(gradient[1].UnpackRGBA, gradient[1])
		local ok2, r2, g2, b2, a2 = pcall(gradient[2].UnpackRGBA, gradient[2])
		if ok and ok2 then
			addon:Write("bar colour", control.SetGradientColors, control, r, g, b, a, r2, g2, b2, a2)
		end
	end
	if gloss and type(gloss.SetHidden) == "function" then
		addon:Write("bar colour", gloss.SetHidden, gloss, false)
	end
	self.blanked[name] = nil
	return true
end

function plain:BlankAll(blank)
	for _, bar in ipairs(self.bars) do
		for _, entry in ipairs(bar.controls) do
			local overlay = self.overlays[entry.name]
			if overlay then
				self:BlankClientBar(bar, overlay, blank)
			end
		end
	end
end

-- ---------------------------------------------------------------------------------------
-- How full the bar is
-- ---------------------------------------------------------------------------------------

function plain:Fraction(bar)
	local powerType = _G["COMBAT_MECHANIC_FLAGS_" .. bar.power:upper()]
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

function plain:UpdateOverlay(overlay, fraction)
	local control = overlay.control
	local barWidth = overlay.sizedWidth
	if not barWidth then
		local okWidth, width = pcall(overlay.bar.GetWidth, overlay.bar)
		if not okWidth or type(width) ~= "number" or width <= 0 then
			control:SetHidden(true)
			return
		end
		barWidth = width
	end
	control:SetHidden(false)

	local fill = overlay.fill
	if not fill then
		return
	end
	local fillWidth = barWidth * fraction
	if fillWidth < 1 then
		fill:SetHidden(true)
		return
	end
	fill:ClearAnchors()
	if overlay.reverse and addon:BarStyle() ~= "neo" then
		fill:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
		fill:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, 0, 0)
	else
		fill:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
		fill:SetAnchor(BOTTOMLEFT, control, BOTTOMLEFT, 0, 0)
	end
	fill:SetWidth(fillWidth)
	fill:SetHidden(false)
end

-- ---------------------------------------------------------------------------------------
-- Liquid
--
-- The native status bars keep their fill, gloss, frames and the amount they show; the engine
-- still owns all of that, including the reversed bars and health's two halves. What is laid over
-- them is meant to read as a liquid in a glass tube, the way Diablo's orbs do, out of nothing but
-- untextured rectangles -- no art ships with this add-on:
--
--   depth     the lower part of the liquid sinks into shadow
--   currents  soft light and dark masses drifting through it at different speeds. Each is four
--             rectangles whose corners are coloured so the brightness falls away from the middle
--             (SetVertexColors), which is what makes them soft rather than lines
--   surface   the moving end of the fill is the liquid's surface: a bright wobbling edge with a
--             glow behind it, which sloshes when the amount changes and settles again
--   drain     what was just lost stays a moment as a pale trace, then drains away
--   bubbles   small beads with a point of light, rising and popping at the top
--   glass     a reflection along the top of the whole tube, and a glint that crosses it now and
--             then
--   frame     a square frame and a see-through track in place of the game's arrow-ended frame
--             and background, which a straight tube of liquid does not fit (1.26.0). It takes
--             the same outline switch and colour as Square and MURA-HIGE
--
-- Parented to the attribute container (not the StatusBar) for console visibility.
-- ---------------------------------------------------------------------------------------
-- See-through, so the liquid reads as liquid over what is behind it rather than as paint: the body
-- at 62%, and every effect over it scaled to 80% of what it was drawn at in 1.25.0.
local LIQUID_BODY_ALPHA = 0.62
local LIQUID_EFFECT_ALPHA = 0.8
-- The track the liquid sits in, dark and see-through.
local LIQUID_TRACK_COLOUR = { 0.02, 0.02, 0.03, 0.45 }
local LIQUID_CURRENTS = 6
local LIQUID_SURFACE_SEGMENTS = 5
local LIQUID_BUBBLES = 4
-- How quickly a slosh settles, and how much a change in the amount stirs it.
local LIQUID_SLOSH_SETTLE_MS = 450
local LIQUID_SLOSH_GAIN = 6
-- The pale trace of what was lost: how long it waits, and how fast it drains (fraction per ms).
local LIQUID_DRAIN_HOLD_MS = 150
local LIQUID_DRAIN_RATE = 0.0009

-- Where the effect may draw, inside one native status bar.
--
-- The status bar a console draws is ZO_PlayerAttributeStatusBar_Gamepad_Template: 64 high
-- (playerattributebartemplates.xml), with the coloured band in the middle of that texture and
-- transparent art above and below it. The bar the player sees is the 23-high container's 17, as
-- it is on keyboard. Everything used to be worked out from the 64, and on a PS5 that meant:
--
--   an end inset of 1.5 x 64 = 96 on each side, which left magicka and stamina 32 pixels of a
--   224-pixel bar in the middle, and left each 111-pixel half of health less than nothing, so
--   health was hidden outright; and a band 41 high over a bar 17 high, drawn above and below it.
--
-- The offline harness built its bars 17 high, the keyboard size, so every one of those tests
-- passed. They are built 64 high now.
--
-- So: the band is 17/23 of the container, centred on the status bar, and never more than the
-- status bar itself. The moving end of the fill keeps two pixels clear of the leading edge.
--
-- Until 1.26.0 the outer ends were also kept clear by half the band, because the game's frame
-- comes to a point there. Liquid draws a square frame of its own now, so there is no point to keep
-- clear of and the liquid runs to both ends. Health's halves always met flat in the middle.
local LIQUID_BAND_OF_CONTAINER = 17 / 23
local LIQUID_BAND_MARGIN = 0.12
local LIQUID_LEADING_EDGE = 2

function plain:LiquidBounds(bar, entry, native, fraction)
	local width, height = native:GetDimensions()
	local container = Control(bar.container)
	local containerHeight = height
	if container then
		local _, measured = container:GetDimensions()
		if type(measured) == "number" and measured > 0 then
			containerHeight = measured
		end
	end
	local band = math.min(height, containerHeight * LIQUID_BAND_OF_CONTAINER)
	local bandTop = (height - band) / 2
	local margin = math.max(1, band * LIQUID_BAND_MARGIN)

	local halves = #bar.controls > 1
	local isRightHalf = halves and bar.controls[2].name == entry.name
	local barFrom, barTo = 0, width

	local filled = width * Clamp(fraction or 0, 0, 1)
	-- A full bar has no moving edge to keep clear of: the liquid meets the end of the tube.
	local edgeClear = (fraction or 0) < 0.99 and LIQUID_LEADING_EDGE or 0
	local from, to
	if entry.reverse then
		from, to = width - filled + edgeClear, width
	else
		from, to = 0, filled - edgeClear
	end
	-- The surface is only drawn where there is a surface: not on a full bar, where the liquid
	-- meets the end of the tube.
	local edgeOpen = (fraction or 0) < 0.99
	from = math.max(from, barFrom)
	to = math.min(to, barTo)

	return {
		width = width,
		from = from,
		to = to,
		top = bandTop + margin,
		bottom = bandTop + band - margin,
		bandTop = bandTop,
		bandBottom = bandTop + band,
		barFrom = barFrom,
		barTo = barTo,
		edgeOpen = edgeOpen and filled > 0,
		reverse = entry.reverse and true or false,
		filled = filled,
		-- Health's right half carries on where the left half stops, so what moves along the bar
		-- is placed in one coordinate that runs the whole length of it.
		offset = isRightHalf and width or 0,
		length = halves and width * 2 or width,
	}
end

local VERTEX_TL, VERTEX_TR = VERTEX_POINTS_TOPLEFT, VERTEX_POINTS_TOPRIGHT
local VERTEX_BL, VERTEX_BR = VERTEX_POINTS_BOTTOMLEFT, VERTEX_POINTS_BOTTOMRIGHT

local function Lighten(r, g, b, k)
	return r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k
end

local function Place(texture, parent, x, y, w, h)
	texture:ClearAnchors()
	texture:SetAnchor(TOPLEFT, parent, TOPLEFT, x, y)
	texture:SetDimensions(w, h)
	texture:SetHidden(false)
end

-- One colour, a different alpha at each corner. Without per-corner colours the texture takes
-- the average, which is dimmer but still in the right place.
local function Corners(texture, r, g, b, topLeft, topRight, bottomLeft, bottomRight)
	if VERTEX_TL and type(texture.SetVertexColors) == "function" then
		texture:SetColor(r, g, b, math.max(topLeft, topRight, bottomLeft, bottomRight))
		texture:SetVertexColors(VERTEX_TL, r, g, b, topLeft)
		texture:SetVertexColors(VERTEX_TR, r, g, b, topRight)
		texture:SetVertexColors(VERTEX_BL, r, g, b, bottomLeft)
		texture:SetVertexColors(VERTEX_BR, r, g, b, bottomRight)
	else
		texture:SetColor(r, g, b, (topLeft + topRight + bottomLeft + bottomRight) / 4)
	end
end

-- A rectangle cut to the bounds it may draw in, or nil when nothing is left of it.
local function Clip(x0, y0, x1, y1, bx0, by0, bx1, by1)
	x0, y0 = math.max(x0, bx0), math.max(y0, by0)
	x1, y1 = math.min(x1, bx1), math.min(y1, by1)
	if x1 - x0 < 0.5 or y1 - y0 < 0.5 then
		return nil
	end
	return x0, y0, x1, y1
end

-- A soft mass of light: four quarters around (cx, cy), each brightest at the middle corner and
-- falling to nothing at the rim, cut to the bounds. The alpha at a corner is worked out from where
-- that corner really is, so a mass cut by the edge of the fill still fades correctly.
local function SoftMass(pieces, parent, cx, cy, hw, hh, r, g, b, alpha, bx0, by0, bx1, by1)
	local function At(x, y)
		local fx = 1 - math.abs(x - cx) / hw
		local fy = 1 - math.abs(y - cy) / hh
		if fx <= 0 or fy <= 0 then
			return 0
		end
		return alpha * fx * fy
	end
	local quarters = {
		{ cx - hw, cy - hh, cx, cy },
		{ cx, cy - hh, cx + hw, cy },
		{ cx - hw, cy, cx, cy + hh },
		{ cx, cy, cx + hw, cy + hh },
	}
	for index, quarter in ipairs(quarters) do
		local piece = pieces[index]
		local x0, y0, x1, y1 = Clip(quarter[1], quarter[2], quarter[3], quarter[4], bx0, by0, bx1, by1)
		if x0 then
			Place(piece, parent, x0, y0, x1 - x0, y1 - y0)
			Corners(piece, r, g, b, At(x0, y0), At(x1, y0), At(x0, y1), At(x1, y1))
		else
			piece:SetHidden(true)
		end
	end
end

function plain:LiquidGroup(bar, entry, native)
	self.liquidRibbons = self.liquidRibbons or {}
	local group = self.liquidRibbons[entry.name]
	if group then
		if group.native ~= native then
			group.control:SetParent(Control(bar.container))
			group.control:ClearAnchors()
			group.control:SetAnchor(TOPLEFT, native, TOPLEFT, 0, 0)
			group.control:SetAnchor(BOTTOMRIGHT, native, BOTTOMRIGHT, 0, 0)
			group.native = native
		end
		return group
	end
	if not WINDOW_MANAGER or not CT_TEXTURE then
		return nil
	end
	local prefix = "PBsLiquid" .. entry.name
	local root = WINDOW_MANAGER:CreateControl(prefix, Control(bar.container), CT_CONTROL)
	root:SetAnchor(TOPLEFT, native, TOPLEFT, 0, 0)
	root:SetAnchor(BOTTOMRIGHT, native, BOTTOMRIGHT, 0, 0)
	root:SetDrawTier(DT_HIGH)
	root:SetDrawLevel(1)
	group = { control = root, native = native, textures = {}, currents = {}, surface = {}, bubbles = {} }
	local count = 0
	local function Texture(level, role)
		count = count + 1
		local texture = WINDOW_MANAGER:CreateControl(prefix .. "Piece" .. count, root, CT_TEXTURE)
		texture:SetDrawLevel(level)
		texture:SetHidden(true)
		texture.pbsLiquidRole = role
		group.textures[#group.textures + 1] = texture
		return texture
	end
	-- Back to front.
	group.shade = Texture(1, "fill")
	for index = 1, LIQUID_CURRENTS do
		local pieces = {}
		for quarter = 1, 4 do
			pieces[quarter] = Texture(2, "fill")
		end
		group.currents[index] = pieces
	end
	group.drain = Texture(2, "tube")
	for index = 1, LIQUID_BUBBLES do
		group.bubbles[index] = { body = Texture(3, "fill"), shine = Texture(4, "fill") }
	end
	group.glow = Texture(4, "fill")
	for index = 1, LIQUID_SURFACE_SEGMENTS do
		group.surface[index] = Texture(5, "fill")
	end
	group.glass = Texture(6, "tube")
	group.glint = { Texture(6, "tube"), Texture(6, "tube") }
	self.liquidRibbons[entry.name] = group
	return group
end

function plain:LiquidRibbons(bar, entry, native, fraction, now)
	local group = self:LiquidGroup(bar, entry, native)
	if not group then
		return
	end
	local root = group.control
	local bounds = self:LiquidBounds(bar, entry, native, fraction)
	local from, to, top, bottom = bounds.from, bounds.to, bounds.top, bounds.bottom
	local depth = bottom - top
	fraction = Clamp(fraction or 0, 0, 1)

	-- The slosh and the drain both need to know how the amount moved since last time.
	local dt = group.lastNow and Clamp(now - group.lastNow, 0, 200) or 0
	group.lastNow = now
	local moved = group.lastFraction and math.abs(fraction - group.lastFraction) or 0
	group.lastFraction = fraction
	group.slosh = math.min(1, (group.slosh or 0) * math.exp(-dt / LIQUID_SLOSH_SETTLE_MS) + moved * LIQUID_SLOSH_GAIN)
	if not group.drainLevel or fraction >= group.drainLevel then
		group.drainLevel, group.drainSince = fraction, nil
	else
		group.drainSince = group.drainSince or now
		if now - group.drainSince > LIQUID_DRAIN_HOLD_MS then
			group.drainLevel = math.max(fraction, group.drainLevel - dt * LIQUID_DRAIN_RATE)
		end
	end
	local draining = group.drainLevel - fraction

	local liquid = depth >= 3 and to - from >= 2
	if not liquid and draining <= 0.002 then
		root:SetHidden(true)
		return
	end
	root:SetHidden(false)
	for _, texture in ipairs(group.textures) do
		texture:SetHidden(true)
	end

	local r, g, b = self:PowerColour(bar)
	local seconds = now / 1000
	local lr, lg, lb = Lighten(r, g, b, 0.55)

	if liquid then
		-- Depth: the lower part of the liquid sinks into shadow.
		local shadeTop = top + depth * 0.35
		Place(group.shade, root, from, shadeTop, to - from, bottom - shadeTop)
		Corners(group.shade, 0, 0, 0, 0, 0, 0.5 * LIQUID_EFFECT_ALPHA, 0.5 * LIQUID_EFFECT_ALPHA)

		-- Currents, placed along the whole bar and cut to what is filled.
		for index, pieces in ipairs(group.currents) do
			local light = index % 3 ~= 0
			local direction = index % 2 == 0 and -1 or 1
			local speed = direction * (7 + index * 4)
			local hw = 14 + (index * 7) % 13
			local hh = depth * (0.42 + (index % 3) * 0.1)
			local travel = bounds.length + hw * 2
			local centre = ((index * 53.7 + speed * seconds) % travel) - hw - bounds.offset
			local cy = top + depth * (0.5 + 0.3 * math.sin(seconds * (0.5 + 0.11 * index) + index * 1.7))
			local breathe = 0.8 + 0.2 * math.sin(seconds * 1.3 + index)
			if light then
				SoftMass(pieces, root, centre, cy, hw, hh, lr, lg, lb, 0.42 * breathe * LIQUID_EFFECT_ALPHA, from, top, to, bottom)
			else
				SoftMass(pieces, root, centre, cy, hw, hh, r * 0.25, g * 0.25, b * 0.25, 0.4 * breathe * LIQUID_EFFECT_ALPHA, from, top, to, bottom)
			end
		end

		-- Bubbles: beads with a point of light that rise and pop at the top.
		if to - from >= 6 then
			for index, bubble in ipairs(group.bubbles) do
				local period = 1.8 + index * 0.35
				local progress = (seconds / period + index * 0.37) % 1
				local size = 1.8 + 0.6 * progress
				local x = from + (to - from) * ((index * 0.29 + 0.11) % 1) + math.sin(seconds * 1.3 + index) * 2
				x = Clamp(x, from, to - size)
				local y = bottom - size - (depth - size) * progress
				local alpha = math.sin(math.pi * progress) * LIQUID_EFFECT_ALPHA
				Place(bubble.body, root, x, y, size, size)
				bubble.body:SetColor(lr, lg, lb, 0.55 * alpha)
				Place(bubble.shine, root, x, y, math.min(1, size), math.min(1, size))
				bubble.shine:SetColor(1, 1, 1, 0.9 * alpha)
			end
		end

		-- The surface, where the fill ends inside the tube.
		if bounds.edgeOpen and to - from >= 6 then
			local slosh = group.slosh
			local amplitude = 0.6 + slosh * 3
			local segment = depth / LIQUID_SURFACE_SEGMENTS
			local lineWidth = 1.5
			local sr, sg, sb = Lighten(r, g, b, 0.8)
			for index, piece in ipairs(group.surface) do
				local wobble = (math.sin(seconds * (7 + slosh * 6) + index * 1.1) * 0.5 + 0.5) * amplitude
				local x = bounds.reverse and from + wobble or to - lineWidth - wobble
				Place(piece, root, x, top + (index - 1) * segment, lineWidth, segment)
				piece:SetColor(sr, sg, sb, 0.85 * LIQUID_EFFECT_ALPHA)
			end
			local glowWidth = math.min(8 + slosh * 6, to - from)
			local glowAlpha = (0.35 + slosh * 0.3) * LIQUID_EFFECT_ALPHA
			if bounds.reverse then
				Place(group.glow, root, from, top, glowWidth, depth)
				Corners(group.glow, lr, lg, lb, glowAlpha, 0, glowAlpha, 0)
			else
				Place(group.glow, root, to - glowWidth, top, glowWidth, depth)
				Corners(group.glow, lr, lg, lb, 0, glowAlpha, 0, glowAlpha)
			end
		end
	end

	-- What was just lost, draining away beyond the surface.
	if draining > 0.002 then
		local width = bounds.width
		local x0, x1
		if bounds.reverse then
			x0, x1 = width - width * group.drainLevel, width - bounds.filled
		else
			x0, x1 = bounds.filled, width * group.drainLevel
		end
		local cx0, cy0, cx1, cy1 = Clip(x0, top, x1, bottom, bounds.barFrom, top, bounds.barTo, bottom)
		if cx0 then
			local alpha = 0.5 * Clamp(draining * 10, 0, 1) * LIQUID_EFFECT_ALPHA
			Place(group.drain, root, cx0, cy0, cx1 - cx0, cy1 - cy0)
			-- Strongest against the liquid, thinning out towards where the level was.
			if bounds.reverse then
				Corners(group.drain, lr, lg, lb, alpha * 0.3, alpha, alpha * 0.3, alpha)
			else
				Corners(group.drain, lr, lg, lb, alpha, alpha * 0.3, alpha, alpha * 0.3)
			end
		end
	end

	-- Glass: a reflection along the top of the whole tube, and a glint that crosses it.
	local glassTop = bounds.bandTop + math.max(1, depth * 0.08)
	local glassHeight = 1.2
	local gx0, gy0, gx1, gy1 = Clip(bounds.barFrom, glassTop, bounds.barTo, glassTop + glassHeight,
		bounds.barFrom, bounds.bandTop, bounds.barTo, bounds.bandBottom)
	if gx0 then
		Place(group.glass, root, gx0, gy0, gx1 - gx0, gy1 - gy0)
		group.glass:SetColor(1, 1, 1, 0.16 * LIQUID_EFFECT_ALPHA)
	end
	local sweep = bounds.length + 240
	local glintCentre = ((seconds * 70) % sweep) - 120 - bounds.offset
	local glintHalf = 16
	local halvesOfGlint = {
		{ glintCentre - glintHalf, glintCentre, 0, 0.5 * LIQUID_EFFECT_ALPHA },
		{ glintCentre, glintCentre + glintHalf, 0.5 * LIQUID_EFFECT_ALPHA, 0 },
	}
	for index, part in ipairs(halvesOfGlint) do
		local piece = group.glint[index]
		local x0, y0, x1, y1 = Clip(part[1], glassTop, part[2], glassTop + 2,
			bounds.barFrom, bounds.bandTop, bounds.barTo, bounds.bandBottom)
		if x0 then
			local function At(x)
				return part[3] + (part[4] - part[3]) * (x - part[1]) / (part[2] - part[1])
			end
			Place(piece, root, x0, y0, x1 - x0, y1 - y0)
			Corners(piece, 1, 1, 1, At(x0), At(x1), At(x0), At(x1))
		end
	end
end

-- The square frame round one whole bar -- both of health's halves together -- in the band the
-- player sees: a see-through track under the game's fill, and an outline over it.
function plain:LiquidFrame(bar)
	self.liquidFrames = self.liquidFrames or {}
	local first = Control(bar.controls[1].name)
	local last = Control(bar.controls[#bar.controls].name)
	local container = Control(bar.container)
	if not first or not last or not container or not WINDOW_MANAGER or not CT_TEXTURE then
		return nil
	end
	local frame = self.liquidFrames[bar.key]
	if not frame then
		local prefix = "PBsLiquidFrame" .. bar.key
		frame = { border = {} }
		-- Under the game's own fill, which is drawn at its default tier.
		frame.track = WINDOW_MANAGER:CreateControl(prefix .. "Track", container, CT_TEXTURE)
		frame.track:SetDrawTier(DT_LOW)
		frame.track:SetDrawLevel(0)
		-- Over the fill and the liquid, under the numbers (level 10).
		for _, side in ipairs({ "Top", "Bottom", "Left", "Right" }) do
			local piece = WINDOW_MANAGER:CreateControl(prefix .. side, container, CT_TEXTURE)
			piece:SetDrawTier(DT_HIGH)
			piece:SetDrawLevel(8)
			frame.border[side] = piece
		end
		self.liquidFrames[bar.key] = frame
	end

	local _, height = first:GetDimensions()
	local _, containerHeight = container:GetDimensions()
	if type(containerHeight) ~= "number" or containerHeight <= 0 then
		containerHeight = height
	end
	local half = math.min(height, containerHeight * LIQUID_BAND_OF_CONTAINER) / 2
	if frame.half ~= half or frame.first ~= first or frame.last ~= last then
		local track = frame.track
		track:ClearAnchors()
		track:SetAnchor(TOPLEFT, first, LEFT, 0, -half)
		track:SetAnchor(BOTTOMRIGHT, last, RIGHT, 0, half)
		local border = frame.border
		border.Top:ClearAnchors()
		border.Top:SetAnchor(TOPLEFT, first, LEFT, 0, -half)
		border.Top:SetAnchor(BOTTOMRIGHT, last, RIGHT, 0, -half + 1)
		border.Bottom:ClearAnchors()
		border.Bottom:SetAnchor(TOPLEFT, first, LEFT, 0, half - 1)
		border.Bottom:SetAnchor(BOTTOMRIGHT, last, RIGHT, 0, half)
		border.Left:ClearAnchors()
		border.Left:SetAnchor(TOPLEFT, first, LEFT, 0, -half)
		border.Left:SetAnchor(BOTTOMRIGHT, first, LEFT, 1, half)
		border.Right:ClearAnchors()
		border.Right:SetAnchor(TOPLEFT, last, RIGHT, -1, -half)
		border.Right:SetAnchor(BOTTOMRIGHT, last, RIGHT, 0, half)
		frame.half, frame.first, frame.last = half, first, last
	end

	local t = LIQUID_TRACK_COLOUR
	frame.track:SetColor(t[1], t[2], t[3], t[4])
	frame.track:SetHidden(false)
	local outline = addon:PlainBorder()
	local colour = BORDER_PALETTE[addon:PlainBorderColour()]
	for _, piece in pairs(frame.border) do
		piece:SetColor(colour[1], colour[2], colour[3], BORDER_ALPHA)
		piece:SetHidden(not outline)
	end
	return frame
end

function plain:HideLiquidFrames()
	for _, frame in pairs(self.liquidFrames or {}) do
		frame.track:SetHidden(true)
		for _, piece in pairs(frame.border) do
			piece:SetHidden(true)
		end
	end
end

function plain:RestoreLiquid()
	for _, group in pairs(self.liquidRibbons or {}) do group.control:SetHidden(true) end
	self:HideLiquidFrames()
	for control, colours in pairs(self.liquidColours or {}) do
		addon:Write("liquid colour", control.SetGradientColors, control, unpack(colours))
	end
	self.liquidColours = nil
end

function plain:UpdateLiquid()
	if not self.liquidColours then
		self:HideAll()
		self:RaiseAllNumbers(false)
		self:BlankAll(false)
		self.liquidColours = {}
	end
	local now = GetFrameTimeMilliseconds and GetFrameTimeMilliseconds() or 0
	local wave = (math.sin(now / 1300) + 1) / 2
	local dark, light = 0.60 + wave * 0.18, 0.12 + (1 - wave) * 0.18
	for _, bar in ipairs(self.bars) do
		local fraction = self:Fraction(bar)
		self:RaiseNumbers(bar, true)
		-- The game's arrow-ended frame and background go; the square frame takes their place.
		self:Dress(bar, true)
		self:LiquidFrame(bar)
		local powerType = _G["COMBAT_MECHANIC_FLAGS_" .. bar.power:upper()]
		local gradient = powerType and ZO_POWER_BAR_GRADIENT_COLORS and ZO_POWER_BAR_GRADIENT_COLORS[powerType]
		if gradient and gradient[1] and gradient[2] then
			local r, g, b, a = gradient[1]:UnpackRGBA()
			local r2, g2, b2, a2 = gradient[2]:UnpackRGBA()
			for _, entry in ipairs(bar.controls) do
				local control = Control(entry.name)
				if control and type(control.SetGradientColors) == "function" then
					self:LiquidRibbons(bar, entry, control, fraction, now)
					self.liquidColours[control] = self.liquidColours[control] or { r, g, b, a, r2, g2, b2, a2 }
					addon:Write("liquid colour", control.SetGradientColors, control,
						r * dark, g * dark, b * dark, a * LIQUID_BODY_ALPHA,
						r2 + (1 - r2) * light, g2 + (1 - g2) * light, b2 + (1 - b2) * light, a2 * LIQUID_BODY_ALPHA)
				end
			end
		end
	end
end

function plain:Update()
	if addon:BarStyle() == "liquidflow" then
		self:UpdateLiquid()
		return
	end
	if self.liquidColours then self:RestoreLiquid() end
	for _, bar in ipairs(self.bars) do
		local fraction = self:Fraction(bar)
		self:Dress(bar, true)
		self:RaiseNumbers(bar, true)
		local sized = addon:BarSizeIsOwn(bar)
		for _, entry in ipairs(bar.controls) do
			local overlay = self:Overlay(bar, entry)
			if overlay then
				self:AnchorOverlay(overlay, bar)
				self:ColourOverlay(bar, overlay)
				self:BlankClientBar(bar, overlay, sized)
				if addon:BarStyle() == "neo" and bar.key == "health" and not entry.reverse then
					-- The left overlay now covers the full health bar. Keep the other
					-- native half blanked, without drawing a duplicate track or border.
					overlay.control:SetHidden(true)
				elseif fraction then
					self:UpdateOverlay(overlay, fraction)
				else
					overlay.control:SetHidden(true)
				end
			end
		end
		self:AlignNumbers(bar, addon:BarsAreMuraHige())
	end
end

-- ---------------------------------------------------------------------------------------
-- What the plain style is really doing
-- ---------------------------------------------------------------------------------------

function plain:PrintStatus()
	local Line = addon.Line
	Line("|cFF69B4%s|r -- the bars this add-on draws", addon.title)
	Line("  style=%s opacity=%d%% outline=%s running=%s hud=%s", addon:BarStyle(), addon:PlainOpacity(),
		tostring(addon:PlainBorder()), tostring(self.running == true), tostring(self.hudShown ~= false))
	if addon:BarStyle() == "standard" then
		Line("  the style is Standard, so nothing is drawn. Set it in the settings panel, or")
		Line("  |cFFFFFF%s style plain|r", addon.slash)
	end

	for _, bar in ipairs(self.bars) do
		local fraction = self:Fraction(bar)
		Line("|cFF69B4  %s|r  full=%s", bar.key, fraction and string.format("%d%%", Round(fraction * 100)) or "unknown")
		for _, entry in ipairs(bar.controls) do
			local barControl = Control(entry.name)
			if not barControl then
				Line("    %s: not on this client", entry.name)
			else
				local okWidth, width = pcall(barControl.GetWidth, barControl)
				local okAlpha, alpha = pcall(barControl.GetAlpha, barControl)
				local overlay = self.overlays[entry.name]
				Line("    %s: bar %s wide, alpha=%s", entry.name, okWidth and tostring(Round(width)) or "?",
					okAlpha and string.format("%.2f", alpha) or "?")
				-- Liquid's geometry, so a PS5 can confirm the band it draws in: the status bar's
				-- own height (64 on a console), the container's, and where the effect goes.
				if addon:BarStyle() == "liquidflow" then
					local okSize, nativeWidth, nativeHeight = pcall(barControl.GetDimensions, barControl)
					local okBounds, bounds = pcall(self.LiquidBounds, self, bar, entry, barControl, fraction or 0)
					local group = self.liquidRibbons and self.liquidRibbons[entry.name]
					if okSize and okBounds then
						Line("      liquid: control %dx%d, band y %.1f-%.1f, x %.1f-%.1f, shown=%s",
							Round(nativeWidth), Round(nativeHeight), bounds.top, bounds.bottom, bounds.from, bounds.to,
							tostring(group ~= nil and not group.control:IsHidden()))
					end
				end
				if overlay then
					local okFill, fillWidth = pcall(overlay.fill.GetWidth, overlay.fill)
					Line("      rectangle: hidden=%s, fill %s wide, fills %s", tostring(overlay.control:IsHidden()),
						okFill and tostring(Round(fillWidth)) or "?", overlay.reverse and "leftwards" or "rightwards")
					local numbers = Control(bar.container .. NUMBERS)
					if numbers and type(numbers.GetDrawTier) == "function" then
						local okTier, tier = pcall(numbers.GetDrawTier, numbers)
						local okLevel, level = pcall(numbers.GetDrawLevel, numbers)
						Line("      numbers: tier=%s level=%s (lifted over the rectangle=%s)",
							okTier and tostring(tier) or "?", okLevel and tostring(level) or "?",
							tostring(self.numbers[bar.key] ~= nil))
					end
				else
					Line("      rectangle: |cFF4040not built|r")
				end
			end
		end
	end

	if addon.writeErrors and addon.writeErrors.PBsConsoleHudCustomizerPlainBar then
		Line("  |cFF4040the template was refused|r: %s", tostring(addon.writeErrors.PBsConsoleHudCustomizerPlainBar))
	end
	Line("  the bars themselves fade out when they are full and you are out of combat, and this")
	Line("  is drawn on them -- so check it with a bar part-empty, or in a fight.")
end

-- ---------------------------------------------------------------------------------------
-- The loop
-- ---------------------------------------------------------------------------------------

function plain:Start()
	if self.running or not addon:PlainWanted() or self.hudShown == false then
		return false
	end
	if not EVENT_MANAGER or type(EVENT_MANAGER.RegisterForUpdate) ~= "function" then
		return false
	end
	EVENT_MANAGER:RegisterForUpdate(addon.name .. "Plain", addon:BarStyle() == "liquidflow" and 50 or UPDATE_INTERVAL_MS, function()
		plain:Update()
	end)
	self.running = true
	self:Update()
	return true
end

function plain:Stop()
	if not self.running then
		return false
	end
	EVENT_MANAGER:UnregisterForUpdate(addon.name .. "Plain")
	self.running = false
	self:RestoreLiquid()
	self:HideAll()
	self:DressAll(false)
	self:RaiseAllNumbers(false)
	self:BlankAll(false)
	return true
end

function plain:Refresh()
	local liquid = addon:BarStyle() == "liquidflow"
	if self.running and self.wasLiquid ~= liquid then self:Stop() end
	self.wasLiquid = liquid
	if addon:PlainWanted() and self.hudShown ~= false then
		self:Restyle()
		if self.running then
			self:Update()
		else
			self:Start()
		end
	else
		self:Stop()
	end
end

function plain:OnHudStateChange(shown)
	self.hudShown = shown and true or false
	if shown then
		self:Refresh()
	else
		self:Stop()
	end
end
