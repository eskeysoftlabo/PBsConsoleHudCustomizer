-- PBS_CONSOLE_HUD_CUSTOMIZER is nil if Main.lua bailed out early (e.g. already loaded).
if not PBS_CONSOLE_HUD_CUSTOMIZER then
	return
end

local addon = PBS_CONSOLE_HUD_CUSTOMIZER

-- Positions move in fives: a d-pad press that moved a bar one unit at a time would take a
-- minute to cross the screen, and nobody can see the difference between 940 and 943.
local POSITION_STEP = 5
local SCALE_STEP = 5

local function AddHeading(settings, LibHarvensAddonSettings, label)
	settings:AddSetting(
		{
			type = LibHarvensAddonSettings.ST_SECTION or LibHarvensAddonSettings.ST_LABEL,
			label = label
		}
	)
end

local function AddLabel(settings, LibHarvensAddonSettings, stringId)
	settings:AddSetting(
		{
			type = LibHarvensAddonSettings.ST_LABEL,
			label = GetString(_G[stringId])
		}
	)
end

-- A slider over one bar's x or y. Every one of them switches the add-on back on when moved:
-- moving a slider and seeing nothing happen because of a switch further up reads as a bug.
local function AddPositionSlider(self, settings, LibHarvensAddonSettings, bar, key, label, tooltip, min, max)
	settings:AddSetting(
		{
			type = LibHarvensAddonSettings.ST_SLIDER,
			label = label,
			tooltip = tooltip,
			min = min,
			max = max,
			step = POSITION_STEP,
			default = self:GamePosition(bar)[key],
			format = "%d",
			unit = "",
			getFunction = function()
				return self:Position(bar)[key]
			end,
			setFunction = function(value)
				-- Both values are saved together: a position is a pair, and half of one saved
				-- against the other half still being the game's reads as a bar that jumped.
				local position = self:Position(bar)
				self:SetPositionValue(bar, "x", position.x)
				self:SetPositionValue(bar, "y", position.y)
				self:SetPositionValue(bar, key, addon.Round(value))
				self:Account().enabled = true
				self:Refresh()
			end
		}
	)
end

function addon:InitSettings()
	local LibHarvensAddonSettings = LibHarvensAddonSettings
	if not LibHarvensAddonSettings then
		return
	end

	local settings = LibHarvensAddonSettings:AddAddon(self.title)
	if not settings then
		return
	end
	self.settingsPanel = settings
	settings.allowDefaults = true
	settings.author = self.author
	settings.version = self.version

	-- The preview follows the panel -- see "Following the settings panel" in Preview.lua for why
	-- this callback alone is not enough on console. Registered on the client's callback manager,
	-- beside everyone else's.
	CALLBACK_MANAGER:RegisterCallback(
		"LibHarvensAddonSettings_AddonSelected",
		function(_, addonSettings)
			if self.preview then
				self.preview:OnAddonSelected(addonSettings)
			end
		end
	)

	-- The sliders' ranges are the screen. GuiRoot is the space the anchor offsets are measured
	-- in, so its size is as far as any bar can usefully go: sideways, half the width each way
	-- from the middle; upwards, the whole height.
	local rootWidth, rootHeight = self:RootSize()
	local halfWidth = addon.Round(rootWidth / 2)
	rootHeight = addon.Round(rootHeight)

	AddLabel(settings, LibHarvensAddonSettings, "SI_PBSCHC_EXPLANATION")

	settings:AddSetting(
		{
			type = LibHarvensAddonSettings.ST_CHECKBOX,
			label = GetString(SI_PBSCHC_ENABLED),
			tooltip = GetString(SI_PBSCHC_ENABLED_TOOLTIP),
			default = true,
			getFunction = function()
				return self:Account().enabled
			end,
			setFunction = function(value)
				self:Account().enabled = value
				self:Refresh()
			end
		}
	)

	settings:AddSetting(
		{
			type = LibHarvensAddonSettings.ST_CHECKBOX,
			label = GetString(SI_PBSCHC_PREVIEW),
			tooltip = GetString(SI_PBSCHC_PREVIEW_TOOLTIP),
			default = true,
			getFunction = function()
				return self:Account().preview
			end,
			setFunction = function(value)
				self:Account().preview = value
				if self.preview then
					self.preview:SetPanelOpen(true)
				end
			end
		}
	)

	-- ---- One section per bar, all three the same three rows --------------------------------
	for _, bar in ipairs(self.bars) do
		local barName = GetString(_G[bar.stringId])
		AddHeading(settings, LibHarvensAddonSettings, barName)

		AddPositionSlider(self, settings, LibHarvensAddonSettings, bar, "x",
			zo_strformat(GetString(SI_PBSCHC_POSITION_X), barName), GetString(SI_PBSCHC_POSITION_X_TOOLTIP),
			-halfWidth, halfWidth)
		AddPositionSlider(self, settings, LibHarvensAddonSettings, bar, "y",
			zo_strformat(GetString(SI_PBSCHC_POSITION_Y), barName), GetString(SI_PBSCHC_POSITION_Y_TOOLTIP),
			0, rootHeight)

		settings:AddSetting(
			{
				type = LibHarvensAddonSettings.ST_SLIDER,
				label = zo_strformat(GetString(SI_PBSCHC_SCALE), barName),
				tooltip = GetString(SI_PBSCHC_SCALE_TOOLTIP),
				min = self.MIN_SCALE,
				max = self.MAX_SCALE,
				step = SCALE_STEP,
				default = self.DEFAULT_SCALE,
				format = "%d",
				unit = "%",
				getFunction = function()
					return self:ScalePercent(bar)
				end,
				setFunction = function(value)
					self:SetScalePercent(bar, value)
					self:Account().enabled = true
					self:Refresh()
				end
			}
		)

		settings:AddSetting(
			{
				type = LibHarvensAddonSettings.ST_BUTTON,
				label = zo_strformat(GetString(SI_PBSCHC_RESET_BAR), barName),
				tooltip = GetString(SI_PBSCHC_RESET_BAR_TOOLTIP),
				buttonText = GetString(SI_PBSCHC_RESET_BUTTON),
				clickHandler = function()
					self:ResetBar(bar)
					self:Refresh()
					-- The rows were built from the old values, so they have to be told to
					-- re-read them or the panel keeps showing what was just discarded.
					if settings.UpdateControls then
						settings:UpdateControls()
					end
				end
			}
		)
	end

	-- ---- Everything ------------------------------------------------------------------------
	AddHeading(settings, LibHarvensAddonSettings, GetString(SI_PBSCHC_SECTION_GENERAL))

	settings:AddSetting(
		{
			type = LibHarvensAddonSettings.ST_BUTTON,
			label = GetString(SI_PBSCHC_RESET),
			tooltip = GetString(SI_PBSCHC_RESET_TOOLTIP),
			buttonText = GetString(SI_PBSCHC_RESET_BUTTON),
			clickHandler = function()
				self:ResetAll()
				if settings.UpdateControls then
					settings:UpdateControls()
				end
			end
		}
	)

	AddLabel(settings, LibHarvensAddonSettings, "SI_PBSCHC_GAME_SETTINGS_HINT")
end
