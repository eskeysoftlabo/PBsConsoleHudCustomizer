-- Behavioural tests for PB's ConsoleHudCustomizer.
--
-- The add-on runs on a console, where one real test costs a whole session: build, upload, boot
-- the PS5, log in. harness.lua stubs the part of the client the add-on actually touches -- the
-- three attribute bar containers with the game's own anchors, a layout resolver that turns an
-- anchor into a rectangle, the attribute visualiser's width writes, saved variables, the HUD
-- fragment and LibHarvensAddonSettings -- so the logic can be exercised here instead.
--
--   lua test/run.lua        (from the add-on folder; any Lua 5.1+)

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/") or ".")
ADDON_DIR = HERE .. "/.."
dofile(HERE .. "/harness.lua")

local failures = 0
local function check(label, got, want)
	local ok = got == want
	if not ok then failures = failures + 1 end
	print(string.format("%s %-58s got=%s want=%s", ok and "PASS" or "FAIL", label, tostring(got), tostring(want)))
end

local HEALTH = "ZO_PlayerAttributeHealth"
local MAGICKA = "ZO_PlayerAttributeMagicka"
local STAMINA = "ZO_PlayerAttributeStamina"
local WEREWOLF = "ZO_PlayerAttributeWerewolf"

print("\n== 1. load ==")
Fire(EVENT_ADD_ON_LOADED, "PBsConsoleHudCustomizer")
local addon = PBS_CONSOLE_HUD_CUSTOMIZER
local health, magicka, stamina = addon.barByKey.health, addon.barByKey.magicka, addon.barByKey.stamina
check("version read from manifest", addon.version, "1.6.3")
check("slash command registered", type(SLASH_COMMANDS["/pbhud"]), "function")
check("short slash command registered", type(SLASH_COMMANDS["/pbhc"]), "function")
check("HUD fragment callback registered", addon.hudRegistered, true)
-- explanation, 2 checkboxes, then per bar: heading + 2 sliders + scale + reset, then
-- heading + reset + hint
-- explanation, 2 checkboxes, then per element: heading + 2 sliders + scale + reset, then the
-- back bar section (heading, label, 2 checkboxes, 2 sliders), the text section (heading, label,
-- dropdown, 3 sliders, 3 checkboxes) and the general one (heading, button, hint)
-- explanation, 2 checkboxes, then per element: heading + 2 sliders + scale + reset, then the
-- spacing section (heading, label, 3 sliders), the back bar section (heading, label,
-- 2 checkboxes, 2 sliders), the text section (heading, label, dropdown, 3 sliders,
-- 3 checkboxes) and the general one (heading, button, hint)
-- explanation, 2 checkboxes, the style section (heading, dropdown, slider), then per element:
-- heading + 2 sliders + scale + reset, then spacing (heading, label, 3 sliders), the back bar
-- (heading, label, 2 checkboxes, 2 sliders), the text (heading, label, dropdown, 3 sliders,
-- 3 checkboxes, 2 more size sliders and the button that puts the other set back to following),
-- the shade (heading, label, 2 checkboxes, slider, dropdown) and the general section (heading,
-- button, hint)
-- ... and the skill bar's section carries one more row than the other three: the switch that
-- hands the whole bar back.
check("settings rows", #PanelRows, 3 + 4 + 4 * 5 + 1 + 5 + 6 + 11 + 6 + 3)

print("\n== 2. the first apply waits for the bars ==")
Fire(EVENT_PLAYER_ACTIVATED)
FlushCallLater() -- the first-apply delay
check("bars not built yet: nothing captured", addon.original.health, nil)
check("and a retry is pending", PendingCallLater(), 1)
BuildAttributeBars()
FlushCallLater()
check("first apply done", addon.firstApplyDone, true)
check("health anchor captured", addon.original.health ~= nil, true)
check("stamina anchor captured", addon.original.stamina ~= nil, true)

print("\n== 3. the game's own positions are measured, not assumed ==")
check("health measured x", addon:GamePosition(health).x, 0)
check("health measured y", addon:GamePosition(health).y, 137)
check("magicka measured x", addon:GamePosition(magicka).x, -388)
check("stamina measured x", addon:GamePosition(stamina).x, 389)
check("measured, not worked out", type(addon:Measured(health).x), "number")
-- Whichever way round it is worked out, the two must agree, or an install whose measurement was
-- refused would quietly move the bars.
check("fallback agrees with the measurement", addon:FallbackPosition(magicka).x, -388)

print("\n== 4. an untouched install writes nothing ==")
check("nothing differs", addon:AnythingDiffers(), false)
check("no anchor written to health", WriteCount(HEALTH, "anchor"), 0)
check("no scale written to magicka", WriteCount(MAGICKA, "scale"), 0)
check("health still anchored to the group", BarAnchor(HEALTH), "128->ZO_PlayerAttribute 128 (0,0)")

print("\n== 5. moving one bar ==")
Row(GetString(SI_PBSCHC_POSITION_Y):gsub("<<1>>", GetString(SI_PBSCHC_BAR_HEALTH))).setFunction(400)
check("health differs", addon:BarDiffers(health), true)
check("the other two do not", addon:BarDiffers(magicka), false)
check("health anchored to the screen", BarAnchor(HEALTH), "128->GuiRoot 4 (0,-400)")
local cx, cy = BarCentre(HEALTH)
check("health middle x on screen", cx, 0)
check("health middle y on screen", cy, 400)
check("magicka untouched", WriteCount(MAGICKA, "anchor"), 0)
check("magicka still where the game put it", select(2, BarCentre(MAGICKA)), 137)

print("\n== 6. scale ==")
Row(GetString(SI_PBSCHC_SCALE):gsub("<<1>>", GetString(SI_PBSCHC_BAR_MAGICKA))).setFunction(150)
check("magicka scaled", _G[MAGICKA]:GetScale(), 1.5)
check("its werewolf bar scaled with it", _G[WEREWOLF]:GetScale(), 1.5)
check("magicka moved to its own anchor", BarAnchor(MAGICKA), "128->GuiRoot 4 (-388,-137)")
check("stamina still untouched", _G[STAMINA]:GetScale(), 1)
check("health kept at full size", _G[HEALTH]:GetScale(), 1.0)
local left, top, width, height = addon:RectOf(magicka)
check("preview rectangle is the scaled size", string.format("%dx%d", math.floor(width), math.floor(height)), "355x34")

print("\n== 7. a HUD show does not rewrite what is already in place ==")
local anchorWrites = WriteCount(HEALTH, "anchor")
local scaleWrites = WriteCount(MAGICKA, "scale")
FireHud(SCENE_FRAGMENT_SHOWN)
FireHud(SCENE_FRAGMENT_SHOWN)
check("no further anchor writes", WriteCount(HEALTH, "anchor"), anchorWrites)
check("no further scale writes", WriteCount(MAGICKA, "scale"), scaleWrites)

print("\n== 8. the attribute visualiser's width writes are left alone ==")
-- A buff on maximum magicka: the client writes 323 onto the container. The add-on holds the bar
-- by its middle, so it grows both ways and stays where it was put.
SetBarState(MAGICKA, "expanded")
FireHud(SCENE_FRAGMENT_SHOWN)
check("the client's width is still there", _G[MAGICKA]:GetDimensions(), 323)
check("the bar has not moved", BarCentre(MAGICKA), -388)
check("and nothing was rewritten", WriteCount(MAGICKA, "scale"), scaleWrites)
SetBarState(MAGICKA, "normal")

print("\n== 9. switching it off puts everything back ==")
Row(GetString(SI_PBSCHC_ENABLED)).setFunction(false)
check("health back on the group's centre", BarAnchor(HEALTH), "128->ZO_PlayerAttribute 128 (0,0)")
check("magicka back on its own anchor", BarAnchor(MAGICKA), "8->ZO_PlayerAttribute 2 (237,0)")
check("magicka back to scale 1", _G[MAGICKA]:GetScale(), 1)
check("the werewolf bar too", _G[WEREWOLF]:GetScale(), 1)
check("health back where the game draws it", select(2, BarCentre(HEALTH)), 137)
check("settings kept", addon:Position(health).y, 400)

print("\n== 10. and switching it on again re-applies them ==")
Row(GetString(SI_PBSCHC_ENABLED)).setFunction(true)
check("health moved again", select(2, BarCentre(HEALTH)), 400)
check("magicka scaled again", _G[MAGICKA]:GetScale(), 1.5)

print("\n== 11. reset ==")
Row(GetString(SI_PBSCHC_RESET_BAR):gsub("<<1>>", GetString(SI_PBSCHC_BAR_MAGICKA))).clickHandler()
check("magicka back where the game draws it", BarAnchor(MAGICKA), "8->ZO_PlayerAttribute 2 (237,0)")
check("magicka back to scale 1", _G[MAGICKA]:GetScale(), 1)
check("health still moved", select(2, BarCentre(HEALTH)), 400)
Row(GetString(SI_PBSCHC_RESET)).clickHandler()
check("everything back", addon:AnythingDiffers(), false)
check("health back on the group", BarAnchor(HEALTH), "128->ZO_PlayerAttribute 128 (0,0)")

print("\n== 12. a measurement is never taken from a stretched bar ==")
-- A fresh session, with a buff already up when the add-on first looks.
SavedStore.PBsConsoleHudCustomizer_Data = nil
addon.account = ZO_SavedVars:NewAccountWide("PBsConsoleHudCustomizer_Data", 1, nil, addon.accountDefaults)
addon:Account()
addon.written, addon.original = {}, {}
BuildAttributeBars()
SetBarState(STAMINA, "expanded")
addon:CaptureAll()
check("stamina not measured while stretched", addon:Measured(stamina).x, nil)
check("health measured all the same", addon:Measured(health).x, 0)
check("the worked-out value is used meanwhile", addon:GamePosition(stamina).x, 389)
SetBarState(STAMINA, "normal")
FireHud(SCENE_FRAGMENT_SHOWN)
check("measured once it is back to normal", addon:Measured(stamina).x, 389)

print("\n== 13. the preview follows the settings panel ==")
local preview = addon.preview
OpenPanel(Panel)
check("shown with the panel", preview:IsShown(), true)
ClosePanel()
check("hidden with the panel", preview:IsShown(), false)
-- Select() fires no callback for the add-on that is already selected, so a second visit has to
-- be carried by the panel scene alone. This is what 1.0.0 of the chat add-on got wrong on PS5.
OpenPanel(Panel)
check("shown again on a second visit", preview:IsShown(), true)
OpenPanel(OtherPanel)
check("not shown for another add-on's panel", preview:IsShown(), false)
OpenPanel(Panel)
check("shown again for ours", preview:IsShown(), true)
Row(GetString(SI_PBSCHC_PREVIEW)).setFunction(false)
AdvanceFrame(1000)
preview.control:Tick()
check("switched off by its checkbox", preview:IsShown(), false)
Row(GetString(SI_PBSCHC_PREVIEW)).setFunction(true)
check("and on again", preview:IsShown(), true)
ClosePanel()

print("\n== 14. slash commands ==")
local slash = SLASH_COMMANDS["/pbhud"]
slash("pos stamina 600 300")
check("position set", string.format("%d,%d", addon:Position(stamina).x, addon:Position(stamina).y), "600,300")
check("and written", BarAnchor(STAMINA), "128->GuiRoot 4 (600,-300)")
slash("scale hp 75")
check("scale set by short name", addon:ScalePercent(health), 75)
slash("scale hp 500")
check("scale clamped", addon:ScalePercent(health), 200)
slash("off")
check("off restores", _G[HEALTH]:GetScale(), 1)
slash("on")
check("on re-applies", _G[HEALTH]:GetScale(), 2)
slash("reset")
check("reset clears everything", addon:AnythingDiffers(), false)
slash("status") -- must not error

print("\n== 15. a different screen size ==")
SetRootSize(1280, 720)
addon.account.measured = {}
addon:Account()
addon.written, addon.original = {}, {}
BuildAttributeBars()
addon:CaptureAll()
-- ResizeToFitScreen's minimum is 1014, wider than 1280 - 502 * 2, so the group is 1014 here too.
check("magicka's game position on a small screen", addon:GamePosition(magicka).x, -388)
check("height above the bottom is the same", addon:GamePosition(magicka).y, 137)
check("the slider range follows the screen", addon:ClampedPosition({ x = 5000, y = 0 }).x, 640)
SetRootSize(1920, 1080)

-- =========================================================================================
-- The skill bar, the back bar and the text on the icons
-- =========================================================================================

local SKILLBAR = "ZO_ActionBar1"
local skillbar = addon.barByKey.skillbar
local timers = addon.timers

print("\n== 16. the skill bar is placed the same way the other three are ==")
SavedStore.PBsConsoleHudCustomizer_Data = nil
addon.account = ZO_SavedVars:NewAccountWide("PBsConsoleHudCustomizer_Data", 1, nil, addon.accountDefaults)
addon:Account()
addon.written, addon.original = {}, {}
BuildAttributeBars()
SetAllSlots()
addon:CaptureAll()
check("the game's own place is measured", addon:GamePosition(skillbar).y, 60)
check("centred", addon:GamePosition(skillbar).x, 0)
check("nothing written while it is untouched", WriteCount(SKILLBAR, "anchor"), 0)
Row(GetString(SI_PBSCHC_POSITION_Y):gsub("<<1>>", GetString(SI_PBSCHC_BAR_SKILLBAR))).setFunction(300)
check("moved", BarAnchor(SKILLBAR), "128->GuiRoot 4 (0,-300)")
Row(GetString(SI_PBSCHC_SCALE):gsub("<<1>>", GetString(SI_PBSCHC_BAR_SKILLBAR))).setFunction(80)
check("scaled", _G[SKILLBAR]:GetScale(), 0.8)
check("the attribute bars are not touched by it", WriteCount(HEALTH, "anchor"), 0)

print("\n== 17. the other weapon set's row ==")
FireHud(SCENE_FRAGMENT_SHOWN)
check("the update loop is running", UpdateRegistered("PBsConsoleHudCustomizerTimers"), true)
local back3 = CreatedControls["PBsConsoleHudCustomizerBack3"]
check("a row control was built per slot", back3 ~= nil, true)
check("it hangs on the game's own button", back3:GetParent():GetName(), "ActionButton3")
check("above it", string.format("%d", back3.anchors[1].offsetY), "-4")
check("it shows the other set's ability", back3.namedChildren.Icon.texture, "back3.dds")
check("the ultimate too", CreatedControls["PBsConsoleHudCustomizerBack8"].namedChildren.Icon.texture, "back8.dds")
-- Swapping weapons swaps which set is the other one.
ActiveHotbar = HOTBAR_CATEGORY_BACKUP
RunUpdates()
check("after a weapon swap it shows the first set", back3.namedChildren.Icon.texture, "front3.dds")
ActiveHotbar = HOTBAR_CATEGORY_PRIMARY
-- A werewolf / siege / mount bar is not one of the two weapon sets.
ActiveHotbar = 42
RunUpdates()
check("hidden on a bar that has no other set", back3:IsHidden(), true)
ActiveHotbar = HOTBAR_CATEGORY_PRIMARY
RunUpdates()
check("back again afterwards", back3:IsHidden(), false)
-- An empty slot.
SetSlot(HOTBAR_CATEGORY_BACKUP, 5, nil)
RunUpdates()
check("an empty slot keeps its frame by default", CreatedControls["PBsConsoleHudCustomizerBack5"]:IsHidden(), false)
Row(GetString(SI_PBSCHC_BACKBAR_EMPTY)).setFunction(false)
RunUpdates()
check("and goes away when that is switched off", CreatedControls["PBsConsoleHudCustomizerBack5"]:IsHidden(), true)
Row(GetString(SI_PBSCHC_BACKBAR_EMPTY)).setFunction(true)
SetAllSlots()
RunUpdates()

print("\n== 18. the countdown comes from the client, for both sets ==")
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 8400, duration = 20000 })
SetSlot(HOTBAR_CATEGORY_BACKUP, 4, { name = "Back 4", icon = "back4.dds", id = 204, remaining = 74000, duration = 80000 })
RunUpdates()
local frontTimer = CreatedControls["PBsConsoleHudCustomizerLabels3"].namedChildren.Timer
local backTimer = CreatedControls["PBsConsoleHudCustomizerBack4"].namedChildren.Timer
check("tenths under ten seconds", frontTimer:GetText(), "8.4")
check("minutes over a minute, on the other set", backTimer:GetText(), "1m")
Row(GetString(SI_PBSCHC_TIMER_DECIMALS)).setFunction(false)
RunUpdates()
check("whole seconds when tenths are off", frontTimer:GetText(), "8")
Row(GetString(SI_PBSCHC_TIMER_DECIMALS)).setFunction(true)
-- Under a second is noise; the game does not show it either.
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 400 })
RunUpdates()
check("nothing under a second", frontTimer:IsHidden(), true)
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 8400 })
RunUpdates()

