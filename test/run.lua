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
check("version read from manifest", addon.version, "1.25.0")
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
-- button, hint), and the measurement section (heading, hint, two buttons)
-- ... and the skill bar's section carries one more row than the other three: the switch that
-- hands the whole bar back.
-- ... and the three attribute bars carry two more rows each: the width and the height
-- MURA-HIGE Style draws them at.
check("settings rows", #PanelRows, 3 + 6 + 4 * 5 + 3 * 2 + 1 + 5 + 6 + 11 + 6 + 3 + 4)

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
check("it inherits visibility from the bar", back3:GetParent():GetName(), "ZO_ActionBar1")
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
-- The addon keeps counting through the final second.
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Front 3", icon = "front3.dds", id = 103, remaining = 400 })
RunUpdates()
check("still visible under a second", frontTimer:IsHidden(), false)
check("tenths continue under a second", frontTimer:GetText(), "0.4")
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
check("weapon swap locked: configured row stays visible", CreatedControls["PBsConsoleHudCustomizerBack3"]:IsHidden(), false)
check("and says why", select(2, addon:WeaponSwapState()), "locked")
check("the setting is untouched", addon:BackBar().enabled, true)
WeaponPairLocked = false
RunUpdates()
check("take the ring off and it is back", CreatedControls["PBsConsoleHudCustomizerBack3"]:IsHidden(), false)
-- A character too low to have earned the second bar.
PlayerLevel = 10
RunUpdates()
check("visibility follows setting even before swap unlock", CreatedControls["PBsConsoleHudCustomizerBack3"]:IsHidden(), false)
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
check("and the fill takes the power's own colour", magickaPlain.namedChildren.Fill.color[3], 0.8)

-- Magicka fills towards its left, so its block hangs off the right edge and is as wide as the
-- bar is full: half, here.
check("the block is held by the edge the bar fills from", magickaPlain.namedChildren.Fill.anchors[1].point, TOPRIGHT)
check("as wide as the bar is full", magickaPlain.namedChildren.Fill:GetWidth(), 112)

-- The game's arrow frame and background are put away while this style is on.
check("the frame is put away", _G.ZO_PlayerAttributeMagickaFrameCenter:IsHidden(), true)
check("and the background with it", _G.ZO_PlayerAttributeMagickaBgContainer:IsHidden(), true)
-- The game's frame is always put away now; the frame on offer is an outline of the add-on's own.
local magickaOverlay = addon.plain.overlays["ZO_PlayerAttributeMagickaBar"]
check("the outline is drawn by default", magickaOverlay.border.Top:IsHidden(), false)
check("dark, and along the whole edge", magickaOverlay.border.Top.centerColor[4] > 0.5, true)
Row(GetString(SI_PBSCHC_PLAIN_BORDER)).setFunction(false)
RunUpdates()
check("and can be switched off", magickaOverlay.border.Top:IsHidden(), true)
check("all four sides with it", magickaOverlay.border.Right:IsHidden(), true)
Row(GetString(SI_PBSCHC_PLAIN_BORDER)).setFunction(true)
RunUpdates()
check("back on again", magickaOverlay.border.Bottom:IsHidden(), false)

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
check("the command selects the new liquid style", addon:BarStyle(), "liquidflow")
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

print("\n== 40. the effect a slot's cast produced ==")
-- Blue Betty again, and this time the way the add-ons that get it right do it: the client's
-- per-slot reading is not asked at all while the cast's own effect is running. It is the
-- reading that hands over -- 22 seconds of buff giving way to the five-second thing the netch
-- does -- and no guard on top of it can tell which one the player means.
addon.timers:Forget_All()
addon.timers.timers = {}
addon.account.text.timerMode = "addon"
addon.account.text.countFromOne = true
SetSlot(HOTBAR_CATEGORY_PRIMARY, 7, { name = "Blue Betty", icon = "betty.dds", id = 170, remaining = 22000, duration = 22000 })
FireHud(SCENE_FRAGMENT_SHOWN)

SetAbilityDuration(170, 22000)
local now5 = GetGameTimeMilliseconds()
FireCast(7)
-- What the netch actually puts on the player is called something else entirely, and the game
-- sends the short one first.
FireEffect(EFFECT_RESULT_GAINED, "Netch Swipe", "player", (now5 + 5000) / 1000, 1, 900)
FireEffect(EFFECT_RESULT_GAINED, "Major Sorcery", "player", (now5 + 22000) / 1000, 1, 901)
RunUpdates()
local timer7 = addon.timers.labels[7].timer
check("the ability duration is used instead of unrelated buffs", timer7:GetText(), "22")

-- The client hands over to the short one. It is not even asked.
AdvanceFrame(18000)
SetSlot(HOTBAR_CATEGORY_PRIMARY, 7, { name = "Blue Betty", icon = "betty.dds", id = 170, remaining = 5000, duration = 5000 })
RunUpdates()
check("and the client's hand-over is not followed", timer7:GetText(), "4.0")

-- The buff ends when it ends.
AdvanceFrame(4000)
RunUpdates()
check("it ends with the effect", timer7:IsHidden(), true)

-- And once the cast's effect is over, the little one the same ability keeps up alongside it does
-- not step in: the icon goes quiet until the ability is cast again.
SetSlot(HOTBAR_CATEGORY_PRIMARY, 7, { name = "Blue Betty", icon = "betty.dds", id = 170, remaining = 5000, duration = 5000 })
RunUpdates()
check("the netch's own five seconds do not take over at the end", timer7:IsHidden(), true)
local now8 = GetGameTimeMilliseconds()
FireCast(7)
FireEffect(EFFECT_RESULT_GAINED, "Major Sorcery", "player", (now8 + 22000) / 1000, 1, 901)
RunUpdates()
check("casting it again starts it again", timer7:GetText(), "22")

-- A cast whose effect lands on several targets: the count comes from that same effect, so it
-- cannot be looking at one thing while the countdown looks at another.
addon.timers:Forget_All()
SetAbilityDuration(140, 20000)
local now6 = GetGameTimeMilliseconds()
SetSlot(HOTBAR_CATEGORY_PRIMARY, 4, { name = "Barbed Trap", icon = "trap.dds", id = 140, remaining = 0, duration = 0 })
FireCast(4)
FireEffect(EFFECT_RESULT_GAINED, "Trap Beast", "", (now6 + 20000) / 1000, 81, 141, "trap.dds")
FireEffect(EFFECT_RESULT_GAINED, "Trap Beast", "", (now6 + 20000) / 1000, 82, 141, "trap.dds")
RunUpdates()
local count4 = addon.timers.labels[4].count
check("the count is of the cast's own effect", count4:GetText(), "2")
check("even though the client times nothing on that slot", timer7 ~= nil and addon.timers.labels[4].timer:GetText(), "20")
-- ... and it stays for the whole of it.
AdvanceFrame(10000)
RunUpdates()
check("still there half way through", count4:GetText(), "2")
AdvanceFrame(11000)
RunUpdates()
check("and gone at the end", count4:IsHidden(), true)

-- A cast of another slot does not steal it.
local now7 = GetGameTimeMilliseconds()
FireCast(6)
FireEffect(EFFECT_RESULT_GAINED, "Something Else", "player", (now7 + 9000) / 1000, 1, 902)
RunUpdates()
check("the other slot matches its own named effect", addon.timers.labels[6].timer:GetText(), "9.0")
check("and this one is untouched", addon.timers.labels[4].timer:IsHidden(), true)

print("\n== 41. the same ability on both weapon sets ==")
-- From a PS5: the netch on both bars counted down to two different numbers. It is one effect,
-- and only the bar it was cast from had it on record; the other fell back to the client's
-- per-slot reading, which is the one that hands over to something else.
addon.timers:Forget_All()
addon.timers.timers = {}
SetSlot(HOTBAR_CATEGORY_PRIMARY, 5, { name = "Blue Betty", icon = "betty.dds", id = 170, remaining = 22000, duration = 22000 })
-- Slotted on the other set as well, in a different slot, as it usually is.
SetSlot(HOTBAR_CATEGORY_BACKUP, 7, { name = "Blue Betty", icon = "betty.dds", id = 170, remaining = 5000, duration = 5000 })
FireHud(SCENE_FRAGMENT_SHOWN)

local now9 = GetGameTimeMilliseconds()
FireCast(5)
FireEffect(EFFECT_RESULT_GAINED, "Major Sorcery", "player", (now9 + 22000) / 1000, 1, 901)
RunUpdates()
local front5 = addon.timers.labels[5].timer
local back7 = CreatedControls["PBsConsoleHudCustomizerBack7"].namedChildren.Timer
check("the bar it was cast from counts the buff", front5:GetText(), "22")
check("and the other set's row says the same", back7:GetText(), "22")

AdvanceFrame(13000)
RunUpdates()
check("both count together", front5:GetText(), "9.0")
check("whatever the client says about the other bar", back7:GetText(), "9.0")

-- A weapon swap does not change the answer: the cast is on record by the ability, not the bar.
ActiveHotbar = HOTBAR_CATEGORY_BACKUP
RunUpdates()
local swappedFront = addon.timers.labels[7].timer
check("after swapping, the bar in hand still has it", swappedFront:GetText(), "9.0")
ActiveHotbar = HOTBAR_CATEGORY_PRIMARY
RunUpdates()

-- A different ability keeps its own answer.
SetSlot(HOTBAR_CATEGORY_BACKUP, 7, { name = "Something Else", icon = "other.dds", id = 180, remaining = 4000, duration = 4000 })
RunUpdates()
check("another ability is not given the netch's time", back7:GetText(), "4.0")

print("\n== 42. what the player's pet puts on the world ==")
-- Filtered to the player as the source, none of what a pet applies is ever seen -- and the netch
-- of Blue Betty is a pet, as are the sorcerer's familiars, the warden's bear and the shade. For
-- those abilities the effect never arrives, so there is no cast to tie it to and nothing to
-- count: "the target count does not work".
addon.timers:Forget_All()
addon.timers.timers = {}
addon.timers.counts = {}
addon.account.text.countFromOne = true
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Blue Betty", icon = "betty.dds", id = 170, remaining = 0, duration = 0 })
FireHud(SCENE_FRAGMENT_SHOWN)

local now10 = GetGameTimeMilliseconds()
FireCast(3)
-- The netch, not the player, is what grants it.
FireEffectFrom(COMBAT_UNIT_TYPE_PLAYER_PET, EFFECT_RESULT_GAINED, "Major Sorcery", "player",
	(now10 + 22000) / 1000, 1, 901, "betty.dds")
RunUpdates()
local timer3b = addon.timers.labels[3].timer
local count3b = addon.timers.labels[3].count
check("the pet's effect is seen", timer3b:GetText(), "22")
-- ... and counts as no target at all, because it landed on the player: a buff on yourself is not
-- a target count, which is where FancyActionBar+ draws the line too.
check("but a buff on yourself is not a target", count3b:IsHidden(), true)
check("both registrations are in place", addon.timers.sources, 2)

print("\n== 43. the cap does not throw away what is being watched ==")
-- A long session fills the table with every effect the player has applied. The entry that goes
-- to make room used to be the one least recently *added*, which is exactly a damage-over-time
-- ticking quietly on three targets.
addon.timers:Forget_All()
local now11 = GetGameTimeMilliseconds()
SetSlot(HOTBAR_CATEGORY_PRIMARY, 4, { name = "Caltrops", icon = "caltrops.dds", id = 140, remaining = 0, duration = 0 })
FireCast(4)
FireEffect(EFFECT_RESULT_GAINED, "Caltrops", "", (now11 + 30000) / 1000, 91, 141)
FireEffect(EFFECT_RESULT_GAINED, "Caltrops", "", (now11 + 30000) / 1000, 92, 141)
RunUpdates()
local count4b = addon.timers.labels[4].count
check("two targets", count4b:GetText(), "2")
-- Another two hundred effects come and go, all of them over as they arrive.
for index = 1, 200 do
	AdvanceFrame(10)
	FireEffect(EFFECT_RESULT_GAINED, "Passing Thing " .. index, "", (GetGameTimeMilliseconds() + 1200) / 1000, 500 + index, 500 + index)
	RunUpdates()
end
check("the one being watched is still there", count4b:GetText(), "2")
check("and something was dropped to make room", (addon.timers.dropped or 0) > 0, true)

print("\n== 44. the two shapes this add-on draws ==")
Row(GetString(SI_PBSCHC_STYLE)).setFunction(nil, nil, { data = "plain" })
RunUpdates()
local plainOverlay = addon.plain.overlays["ZO_PlayerAttributeStaminaBar"]
local plainBar = plainOverlay.control
check("square draws the rectangle", plainOverlay.fill:IsHidden(), false)
check("at the game's own size", plainOverlay.sizedWidth, nil)

Row(GetString(SI_PBSCHC_STYLE)).setFunction(nil, nil, { data = "rounded" })
RunUpdates()
check("MURA-HIGE draws the same rectangle", plainOverlay.fill:IsHidden(), false)
check("the frame is still put away", _G.ZO_PlayerAttributeStaminaFrameCenter:IsHidden(), true)
check("and the numbers still lifted over it", _G.ZO_PlayerAttributeStaminaResourceNumbers:GetDrawTier(), DT_HIGH)

-- The command takes it, by either name.
SLASH_COMMANDS["/pbhud"]("style mura")
check("the command understands mura", addon:BarStyle(), "rounded")
SLASH_COMMANDS["/pbhud"]("style standard")
RunUpdates()
check("standard puts it away", plainBar:IsHidden(), true)

print("\n== 45. the effect the ability is, not the longest one it brings ==")
-- From a PS5: Templar's Power of the Light lasts 6 seconds and showed 20. One cast puts more
-- than one effect on the world -- the ability's own, and Major Breach for twenty seconds -- and
-- "the longest of that cast" is the wrong one of the two.
--
-- FancyActionBar+ does not guess: it reads GetAbilityDuration for the ability in the slot. With
-- that in hand the right effect is the one whose length is the ability's.
addon.timers:Forget_All()
addon.timers.timers = {}
addon.timers.counts = {}
SetSlot(HOTBAR_CATEGORY_PRIMARY, 5, { name = "Power of the Light", icon = "potl.dds", id = 103003, remaining = 0, duration = 0 })
SetAbilityDuration(103003, 6000)
FireHud(SCENE_FRAGMENT_SHOWN)

local now12 = GetGameTimeMilliseconds()
FireCast(5)
-- Both arrive, the long one first.
FireEffect(EFFECT_RESULT_GAINED, "Major Breach", "", (now12 + 20000) / 1000, 71, 61743)
FireEffect(EFFECT_RESULT_GAINED, "Power of the Light", "", (now12 + 6000) / 1000, 71, 103003)
RunUpdates()
local potl = addon.timers.labels[5].timer
check("six seconds, not twenty", potl:GetText(), "6.0")
-- ... and the other way round, in case the game sends them in the other order.
addon.timers:Forget_All()
local now13 = GetGameTimeMilliseconds()
FireCast(5)
FireEffect(EFFECT_RESULT_GAINED, "Power of the Light", "", (now13 + 6000) / 1000, 71, 103003)
FireEffect(EFFECT_RESULT_GAINED, "Major Breach", "", (now13 + 20000) / 1000, 71, 61743)
RunUpdates()
check("whichever order they arrive in", potl:GetText(), "6.0")

-- An ability the game gives no duration for falls back to the longest, which is all there is.
addon.timers:Forget_All()
SetSlot(HOTBAR_CATEGORY_PRIMARY, 6, { name = "Mystery", icon = "mystery.dds", id = 104004, remaining = 0, duration = 0 })
local now14 = GetGameTimeMilliseconds()
FireCast(6)
FireEffect(EFFECT_RESULT_GAINED, "Short Thing", "player", (now14 + 4000) / 1000, 1, 1041)
FireEffect(EFFECT_RESULT_GAINED, "Long Thing", "player", (now14 + 18000) / 1000, 1, 1042)
RunUpdates()
check("with nothing to compare against, the longest still wins", addon.timers.labels[6].timer:GetText(), "18")

print("\n== 46. targets the game reports without a unit id ==")
-- Some area effects report no unit id at all. Keyed by the unit tag alone, every target
-- collapsed onto one key: a count of 1 however many were hit, and one fade clearing the lot.
-- The effect's own slot tells them apart, which is what FancyActionBar+ uses.
addon.timers:Forget_All()
addon.timers.counts = {}
addon.account.text.countFromOne = true
SetSlot(HOTBAR_CATEGORY_PRIMARY, 4, { name = "Caltrops", icon = "caltrops.dds", id = 140, remaining = 0, duration = 0 })
SetAbilityDuration(140, 20000)
local now15 = GetGameTimeMilliseconds()
FireCast(4)
FireEffect(EFFECT_RESULT_GAINED, "Caltrops", "", (now15 + 20000) / 1000, 0, 141, nil, 11)
FireEffect(EFFECT_RESULT_GAINED, "Caltrops", "", (now15 + 20000) / 1000, 0, 141, nil, 12)
FireEffect(EFFECT_RESULT_GAINED, "Caltrops", "", (now15 + 20000) / 1000, 0, 141, nil, 13)
RunUpdates()
check("three targets, not one", addon.timers.labels[4].count:GetText(), "3")
AdvanceFrame(1000)
FireEffect(EFFECT_RESULT_FADED, "Caltrops", "", (now15 + 20000) / 1000, 0, 141, nil, 12)
RunUpdates()
check("and one fade takes one of them", addon.timers.labels[4].count:GetText(), "2")

print("\n== 47. MURA-HIGE Style draws a bar at the size it is given ==")
-- Every other style scales the game's own bar, because the width of those controls is the
-- game's to write. This one draws the bar itself, so it can simply be told how big to be.
-- The world as the previous sections left it: the overlays are already built, which is the
-- point -- a style change must not need them rebuilt.
addon:Account().bars.stamina.width, addon:Account().bars.stamina.height = nil, nil
addon:Account().bars.health.width, addon:Account().bars.health.height = nil, nil
FireHud(SCENE_FRAGMENT_SHOWN)
SetPower(COMBAT_MECHANIC_FLAGS_STAMINA, 500, 1000)
SetPower(COMBAT_MECHANIC_FLAGS_HEALTH, 1000, 1000)

Row(GetString(SI_PBSCHC_STYLE)).setFunction(nil, nil, { data = "rounded" })
RunUpdates()
local stamina = addon.plain.overlays["ZO_PlayerAttributeStaminaBar"]
-- Choosing the style is enough: the bar is drawn at a size straight away, the game's own size
-- until one is set. Until 1.10.2 nothing happened until a slider was moved.
check("the style alone puts it at a size", stamina.sizedWidth, addon.GAME_BAR_WIDTH)
check("and the game's own fill goes at once", stamina.bar.gradient[4], 0)

Row(GetString(SI_PBSCHC_BAR_WIDTH):gsub("<<1>>", GetString(SI_PBSCHC_BAR_STAMINA))).setFunction(300)
Row(GetString(SI_PBSCHC_BAR_HEIGHT):gsub("<<1>>", GetString(SI_PBSCHC_BAR_STAMINA))).setFunction(8)
RunUpdates()
check("the bar is the width it was given", stamina.control.width, 300)
check("and the height", stamina.control.height, 8)
check("held by the edge it fills from", stamina.control.anchors[1].point, LEFT)
check("half full is half of that width", stamina.fill:GetWidth(), 150)
-- The game's own fill would show round a bar narrower than its own, so it is taken to nothing --
-- without hiding the control, which is where the damage shield overlay lives.
check("the game's fill is blanked", stamina.bar.gradient[4], 0)
check("and its gloss hidden", stamina.bar:GetNamedChild("Gloss"):IsHidden(), true)

-- The health bar is two halves that meet in the middle: each is half of what was asked for.
Row(GetString(SI_PBSCHC_BAR_WIDTH):gsub("<<1>>", GetString(SI_PBSCHC_BAR_HEALTH))).setFunction(400)
RunUpdates()
check("each half of the health bar is half the width",
	addon.plain.overlays["ZO_PlayerAttributeHealthBarLeft"].control.width, 200)

-- Back to a style that scales, and the game's bar is handed back as it was.
Row(GetString(SI_PBSCHC_STYLE)).setFunction(nil, nil, { data = "plain" })
RunUpdates()
check("the game's colours are put back", stamina.bar.gradient[4], 1)
check("and its gloss with them", stamina.bar:GetNamedChild("Gloss"):IsHidden(), false)
check("the size is ignored by the other styles", stamina.sizedWidth, nil)
Row(GetString(SI_PBSCHC_STYLE)).setFunction(nil, nil, { data = "standard" })
RunUpdates()

-- The command sets both at once, and the style answers to its name.
SLASH_COMMANDS["/pbhud"]("size stamina 260 12")
local w, h = addon:BarSize(addon.barByKey.stamina)
check("the command sets the size", string.format("%dx%d", w, h), "260x12")
SLASH_COMMANDS["/pbhud"]("style mura")
check("and the style answers to MURA-HIGE", addon:BarStyle(), "rounded")
SLASH_COMMANDS["/pbhud"]("style standard")

print("\n== 48. the preview's row is the row, not the whole bar ==")
-- From a PS5: the other weapon set's outline in the settings panel looked far too wide. It was
-- drawn at the bar's full width -- and the bar's control is 606 wide while the buttons occupy
-- rather less of it, with the invisible weapon swap marker holding the left-hand end.
addon:Account().skillBar = true
addon:Account().enabled = true
addon:ResetSpacing()
BuildAttributeBars()
SetAllSlots()
addon:CaptureAll()

local from, to = addon:ButtonSpan()
check("the buttons' span is measured", from ~= nil, true)
-- The marker holds 61 + its own 45 of the bar's left-hand end, and the quickslot sits 5 to the
-- left of it, so the row starts a good way in but not at the very edge.
-- The marker holds 61 of the bar's left-hand end and is 45 wide, and the first ability is 10
-- past it: the row starts a fifth of the way in, not at the edge.
check("it starts at the first ability", string.format("%.3f", from), string.format("%.3f", (61 + 45 + 10) / 606))
check("and ends with the ultimate", to > from, true)
check("and it is not the whole bar", to - from < 1, true)

-- The fraction holds whatever size the bar is set to, because both numbers scale together.
Row(GetString(SI_PBSCHC_SCALE):gsub("<<1>>", GetString(SI_PBSCHC_BAR_SKILLBAR))).setFunction(70)
local from2, to2 = addon:ButtonSpan()
check("scaling the bar does not move the fraction", string.format("%.3f", from2), string.format("%.3f", from))
check("nor the far end", string.format("%.3f", to2), string.format("%.3f", to))
Row(GetString(SI_PBSCHC_SCALE):gsub("<<1>>", GetString(SI_PBSCHC_BAR_SKILLBAR))).setFunction(100)

-- Closing the gaps brings the far end in.
Row(GetString(SI_PBSCHC_GAP_ULTIMATE)).setFunction(4)
local _, to3 = addon:ButtonSpan()
check("closing a gap shortens the row", to3 < to, true)
Row(GetString(SI_PBSCHC_GAP_ULTIMATE)).setFunction(65)

-- The quickslot has no row above it, so it is not part of the span.
check("the quickslot is not counted in", from > 0, true)

print("\n== 50. an install that had kept the game's frame ==")
-- 1.9.x offered to leave the arrow frame in place. It is always put away now, and the key goes
-- with it rather than sitting in the saved variables for ever.
SavedStore.PBsConsoleHudCustomizer_Data = { style = "plain", plainKeepFrame = true }
addon.account = ZO_SavedVars:NewAccountWide("PBsConsoleHudCustomizer_Data", 1, nil, addon.accountDefaults)
addon:Account()
check("the old key is cleared away", addon.account.plainKeepFrame, nil)
check("and the outline is on, which is the frame now", addon:PlainBorder(), true)

print("\n== 51. the size rows and the scale row take turns ==")
-- A bar drawn at a width and a height has no use for a percentage as well, and a panel that
-- offers both invites the two to fight.
local staminaScale = Row(GetString(SI_PBSCHC_SCALE):gsub("<<1>>", GetString(SI_PBSCHC_BAR_STAMINA)))
local staminaWidth = Row(GetString(SI_PBSCHC_BAR_WIDTH):gsub("<<1>>", GetString(SI_PBSCHC_BAR_STAMINA)))
local skillScale = Row(GetString(SI_PBSCHC_SCALE):gsub("<<1>>", GetString(SI_PBSCHC_BAR_SKILLBAR)))

Row(GetString(SI_PBSCHC_STYLE)).setFunction(nil, nil, { data = "plain" })
check("square: the percentage is live", Panel:IsDisabled(staminaScale), false)
check("and the pixels are not", Panel:IsDisabled(staminaWidth), true)

Row(GetString(SI_PBSCHC_STYLE)).setFunction(nil, nil, { data = "rounded" })
check("MURA-HIGE: the pixels are live", Panel:IsDisabled(staminaWidth), false)
check("and the percentage is not", Panel:IsDisabled(staminaScale), true)
check("the skill bar is scaled whatever the bars are doing", Panel:IsDisabled(skillScale), false)
check("and the panel is told to re-read them", Panel.updates > 0, true)

Row(GetString(SI_PBSCHC_STYLE)).setFunction(nil, nil, { data = "standard" })
check("standard: back to the percentage", Panel:IsDisabled(staminaScale), false)

print("\n== 52. what counts as a target ==")
-- Compared against FancyActionBar+, which draws the same line: an effect on yourself is not a
-- target count, and neither is one on something of yours. An enemy is, including the ones the
-- client reports with no unit tag at all, which is most of them.
addon.timers:Forget_All()
addon.timers.counts = {}
addon.account.text.countFromOne = true
SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Rally", icon = "rally.dds", id = 190, remaining = 0, duration = 0 })
SetAbilityDuration(190, 30000)
FireHud(SCENE_FRAGMENT_SHOWN)
local now16 = GetGameTimeMilliseconds()
FireCast(3)
FireEffect(EFFECT_RESULT_GAINED, "Rally", "player", (now16 + 30000) / 1000, 1, 191)
RunUpdates()
local rallyTimer, rallyCount = addon.timers.labels[3].timer, addon.timers.labels[3].count
check("the buff on yourself is counted down", rallyTimer:GetText(), "30")
check("and carries no target count", rallyCount:IsHidden(), true)

-- Something of yours is not a target either.
FireEffectFrom(COMBAT_UNIT_TYPE_PLAYER, EFFECT_RESULT_GAINED, "Rally", "playerpet1", (now16 + 30000) / 1000, 2, 191)
RunUpdates()
check("nor is a pet of yours", rallyCount:IsHidden(), true)

-- An enemy is, tag or no tag.
FireEffect(EFFECT_RESULT_GAINED, "Rally", "reticleover", (now16 + 30000) / 1000, 3, 191)
FireEffect(EFFECT_RESULT_GAINED, "Rally", "", (now16 + 30000) / 1000, 4, 191)
RunUpdates()
check("two enemies are", rallyCount:GetText(), "2")

print("\n== 53. the countdown stays tied to the cast across targets ==")
-- Two things FancyActionBar+ does that this did not.
--
-- One: it starts counting at the cast, from the ability's own length, rather than waiting for an
-- effect the client may never report (config.lua's onAbilityUsed entries; main.lua sets
-- effect.endTime = duration + t). It has a list of the abilities that need it; with no list
-- here, any ability that declares a length gets it, and the first effect of the cast takes over.
addon.timers:Forget_All()
addon.timers.timers = {}
addon.timers.counts = {}
SetSlot(HOTBAR_CATEGORY_PRIMARY, 4, { name = "Ritual", icon = "ritual.dds", id = 220, remaining = 0, duration = 0 })
SetAbilityDuration(220, 16000)
FireHud(SCENE_FRAGMENT_SHOWN)
FireCast(4)
RunUpdates()
local ritual = addon.timers.labels[4].timer
check("counting from the moment it is cast", ritual:GetText(), "16")
check("even though the client reports nothing for the slot",
	GetActionSlotEffectTimeRemaining(4, HOTBAR_CATEGORY_PRIMARY), 0)
AdvanceFrame(4000)
RunUpdates()
check("and counting down", ritual:GetText(), "12")

-- The real effect, when it comes, is what is followed: the game's number beats the tooltip's.
local now17 = GetGameTimeMilliseconds()
FireCast(4)
FireEffect(EFFECT_RESULT_GAINED, "Ritual", "", (now17 + 20000) / 1000, 41, 221)
RunUpdates()
check("the effect takes over from the tooltip", ritual:GetText(), "20")

-- Later targets affect the count, but must not move the skill countdown origin.
AdvanceFrame(10000)
local now18 = GetGameTimeMilliseconds()
FireEffect(EFFECT_RESULT_GAINED, "Ritual", "", (now18 + 20000) / 1000, 42, 221)
RunUpdates()
check("a later target does not restart the countdown", ritual:GetText(), "10")
-- And a shorter one does not pull it in.
FireEffect(EFFECT_RESULT_GAINED, "Ritual", "", (now18 + 3000) / 1000, 43, 221)
RunUpdates()
check("a shorter one does not pull it in", ritual:GetText(), "10")
check("all three are counted as targets", addon.timers.labels[4].count:GetText(), "3")

print("\n== 54. a ten-second ability that also puts a six-second effect out ==")
-- From a PS5: Templar's Blinding Flashes lasts 10 seconds and the bar read 6. One cast, two
-- effects again -- but this time the ability's own is the one the client does not report, and
-- the shorter one was followed because it was the only candidate there was.
--
-- The game's own length for the ability is the reference. An effect is followed only if it is
-- about that long; otherwise what stands is the length from the tooltip, counted from the cast.
addon.timers:Forget_All()
addon.timers.timers = {}
addon.timers.counts = {}
addon.timers.mismatched = 0
SetSlot(HOTBAR_CATEGORY_PRIMARY, 6, { name = "Blinding Flashes", icon = "blind.dds", id = 230, remaining = 0, duration = 0 })
SetAbilityDuration(230, 10000)
FireHud(SCENE_FRAGMENT_SHOWN)
local now19 = GetGameTimeMilliseconds()
FireCast(6)
FireEffect(EFFECT_RESULT_GAINED, "Blinding Flashes", "", (now19 + 6000) / 1000, 51, 231)
RunUpdates()
local blind = addon.timers.labels[6].timer
check("the ten seconds the game gives it", blind:GetText(), "10")
check("and the six-second effect was refused", addon.timers.mismatched >= 1, true)

-- An effect that *is* about the ability's length is followed, and its real end is what counts.
addon.timers:Forget_All()
AdvanceFrame(11000)
local now20 = GetGameTimeMilliseconds()
FireCast(6)
FireEffect(EFFECT_RESULT_GAINED, "Blinding Flashes", "", (now20 + 11000) / 1000, 52, 231)
RunUpdates()
check("a matching effect is followed, at its own end", blind:GetText(), "11")

-- Power of the Light is the same rule the other way round: 6 seconds declared, and the 20-second
-- Major Breach it also applies is refused rather than followed.
addon.timers:Forget_All()
SetSlot(HOTBAR_CATEGORY_PRIMARY, 5, { name = "Power of the Light", icon = "potl.dds", id = 103003, remaining = 0, duration = 0 })
SetAbilityDuration(103003, 6000)
local now21 = GetGameTimeMilliseconds()
FireCast(5)
FireEffect(EFFECT_RESULT_GAINED, "Major Breach", "", (now21 + 20000) / 1000, 53, 61743)
FireEffect(EFFECT_RESULT_GAINED, "Power of the Light", "", (now21 + 6000) / 1000, 53, 103003)
RunUpdates()
check("still six, not twenty", addon.timers.labels[5].timer:GetText(), "6.0")

-- ---------------------------------------------------------------------------------------
-- The trace
--
-- It is a measuring instrument, so what is tested is that it measures: that it is silent until
-- asked, that it registers only events this client really has -- the mistake that cost 1.12.0 --
-- and that a press, a placement and the effect that follows come back in the order they arrived.
-- ---------------------------------------------------------------------------------------
print("\n== 20. the trace ==")
local trace = addon.trace
check("off until asked", trace.running ~= true, true)
check("and it has registered nothing", handlers[EVENT_ENTER_GROUND_TARGET_MODE] == nil, true)

trace:Command("quiet")
trace:Command("on")
check("on", trace.running, true)
check("both ground events this client has", trace.groundEvents, 2)
check("LEAVE is not one of them", EVENT_LEAVE_GROUND_TARGET_MODE, nil)
check("and the aiming poll is running", trace.polling, true)

-- A ground-targeted ability, as the player casts it: press, circle up, place, effect.
SetSlot(HOTBAR_CATEGORY_PRIMARY, 4, { name = "Caltrops", icon = "caltrops.dds", id = 40252, remaining = 0, duration = 0 })
SetAbilityDuration(40252, 18000)
FireCast(4)
FireGround("enter")
SetGroundTargeting(true)
RunUpdates()
AdvanceFrame(1200)
SetGroundTargeting(false)
RunUpdates()
local placedAt = GetGameTimeMilliseconds()
FireCombat(ACTION_RESULT_EFFECT_GAINED, "Caltrops", 40252, "a bandit")
FireEffect(EFFECT_RESULT_GAINED, "Caltrops", "", (placedAt + 18000) / 1000, 90, 40252)
FireEffect(EFFECT_RESULT_GAINED, "Caltrops", "", (placedAt + 18000) / 1000, 91, 40252)

local kinds = {}
for index = 1, trace.count do
	local entry = trace.entries[(index - 1) % #trace.entries + 1]
	kinds[#kinds + 1] = entry.kind
end
check("press, circle up, circle gone, combat, effect", table.concat(kinds, ","), "press,ground,aiming,aiming,combat,effect")
check("the second target did not add a line", trace.count, 6)
check("the press wrote down what the game says it lasts", trace.entries[1].text:find("lasts 18.0s", 1, true) ~= nil, true)
check("the placement is timed from the press", trace.entries[4].ms >= 1200, true)

-- Nobody else's combat events, and nothing from an ability that was never pressed.
FireCombat(ACTION_RESULT_EFFECT_GAINED, "Someone else's hit", 99999, "a bandit")
FireEffect(EFFECT_RESULT_GAINED, "Minor Vitality", "", (placedAt + 10000) / 1000, 92, 88888)
check("an ability that was not pressed is ignored", trace.count, 6)

-- And it lets go: twelve seconds on, the same ability is somebody else's business again.
AdvanceFrame(13000)
FireEffect(EFFECT_RESULT_FADED, "Caltrops", "", 0, 90, 40252)
check("a press is followed for a while, not for ever", trace.count, 6)

trace:Command("off")
check("off again", trace.running, false)
check("and the registration is gone", handlers[EVENT_ENTER_GROUND_TARGET_MODE][addon.name .. "TraceEnter"], nil)
check("the lines are still readable", trace.count, 6)
trace:Command("clear")
check("until cleared", trace.count, 0)

-- The two buttons in the panel, which is how it is really used: a console player should not have
-- to type a slash command on an on-screen keyboard to measure something.
OpenPanel(Panel)
Row(GetString(SI_PBSCHC_TRACE_START)).clickHandler()
check("the panel's Start button starts it", trace.running, true)
FireCast(4)
check("and it is recording", trace.count >= 1, true)
Row(GetString(SI_PBSCHC_TRACE_SHOW)).clickHandler()
check("the Show button stops it", trace.running, false)
trace:Command("clear")

-- ---------------------------------------------------------------------------------------
-- Abilities that are aimed before they land
--
-- These replay what a PS5 really sent (FINDINGS 51): the press arrives with
-- IsPlayerGroundTargeting() already true, nothing at all marks the placement, and a cancel
-- comes with its own event. Nothing here is invented -- the times are the measured ones.
-- ---------------------------------------------------------------------------------------
print("\n== 21. aimed abilities ==")
local T = addon.timers
T:Forget_All()
T:ForgetLinks()
T.groundPending = nil
SetGroundTargeting(false)
RunUpdates()

-- Scalding Rune: the game says 22s, the effect that follows says 24s.
SetSlot(HOTBAR_CATEGORY_PRIMARY, 6, { name = "Scalding Rune", icon = "rune.dds", id = 40465, remaining = 0, duration = 0 })
SetAbilityDuration(40465, 22000)
local rune = T.labels[6].timer

-- The circle goes up, and the press is answered by "you are aiming".
SetGroundTargeting(true)
FireCast(6)
check("the press is held, not counted", T.groundHeld, 1)
AdvanceFrame(300)
RunUpdates()
check("and nothing is counting while the circle is up", rune:IsHidden(), true)

-- Placed: the circle goes down, and the effect arrives 180ms later, as it did on the PS5.
AdvanceFrame(320)
SetGroundTargeting(false)
RunUpdates()
AdvanceFrame(180)
local placed = GetGameTimeMilliseconds()
FireEffect(EFFECT_RESULT_GAINED, "Scalding Rune", "", (placed + 24000) / 1000, 70, 40465)
RunUpdates()
check("the effect is what counts, at its own length", rune:GetText(), "24")
check("and the circle is settled", T.groundPending, nil)

-- Held for three seconds: the old 1.5s window would have thrown this effect away.
T:Forget_All()
T:ForgetLinks()
AdvanceFrame(30000)
SetGroundTargeting(true)
FireCast(6)
AdvanceFrame(3000)
RunUpdates()
SetGroundTargeting(false)
RunUpdates()
local late = GetGameTimeMilliseconds()
FireEffect(EFFECT_RESULT_GAINED, "Scalding Rune", "", (late + 24000) / 1000, 71, 40465)
RunUpdates()
check("a circle held for three seconds still links its effect", rune:GetText(), "24")

-- An ability the game reports no effect for: the tooltip's length, counted from the placement
-- rather than from the press that raised the circle.
T:Forget_All()
T:ForgetLinks()
AdvanceFrame(30000)
SetGroundTargeting(true)
FireCast(6)
AdvanceFrame(4000)
RunUpdates()
SetGroundTargeting(false)
RunUpdates()
RunUpdates()
check("placed, so the fallback starts", T.groundPlaced >= 2, true)
check("and it counts from the placement, not the press", rune:GetText(), "22")

-- Cancelled: the ○ button drops the circle and casts what is bound to it. Nothing is counted
-- for the rune, and the other ability counts as it always did.
T:Forget_All()
T:ForgetLinks()
AdvanceFrame(30000)
SetGroundTargeting(true)
FireCast(6)
AdvanceFrame(500)
RunUpdates()
SetGroundTargeting(false)
Fire(EVENT_CANCEL_GROUND_TARGET_MODE)
check("a cancelled circle is dropped", T.groundCancelled, 1)
SetSlot(HOTBAR_CATEGORY_PRIMARY, 5, { name = "Obsidian Shard", icon = "shard.dds", id = 29071, remaining = 0, duration = 0 })
SetAbilityDuration(29071, 6000)
FireCast(5)
RunUpdates()
RunUpdates()
check("nothing is counted for the ability never cast", rune:IsHidden(), true)
check("and the ability that was cast counts as ever", addon.timers.labels[5].timer:GetText(), "6.0")

-- The failure of 1.12.0 and 1.12.1, as a test: a circle left up must never stop anything else.
T:Forget_All()
T:ForgetLinks()
AdvanceFrame(30000)
SetGroundTargeting(true)
FireCast(6)
AdvanceFrame(200)
RunUpdates()
SetGroundTargeting(false)
FireCast(5)
RunUpdates()
check("another ability counts while a circle is pending", addon.timers.labels[5].timer:GetText(), "6.0")
check("and the circle is forgotten by the press that followed", T.groundPending, nil)
SetGroundTargeting(false)

print("\n== 57. fixed cast origin and stale effects ==")
T:Forget_All()
ActiveHotbar = HOTBAR_CATEGORY_PRIMARY
SetSlot(HOTBAR_CATEGORY_PRIMARY, 4, { name = "Ritual", icon = "ritual.dds", id = 220, remaining = 0, duration = 0 })
SetAbilityDuration(220, 16000)
FireCast(4)
local castAt = GetFrameTimeMilliseconds()
AdvanceFrame(600)
local arrived = GetFrameTimeMilliseconds()
FireEffect(EFFECT_RESULT_GAINED, "Ritual", "player", (arrived + 16000) / 1000, 1, 220, "ritual.dds", nil, arrived / 1000)
check("delayed effect retains the player cast origin", T:SlotTimer(4, HOTBAR_CATEGORY_PRIMARY, arrived), 15400)
AdvanceFrame(16000)
SetSlot(HOTBAR_CATEGORY_PRIMARY, 4, { name = "Ritual", icon = "ritual.dds", id = 220, remaining = 16000, duration = 16000 })
check("client refresh cannot revive an expired cast", T:SlotTimer(4, HOTBAR_CATEGORY_PRIMARY, GetFrameTimeMilliseconds()), 0)
FireCast(4)
local recastAt = GetFrameTimeMilliseconds()
FireEffect(EFFECT_RESULT_UPDATED, "Old Ritual", "player", (recastAt + 15000) / 1000, 1, 220, "ritual.dds", nil, (recastAt - 1000) / 1000)
check("old effect cannot claim the new cast", T:LinkedEffect(4, HOTBAR_CATEGORY_PRIMARY, recastAt).key, nil)
SetSlot(HOTBAR_CATEGORY_BACKUP, 4, { name = "Ritual", icon = "ritual.dds", id = 220, remaining = 0, duration = 0 })
AdvanceFrame(3000)
ActiveHotbar = HOTBAR_CATEGORY_BACKUP
FireCast(4)
check("both slotted copies follow the latest cast", T:SlotTimer(4, HOTBAR_CATEGORY_PRIMARY, GetFrameTimeMilliseconds()), 16000)
ActiveHotbar = HOTBAR_CATEGORY_PRIMARY
T:Forget_All()
SetGroundTargeting(true)
FireCast(4)
local aimingAt = GetFrameTimeMilliseconds()
FireEffect(EFFECT_RESULT_GAINED, "Ritual", "player", (aimingAt + 16000) / 1000, 1, 220)
check("effect during aiming cannot confirm placement", T:LinkedEffect(4, HOTBAR_CATEGORY_PRIMARY, aimingAt), nil)
T:OnGroundCancel()
SetGroundTargeting(false)
FireEffect(EFFECT_RESULT_GAINED, "Ritual", "player", (aimingAt + 16000) / 1000, 1, 220)
check("effect after cancellation cannot confirm a cast", T:LinkedEffect(4, HOTBAR_CATEGORY_PRIMARY, aimingAt), nil)

print("\n== 58. interrupted icon animations and ultimate fit ==")
local gamepadMode = true
IsInGamepadPreferredMode = function() return gamepadMode end
local buttons = {}
for slot = 3, 8 do
	local control = _G["ActionButton" .. slot]
	buttons[slot] = { icon = control:GetNamedChild("Icon"),
		flipCard = MakeControl("TestFlip" .. slot, control, "control") }
end
ZO_ActionBar_GetButton = function(slot) return buttons[slot] end
local playing = true
buttons[3].iconBounceAnimation = { IsPlaying = function() return playing end }
buttons[3].icon:SetDimensions(75, 75)
buttons[8].icon:SetDimensions(74, 74)
buttons[8].flipCard:SetDimensions(61, 61)
addon.skillbar:RepairIcons()
check("live bounce retains its animated size", buttons[3].icon:GetWidth(), 75)
check("ultimate icon restored to meter's reference size", buttons[8].icon:GetWidth(), 67)
check("ultimate reference frame restored too", buttons[8].flipCard:GetWidth(), 67)
playing = false
RunUpdates()
check("interrupted bounce returns to normal size", buttons[3].icon:GetWidth(), 61)
local dimensionWrites = WriteCount("ActionButton3Icon", "dimensions")
RunUpdates()
check("settled icons are not rewritten every tick", WriteCount("ActionButton3Icon", "dimensions"), dimensionWrites)
buttons[3].hotbarSwapAnimation = { IsPlaying = function() return true end }
buttons[3].flipCard:SetDimensions(12, 61)
RunUpdates()
check("weapon swap size animation is preserved", buttons[3].flipCard:GetWidth(), 12)
gamepadMode = false
buttons[8].icon:SetDimensions(47, 47)
RunUpdates()
check("keyboard dimensions are untouched", buttons[8].icon:GetWidth(), 47)
gamepadMode = true
addon:SetSkillBarAllowed(false)
addon.skillbar:RepairIcons()
check("skill bar opt-out prevents icon repairs", buttons[8].icon:GetWidth(), 47)
addon:SetSkillBarAllowed(true)
_G.ActionButton3:SetHidden(true)
WeaponPairLocked = true
RunUpdates()
local persistentBack = T.back[3].control
check("back row stays shown while front slot hides", persistentBack:IsHidden(), false)
check("hidden front slot is not its parent", persistentBack:GetParent():GetName(), "ZO_ActionBar1")
_G.ActionButton3:SetHidden(false)
WeaponPairLocked = false

print("\n== 59. independent front/back sizes survive repeated weapon swaps ==")
-- Model the client's cached size-animation endpoints, including a style update
-- that captures an already shrunken FlipCard before the swap finishes.
local function SizeAnimation()
	return {
		SetStartAndEndWidth = function(self, a, b) self.startWidth, self.endWidth = a, b end,
		SetStartAndEndHeight = function(self, a, b) self.startHeight, self.endHeight = a, b end,
	}
end
local function SwapTimeline(size)
	local first, last = SizeAnimation(), SizeAnimation()
	first:SetStartAndEndWidth(size, size)
	first:SetStartAndEndHeight(size, 0)
	last:SetStartAndEndWidth(size, size)
	last:SetStartAndEndHeight(0, size)
	return {
		playing = false,
		IsPlaying = function(self) return self.playing end,
		GetFirstAnimation = function() return first end,
		GetLastAnimation = function() return last end,
	}
end
local function VisibleWidth(control)
	local width = control:GetWidth()
	while control and control ~= GuiRoot do
		width = width * control:GetScale()
		control = control:GetParent()
	end
	return width
end
T:HideAll()
-- Earlier harness sections rebuilt the game bar; reconnect existing mock controls.
for slot, entry in pairs(T.back) do
	entry.control.parent = _G.ZO_ActionBar1
	entry.button = _G["ActionButton" .. slot]
end
for slot = 3, 8 do
	buttons[slot].slot = _G["ActionButton" .. slot]
	buttons[slot].hotbarSwapAnimation = SwapTimeline(44)
end
for _, sizes in ipairs({ { 140, 65 }, { 60, 180 }, { 100, 70 } }) do
	addon:SetScalePercent(addon.actionBar, sizes[1])
	addon:SetBackBarScale(sizes[2])
	addon:Refresh()
	for swap = 1, 2 do
		ActiveHotbar = ActiveHotbar == HOTBAR_CATEGORY_PRIMARY and HOTBAR_CATEGORY_BACKUP or HOTBAR_CATEGORY_PRIMARY
		for _, slot in ipairs({ 3, 8 }) do
			local button = buttons[slot]
			local timeline = button.hotbarSwapAnimation
			timeline.playing = true
			-- A stale template/scale and cached endpoint must not persist as the
			-- final front size, even if dimensions alone already look correct.
			button.slot:SetScale(sizes[2] / 100)
			button.flipCard:SetScale(sizes[2] / 100)
			button.icon:SetScale(sizes[2] / 100)
			button.flipCard:SetDimensions(44, 0)
			timeline:GetLastAnimation():SetStartAndEndWidth(44, 44)
			timeline:GetLastAnimation():SetStartAndEndHeight(0, 44)
		end
		RunUpdates()
		check("swap keeps ownership of intermediate dimensions", buttons[3].flipCard:GetHeight(), 0)
		for _, slot in ipairs({ 3, 8 }) do
			local button = buttons[slot]
			local last = button.hotbarSwapAnimation:GetLastAnimation()
			button.flipCard:SetDimensions(last.endWidth, last.endHeight)
			button.icon:SetDimensions(last.endWidth, last.endHeight)
			button.hotbarSwapAnimation.playing = false
		end
		RunUpdates()
		for _, slot in ipairs({ 3, 8 }) do
			local size = slot == 8 and 67 or 61
			local button = buttons[slot]
			check("front uses its own scale after swap", addon.Round(VisibleWidth(button.icon) * 100), addon.Round(size * sizes[1]))
			check("front frame matches icon after swap", VisibleWidth(button.flipCard), VisibleWidth(button.icon))
			check("next swap restores the front size", button.hotbarSwapAnimation:GetLastAnimation().endHeight, size)
			check("back keeps its own scale after swap", T.back[slot].control:GetScale(), sizes[2] / 100)
			check("back icon dimensions never become front dimensions", T.back[slot].icon:GetWidth(), 44)
		end
	end
end
-- Recover scale alone, even with no custom front setting and no size change.
_G.ZO_ActionBar1:SetScale(0.7)
buttons[3].icon:SetScale(0.7)
RunUpdates()
check("default front scale is restored too", _G.ZO_ActionBar1:GetScale(), 1)
check("scale-only drift is repaired", buttons[3].icon:GetScale(), 1)
local lastSwap = buttons[3].hotbarSwapAnimation:GetLastAnimation()
local originalSetter = lastSwap.SetStartAndEndHeight
local endpointWrites = 0
lastSwap.SetStartAndEndHeight = function(self, a, b)
	endpointWrites = endpointWrites + 1
	originalSetter(self, a, b)
end
RunUpdates()
check("settled swap endpoints are not rewritten every tick", endpointWrites, 0)
-- Replacing a timeline must initialize its endpoint even without another swap.
buttons[3].hotbarSwapAnimation = SwapTimeline(44)
RunUpdates()
check("replacement timeline gets the front endpoint", buttons[3].hotbarSwapAnimation:GetLastAnimation().endHeight, 61)
FireHud(SCENE_FRAGMENT_HIDDEN)
buttons[3].icon:SetScale(0.65)
FireHud(SCENE_FRAGMENT_SHOWN)
check("returning to HUD repairs scale without reload", buttons[3].icon:GetScale(), 1)

print("\n== 60. channel duration and conservative effect association ==")
do
	T:Forget_All()
	ActiveHotbar = HOTBAR_CATEGORY_PRIMARY
	SetGroundTargeting(false)
	local savedCastInfo, savedDuration = GetAbilityCastInfo, GetAbilityDuration
	local castInfo = {}
	GetAbilityCastInfo = function(id)
		local info = castInfo[id] or { false, 0, 0 }
		return info[1], info[2], info[3]
	end
	local function Prepare(id, duration, channel, castMs, channelMs)
		T:Forget_All()
		SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Test Skill", icon = "testskill.dds", id = id, remaining = 20000, duration = 20000 })
		SetAbilityDuration(id, duration)
		castInfo[id] = { channel, castMs, channelMs }
		FireCast(3)
		return GetFrameTimeMilliseconds()
	end
	local function Effect(name, id, icon, duration)
		local now = GetFrameTimeMilliseconds()
		FireEffect(EFFECT_RESULT_GAINED, name, "player", (now + duration) / 1000, 1, id, icon, nil, now / 1000)
	end
	local function Remaining()
		return T:SlotTimer(3, HOTBAR_CATEGORY_PRIMARY, GetFrameTimeMilliseconds())
	end
	Prepare(800001, 0, true, 0, 3800)
	check("channel counts without an ordinary effect duration", Remaining(), 3800)
	Effect("Triggered Passive", 800099, "passive.dds", 20000)
	check("20-second passive cannot replace 3.8-second channel", Remaining(), 3800)
	Effect("Test Skill", 800001, "testskill.dds", 5000)
	check("channel remains authoritative even for matching effects", Remaining(), 3800)
	AdvanceFrame(1000)
	check("channel counts from the cast", Remaining(), 2800)
	AdvanceFrame(2800)
	check("expired channel cannot fall back to passive client timer", Remaining(), 0)
	Prepare(800002, 20000, true, 0, 3800)
	check("channel takes priority over nonzero effect duration", Remaining(), 3800)
	Prepare(800003, 0, true, 3800, 0)
	check("channel supports clients reporting time in second result", Remaining(), 3800)
	Prepare(800004, 20000, true, 0, 0)
	Effect("Test Skill", 800004, "testskill.dds", 20000)
	check("unknown channel time never substitutes a buff duration", Remaining(), 0)
	Prepare(800005, 10000, false, 1200, 0)
	check("ordinary cast time does not replace effect duration", Remaining(), 10000)
	Effect("Triggered Passive", 800099, "passive.dds", 10000)
	check("same-length unrelated passive has no association", T:LinkedEffect(3, HOTBAR_CATEGORY_PRIMARY, GetFrameTimeMilliseconds()).key, nil)
	Effect("Test Skill", 800005, "testskill.dds", 20000)
	check("wrong-length matching effect is rejected", Remaining(), 10000)
	Effect("Test Skill", 800005, "testskill.dds", 11000)
	check("matching ordinary effect can refine the duration", Remaining(), 11000)
	Prepare(800006, 0, false, 0, 0)
	Effect("Triggered Passive", 800099, "passive.dds", 20000)
	check("unknown duration does not pick the longest effect", Remaining(), 0)
	SetSlot(HOTBAR_CATEGORY_BACKUP, 3, { name = "Test Skill", icon = "testskill.dds", id = 800006, remaining = 20000, duration = 20000 })
	check("unidentified timer also stays hidden on the other bar", T:SlotTimer(3, HOTBAR_CATEGORY_BACKUP, GetFrameTimeMilliseconds()), 0)
	Effect("Renamed Effect", 800006, "different.dds", 6000)
	check("unknown duration can be resolved by ability ID", Remaining(), 6000)
	Prepare(800007, 0, false, 0, 0)
	Effect("Test Skill", 800099, "different.dds", 7000)
	check("unknown duration can be resolved by name", Remaining(), 7000)
	Prepare(800008, 0, false, 0, 0)
	Effect("Renamed Effect", 800099, "testskill.dds", 8000)
	check("unknown duration can be resolved by icon", Remaining(), 8000)
	Effect("Another Effect", 800098, "testskill.dds", 20000)
	check("a longer equally weak match does not win", Remaining(), 8000)
	GetAbilityDuration = nil
	Prepare(800009, 0, true, 0, 3800)
	check("channel API works independently of duration API", Remaining(), 3800)
	GetAbilityDuration = savedDuration
	GetAbilityCastInfo = function() error("not available") end
	SetAbilityDuration(800009, 9000)
	check("cast-info failure still permits ordinary duration", T:AbilityDuration(3, HOTBAR_CATEGORY_PRIMARY), 9000)
	GetAbilityCastInfo = nil
	check("absent cast-info API still permits ordinary duration", T:AbilityDuration(3, HOTBAR_CATEGORY_PRIMARY), 9000)
	GetAbilityCastInfo = savedCastInfo
end

print("\n== 61. countdown and shade continue through the final second ==")
do
	T:Forget_All()
	ActiveHotbar = HOTBAR_CATEGORY_PRIMARY
	addon:Text().decimals = true
	for _, hotbar in ipairs({ HOTBAR_CATEGORY_PRIMARY, HOTBAR_CATEGORY_BACKUP }) do
		SetSlot(hotbar, 3, { name = "Final Second", icon = "finalsecond.dds", id = 810001, remaining = 0, duration = 0 })
	end
	SetAbilityDuration(810001, 3800)
	FireCast(3)
	RunUpdates()
	local front, back = T.labels[3].timer, T.back[3].timer
	AdvanceFrame(2800)
	for _, sample in ipairs({ { 0, "1.0" }, { 100, "0.9" }, { 500, "0.4" }, { 300, "0.1" } }) do
		AdvanceFrame(sample[1])
		RunUpdates()
		check("front shows the final second", front:GetText(), sample[2])
		check("front remains visible until expiry", front:IsHidden(), false)
		check("back shows the final second", back:GetText(), sample[2])
		check("back remains visible until expiry", back:IsHidden(), false)
		check("front shade continues until expiry", T.shades[3].control:IsHidden(), false)
		check("back shade continues until expiry", T.back[3].shade:IsHidden(), false)
	end
	addon:Text().decimals = false
	RunUpdates()
	check("integer setting still keeps final second visible", front:IsHidden(), false)
	check("integer rounding is preserved", front:GetText(), "0")
	addon:Text().decimals = true
	AdvanceFrame(100)
	RunUpdates()
	check("front hides at zero", front:IsHidden(), true)
	check("back hides at zero", back:IsHidden(), true)
	check("front shade hides at zero", T.shades[3].control:IsHidden(), true)
	check("back shade hides at zero", T.back[3].shade:IsHidden(), true)
	T:Forget_All()
	T.timers = {}
	for _, hotbar in ipairs({ HOTBAR_CATEGORY_PRIMARY, HOTBAR_CATEGORY_BACKUP }) do
		SetSlot(hotbar, 3, { name = "Final Second", icon = "finalsecond.dds", id = 810001, remaining = 100, duration = 3800 })
	end
	RunUpdates()
	check("client fallback also shows final tenths on front", front:GetText(), "0.1")
	check("client fallback also shows final tenths on back", back:GetText(), "0.1")
	check("client fallback is visible under a second", front:IsHidden(), false)
	SetSlot(HOTBAR_CATEGORY_PRIMARY, 3, { name = "Final Second", icon = "finalsecond.dds", id = 810001, remaining = -1, duration = 3800 })
	RunUpdates()
	check("negative remaining time is hidden", front:IsHidden(), true)
end

print("\n== 62. only equipped Oakensoul overrides back-row visibility ==")
do
	local savedInfo, savedBag = GetItemInfo, BAG_WORN
	local savedRing1, savedRing2 = EQUIP_SLOT_RING1, EQUIP_SLOT_RING2
	BAG_WORN, EQUIP_SLOT_RING1, EQUIP_SLOT_RING2 = "worn", "ring1", "ring2"
	local worn = {}
	GetItemInfo = function(bag, slot)
		assert(bag == BAG_WORN, "must only inspect equipped items")
		return worn[slot] or ""
	end
	addon:BackBar().enabled = true
	ActiveHotbar = HOTBAR_CATEGORY_PRIMARY
	WeaponPairLocked = true
	RunUpdates()
	check("temporary swap lock does not hide back row", T.back[3].control:IsHidden(), false)
	for _, ring in ipairs({ EQUIP_SLOT_RING1, EQUIP_SLOT_RING2 }) do
		worn[ring] = "/esoui/art/icons/u34_mythic_oakensoul_ring.dds"
		RunUpdates()
		check("Oakensoul in either worn slot is detected", addon:OakensoulEquipped(), true)
		check("Oakensoul hides the back ability", T.back[3].control:IsHidden(), true)
		check("Oakensoul hides the back ultimate", T.back[8].control:IsHidden(), true)
		check("equipping the ring preserves the saved setting", addon:BackBar().enabled, true)
		worn[ring] = nil
		RunUpdates()
		check("removing the ring restores back row without reload", T.back[3].control:IsHidden(), false)
	end
	worn[EQUIP_SLOT_RING1] = "ESOUI/ART/ICONS/U34_MYTHIC_OAKENSOUL_RING.DDS"
	check("icon normalization handles case and leading slash", addon:OakensoulEquipped(), true)
	addon:BackBar().enabled = false
	worn[EQUIP_SLOT_RING1] = nil
	RunUpdates()
	check("removing ring respects disabled display setting", T.back[3].control:IsHidden(), true)
	addon:BackBar().enabled = true
	worn[EQUIP_SLOT_RING1] = "/esoui/art/icons/another_ring.dds"
	check("other rings do not trigger the exception", addon:OakensoulEquipped(), false)
	GetItemInfo = function() error("unavailable") end
	check("unavailable equipment data does not hide row", addon:BackBarEnabled(), true)
	GetItemInfo = nil
	check("missing equipment API does not hide row", addon:BackBarEnabled(), true)
	GetItemInfo, BAG_WORN = savedInfo, savedBag
	EQUIP_SLOT_RING1, EQUIP_SLOT_RING2 = savedRing1, savedRing2
	WeaponPairLocked = false
end

print("\n== MURA-HIGE NEO fills every resource to the right ==")
do
	addon:Account().enabled = true
	Row(GetString(SI_PBSCHC_STYLE)).setFunction(nil, nil, { data = "neo" })
	check("NEO style is selectable", addon:BarStyle(), "neo")
	check("NEO has its requested display name", GetString(SI_PBSCHC_STYLE_NEO), "MURA-HIGE NEO Style")
	check("NEO enables width and height controls", addon:BarsAreMuraHige(), true)
	for _, key in ipairs({ "health", "magicka", "stamina" }) do
		addon:SetBarSize(addon.barByKey[key], "width", 400)
		addon:SetBarSize(addon.barByKey[key], "height", 20)
	end
	FireHud(SCENE_FRAGMENT_SHOWN)
	local powers = { COMBAT_MECHANIC_FLAGS_HEALTH, COMBAT_MECHANIC_FLAGS_MAGICKA, COMBAT_MECHANIC_FLAGS_STAMINA }
	local names = { "ZO_PlayerAttributeHealthBarLeft", "ZO_PlayerAttributeMagickaBar", "ZO_PlayerAttributeStaminaBar" }
	for _, amount in ipairs({ 0, 250, 500, 1000, 250 }) do
		for _, power in ipairs(powers) do SetPower(power, amount, 1000) end
		RunUpdates()
		for _, name in ipairs(names) do
			local overlay = addon.plain.overlays[name]
			check("NEO uses the full configured width", overlay.control:GetWidth(), 400)
			check("NEO uses the configured height", overlay.control:GetHeight(), 20)
			check("empty resource hides only its fill", overlay.fill:IsHidden(), amount == 0)
			check("resource track stays visible", overlay.control:IsHidden(), false)
			if amount > 0 then
				check("NEO filled length matches resource fraction", overlay.fill:GetWidth(), amount * 0.4)
				check("NEO fill begins at the left edge", overlay.fill.anchors[1].point, TOPLEFT)
			end
		end
		check("NEO health has no duplicate right-half overlay", addon.plain.overlays.ZO_PlayerAttributeHealthBarRight.control:IsHidden(), true)
	end
	local left = addon.plain.overlays.ZO_PlayerAttributeHealthBarLeft
	check("NEO health remains centered on native midpoint", left.control.anchors[1].point, CENTER)
	check("NEO midpoint is the native left half's right edge", left.control.anchors[1].relativePoint, RIGHT)
	addon:SetBarStyle("rounded")
	addon:Refresh()
	check("original MURA health returns to two half-width bars", left.control:GetWidth(), 200)
	check("original MURA health left half fills leftward", left.fill.anchors[1].point, TOPRIGHT)
	check("original MURA health right half returns", addon.plain.overlays.ZO_PlayerAttributeHealthBarRight.control:IsHidden(), false)
	check("original MURA magicka fills leftward", addon.plain.overlays.ZO_PlayerAttributeMagickaBar.fill.anchors[1].point, TOPRIGHT)
	SLASH_COMMANDS["/pbhud"]("style neo")
	check("NEO is available through slash command", addon:BarStyle(), "neo")
	addon:SetBarStyle("standard")
	addon:Refresh()
	check("standard hides NEO overlays", left.control:IsHidden(), true)
	check("standard restores native frame", _G.ZO_PlayerAttributeMagickaFrameLeft:IsHidden(), false)
end

print("\n== resource outline colour choices ==")
do
	local row = Row(GetString(SI_PBSCHC_BORDER_COLOUR))
	check("six outline colour choices", #row.items, 6)
	addon:Account().plainBorderColour = nil
	check("existing settings keep the black outline", addon:PlainBorderColour(), "black")
	for _, item in ipairs(row.items) do
		row.setFunction(nil, item.name, item)
		check("colour selection is persisted", addon:Account().plainBorderColour, item.data)
		check("dropdown reports selected colour", row.getFunction(), item.name)
	end
	addon:SetPlainBorderColour("gold")
	addon:SetPlainBorder(true)
	addon:SetPlainOpacity(50)
	for _, style in ipairs({ "plain", "rounded", "neo" }) do
		addon:SetBarStyle(style)
		addon:Refresh()
		for _, name in ipairs({ "ZO_PlayerAttributeHealthBarLeft", "ZO_PlayerAttributeMagickaBar", "ZO_PlayerAttributeStaminaBar" }) do
			for _, piece in pairs(addon.plain.overlays[name].border) do
				check("gold is applied to each border edge", table.concat(piece.centerColor, ","), "1,0.84,0,0.41")
				check("selected outline remains visible", piece:IsHidden(), false)
			end
		end
	end
	addon:SetPlainBorder(false)
	addon:SetPlainBorderColour("white")
	addon:Refresh()
	local edge = addon.plain.overlays.ZO_PlayerAttributeStaminaBar.border.Top
	check("colour changes do not enable disabled outlines", edge:IsHidden(), true)
	addon:SetPlainBorder(true)
	addon:Refresh()
	check("reenabling outline uses the selected colour", table.concat(edge.centerColor, ","), "1,1,1,0.41")
	addon:Account().plainBorderColour = "unknown"
	check("invalid saved colour falls back safely", addon:PlainBorderColour(), "black")
	addon:SetPlainBorderColour("gold")
	check("invalid selection is rejected", addon:SetPlainBorderColour("unknown"), false)
	check("invalid selection preserves the saved colour", addon:PlainBorderColour(), "gold")
	addon:SetBarStyle("standard")
	addon:Refresh()
	check("standard still hides custom outlines", addon.plain.overlays.ZO_PlayerAttributeStaminaBar.control:IsHidden(), true)
end

print("\n== MURA gradients are bright at top and dark at bottom ==")
do
	addon:SetPlainOpacity(50)
	for _, style in ipairs({ "rounded", "neo" }) do
		addon:SetBarStyle(style)
		addon:Refresh()
		for _, overlay in pairs(addon.plain.overlays) do
			local vertices = overlay.fill.vertices
			local top, bottom = vertices[VERTEX_POINTS_TOPLEFT], vertices[VERTEX_POINTS_BOTTOMLEFT]
			for channel = 1, 3 do
				check("top is brighter than bottom", top[channel] > bottom[channel], true)
			end
			check("top edge is uniform", table.concat(top, ","), table.concat(vertices[VERTEX_POINTS_TOPRIGHT], ","))
			check("bottom edge is uniform", table.concat(bottom, ","), table.concat(vertices[VERTEX_POINTS_BOTTOMRIGHT], ","))
			check("top preserves opacity", top[4], 0.5)
			check("bottom preserves opacity", bottom[4], 0.5)
		end
	end
	addon:SetBarStyle("plain")
	addon:Refresh()
	for _, overlay in pairs(addon.plain.overlays) do
		check("Square returns to solid fill", table.concat(overlay.fill.vertices[1], ","), table.concat(overlay.fill.vertices[4], ","))
	end
end

print("\n== MURA resource text alignment ==")
do
	addon:SetBarStyle("standard")
	addon:Refresh()
	addon:Account().resourceTextAlignment = nil
	check("existing settings default to left", addon:ResourceTextAlignment(), "left")
	local row = Row(GetString(SI_PBSCHC_RESOURCE_ALIGN))
	check("three text alignment choices", #row.items, 3)
	check("alignment setting disabled for standard", row.disable(), true)
	for _, bar in ipairs(addon.plain.bars) do
		local label = _G[bar.container .. "ResourceNumbers"]
		label:ClearAnchors()
		label:SetAnchor(CENTER, _G[bar.container], CENTER, 7, 2)
		label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
		label:SetText("250 / 1000")
		label:SetHidden(true)
	end
	for _, style in ipairs({ "rounded", "neo" }) do
		addon:SetBarStyle(style)
		addon:Refresh()
		check("alignment setting enabled for MURA", row.disable(), false)
		for _, item in ipairs(row.items) do
			row.setFunction(nil, item.name, item)
			local alignment = item.data == "left" and TEXT_ALIGN_LEFT or item.data == "right" and TEXT_ALIGN_RIGHT or TEXT_ALIGN_CENTER
			check("alignment choice is saved", addon:Account().resourceTextAlignment, item.data)
			for _, bar in ipairs(addon.plain.bars) do
				local label = _G[bar.container .. "ResourceNumbers"]
				local first = addon.plain.overlays[bar.controls[1].name].control
				local last = style == "neo" and first or addon.plain.overlays[bar.controls[#bar.controls].name].control
				check("selected alignment applies to every resource", label:GetHorizontalAlignment(), alignment)
				check("text starts at drawn left edge", label.anchors[1].relativeTo, first)
				check("text ends at drawn right edge", label.anchors[2].relativeTo, last)
				check("game's number contents are preserved", label:GetText(), "250 / 1000")
				check("game's hidden-number preference is preserved", label:IsHidden(), true)
			end
		end
	end
	addon:SetBarStyle("plain")
	addon:Refresh()
	check("alignment setting disabled for Square", row.disable(), true)
	for _, bar in ipairs(addon.plain.bars) do
		local label = _G[bar.container .. "ResourceNumbers"]
		check("original horizontal alignment restored", label:GetHorizontalAlignment(), TEXT_ALIGN_CENTER)
		check("original anchor restored", label.anchors[1].relativeTo, _G[bar.container])
		check("original horizontal offset restored", label.anchors[1].offsetX, 7)
		check("second custom anchor removed", #label.anchors, 1)
	end
	addon:SetBarStyle("neo")
	addon:Refresh()
	addon:Account().enabled = false
	addon:Refresh()
	check("disabling addon restores text anchor", _G.ZO_PlayerAttributeHealthResourceNumbers.anchors[1].offsetX, 7)
	addon:Account().enabled = true
	addon:Account().resourceTextAlignment = "invalid"
	check("invalid saved alignment defaults to left", addon:ResourceTextAlignment(), "left")
end

print("\n== Liquid retains native geometry and restores colours ==")
do
	addon:Account().enabled = true
	addon:SetBarStyle("standard")
	addon:Refresh()
	local originals = {}
	for _, bar in ipairs(addon.plain.bars) do
		for _, entry in ipairs(bar.controls) do
			local control = _G[entry.name]
			originals[control] = { width = control:GetWidth(), height = control:GetHeight(), anchors = WriteCount(entry.name, "anchor") }
		end
	end
	Row(GetString(SI_PBSCHC_STYLE)).setFunction(nil, nil, { data = "liquidflow" })
	check("Liquid style is selectable and persists", addon:BarStyle(), "liquidflow")
	check("Liquid uses standard scaling", addon:BarsAreMuraHige(), false)
	for _, bar in ipairs(addon.plain.bars) do
		check("Liquid retains the native frame", _G[bar.container .. "FrameLeft"]:IsHidden(), false)
		check("Liquid retains the native background", _G[bar.container .. "BgContainer"]:IsHidden(), false)
		for _, entry in ipairs(bar.controls) do
			local control = _G[entry.name]
			check("Liquid leaves native width unchanged", control:GetWidth(), originals[control].width)
			check("Liquid leaves native height unchanged", control:GetHeight(), originals[control].height)
			check("Liquid does not reanchor native fills", WriteCount(entry.name, "anchor"), originals[control].anchors)
			check("Liquid leaves native gloss visible", control:GetNamedChild("Gloss"):IsHidden(), false)
			check("Liquid does not draw rectangular overlays", addon.plain.overlays[entry.name].control:IsHidden(), true)
			check("Liquid colours the existing fill", #control.gradient, 8)
		end
	end
	local control = _G.ZO_PlayerAttributeMagickaBar
	local firstColour = table.concat(control.gradient, ",")
	AdvanceFrame(700)
	RunUpdates()
	check("Liquid shading changes over time", table.concat(control.gradient, ",") ~= firstColour, true)
	local function CheckRestored()
		for _, bar in ipairs(addon.plain.bars) do
			local gradient = ZO_POWER_BAR_GRADIENT_COLORS[_G["COMBAT_MECHANIC_FLAGS_" .. bar.power:upper()]]
			local r,g,b,a = gradient[1]:UnpackRGBA()
			local r2,g2,b2,a2 = gradient[2]:UnpackRGBA()
			for _, entry in ipairs(bar.controls) do
				check("native gradient is restored", table.concat(_G[entry.name].gradient, ","), table.concat({r,g,b,a,r2,g2,b2,a2}, ","))
			end
		end
	end
	FireHud(SCENE_FRAGMENT_HIDDEN)
	check("Liquid loop stops behind menus", addon.plain.running, false)
	CheckRestored()
	FireHud(SCENE_FRAGMENT_SHOWN)
	check("Liquid loop resumes on HUD", addon.plain.running, true)
	addon:SetBarStyle("standard")
	addon:Refresh()
	CheckRestored()
	addon:SetBarStyle("neo")
	addon:Refresh()
	addon:SetBarStyle("liquidflow")
	addon:Refresh()
	check("entering Liquid from NEO restores the frame", _G.ZO_PlayerAttributeHealthFrameLeft:IsHidden(), false)
	check("entering Liquid restores text layout", _G.ZO_PlayerAttributeHealthResourceNumbers.anchors[1].offsetX, 7)
	addon:Account().enabled = false
	addon:Refresh()
	CheckRestored()
	addon:Account().enabled = true
end

print("\n== Liquid: a liquid in a glass tube, inside the bar a console really draws ==")
-- The status bars here are 64 high, as on a console, with the 17-pixel band in their middle.
-- Liquid's pieces come in two kinds: "fill" pieces belong to the liquid and must stay inside what
-- is filled; "tube" pieces (the glass, and the trace of what drained) belong to the tube and must
-- stay inside the bar. Both must stay inside the band, and clear of the pointed outer ends.
do
	local plain = addon.plain
	addon:Account().enabled = true
	addon:SetBarStyle("liquidflow")
	FireHud(SCENE_FRAGMENT_SHOWN)
	addon:Refresh()

	local TAPER = 17 / 2
	local function Entry(barIndex, controlIndex)
		local bar = plain.bars[barIndex]
		local entry = bar.controls[controlIndex]
		return { bar = bar, entry = entry, name = entry.name, native = _G[entry.name] }
	end
	local entries = { Entry(1, 1), Entry(1, 2), Entry(2, 1), Entry(3, 1) }
	local function Pointed(which)
		local halves = #which.bar.controls > 1
		local right = halves and which.bar.controls[2].name == which.name
		return not halves or not right, not halves or right
	end
	local function Draw(which, fraction, now)
		plain:LiquidRibbons(which.bar, which.entry, which.native, fraction, now)
		return plain.liquidRibbons[which.name]
	end
	local function Shown(group)
		local list = {}
		if group.control:IsHidden() then return list end
		for _, texture in ipairs(group.textures) do
			if not texture:IsHidden() then list[#list + 1] = texture end
		end
		return list
	end
	local function Box(texture)
		local a = texture.anchors[1]
		return a.offsetX, a.offsetY, a.offsetX + texture:GetWidth(), a.offsetY + texture:GetHeight()
	end
	local E = 0.0001

	-- Nothing leaves the band, the fill or the tube, at any amount, at any moment, on any bar.
	for _, which in ipairs(entries) do
		local width, height = which.native:GetDimensions()
		local bandTop, bandBottom = (height - 17) / 2, (height + 17) / 2
		local pointedLeft, pointedRight = Pointed(which)
		local tubeFrom, tubeTo = pointedLeft and TAPER or 0, pointedRight and width - TAPER or width
		local fits, drawn = true, 0
		local time = 100000
		for _, fraction in ipairs({ 1, 0.75, 0.5, 0.25, 0.05, 0.6, 0.02 }) do
			for step = 0, 12 do
				time = time + 83
				local group = Draw(which, fraction, time)
				local fillFrom = which.entry.reverse and width * (1 - fraction) or 0
				local fillTo = which.entry.reverse and width or width * fraction
				for _, texture in ipairs(Shown(group)) do
					drawn = drawn + 1
					local x0, y0, x1, y1 = Box(texture)
					local inside = y0 >= bandTop - E and y1 <= bandBottom + E and x0 >= tubeFrom - E and x1 <= tubeTo + E
					if texture.pbsLiquidRole == "fill" then
						inside = inside and x0 >= fillFrom - E and x1 <= fillTo + E
					end
					if not inside then fits = false end
				end
			end
		end
		check("nothing leaves the band, the fill or the tube: " .. which.name, fits, true)
		check("and there was something to check on " .. which.name, drawn > 100, true)
	end

	-- The liquid runs the length of what is filled -- the PS5's "only in the middle" and "nothing
	-- on health" -- measured as how much of the bar the fill pieces cover.
	local function Covered(which, fraction, now)
		local group = Draw(which, fraction, now)
		local left, right = math.huge, -math.huge
		for _, texture in ipairs(Shown(group)) do
			if texture.pbsLiquidRole == "fill" then
				local x0, _, x1 = Box(texture)
				left, right = math.min(left, x0), math.max(right, x1)
			end
		end
		return left, right, which.native:GetWidth()
	end
	for _, which in ipairs(entries) do
		local left, right, width = Covered(which, 1, 200000)
		check("the liquid covers " .. which.name, left ~= math.huge and (right - left) / width > 0.9, true)
	end
	local _, leftHalfRight, leftHalfWidth = Covered(entries[1], 1, 200000)
	local rightHalfLeft = Covered(entries[2], 1, 200000)
	check("health's left half reaches the middle", math.abs(leftHalfRight - leftHalfWidth) < E, true)
	check("health's right half starts at the middle", math.abs(rightHalfLeft) < E, true)
	check("health still draws at half", Covered(entries[1], 0.5, 200000) ~= math.huge and Covered(entries[2], 0.5, 200000) ~= math.huge, true)

	-- Soft, not lines: the currents fade from their middle to nothing at the rim.
	local group = Draw(entries[4], 1, 210000)
	local soft = false
	for _, pieces in ipairs(group.currents) do
		for _, piece in ipairs(pieces) do
			if not piece:IsHidden() and piece.vertices then
				local alphas = {}
				for _, corner in ipairs({ 1, 2, 4, 8 }) do alphas[#alphas + 1] = piece.vertices[corner][4] end
				if math.max(unpack(alphas)) > 0.1 and math.min(unpack(alphas)) < 0.05 then soft = true end
			end
		end
	end
	check("the currents are soft masses, not lines", soft, true)
	check("the lower part of the liquid sinks into shadow",
		group.shade.vertices[1][4] == 0 and group.shade.vertices[4][4] > 0.3, true)

	-- The surface: where the fill ends inside the tube, and not when it is pressed into the point.
	local stamina = entries[4]
	group = Draw(stamina, 0.6, 220000)
	check("a part-filled bar has a surface", group.surface[1]:IsHidden(), false)
	local surfaceX = group.surface[1].anchors[1].offsetX
	check("the surface is at the level", math.abs(surfaceX - 224 * 0.6) < 8, true)
	group = Draw(stamina, 1, 220100)
	check("a full bar has no surface pressed into its point", group.surface[1]:IsHidden(), true)

	-- It sloshes when the amount changes, and settles again.
	local function Spread(fraction, from, frames)
		local low, high = math.huge, -math.huge
		for frame = 1, frames do
			local g = Draw(stamina, fraction, from + frame * 50)
			for _, piece in ipairs(g.surface) do
				local x = piece.anchors[1].offsetX
				low, high = math.min(low, x), math.max(high, x)
			end
		end
		return high - low
	end
	Draw(stamina, 0.6, 300000)
	for frame = 1, 40 do Draw(stamina, 0.6, 300000 + frame * 50) end
	local calm = Spread(0.6, 302000, 6)
	Draw(stamina, 0.4, 302400)
	local stirred = Spread(0.4, 302400, 6)
	check("a sudden change stirs the surface", stirred > calm + 1, true)
	for frame = 1, 60 do Draw(stamina, 0.4, 302700 + frame * 50) end
	check("and it settles again", Spread(0.4, 305800, 6) < stirred - 1, true)

	-- What was lost stays a moment, then drains away.
	Draw(stamina, 0.8, 400000)
	group = Draw(stamina, 0.3, 400050)
	check("a hit leaves a trace of what was lost", group.drain:IsHidden(), false)
	local dx0, _, dx1 = Box(group.drain)
	check("the trace lies between the new level and the old", dx0 >= 224 * 0.3 - E and dx1 <= 224 * 0.8 + E, true)
	for frame = 1, 40 do group = Draw(stamina, 0.3, 400050 + frame * 50) end
	check("and has drained away two seconds later", group.drain:IsHidden(), true)

	-- The glass runs along the tube, full or not.
	group = Draw(stamina, 0.3, 500000)
	local gx0, _, gx1 = Box(group.glass)
	check("the glass runs along the whole tube", group.glass:IsHidden() == false and (gx1 - gx0) > 224 - 17 - 1, true)

	-- Bubbles rise.
	group = Draw(stamina, 1, 600000)
	local bubble = group.bubbles[1].body
	local y = bubble.anchors[1].offsetY
	group = Draw(stamina, 1, 600200)
	check("bubbles rise", bubble.anchors[1].offsetY < y, true)

	-- Empty, and no trace left: nothing drawn. Filled again: back.
	for frame = 1, 80 do group = Draw(stamina, 0, 700000 + frame * 50) end
	check("nothing on an empty bar", group.control:IsHidden(), true)
	group = Draw(stamina, 0.004, 705000)
	check("nor on a sliver pressed into the point", group.control:IsHidden(), true)
	group = Draw(stamina, 1, 705050)
	check("and back when it fills", group.control:IsHidden(), false)

	-- Built once and reused: a long fight must not create controls.
	local created = 0
	for _ in pairs(CreatedControls) do created = created + 1 end
	for frame = 1, 200 do
		for _, which in ipairs(entries) do Draw(which, 0.5 + 0.4 * math.sin(frame / 7), 800000 + frame * 50) end
	end
	local after = 0
	for _ in pairs(CreatedControls) do after = after + 1 end
	check("no controls are created while it runs", after, created)
	check("and each bar section is a modest number of pieces", #plain.liquidRibbons[stamina.name].textures <= 45, true)

	-- The liquid body is nearly solid, and the loop keeps it there.
	SetPower(COMBAT_MECHANIC_FLAGS_STAMINA, 600, 1000)
	RunUpdates()
	local gradient = ZO_POWER_BAR_GRADIENT_COLORS[COMBAT_MECHANIC_FLAGS_STAMINA]
	local _, _, _, alpha = gradient[1]:UnpackRGBA()
	check("the liquid body is nearly solid", math.abs(_G[stamina.name].gradient[4] - alpha * 0.92) < E, true)

	-- It goes with the HUD and with the style.
	group = plain.liquidRibbons[stamina.name]
	FireHud(SCENE_FRAGMENT_HIDDEN)
	check("the liquid hides with the HUD", group.control:IsHidden(), true)
	FireHud(SCENE_FRAGMENT_SHOWN)
	RunUpdates()
	check("and returns with it", group.control:IsHidden(), false)
	addon:SetBarStyle("standard")
	addon:Refresh()
	check("choosing another style removes it", group.control:IsHidden(), true)
	check("and the body's own opacity comes back", _G[stamina.name].gradient[4], alpha)
end

print("")
if failures == 0 then
	print("all checks passed")
else
	print(failures .. " FAILED")
end
os.exit(failures == 0 and 0 or 1)
