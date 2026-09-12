local strings = {
	SI_PBSCHC_EXPLANATION = "Moves and resizes the health, magicka and stamina bars on the HUD. The game fixes all three to the bottom of the screen at one size; each one below starts at the game's own place, and nothing is changed until you move something. While this panel is open, a coloured outline shows where each bar will sit.",

	SI_PBSCHC_ENABLED = "Change the resource bars",
	SI_PBSCHC_ENABLED_TOOLTIP = "Apply the settings below. Turn this off to put all three bars straight back where the game has them -- your settings are kept for when you turn it on again.",

	SI_PBSCHC_PREVIEW = "Show a preview here",
	SI_PBSCHC_PREVIEW_TOOLTIP = "The bars are only drawn on the HUD, so they cannot be seen from this menu. While this is on, an outline the size of each bar is drawn where it will sit.",

	SI_PBSCHC_BAR_HEALTH = "Health",
	SI_PBSCHC_BAR_MAGICKA = "Magicka",
	SI_PBSCHC_BAR_STAMINA = "Stamina",

	SI_PBSCHC_BAR_SKILLBAR = "Skill bar",

	-- ---- The other weapon set ----------------------------------------------------------
	SI_PBSCHC_SECTION_BACKBAR = "The other weapon set",
	SI_PBSCHC_BACKBAR_EXPLANATION = "A row of your other weapon set's abilities, above the skill bar, with the same countdown and target count on each. The game has a row of its own, but it only appears for a slot whose effect is still running; this one is always there.",
	SI_PBSCHC_BACKBAR_ENABLED = "Show the other weapon set",
	SI_PBSCHC_BACKBAR_ENABLED_TOOLTIP = "Draw the abilities of the weapon set you are not on, above the skill bar. They swap over when you swap weapons.",
	SI_PBSCHC_BACKBAR_EMPTY = "Show empty slots",
	SI_PBSCHC_BACKBAR_EMPTY_TOOLTIP = "Keep the frame of a slot with nothing in it, so the row stays the same width. Off, only the slots with an ability in them are drawn.",
	SI_PBSCHC_BACKBAR_SCALE = "Size of the row",
	SI_PBSCHC_BACKBAR_SCALE_TOOLTIP = "The size of the other set's icons, as a percentage. This is on top of the skill bar's own size, so a bar at 80% with a row at 80% draws the row smaller again.",
	SI_PBSCHC_BACKBAR_GAP = "Gap above the bar",
	SI_PBSCHC_BACKBAR_GAP_TOOLTIP = "How far above the skill bar the row sits. The row follows the bar wherever you put it, so this is the only distance that needs setting.",

	-- ---- The text on the icons ---------------------------------------------------------
	SI_PBSCHC_SECTION_TEXT = "Text on the skill bar",
	SI_PBSCHC_TEXT_EXPLANATION = "How long is left on each ability's effect, and how many targets are under it, written on the icon -- on both weapon sets. The time comes from the game itself, the same number its own bar timers use.",
	SI_PBSCHC_TIMER_MODE = "Countdown on the bar you are on",
	SI_PBSCHC_TIMER_MODE_TOOLTIP = "The set you are not on always gets this add-on's countdown, because the game never draws one there. On the set you are on the game draws its own when Settings > Interface > Action Bar Timers is on, at a size no add-on can change. This add-on: ours, with the game's faded out of the way, so the text size below always does something. Both: ours next to the game's. The game: the front bar is left alone.",
	SI_PBSCHC_TIMER_MODE_ADDON = "This add-on",
	SI_PBSCHC_TIMER_MODE_BOTH = "Both",
	SI_PBSCHC_TIMER_MODE_GAME = "The game",
	SI_PBSCHC_TIMER_SIZE = "Countdown text size",
	SI_PBSCHC_TIMER_SIZE_TOOLTIP = "Size of the time left, on both sets. The game's own is 27.",
	SI_PBSCHC_TIMER_DECIMALS = "Tenths under ten seconds",
	SI_PBSCHC_TIMER_DECIMALS_TOOLTIP = "Under ten seconds, show one decimal place (9.4) instead of whole seconds. A minute or more is always shown as whole minutes.",
	SI_PBSCHC_COUNT_ENABLED = "Show the target count",
	SI_PBSCHC_COUNT_ENABLED_TOOLTIP = "How many targets are under the effect, in the corner of the icon. Counted from the effects you apply, matched to the slot by the ability's name -- a morph that applies an effect under another name will not be counted.",
	SI_PBSCHC_COUNT_SIZE = "Target count text size",
	SI_PBSCHC_COUNT_SIZE_TOOLTIP = "Size of the target count, on both sets.",
	SI_PBSCHC_COUNT_FROM_ONE = "Show it for a single target",
	SI_PBSCHC_COUNT_FROM_ONE_TOOLTIP = "Write the count even when there is only one target, which is how it starts. Off, the number appears from two targets, so a single-target ability does not carry a 1 for its whole duration -- but a single-target ability then shows nothing at all.",

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