print("\n== 19. the target count ==")
local frontCount = CreatedControls["PBsConsoleHudCustomizerLabels3"].namedChildren.Count
local now = GetGameTimeMilliseconds()
FireEffect(EFFECT_RESULT_GAINED, "Front 3", "reticleover", (now + 9000) / 1000, 11, 303)
RunUpdates()
-- One target is written: "nothing is showing" is a worse first impression than a 1.
check("a single target is written by default", frontCount:GetText(), "1")
Row(GetString(SI_PBSCHC_COUNT_FROM_ONE)).setFunction(false)
RunUpdates()
check("and can be switched to two or more", frontCount:IsHidden(), true)
Row(GetString(SI_PBSCHC_COUNT_FROM_ONE)).setFunction(true)
FireEffect(EFFECT_RESULT_GAINED, "Front 3", "", (now + 9000) / 1000, 12, 303)
FireEffect(EFFECT_RESULT_GAINED, "Front 3", "", (now + 9000) / 1000, 13, 303)
RunUpdates()
check("three targets", frontCount:GetText(), "3")
-- A fade a moment later is a real one. (Straight after an application it would be the old
-- instance being replaced, which is ignored -- see section 37.)
AdvanceFrame(1000)
FireEffect(EFFECT_RESULT_FADED, "Front 3", "", (now + 9000) / 1000, 12, 303)
RunUpdates()
check("two after one falls off", frontCount:GetText(), "2")
-- A group member's copy of the same effect is not another target.
FireEffect(EFFECT_RESULT_GAINED, "Front 3", "group3", (now + 9000) / 1000, 14, 303)
RunUpdates()
check("a group member's copy is not counted", frontCount:GetText(), "2")
FireEffect(EFFECT_RESULT_GAINED, "Back 4", "", (now + 9000) / 1000, 21, 404)
RunUpdates()
check("the other set is counted too", CreatedControls["PBsConsoleHudCustomizerBack4"].namedChildren.Count:GetText(), "1")
-- The count is matched by name; an ability with no effect of its own has none.
check("an untouched slot has no count", CreatedControls["PBsConsoleHudCustomizerLabels6"].namedChildren.Count:IsHidden(), true)
-- The count now lives as long as the client says the slot's effect does, so the effect running
-- out is the client's timer reaching zero.
AdvanceFrame(10000)
RunUpdates()
check("held while the client still times the effect", frontCount:IsHidden(), false)
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 0, duration = 0 })
RunUpdates()
check("and gone when that timer ends", frontCount:IsHidden(), true)
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 8400 })
Row(GetString(SI_PBSCHC_COUNT_ENABLED)).setFunction(false)
RunUpdates()
check("switched off entirely", CreatedControls["PBsConsoleHudCustomizerBack4"].namedChildren.Count:IsHidden(), true)
Row(GetString(SI_PBSCHC_COUNT_ENABLED)).setFunction(true)

