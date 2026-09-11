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
check("version read from manifest", addon.version, "1.0.0")
check("slash command registered", type(SLASH_COMMANDS["/pbhud"]), "function")
check("short slash command registered", type(SLASH_COMMANDS["/pbhc"]), "function")
check("HUD fragment callback registered", addon.hudRegistered, true)
-- explanation, 2 checkboxes, then per bar: heading + 2 sliders + scale + reset, then
-- heading + reset + hint
-- explanation, 2 checkboxes, then per element: heading + 2 sliders + scale + reset, then the
-- back bar section (heading, label, 2 checkboxes, 2 sliders), the text section (heading, label,
-- dropdown, 3 sliders, 3 checkboxes) and the general one (heading, button, hint)
check("settings rows", #PanelRows, 3 + 4 * 5 + 6 + 8 + 3)

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
check("one target is not written by default", frontCount:IsHidden(), true)
FireEffect(EFFECT_RESULT_GAINED, "Front 3", "", (now + 9000) / 1000, 12, 303)
FireEffect(EFFECT_RESULT_GAINED, "Front 3", "", (now + 9000) / 1000, 13, 303)
RunUpdates()
check("three targets", frontCount:GetText(), "3")
FireEffect(EFFECT_RESULT_FADED, "Front 3", "", 0, 12, 303)
RunUpdates()
check("two after one falls off", frontCount:GetText(), "2")
-- A group member's copy of the same effect is not another target.
FireEffect(EFFECT_RESULT_GAINED, "Front 3", "group3", (now + 9000) / 1000, 14, 303)
RunUpdates()
check("a group member's copy is not counted", frontCount:GetText(), "2")
Row(GetString(SI_PBSCHC_COUNT_FROM_ONE)).setFunction(true)
FireEffect(EFFECT_RESULT_GAINED, "Back 4", "", (now + 9000) / 1000, 21, 404)
RunUpdates()
check("a single target is written when that is asked for", CreatedControls["PBsConsoleHudCustomizerBack4"].namedChildren.Count:GetText(), "1")
-- The count is matched by name; an ability with no effect of its own has none.
check("an untouched slot has no count", CreatedControls["PBsConsoleHudCustomizerLabels6"].namedChildren.Count:IsHidden(), true)
-- Expiry is by the clock, not by an event.
AdvanceFrame(10000)
RunUpdates()
check("an effect that has run out stops being counted", frontCount:IsHidden(), true)
Row(GetString(SI_PBSCHC_COUNT_ENABLED)).setFunction(false)
RunUpdates()
check("switched off entirely", CreatedControls["PBsConsoleHudCustomizerBack4"].namedChildren.Count:IsHidden(), true)
Row(GetString(SI_PBSCHC_COUNT_ENABLED)).setFunction(true)

print("\n== 20. the game's own numbers, the text size, and the loop ==")
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 8400 })
GameBarTimers = true
RunUpdates()
check("automatic keeps off the bar the game is writing on", frontTimer:IsHidden(), true)
check("but still writes on the other set", backTimer:IsHidden(), false)
Row(GetString(SI_PBSCHC_TIMER_MODE)).setFunction(nil, nil, { data = "always" })
RunUpdates()
check("always writes anyway", frontTimer:GetText(), "8.4")
Row(GetString(SI_PBSCHC_TIMER_MODE)).setFunction(nil, nil, { data = "never" })
RunUpdates()
check("never writes on either", frontTimer:IsHidden(), true)
check("nor on the other set", backTimer:IsHidden(), true)
Row(GetString(SI_PBSCHC_TIMER_MODE)).setFunction(nil, nil, { data = "auto" })
GameBarTimers = false
RunUpdates()
check("and back", frontTimer:GetText(), "8.4")

Row(GetString(SI_PBSCHC_TIMER_SIZE)).setFunction(36)
check("the countdown font follows the slider", frontTimer.font, "$(GAMEPAD_BOLD_FONT)|36|thick-outline")
check("on the other set too", backTimer.font, "$(GAMEPAD_BOLD_FONT)|36|thick-outline")
Row(GetString(SI_PBSCHC_COUNT_SIZE)).setFunction(16)
check("and the count has its own size", frontCount.font, "$(GAMEPAD_BOLD_FONT)|16|thick-outline")

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
check("at its own size", _G[SKILLBAR]:GetScale(), 1)
Row(GetString(SI_PBSCHC_ENABLED)).setFunction(true)
check("on again", UpdateRegistered("PBsConsoleHudCustomizerTimers"), true)

print("")
if failures == 0 then
	print("all checks passed")
else
	print(failures .. " FAILED")
end
os.exit(failures == 0 and 0 or 1)
