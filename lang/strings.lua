local strings = {
	SI_PBSCHC_EXPLANATION = "Moves and resizes the health, magicka and stamina bars on the HUD. The game fixes all three to the bottom of the screen at one size; each one below starts at the game's own place, and nothing is changed until you move something. While this panel is open, a coloured outline shows where each bar will sit.",

	SI_PBSCHC_ENABLED = "Change the resource bars",
	SI_PBSCHC_ENABLED_TOOLTIP = "Apply the settings below. Turn this off to put all three bars straight back where the game has them -- your settings are kept for when you turn it on again.",

	SI_PBSCHC_PREVIEW = "Show a preview here",
	SI_PBSCHC_PREVIEW_TOOLTIP = "The bars are only drawn on the HUD, so they cannot be seen from this menu. While this is on, an outline the size of each bar is drawn where it will sit.",

	SI_PBSCHC_BAR_HEALTH = "Health",
	SI_PBSCHC_BAR_MAGICKA = "Magicka",
	SI_PBSCHC_BAR_STAMINA = "Stamina",

	SI_PBSCHC_POSITION_X = "<<1>>: sideways",
	SI_PBSCHC_POSITION_X_TOOLTIP = "How far the middle of the bar is from the middle of the screen. 0 is dead centre, negative is to the left, positive is to the right.",
	SI_PBSCHC_POSITION_Y = "<<1>>: height",
	SI_PBSCHC_POSITION_Y_TOOLTIP = "How far the middle of the bar is up from the bottom edge of the screen. The game's own bars sit 137 up, clear of the skill bar.",

	SI_PBSCHC_SCALE = "<<1>>: size",
	SI_PBSCHC_SCALE_TOOLTIP = "The size of the bar, as a percentage of the game's own. The frame, the background, the bar itself and the numbers on it all grow and shrink together, and the bar stays where its middle was put. The small bar that belongs to it -- werewolf over magicka, mount stamina under stamina, siege health under health -- is given the same size.",

	SI_PBSCHC_RESET_BAR = "Reset <<1>>",
	SI_PBSCHC_RESET_BAR_TOOLTIP = "Put this one bar back where the game draws it, at the game's own size.",

	SI_PBSCHC_SECTION_GENERAL = "All three bars",
	SI_PBSCHC_RESET = "Reset everything",
	SI_PBSCHC_RESET_TOOLTIP = "Put all three bars back where the game draws them, at the game's own size.",
	SI_PBSCHC_RESET_BUTTON = "Reset",

	SI_PBSCHC_GAME_SETTINGS_HINT = "Whether the numbers are shown on the bars, and whether the bars fade out when nothing is happening, are the game's own settings under Settings > Interface. An add-on cannot change those, so set them there.",

	SI_PBSCHC_PREVIEW_CAPTION = "Resource bars (preview)",
}

for stringId, stringValue in pairs(strings) do
	ZO_CreateStringId(stringId, stringValue)
	SafeAddVersion(stringId, 1)
end