print("\n== 20. the game's own numbers, the text size, and the loop ==")
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 8400 })
local gameTimer = _G["ActionButton3"].namedChildren.TimerText
GameBarTimers = true
RunUpdates()
-- The whole point of the default: ours is on the icon, so the size slider does something, and
-- the game's own number -- which no add-on can resize -- is faded out of the way.
check("ours is written even while the game writes its own", frontTimer:GetText(), "8.4")
check("and the game's is faded out", gameTimer:GetAlpha(), 0)
check("the other set is ours as always", backTimer:IsHidden(), false)
Row(GetString(SI_PBSCHC_TIMER_MODE)).setFunction(nil, nil, { data = "both" })
RunUpdates()
check("both leaves the game's alone", gameTimer:GetAlpha(), 1)
check("and still writes ours", frontTimer:GetText(), "8.4")
Row(GetString(SI_PBSCHC_TIMER_MODE)).setFunction(nil, nil, { data = "game" })
RunUpdates()
check("the game alone means nothing of ours on the front bar", frontTimer:IsHidden(), true)
check("the game's own is back to full", gameTimer:GetAlpha(), 1)
check("but the other set keeps ours, because the game draws none there", backTimer:IsHidden(), false)
Row(GetString(SI_PBSCHC_TIMER_MODE)).setFunction(nil, nil, { data = "addon" })
RunUpdates()
check("and back", frontTimer:GetText(), "8.4")
check("faded again", gameTimer:GetAlpha(), 0)
GameBarTimers = false
RunUpdates()
-- Still faded: whether the game is drawing its number is read for status, but it is not what
-- decides this. A label with nothing on it costs nothing to fade, and depending on that reading
-- is how two numbers end up on one icon.
check("faded whatever the game's setting says", gameTimer:GetAlpha(), 0)

Row(GetString(SI_PBSCHC_TIMER_SIZE)).setFunction(36)
check("the countdown font follows the slider", frontTimer.font, "$(GAMEPAD_BOLD_FONT)|36|thick-outline")
check("and the other set follows it while it has no size of its own", backTimer.font, "$(GAMEPAD_BOLD_FONT)|36|thick-outline")
-- Given one, the row keeps it: its icons are smaller than the bar's.
Row(GetString(SI_PBSCHC_TIMER_SIZE_BACK)).setFunction(20)
check("the other set takes its own size", backTimer.font, "$(GAMEPAD_BOLD_FONT)|20|thick-outline")
check("and this bar is not touched by it", frontTimer.font, "$(GAMEPAD_BOLD_FONT)|36|thick-outline")
Row(GetString(SI_PBSCHC_TIMER_SIZE)).setFunction(30)
check("moving this bar's no longer moves the row's", backTimer.font, "$(GAMEPAD_BOLD_FONT)|20|thick-outline")
check("but this bar still follows its own", frontTimer.font, "$(GAMEPAD_BOLD_FONT)|30|thick-outline")
Row(GetString(SI_PBSCHC_TEXT_SIZE_MATCH)).clickHandler()
check("and the row can be put back to following", backTimer.font, "$(GAMEPAD_BOLD_FONT)|30|thick-outline")
Row(GetString(SI_PBSCHC_TIMER_SIZE)).setFunction(36)
check("following again", backTimer.font, "$(GAMEPAD_BOLD_FONT)|36|thick-outline")
Row(GetString(SI_PBSCHC_COUNT_SIZE)).setFunction(16)
check("and the count has its own size", frontCount.font, "$(GAMEPAD_BOLD_FONT)|16|thick-outline")
Row(GetString(SI_PBSCHC_COUNT_SIZE_BACK)).setFunction(14)
check("the row's count too", CreatedControls["PBsConsoleHudCustomizerBack4"].namedChildren.Count.font, "$(GAMEPAD_BOLD_FONT)|14|thick-outline")

