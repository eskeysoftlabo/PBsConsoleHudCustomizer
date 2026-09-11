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
check("settings rows", #PanelRows, 3 + 3 * 5 + 3)

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

print("")
if failures == 0 then
	print("all checks passed")
else
	print(failures .. " FAILED")
end
os.exit(failures == 0 and 0 or 1)