Row(GetString(SI_PBSCHC_BACKBAR_SCALE)).setFunction(70)
check("the row is scaled", back3:GetScale(), 0.7)

FireHud(SCENE_FRAGMENT_HIDDEN)
check("the loop stops with the HUD", UpdateRegistered("PBsConsoleHudCustomizerTimers"), false)
check("and everything of ours goes with it", back3:IsHidden(), true)
-- The settings panel is reached through a menu, with the HUD down: moving a slider there must
-- not start a hundred-millisecond loop behind it.
Row(GetString(SI_PBSCHC_TIMER_SIZE)).setFunction(30)
check("a slider moved behind a menu does not start it", UpdateRegistered("PBsConsoleHudCustomizerTimers"), false)
check("but the font is still set for when it comes back", frontTimer.font, "$(GAMEPAD_BOLD_FONT)|30|thick-outline")
FireHud(SCENE_FRAGMENT_SHOWN)
check("and comes back", UpdateRegistered("PBsConsoleHudCustomizerTimers"), true)

Row(GetString(SI_PBSCHC_ENABLED)).setFunction(false)
check("the master switch stops it too", UpdateRegistered("PBsConsoleHudCustomizerTimers"), false)
check("and puts the skill bar back", BarAnchor(SKILLBAR), "4->GuiRoot 4 (0,-25)")
check("the game's own countdown is handed back", _G["ActionButton3"].namedChildren.TimerText:GetAlpha(), 1)
check("at its own size", _G[SKILLBAR]:GetScale(), 1)
Row(GetString(SI_PBSCHC_ENABLED)).setFunction(true)
check("on again", UpdateRegistered("PBsConsoleHudCustomizerTimers"), true)

print("\n== 21. a setting saved by 1.1.0 ==")
-- 1.1.0 called the three modes auto / always / never. A player's choice is carried over rather
-- than reset to the default.
addon.account.text.timerMode = "never"
addon:Account()
check("never became the game", addon:TimerMode(), "game")
addon.account.text.timerMode = "auto"
addon:Account()
check("auto became this add-on", addon:TimerMode(), "addon")
addon.account.text.timerMode = "nonsense"
check("and anything else falls back", addon:TimerMode(), "addon")
addon.account.text.timerMode = "addon"

print("\n== 22. a template that did not load is survived, and said out loud ==")
-- Controls.xml not loading on a console is a whole session lost if it leaves nothing on screen
-- and nothing to read. The controls are built in plain Lua instead, and status says so.
addon.writeErrors = nil
addon.timers.labels[3] = nil
addon.timers.usedFallback = false
-- As it would be in a session where the XML never loaded: the name has not been taken.
CreatedControls["PBsConsoleHudCustomizerLabels3"] = nil
local realCreate = CreateControlFromVirtual
CreateControlFromVirtual = function() error("no such template") end
local pair = addon.timers:Labels(3)
CreateControlFromVirtual = realCreate
check("the failure is recorded", (addon.writeErrors or {}).PBsConsoleHudCustomizerSlotLabels ~= nil, true)
check("but the labels are still built", pair ~= nil and pair.timer ~= nil, true)
check("and say so", addon.timers.usedFallback, true)
addon.timers:StyleLabels(pair)
check("with the chosen font on them", pair.timer.font, "$(GAMEPAD_BOLD_FONT)|30|thick-outline")
addon.writeErrors = nil
addon.timers.usedFallback = false

print("\n== 23. the gaps along the skill bar ==")
-- A fresh session with nothing written, so the game's own chain is what gets measured.
SavedStore.PBsConsoleHudCustomizer_Data = nil
addon.account = ZO_SavedVars:NewAccountWide("PBsConsoleHudCustomizer_Data", 1, nil, addon.accountDefaults)
addon:Account()
addon.written, addon.original = {}, {}
addon.skillbar.original, addon.skillbar.written = nil, false
BuildAttributeBars()
SetAllSlots()
addon:CaptureAll()
addon.skillbar:Measure()
check("the gap between abilities is measured", addon:GameGap("skill"), 10)
check("the gap before the ultimate too", addon:GameGap("ultimate"), 65)
-- 5 to the marker, the marker's own 45, then 10 to the first ability: what the eye sees as one
-- gap is three numbers with an invisible control in the middle.
check("and the item's, marker and all", addon:GameGap("item"), 5 + WEAPON_SWAP_WIDTH + 10)
check("nothing written while they are the game's", WriteCount("ActionButton4", "anchor"), 0)
check("nor on the quickslot", WriteCount("QuickslotButton", "anchor"), 0)

Row(GetString(SI_PBSCHC_GAP_ULTIMATE)).setFunction(12)
check("the ultimate is pulled in", BarAnchor("ActionButton8"), "2->ActionButton7 8 (12,0)")
check("the abilities are left alone", BarAnchor("ActionButton4"), "2->ActionButton3 8 (10,0)")
Row(GetString(SI_PBSCHC_GAP_ITEM)).setFunction(8)
-- Anchored to the first ability itself, so the hidden marker is out of the way for good.
check("the item comes in beside the first ability", BarAnchor("QuickslotButton"), "8->ActionButton3 2 (-8,0)")
Row(GetString(SI_PBSCHC_GAP_SKILL)).setFunction(4)
check("and the abilities close up", BarAnchor("ActionButton5"), "2->ActionButton4 8 (4,0)")
check("the first one is not moved: it is what the rest hang off", BarAnchor("ActionButton3"), "2->ZO_ActionBar1WeaponSwap 8 (10,0)")

-- A companion joins the row between the item and the abilities, and takes the same gap.
SetCompanionOut(true)
addon:Refresh()
check("the companion's ultimate takes the item gap", BarAnchor("CompanionUltimateButton"), "8->ActionButton3 2 (-8,0)")
check("and the item sits beside it", BarAnchor("QuickslotButton"), "8->CompanionUltimateButton 2 (-8,0)")
SetCompanionOut(false)
addon:Refresh()

check("everything differs while the gaps do", addon:AnythingDiffers(), true)
Row(GetString(SI_PBSCHC_RESET_BAR):gsub("<<1>>", GetString(SI_PBSCHC_BAR_SKILLBAR))).clickHandler()
check("the skill bar's reset puts the gaps back too", BarAnchor("ActionButton8"), "2->ActionButton7 8 (65,0)")
check("and the item back on the marker", BarAnchor("QuickslotButton"), "8->ZO_ActionBar1WeaponSwap 2 (-5,0)")
check("nothing differs again", addon:AnythingDiffers(), false)

Row(GetString(SI_PBSCHC_GAP_SKILL)).setFunction(4)
Row(GetString(SI_PBSCHC_ENABLED)).setFunction(false)
check("the master switch puts them back as well", BarAnchor("ActionButton5"), "2->ActionButton4 8 (10,0)")
Row(GetString(SI_PBSCHC_ENABLED)).setFunction(true)
check("and on again", BarAnchor("ActionButton5"), "2->ActionButton4 8 (4,0)")

print("\n== 24. no second weapon set, no row for it ==")
FireHud(SCENE_FRAGMENT_SHOWN)
check("the row is there to begin with", CreatedControls["PBsConsoleHudCustomizerBack3"]:IsHidden(), false)
-- The Oakensoul Ring, and anything else that welds you to one bar: GetActiveWeaponPairInfo's
-- second return. No setting of ours is touched.
WeaponPairLocked = true
RunUpdates()
check("locked to one bar: the row goes", CreatedControls["PBsConsoleHudCustomizerBack3"]:IsHidden(), true)
check("and says why", select(2, addon:WeaponSwapState()), "locked")
check("the setting is untouched", addon:BackBar().enabled, true)
WeaponPairLocked = false
RunUpdates()
check("take the ring off and it is back", CreatedControls["PBsConsoleHudCustomizerBack3"]:IsHidden(), false)
-- A character too low to have earned the second bar.
PlayerLevel = 10
RunUpdates()
check("too low a level: the row goes", CreatedControls["PBsConsoleHudCustomizerBack3"]:IsHidden(), true)
check("and says why", select(2, addon:WeaponSwapState()), "unearned")
PlayerLevel = 50
RunUpdates()
check("and comes back on levelling", CreatedControls["PBsConsoleHudCustomizerBack3"]:IsHidden(), false)

print("\n== 25. the shade over a skill in use ==")
addon.account.text.timerMode = "addon"
SetAllSlots()
FireHud(SCENE_FRAGMENT_SHOWN)
local shade3 = CreatedControls["PBsConsoleHudCustomizerShade3"]
check("a shade is built for each slot", shade3 ~= nil, true)
check("over the game's own icon", shade3:GetParent():GetName(), "ActionButton3")
check("and hidden while nothing is running", shade3:IsHidden(), true)

-- An ability is used: the client starts reporting time left on that slot.
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 20000, duration = 20000 })
RunUpdates()
check("the shade comes up", shade3:IsHidden(), false)
check("the icon is what is shaded", shade3.texture, "front3.dds")
check("swept vertically", shade3.cooldown.cdType, CD_TYPE_VERTICAL_REVEAL)
check("for exactly the effect's length", shade3.cooldown.duration, 20000)
check("from where it is now", shade3.cooldown.remaining, 20000)
check("clearing downwards by default", shade3.cooldown.timeType, CD_TIME_TYPE_TIME_UNTIL)
check("as dark as the setting says", shade3.fillColor[4], 0.6)

-- Ticking on is not a restart: the engine is doing the sweep.
local started = WriteCount("PBsConsoleHudCustomizerShade3", "cooldown")
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 17000, duration = 20000 })
RunUpdates()
RunUpdates()
check("counting down does not restart it", WriteCount("PBsConsoleHudCustomizerShade3", "cooldown"), started)
-- Casting it again does.
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 20000, duration = 20000 })
RunUpdates()
check("re-casting does", WriteCount("PBsConsoleHudCustomizerShade3", "cooldown"), started + 1)

Row(GetString(SI_PBSCHC_SHADE_DIRECTION)).setFunction(nil, nil, { data = "up" })
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 20000, duration = 30000 })
RunUpdates()
check("the direction can be turned round", shade3.cooldown.timeType, CD_TIME_TYPE_TIME_REMAINING)
Row(GetString(SI_PBSCHC_SHADE_DIRECTION)).setFunction(nil, nil, { data = "down" })

-- The other weapon set is shaded the same way.
SetSlot(HOTBAR_CATEGORY_BACKUP, 5, { name = "Back 5", icon = "back5.dds", id = 205, remaining = 12000, duration = 12000 })
RunUpdates()
local backShade = CreatedControls["PBsConsoleHudCustomizerBack5"].namedChildren.Shade
check("the other set is shaded too", backShade:IsHidden(), false)
check("with its own icon", backShade.texture, "back5.dds")

-- The effect ends.
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 0, duration = 0 })
RunUpdates()
check("the shade goes when the effect does", shade3:IsHidden(), true)

SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 9000, duration = 10000 })
RunUpdates()
Row(GetString(SI_PBSCHC_SHADE_ENABLED)).setFunction(false)
RunUpdates()
check("and switching it off takes it away", shade3:IsHidden(), true)
Row(GetString(SI_PBSCHC_SHADE_ENABLED)).setFunction(true)
RunUpdates()
check("on again", shade3:IsHidden(), false)

print("\n== 26. the plain look ==")
check("standard builds nothing", CreatedControls["PBsConsoleHudCustomizerPlainZO_PlayerAttributeMagickaBar"], nil)
check("and runs no loop", UpdateRegistered("PBsConsoleHudCustomizerPlain"), false)

Row(GetString(SI_PBSCHC_STYLE)).setFunction(nil, nil, { data = "plain" })
check("the loop starts with the style", UpdateRegistered("PBsConsoleHudCustomizerPlain"), true)
local magickaPlain = CreatedControls["PBsConsoleHudCustomizerPlainZO_PlayerAttributeMagickaBar"]
check("a rectangle is built per bar", magickaPlain ~= nil, true)
-- On the container, not on the status bar: the container is what the client's own frame,
-- background and numbers hang on, so there is no question about a child of it drawing.
check("built on the container", magickaPlain:GetParent():GetName(), "ZO_PlayerAttributeMagicka")
check("over the bar's own rectangle", magickaPlain.anchors[1].relativeTo:GetName(), "ZO_PlayerAttributeMagickaBar")
check("the track is a backdrop, not a texture", magickaPlain.namedChildren.Track.kind, "control")
check("coloured, with no art", magickaPlain.namedChildren.Track.centerColor ~= nil, true)
check("and the fill takes the power's own colour", magickaPlain.namedChildren.Fill.centerColor[3], 0.8)

-- Magicka fills towards its left, so its block hangs off the right edge and is as wide as the
-- bar is full: half, here.
check("the block is held by the edge the bar fills from", magickaPlain.namedChildren.Fill.anchors[1].point, TOPRIGHT)
check("as wide as the bar is full", magickaPlain.namedChildren.Fill:GetWidth(), 112)

-- The game's arrow frame and background are put away while this style is on.
check("the frame is put away", _G.ZO_PlayerAttributeMagickaFrameCenter:IsHidden(), true)
check("and the background with it", _G.ZO_PlayerAttributeMagickaBgContainer:IsHidden(), true)
Row(GetString(SI_PBSCHC_PLAIN_KEEP_FRAME)).setFunction(true)
RunUpdates()
check("kept when that is asked for", _G.ZO_PlayerAttributeMagickaFrameCenter:IsHidden(), false)
Row(GetString(SI_PBSCHC_PLAIN_KEEP_FRAME)).setFunction(false)
RunUpdates()

SetPower(COMBAT_MECHANIC_FLAGS_MAGICKA, 100, 1000)
RunUpdates()
check("the block follows the value", string.format("%.1f", magickaPlain.namedChildren.Fill:GetWidth()), "22.4")
SetPower(COMBAT_MECHANIC_FLAGS_MAGICKA, 0, 1000)
RunUpdates()
check("an empty bar shows only the track", magickaPlain.namedChildren.Fill:IsHidden(), true)
check("and the track is still there", magickaPlain:IsHidden(), false)
SetPower(COMBAT_MECHANIC_FLAGS_MAGICKA, 500, 1000)
RunUpdates()

FireHud(SCENE_FRAGMENT_HIDDEN)
check("the loop stops with the HUD", UpdateRegistered("PBsConsoleHudCustomizerPlain"), false)
check("and the game's frame comes back", _G.ZO_PlayerAttributeMagickaFrameCenter:IsHidden(), false)
FireHud(SCENE_FRAGMENT_SHOWN)
check("and it all comes back", UpdateRegistered("PBsConsoleHudCustomizerPlain"), true)
Row(GetString(SI_PBSCHC_STYLE)).setFunction(nil, nil, { data = "standard" })
check("standard puts it away again", UpdateRegistered("PBsConsoleHudCustomizerPlain"), false)
check("and hands the frame back", _G.ZO_PlayerAttributeMagickaFrameCenter:IsHidden(), false)

print("\n== 27. the plain look survives a template that did not load ==")
Row(GetString(SI_PBSCHC_STYLE)).setFunction(nil, nil, { data = "plain" })
addon.plain.overlays["ZO_PlayerAttributeStaminaBar"] = nil
CreatedControls["PBsConsoleHudCustomizerPlainZO_PlayerAttributeStaminaBar"] = nil
addon.timers.usedFallback = false
addon.writeErrors = nil
local realCreate = CreateControlFromVirtual
CreateControlFromVirtual = function() error("no such template") end
local overlay = addon.plain:Overlay(addon.plain.bars[3], { name = "ZO_PlayerAttributeStaminaBar", reverse = false })
CreateControlFromVirtual = realCreate
check("the rectangle is built anyway", overlay ~= nil, true)
check("with its track and its fill", overlay ~= nil and overlay.track ~= nil and overlay.fill ~= nil, true)
check("the refusal is recorded", (addon.writeErrors or {}).PBsConsoleHudCustomizerPlainBar ~= nil, true)
RunUpdates()
check("and it draws", overlay ~= nil and not overlay.control:IsHidden(), true)
addon.writeErrors = nil
addon.timers.usedFallback = false

-- The diagnostic has to work in either style, because it is what says which.
addon.plain:PrintStatus()
Row(GetString(SI_PBSCHC_STYLE)).setFunction(nil, nil, { data = "standard" })
addon.plain:PrintStatus()
check("the diagnostic runs in either style", true, true)

print("\n== 28. a rectangle that cannot be read must not stop the move ==")
-- The bug behind "the position setting does not take effect, sometimes": the measurement and the
-- capture were one call, so a control whose rectangle was not readable at that moment -- which
-- depends on how far the UI has got at login -- made the add-on refuse to write at all.
SavedStore.PBsConsoleHudCustomizer_Data = nil
addon.account = ZO_SavedVars:NewAccountWide("PBsConsoleHudCustomizer_Data", 1, nil, addon.accountDefaults)
addon:Account()
addon.written, addon.original = {}, {}
addon.skillbar.original, addon.skillbar.written = nil, false
BuildAttributeBars()
SetAllSlots()

-- As if the client had not laid the bars out yet.
local health = _G[HEALTH]
local realWidth, realHeight = health.width, health.height
health.width, health.height = 0, 0
addon:CaptureAll()
check("the measurement is refused", addon:Measured(health_bar or addon.barByKey.health).x, nil)
check("but the anchor was still captured", addon.original.health ~= nil, true)

Row(GetString(SI_PBSCHC_POSITION_Y):gsub("<<1>>", GetString(SI_PBSCHC_BAR_HEALTH))).setFunction(500)
check("and the bar still moves", BarAnchor(HEALTH), "128->GuiRoot 4 (0,-500)")
check("no capture error was recorded", (addon.writeErrors or {}).capture, nil)

-- The rectangle turns up later; the game's own position is only then known.
health.width, health.height = realWidth, realHeight
FireHud(SCENE_FRAGMENT_SHOWN)
check("the measurement is not taken once ours is on the bar", addon:Measured(addon.barByKey.health).x, nil)
check("and the bar has not moved because of it", BarAnchor(HEALTH), "128->GuiRoot 4 (0,-500)")

print("\n== 29. anything that moves a bar back is put right again ==")
check("the watch runs while the HUD is up", addon.watching, true)
local repairs = addon.repairs or 0
-- Something else re-anchors the health bar, the way a client update or another add-on might.
_G[HEALTH]:ClearAnchors()
_G[HEALTH]:SetAnchor(CENTER, _G.ZO_PlayerAttribute, CENTER, 0, 0)
addon:Verify()
check("it is put back", BarAnchor(HEALTH), "128->GuiRoot 4 (0,-500)")
check("and counted", (addon.repairs or 0) > repairs, true)
addon:Verify()
check("a second look writes nothing", addon.repairs, repairs + 1)
FireHud(SCENE_FRAGMENT_HIDDEN)
check("the watch stops with the HUD", addon.watching, false)
FireHud(SCENE_FRAGMENT_SHOWN)
check("and comes back with it", addon.watching, true)

print("\n== 30. the first apply can try again on a later zone load ==")
addon.firstApplyDone, addon.firstApplyScheduled = false, false
PLAYER_ATTRIBUTE_BARS = nil
Fire(EVENT_PLAYER_ACTIVATED)
for _ = 1, 12 do
	FlushCallLater()
end
check("it gives up after its attempts", addon.firstApplyDone, false)
check("but does not stay given up", addon.firstApplyScheduled, false)
PLAYER_ATTRIBUTE_BARS = { bars = {} }
Fire(EVENT_PLAYER_ACTIVATED)
FlushCallLater()
check("so the next zone load applies it", addon.firstApplyDone, true)

print("\n== 31. the countdown sits where the game's own does ==")
-- Reported from a PS5: our number was off the middle of the icon. It was anchored to the bottom
-- of the button, to stay clear of the client's own number -- but in the default mode the
-- client's is faded out and ours should be standing exactly where it was.
addon.account.text.timerMode = "addon"
GameBarTimers = true
SetAllSlots()
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 8400, duration = 20000 })
FireHud(SCENE_FRAGMENT_SHOWN)
RunUpdates()
-- Taken from the add-on rather than by name: a pair built through the fallback path earlier in
-- this run has its children on the control itself, not under a named child.
local pair3 = addon.timers.labels[3]
local labels3 = pair3.control
local timer3 = pair3.timer
check("the labels hang on the icon, not the button", labels3.anchors[1].relativeTo:GetName(), "ActionButton3Icon")
check("the countdown is centred", timer3.anchors[1].point, CENTER)
-- Dead centre on the icon. The client puts its own 4 down
-- (ACTION_BUTTON_TIMER_TEXT_OFFSET_Y_DEFAULT_GAMEPAD); ours is not, because at 4 it reads as
-- sitting low, which is what came back from the PS5.
check("with no offset of its own", timer3.anchors[1].offsetY, 0)
-- And it is as tall as its own text, or a big size cannot centre in it.
check("the label is the height of its font", timer3.height > 0, true)
check("only one anchor on it", #timer3.anchors, 1)
check("the game's number is out of the way", _G["ActionButton3"].namedChildren.TimerText:GetAlpha(), 0)

-- Both: the client's number is there as well, so ours cannot sit on top of it.
Row(GetString(SI_PBSCHC_TIMER_MODE)).setFunction(nil, nil, { data = "both" })
RunUpdates()
check("ours steps aside when both are drawn", timer3.anchors[1].point, BOTTOM)
check("and the game's is left alone", _G["ActionButton3"].namedChildren.TimerText:GetAlpha(), 1)
Row(GetString(SI_PBSCHC_TIMER_MODE)).setFunction(nil, nil, { data = "addon" })
RunUpdates()
check("and back to the middle", timer3.anchors[1].point, CENTER)

-- With the game not drawing one at all, ours is centred whichever mode is chosen.
GameBarTimers = false
Row(GetString(SI_PBSCHC_TIMER_MODE)).setFunction(nil, nil, { data = "both" })
RunUpdates()
check("Both keeps ours out of the way either way", timer3.anchors[1].point, BOTTOM)
check("and hands the game's back", _G["ActionButton3"].namedChildren.TimerText:GetAlpha(), 1)
Row(GetString(SI_PBSCHC_TIMER_MODE)).setFunction(nil, nil, { data = "addon" })
RunUpdates()
check("addon takes the middle and fades the game's", timer3.anchors[1].point, CENTER)

-- The target count keeps out of the corner the client uses for its stack count (CENTER +23, -20).
check("the target count is in the other corner", pair3.count.anchors[1].point, TOPLEFT)

print("\n== 32. a button that has been rebuilt is faded again ==")
-- The fade was remembered per slot, so a slot whose button had been replaced was taken for done
-- and left with the game's number sitting on top of ours.
addon.account.text.timerMode = "addon"
RunUpdates()
local oldTimerText = _G["ActionButton3"].namedChildren.TimerText
check("the one on screen is faded", oldTimerText:GetAlpha(), 0)
BuildActionBar()
local newTimerText = _G["ActionButton3"].namedChildren.TimerText
check("and the rebuild is a different control", newTimerText ~= oldTimerText, true)
RunUpdates()
check("which is faded as well", newTimerText:GetAlpha(), 0)
check("the one it replaced is handed back", oldTimerText:GetAlpha(), 1)

print("\n== 33. a default thought better of, on an install that already ran ==")
-- ZO_SavedVars copies defaults into the saved table, so 1.1.0's countFromOne = false is still
-- there on every install that ran it, and 1.1.1's change of mind never reached them: the target
-- count then says nothing at all for a single-target ability.
SavedStore.PBsConsoleHudCustomizer_Data = { text = { timerMode = "auto", countFromOne = false } }
addon.account = ZO_SavedVars:NewAccountWide("PBsConsoleHudCustomizer_Data", 1, nil, addon.accountDefaults)
addon:Account()
check("the old setting is moved on", addon:Text().countFromOne, true)
check("and the old mode name with it", addon:TimerMode(), "addon")
check("marked, so it is only done once", addon:Text().version, 2)
-- And a player who really does want it from two is left alone.
addon:Text().countFromOne = false
addon:Account()
check("a choice made since is kept", addon:Text().countFromOne, false)
addon:Text().countFromOne = true

print("\n== 34. an effect whose name is not the ability's is matched by its icon ==")
addon.timers:Forget_All()
SetAllSlots()
SetSlot(HOTBAR_CATEGORY_PRIMARY, 4, { name = "Barbed Trap", icon = "trap.dds", id = 140, remaining = 9000, duration = 20000 })
local now2 = GetGameTimeMilliseconds()
-- The effect the client reports carries another name, as a morph's often does, but the same art.
Fire(EVENT_EFFECT_CHANGED, EFFECT_RESULT_GAINED, 1, "Trap Beast", "", 0, (now2 + 9000) / 1000, 0,
	"/Trap.dds", nil, 1, 1, 0, "someone", 77, 999, COMBAT_UNIT_TYPE_PLAYER)
RunUpdates()
local _, countText, count, matchedBy = addon.timers:SlotText(4, HOTBAR_CATEGORY_PRIMARY, GetGameTimeMilliseconds())
check("the name does not match", addon.timers.Normalize("Barbed Trap") == addon.timers.Normalize("Trap Beast"), false)
check("but the icon does", matchedBy, "icon")
check("so it is counted", count, 1)
check("and written", countText, "1")

print("\n== 35. an install that had chosen the liquid style ==")
-- 1.3.x had a liquid style that never drew anything on a console. It is gone; anyone who had
-- chosen it gets the plain one rather than being dropped back to Standard without being told.
SavedStore.PBsConsoleHudCustomizer_Data = { style = "liquid", liquidStrength = 150 }
addon.account = ZO_SavedVars:NewAccountWide("PBsConsoleHudCustomizer_Data", 1, nil, addon.accountDefaults)
addon:Account()
check("the style is carried over", addon:BarStyle(), "plain")
check("and its strength becomes an opacity in range", addon:PlainOpacity(), 100)
check("the old key is cleared away", addon.account.liquidStrength, nil)
-- And the command still answers to the old name.
SLASH_COMMANDS["/pbhud"]("style liquid")
check("so does the command", addon:BarStyle(), "plain")
SLASH_COMMANDS["/pbhud"]("style standard")

print("\n== 36. handing the skill bar back to another add-on ==")
SavedStore.PBsConsoleHudCustomizer_Data = nil
addon.account = ZO_SavedVars:NewAccountWide("PBsConsoleHudCustomizer_Data", 1, nil, addon.accountDefaults)
addon:Account()
addon.written, addon.original = {}, {}
addon.skillbar.original, addon.skillbar.written = nil, false
BuildAttributeBars()
SetAllSlots()
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 9000, duration = 20000 })
addon:CaptureAll()
FireHud(SCENE_FRAGMENT_SHOWN)

-- Everything the add-on does to the bar, on.
Row(GetString(SI_PBSCHC_POSITION_Y):gsub("<<1>>", GetString(SI_PBSCHC_BAR_SKILLBAR))).setFunction(300)
Row(GetString(SI_PBSCHC_SCALE):gsub("<<1>>", GetString(SI_PBSCHC_BAR_SKILLBAR))).setFunction(80)
Row(GetString(SI_PBSCHC_GAP_ULTIMATE)).setFunction(12)
RunUpdates()
check("the bar is moved", BarAnchor(SKILLBAR), "128->GuiRoot 4 (0,-300)")
check("the gaps are ours", BarAnchor("ActionButton8"), "2->ActionButton7 8 (12,0)")
check("the other set's row is drawn", CreatedControls["PBsConsoleHudCustomizerBack3"]:IsHidden(), false)
check("the game's countdown is faded", _G["ActionButton3"].namedChildren.TimerText:GetAlpha(), 0)

-- Handed back.
Row(GetString(SI_PBSCHC_SKILLBAR_ENABLED)).setFunction(false)
check("the bar goes back where the game has it", BarAnchor(SKILLBAR), "4->GuiRoot 4 (0,-25)")
check("at the game's size", _G[SKILLBAR]:GetScale(), 1)
check("the gaps go back too", BarAnchor("ActionButton8"), "2->ActionButton7 8 (65,0)")
check("the row goes", CreatedControls["PBsConsoleHudCustomizerBack3"]:IsHidden(), true)
check("the game's countdown is handed back", _G["ActionButton3"].namedChildren.TimerText:GetAlpha(), 1)
check("the shade goes", CreatedControls["PBsConsoleHudCustomizerShade3"]:IsHidden(), true)
check("and the loop stops", UpdateRegistered("PBsConsoleHudCustomizerTimers"), false)
check("nothing of ours differs any more", addon:AnythingDiffers(), false)
-- Another add-on lays the bar out its own way; the watch must not take it back.
_G[SKILLBAR]:ClearAnchors()
_G[SKILLBAR]:SetAnchor(TOP, GuiRoot, TOP, 0, 40)
addon:Verify()
RunUpdates()
check("and the watch leaves it alone", BarAnchor(SKILLBAR), "1->GuiRoot 1 (0,40)")

-- The attribute bars are none of its business.
Row(GetString(SI_PBSCHC_POSITION_Y):gsub("<<1>>", GetString(SI_PBSCHC_BAR_HEALTH))).setFunction(420)
check("the health bar still moves", BarAnchor(HEALTH), "128->GuiRoot 4 (0,-420)")

-- And back: the settings were kept.
Row(GetString(SI_PBSCHC_SKILLBAR_ENABLED)).setFunction(true)
RunUpdates()
check("the bar is placed again", BarAnchor(SKILLBAR), "128->GuiRoot 4 (0,-300)")
check("the gaps come back", BarAnchor("ActionButton8"), "2->ActionButton7 8 (12,0)")
check("and so does the row", CreatedControls["PBsConsoleHudCustomizerBack3"]:IsHidden(), false)

print("\n== 37. the three things the PS5 came back with ==")
-- (a) A target count that appeared and vanished again in the same breath. Re-applying a
-- damage-over-time on a target that already has it sends the new application first and the old
-- one's fade after it, and the fade was taken at face value.
addon.timers:Forget_All()
addon.account.text.countFromOne = true
SetAllSlots()
SetSlot(HOTBAR_CATEGORY_PRIMARY, 5, { name = "Twin Slashes", icon = "slash.dds", id = 150, remaining = 10000, duration = 10000 })
FireHud(SCENE_FRAGMENT_SHOWN)
local now3 = GetGameTimeMilliseconds()
FireEffect(EFFECT_RESULT_GAINED, "Twin Slashes", "", (now3 + 10000) / 1000, 55, 150)
RunUpdates()
local count5 = addon.timers.labels[5].count
check("the count is written", count5:GetText(), "1")
-- Cast again: a new application, then the old one's fade.
FireEffect(EFFECT_RESULT_GAINED, "Twin Slashes", "", (now3 + 20000) / 1000, 55, 150)
FireEffect(EFFECT_RESULT_FADED, "Twin Slashes", "", (now3 + 10000) / 1000, 55, 150)
RunUpdates()
check("a fade for the instance just replaced is ignored", count5:IsHidden(), false)
check("and the count still stands", count5:GetText(), "1")
check("it was counted as stale", addon.timers.staleFades >= 1, true)
-- A real fade, a moment later and of the instance on record, does take the unit off. The number
-- is still held, because the client still says the slot's effect is running -- that is the point
-- of the hold, and what stops the count blinking whatever the effect events do.
AdvanceFrame(1000)
FireEffect(EFFECT_RESULT_FADED, "Twin Slashes", "", (now3 + 20000) / 1000, 55, 150)
RunUpdates()
check("the unit is taken off", addon.timers:CountFor(addon.timers.Normalize("Twin Slashes"), 150, nil, GetGameTimeMilliseconds()), 0)
check("but the number is held while the client times it", count5:GetText(), "1")
check("and the hold is counted", (addon.timers.held or 0) >= 1, true)
-- The client's timer reaching zero is what ends it.
SetSlot(HOTBAR_CATEGORY_PRIMARY, 5, { name = "Twin Slashes", icon = "slash.dds", id = 150, remaining = 0, duration = 0 })
RunUpdates()
check("the effect running out ends it", count5:IsHidden(), true)
SetSlot(HOTBAR_CATEGORY_PRIMARY, 5, { name = "Twin Slashes", icon = "slash.dds", id = 150, remaining = 10000, duration = 10000 })
-- An effect whose end time has already gone by is the two clocks disagreeing, not an effect that
-- is over: kept until its own fade rather than dropped the moment it is looked at.
FireEffect(EFFECT_RESULT_GAINED, "Twin Slashes", "", (now3 - 5000) / 1000, 55, 150)
RunUpdates()
check("an effect that arrives already over is kept", count5:GetText(), "1")
check("and counted as the oddity it is", (addon.timers.pastEffects or 0) >= 1, true)
FireEffect(EFFECT_RESULT_FADED, "Twin Slashes", "", 0, 55, 150)
RunUpdates()

-- (b) The game's own countdown came back from behind ours. ActionButton:ApplyStyle re-applies
-- the platform template on every HandleSlotChanged -- a weapon swap, a zone load, a slot change
-- -- and hands the label its alpha back.
addon.account.text.timerMode = "addon"
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 9000, duration = 20000 })
RunUpdates()
local gameTimer3 = _G["ActionButton3"].namedChildren.TimerText
check("faded to begin with", gameTimer3:GetAlpha(), 0)
gameTimer3:SetAlpha(1) -- the client's template, re-applied
RunUpdates()
check("and faded again the moment it is back", gameTimer3:GetAlpha(), 0)
check("which is counted", (addon.timers.redims or 0) >= 2, true)

-- (c) The resource numbers were behind the plain rectangle: the numbers are drawn at the
-- default tier and the rectangles at HIGH.
Row(GetString(SI_PBSCHC_STYLE)).setFunction(nil, nil, { data = "plain" })
RunUpdates()
local numbers = _G.ZO_PlayerAttributeMagickaResourceNumbers
check("the numbers are lifted to the rectangle's tier", numbers:GetDrawTier(), DT_HIGH)
check("and above it", numbers:GetDrawLevel() > 1, true)
Row(GetString(SI_PBSCHC_STYLE)).setFunction(nil, nil, { data = "standard" })
check("and put back when the style is", numbers:GetDrawTier(), "medium")
check("at the level the client had them", numbers:GetDrawLevel(), 0)

print("\n== 38. the count is held for the whole of the effect ==")
-- The guarantee, after two rounds of the count blinking out: whatever the effect events do, the
-- number stays on the icon for as long as the client says that slot's effect is running, and
-- goes when it stops. The countdown beside it is the same client number, so the two end together.
addon.timers:Forget_All()
addon.timers.counts = {}
addon.account.text.countFromOne = true
SetSlot(HOTBAR_CATEGORY_PRIMARY, 6, { name = "Caltrops", icon = "caltrops.dds", id = 160, remaining = 18000, duration = 20000 })
local now4 = GetGameTimeMilliseconds()
FireEffect(EFFECT_RESULT_GAINED, "Caltrops", "", (now4 + 18000) / 1000, 61, 160)
FireEffect(EFFECT_RESULT_GAINED, "Caltrops", "", (now4 + 18000) / 1000, 62, 160)
RunUpdates()
local count6 = addon.timers.labels[6].count
check("three... two targets", count6:GetText(), "2")
-- Every trace of them goes: a fade the add-on believes, or bookkeeping lost for any other
-- reason. The client still times the slot, so the number stays.
addon.timers:Forget_All()
RunUpdates()
check("the number stays when the bookkeeping does not", count6:GetText(), "2")
-- A real change is still a change: a live count replaces the held one.
FireEffect(EFFECT_RESULT_GAINED, "Caltrops", "", (now4 + 18000) / 1000, 63, 160)
RunUpdates()
check("a live count replaces it", count6:GetText(), "1")
-- Another ability in the slot starts again from nothing.
SetSlot(HOTBAR_CATEGORY_PRIMARY, 6, { name = "Something Else", icon = "other.dds", id = 161, remaining = 18000, duration = 20000 })
RunUpdates()
check("a different ability in the slot holds nothing", count6:IsHidden(), true)

print("\n== 39. one slot, two effects: Blue Betty ==")
-- From a PS5: the netch's countdown ran 22, 21, ... and then, a few seconds from the end,
-- started again at 5. One slot can have more than one effect of the player's own running, and
-- the client answers with whichever has the longer left -- so a few seconds from the end it
-- hands over to the thing the netch does every 5 seconds.
addon.timers.timers = {}
addon.timers.shorterIgnored = 0
addon.account.text.timerMode = "addon"
local BETTY = { name = "Blue Betty", icon = "betty.dds", id = 170 }
local function Betty(remaining, duration)
	SetSlot(HOTBAR_CATEGORY_PRIMARY, 7, { name = BETTY.name, icon = BETTY.icon, id = BETTY.id,
		remaining = remaining, duration = duration })
end
Betty(22000, 22000)
FireHud(SCENE_FRAGMENT_SHOWN)
RunUpdates()
local bettyTimer = addon.timers.labels[7].timer
check("the buff's own time is shown", bettyTimer:GetText(), "22")
Betty(9000, 22000)
RunUpdates()
check("counting down", bettyTimer:GetText(), "9.0")
-- The client hands over to the netch's own five-second effect.
AdvanceFrame(1000)
Betty(5000, 5000)
RunUpdates()
check("the shorter one does not take over", bettyTimer:GetText(), "8.0")
check("and that is counted", addon.timers.shorterIgnored >= 1, true)
-- It carries on counting the buff out, whatever the client reports in the meantime.
AdvanceFrame(4000)
Betty(4000, 5000)
RunUpdates()
check("still the buff's own time", bettyTimer:GetText(), "4.0")
-- Re-casting the same ability is not a shorter effect: same length, and it starts again.
AdvanceFrame(1000)
Betty(22000, 22000)
RunUpdates()
check("a re-cast is taken", bettyTimer:GetText(), "22")
-- When it really is over, it is over.
Betty(0, 0)
RunUpdates()
check("and the end is the end", bettyTimer:IsHidden(), true)
-- A short effect on its own, with nothing longer running, is shown as it is.
AdvanceFrame(1000)
Betty(5000, 5000)
RunUpdates()
check("a short effect on its own is shown", bettyTimer:GetText(), "5.0")
Betty(0, 0)
RunUpdates()

print("")
if failures == 0 then
	print("all checks passed")
else
	print(failures .. " FAILED")
end
os.exit(failures == 0 and 0 or 1)
