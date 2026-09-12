# Findings

What the client's own source says about the player's attribute bars, and why the add-on is built
the way it is. Everything here is **from source** (`esoui/esoui`, tag 12.0.8, API 101050) unless
it says it was measured; the list at the end is what still has to be looked at on a PS5.

## 1. Three controls in one top-level

`ZO_PlayerAttribute` (`playerattributebars.xml`) is the top-level, 64 high and hidden until the
HUD shows it. Inside it are six controls: the three the player knows —

| | anchor in the XML |
| --- | --- |
| `ZO_PlayerAttributeHealth` | `CENTER` of the group |
| `ZO_PlayerAttributeMagicka` | `RIGHT` on the group's `LEFT`, +237 |
| `ZO_PlayerAttributeStamina` | `LEFT` on the group's `RIGHT`, -237 |

— and three small companions, each anchored to the bar it belongs to: `Werewolf` under magicka,
`MountStamina` under stamina, `SiegeHealth` under health. All six are `ZO_PlayerAttributeContainer`
(237 × 23) or `...ContainerSmall` (228 × 12), and everything visible — background, frame, the
status bars, the warner, the resource numbers — is anchored inside its container. So a container's
anchor and scale are the whole bar's position and size.

The group itself is placed by `ZO_PlayerAttribute_Gamepad_Template`: `BOTTOM` of `GuiRoot`,
105 up. Its width comes from `ResizeToFitScreen`:

```lua
local barAreaWidth = screenWidth - BAR_OFFSET_FROM_SCREEN_EDGE * 2   -- 502
barAreaWidth = zo_clamp(barAreaWidth, MIN_BAR_AREA_WIDTH, MAX_BAR_AREA_WIDTH)  -- 1014, 1600
```

At 1920 wide that is 1014 — the minimum, not the screen — which is why the bars sit where they do
regardless of the TV. The middles work out at 137 up from the bottom, and 0 / -388 / +389 from the
middle of the screen. The add-on measures all six numbers off the controls anyway; those are only
the fallback.

## 2. What the client writes to these controls, and when

- `ResizeToFitScreen`, on `EVENT_SCREEN_RESIZED` and once at startup: the **group's width**. With
  the three containers anchored to the group, that moves magicka and stamina. Once they are
  anchored to `GuiRoot` instead, it does not reach them.
- `ZO_PlayerAttributeBars:ApplyStyle`, on `EVENT_GAMEPAD_PREFERRED_MODE_CHANGED`: templates for
  the group, the textures and the sub-bars. It re-anchors the **sub-bars inside** each container
  and the **group**, but never a container itself.
- `ZO_UnitVisualizer_ShrinkExpandModule`: the **container's width**, and its background's, as
  buffs and debuffs move a maximum:

```lua
ATTRIBUTE_BAR_STATE_EXPANDED -> 323
ATTRIBUTE_BAR_STATE_SHRUNK   -> 141
ATTRIBUTE_BAR_STATE_NORMAL   -> 237
```

  instantly on `EVENT_PLAYER_ACTIVATED`, and through a 750 ms `SizeAnimation` the rest of the time.

Nothing in the client writes a container's **anchor** or its **scale** after the UI is built.

## 3. Why scale, and not `SetDimensions`

§2 is the whole argument. A width written by an add-on survives until the player eats a meal,
takes a debuff, or zones — and then the visualiser animates the bar to 141, 237 or 323 and leaves
it there. Fighting that would mean rewriting the width on every one of those changes, which is a
loop with the client's own animation. Scale is never touched by the client, needs no upkeep, and
takes the frame textures, the background, the status bar and the resource numbers with it in
proportion — a stretched-width bar keeps its 64-pixel arrow ends and looks wrong.

The cost is that size is one number rather than two. For a HUD bar that reads as the right trade:
nobody wants a health bar three times as tall as it is wide.

## 4. Why the middle, and `GuiRoot`

Each container is anchored `CENTER` → `GuiRoot` `BOTTOM`, at (x, -y). Two reasons for the middle
rather than a corner: the width is not ours (§2), so a bar held by an edge would slide as buffs
come and go; and whatever ESO's scaling pivot turns out to be, a control whose anchor point is its
own centre stays put when it is scaled.

`GuiRoot` rather than the group, because three bars anchored to a 1014-wide group cannot be placed
apart from each other, and because the group's width moves on `EVENT_SCREEN_RESIZED`. The
containers stay **children** of `ZO_PlayerAttribute` — only the anchor changes — so
`PLAYER_ATTRIBUTE_BARS_FRAGMENT` (a `ZO_HUDFadeSceneFragment` over the group) still fades and
hides them exactly as before, and the game's own "fade out of combat" setting still works.

The companions keep their own anchors, which are relative to their partner, so they follow it.
They are given the same scale, or the pair no longer meets.

## 5. Measuring the game's own position

Taken once per session per bar, before anything is written, off `GetLeft` / `GetTop` /
`GetDimensions` — and **only while the container is its normal 237 wide**. The middle of a
stretched bar is not where the middle of a normal one is: the game holds magicka by its right edge
and stamina by its left, so at 323 the middle has moved 43 in. A bar that is not at its normal
width is left for the next HUD show to measure, and the worked-out fallback stands in meanwhile.
The two agree exactly at 1920 × 1080, which the tests check.

## 6. Why nothing is hooked

The rule from PB's MailerExtension (measured on PS5): a client closure created while an add-on
frame is on the stack is permanently untrusted, and fails the moment it reaches a private
function. These controls run combat code — `EVENT_POWER_UPDATE` several times a second in a fight,
the attribute visualiser's modules, the warners, the fade timeline — so a tainted closure here
would surface in the middle of a fight.

So the add-on never wraps an attribute bar method and never calls one. Everything is a write to a
control:

| | written | the game's own equivalent |
| --- | --- | --- |
| position | `ClearAnchors` / `SetAnchor` on each container | the XML anchors |
| size | `SetScale` on each container and its companion | (nothing — the client never scales them) |

The one registration is a `"StateChange"` callback on `HUD_FRAGMENT`: our function is stored
beside the client's, nothing of theirs is wrapped. The preview is built entirely from controls of
the add-on's own — showing the real bars in a menu would mean driving the group's fragment from
add-on code.

## 7. When the settings panel is actually open

Carried over from PB's ChatWindowCustomizer 1.0.1, found on PS5 and confirmed in the library's
source (`votan73/ESO`, `LibHarvensAddonSettings/Console/Settings.lua`): the console add-on list
opens a panel in two steps —

```lua
addon:Select()                                      -- fires AddonSelected, then sets .selected
SCENE_MANAGER:Push("LibHarvensAddonSettingsScene")  -- and only then shows the panel
```

— so `AddonSelected` arrives while the *list* is still the current scene, and `Select()` returns
early for the add-on already selected, firing nothing at all on a second visit. The preview
follows the library's own panel scene instead. The test harness opens panels in that same order.

## 8. Cost on console

Moving and scaling a control costs nothing lasting, and no font or texture is built: the preview
uses `ZoFontGamepad22`, which the gamepad UI has already, and plain colour textures. Nothing is
written at all while the settings still equal the game's own, so an installed-but-unset add-on is
indistinguishable from not having it.

## 9. The skill bar is one top-level too

`ZO_ActionBar1` (`actionbar.xml`) is 70 high and, on the gamepad, 606 wide and `BOTTOM` of
`GuiRoot` at -25 (`GAMEPAD_CONSTANTS` in `actionbar.lua`). Every button hangs inside it: the five
abilities and the ultimate are `ActionButton3` to `ActionButton8`, chained off
`ZO_ActionBar1WeaponSwap`, with the quickslot and the companion ultimate anchored to those. So
its anchor and its scale are the whole bar's, and it is placed and sized exactly like the three
attribute bars -- the same `CENTER` → `GuiRoot` `BOTTOM` anchor, the same scale, the same
measurement before the first write.

The one client write to watch is `ApplyStyle`, through `ZO_PlatformStyle`: on
`EVENT_GAMEPAD_PREFERRED_MODE_CHANGED` it does `ZO_ActionBar1:ClearAnchors()`, re-anchors and
sets the width back to 606. That is the same case the attribute bars have, and the same answer:
every HUD show compares and rewrites only what no longer matches.

The buttons are named controls (`CreateControlFromVirtual("ActionButton"..slotNum, ...)`), so
they are reached with a plain `_G` lookup. `ZO_ActionBar_GetButton` is never called -- not
because that function is dangerous in itself, but because a name lookup cannot be.

## 10. The client has a back row, and it is not the one the player wants

`ZO_ActionBarTimer` (`actionbutton.lua`) is a real back row: `ActionBarTimer3` to
`ActionBarTimer8`, anchored `CENTER` on each main button at `backRowSlotOffsetY` = -17, with the
other set's icon and a fill bar. But:

- it is gated on two settings, `UI_SETTING_SHOW_ACTION_BAR_TIMERS` and
  `UI_SETTING_SHOW_ACTION_BAR_BACK_ROW`, and
- `UpdateFillBar` hides a slot the moment it has no running effect
  (`self.slot:SetHidden(true)` whenever `HasValidDuration()` is false).

So it shows a slot while a timer runs on it and nothing the rest of the time -- it is a timer
display, not a second bar. Forcing those controls to stay visible would mean fighting an
`OnUpdate` handler of the client's on every frame, so this add-on draws a row of its own instead
and leaves the client's alone. If the player has the game's own row on, both are drawn; that is
the game's setting to turn off, and status prints what it is set to.

## 11. The countdown is the client's own number

`HandleSlotEffectUpdated` in `actionbar.lua`:

```lua
local timeRemainingMS = GetActionSlotEffectTimeRemaining(slotNum, g_backHotbar)
local durationMS = GetActionSlotEffectDuration(slotNum, g_backHotbar)
...
local stackCount = GetActionSlotEffectStackCount(slotNum, hotbarCategory)
```

Three functions, and the crucial part is the second argument: **they answer for the hotbar you
are not on**. That is the whole countdown for both weapon sets, straight from the client, with no
need to work out which effect came from which cast -- the problem that makes Action Duration
Reminder two thousand lines of heuristics. This add-on reads them for slots 3-8 of both
categories, every 100 ms, and writes the number on the icon.

`MINIMUM_ACTION_BAR_TIMER_DISPLAYED_TIME_MS` is 1000 in the client, and the same floor is used
here: a number that flashes up for half a second as an ability is cast is noise.

## 12. Counting targets is the one part with no API

There is no `GetActionSlotEffectTargetCount`, and nothing else in the client answers it. So it is
counted from `EVENT_EFFECT_CHANGED`, filtered with the client's own
`REGISTER_FILTER_SOURCE_COMBAT_UNIT_TYPE` / `COMBAT_UNIT_TYPE_PLAYER` so only what the player
applied is seen: one entry per effect name, holding the units under it and when each expires.
Effects on `group*` unit tags are skipped -- a group member's copy of a buff would otherwise turn
a self-buff into "12".

A slot is matched to an entry by **name**, with the ability id as a second chance. That is a
heuristic, and an honest one: an effect usually carries the name of the ability that applied it,
but a morph that applies something under another name will not line up. The countdown does not
depend on it, so the worst case is a missing count, never a wrong time.

The table is bounded: expired units are dropped as they are read and again every 3 s, and at 96
effect names the least recently touched is dropped. On console that cap is the point -- a long
fight in a crowd must not grow a table for ever against the 100 MB pool.

## 13. Where the add-on's own controls live

`Controls.xml` holds two virtual templates -- one back bar slot (52 x 68 with a 44 x 44 icon, the
sizes and texture coordinates of `ZO_ActionBarTimer_BackBarSlot_Gamepad`, drawn in the game's own
back row art) and one pair of labels. They are laid out in XML rather than assembled with
`SetAnchor` from Lua, after PB's MailerExtension ran into anchor limits and zero-height rows
doing the latter on the console gamepad UI.

Only the parent is chosen at runtime, with `CreateControlFromVirtual`, because the controls they
hang on do not exist until the UI has loaded. Each one is parented to the `ActionButton` it
belongs to, which is what makes the action bar's own `ZO_HUDFadeSceneFragment` fade and hide
them with the bar, and what makes them inherit the scale this add-on puts on the bar.

## 14. What the update costs

One `RegisterForUpdate` at 100 ms, reading three numbers for each of twelve slots and writing at
most twenty-four short strings. It runs only while the HUD is up and only while something it
draws is switched on: `SCENE_FRAGMENT_HIDDEN` unregisters it, and so does the master switch. Two
fonts are built, one per text size in use.

## 15. The game's own countdown, and why it is faded rather than left alone

`ActionButton<n>TimerText` is the client's own number on the front bar, written by
`ActionButton:SetTimer` and sized by the platform template (`ZoFontGamepad27` on the gamepad).
Its size is not an add-on's to change, and the setting that turns it on
(`UI_SETTING_SHOW_ACTION_BAR_TIMERS`) is read-only from here. So with that setting on and this
add-on drawing its own number, the icon carries two.

1.1.0 answered that by not drawing ours while the game's was on. That was wrong in the way that
matters: the text size slider then did nothing at all, on the bar the player is looking at, and
the only clue was a tooltip. From 1.1.1 the default is to draw ours and set the client label's
**alpha to 0** instead.

Alpha is the right lever because `SetTimer` and `UpdateTimer` only ever write that label's text
and its hidden state -- alpha is never touched, so there is nothing to fight and nothing to
re-apply per frame. It is restored to 1 the moment ours stops being drawn: the mode is changed,
the master switch goes off, or the loop stops.

## 16. Controls.xml not loading is survivable

`CreateControlFromVirtual` raises if the template is not there -- a manifest that missed the XML,
or a client that would not parse it. On a console that is a whole session lost for nothing on
screen and nothing to read, so the failure is recorded (status prints it) and the same controls
are built from plain `CreateControl` calls instead, with the anchors and sizes the XML would have
given them. `/pbhud slots` says which of the two was used.

## 17. The gaps along the bar, and the control nobody sees

`ActionButton:ApplyAnchor` is the whole layout:

```lua
function ActionButton:ApplyAnchor(target, offsetX, isAnchoredLeft)
    if not isAnchoredLeft then
        self.slot:SetAnchor(LEFT, target, RIGHT, offsetX, 0)
    else
        self.slot:SetAnchor(RIGHT, target, LEFT, -offsetX, 0)
    end
end
```

and `ApplyStyle` chains the row with it, off `GAMEPAD_CONSTANTS`: `abilitySlotOffsetX` 10 between
the five abilities, `ultimateSlotOffsetX` 65 before the ultimate, `weaponSwapOffsetX` 61 for the
weapon swap marker inside the bar, and `quickslotOffsetXFromFirstSlot` 5 for the quickslot on the
far side of that marker.

The marker is the catch. On the gamepad `showWeaponSwapButton` is false and
`ZO_WeaponSwap_SetPermanentlyHidden` hides it -- but it is still a control with a width, and the
quickslot is anchored to its other side. So the gap the player sees between the item and the
first ability is `5 + the marker's width + 10`, and no single number in the client is that gap.

This add-on writes the same anchors with its own offsets, and anchors the quickslot to the
**first ability** instead of the marker, so the number in the settings panel is the distance on
screen. `ActionButton3` is left exactly where the client puts it, because it is what the rest of
the row hangs off; everything else closes up towards it. The three gaps are measured off the
controls first (`GetLeft` / `GetRight`, at the bar's own scale, before anything of ours is
written), so an untouched install still writes nothing.

The original anchor of each control is remembered the moment before the first write **to that
control**, never in one pass up front: the row can grow. `SetCompanionAnchors` puts a companion's
ultimate between the item and the abilities when one is summoned, and re-anchors the quickslot
past it -- a button the client has only just laid out, whose own anchor has to be read then, not
before. Reading them all again later would record our own offsets as the game's, which is the
mistake PB's NamePlateChanger had to grow a repair path for.

## 18. Whether the weapon sets can be swapped at all

Two client answers, and neither is a guess at an item:

```lua
local activeWeaponPair, locked = GetActiveWeaponPairInfo()          -- the Oakensoul Ring, etc.
local unearned = GetUnitLevel("player") < GetWeaponSwapUnlockedLevel()
```

Both are what the client's own weapon swap button reads
(`ZO_WeaponSwap_OnInitialized`, `buttontemplates.lua`), with `EVENT_WEAPON_PAIR_LOCK_CHANGED` and
`EVENT_ACTIVE_WEAPON_PAIR_CHANGED` behind the first and `EVENT_LEVEL_UPDATE` behind the second.
Action Duration Reminder looks for `oakensoul` in the icon of each worn ring instead
(`Bar.lua`, `barShowShiftFully`); that misses everything else that locks a bar, and breaks on a
renamed icon.

While either says no, there is no second set to show, so the back bar hides itself -- the
setting is left alone, and it comes back when the ring comes off. The update loop already
re-reads this every tick, so nothing has to be registered for it.

## 19. The shade over a skill is the client's own cooldown control

ESO has a `Cooldown` control type, and two of its sweep shapes are in the client's own Lua:
`CD_TYPE_RADIAL`, which the action bar uses for ability cooldowns, and
`CD_TYPE_VERTICAL_REVEAL`, which the utility wheel uses:

```lua
control.cooldown:SetTexture(GetSlotTexture(slotNum, hotbarCategory))
control.cooldown:SetFillColor(ZO_SELECTED_TEXT:UnpackRGBA())
control.cooldown:SetVerticalCooldownLeadingEdgeHeight(4)
control.cooldown:StartCooldown(remaining, duration, CD_TYPE_VERTICAL_REVEAL, CD_TIME_TYPE_TIME_UNTIL, USE_LEADING_EDGE)
```

That is the whole feature: a `Cooldown` of the add-on's own, over the button's icon, given the
ability's icon and started when an effect starts. **The engine runs the sweep**, so there is no
work per frame here and it cannot drift from the effect -- the length it is given is
`GetActionSlotEffectDuration`, the client's own number, on either weapon set.

It is only ever started again when something changes: a different duration, a different ability
in the slot, or the time left jumping back up, which is a re-cast. Ticking down is left alone.

Which way the sweep runs is `CD_TIME_TYPE_TIME_UNTIL` against `CD_TIME_TYPE_TIME_REMAINING` --
one counts towards the end and the other away from it. The setting is a **direction** rather than
a time type for that reason: nothing in the source says which way round the reveal is drawn, so
if it comes out upside down on a PS5 the player flips it, and a client that ever changes it costs
nobody a release.

## 20. Liquid without any new art

The liquid style is drawn **over** the client's own fill, not instead of it. That is the design
decision the rest follows from: the damage shield overlays, the armour, possession and unwavering
modules and the warners are all controls the attribute visualiser hangs on those same bar
controls (`ZO_PlayerAttributeHealthBarLeft`, `...Magicka Bar`, `...StaminaBar`), and a style that
hid the client's bars would take all of that with it. One child per bar control instead: it
inherits the bar's alpha -- the game's own fade out of combat -- its hidden state, and any scale
this add-on has put on the attribute bars.

The look is three things over the fill: a darker bottom for depth, two bands of light drifting
across at different speeds, and a bright line at the surface where the fill ends. Every texture
is one those bars already load (`attributeBar_dynamic_fill_gloss`,
`attributeBar_dynamic_leadingEdge_gloss`) or one the generic progress bars use, so the style adds
**nothing** to the 100 MB pool console add-ons share. There is no art file in this add-on.

Two things have to be worked out rather than read:

- **How full the bar is.** `GetUnitPower("player", COMBAT_MECHANIC_FLAGS_*)` each tick, rather
  than following `EVENT_POWER_UPDATE`: one call per bar is cheaper than keeping a copy of the
  client's bookkeeping in step, and it cannot drift out of it. The two halves of the health bar
  each hold half the value, so the fraction is the same for both.
- **Where the fill ends.** A bar with `barAlignment="REVERSE"` (magicka, and the left half of
  health) fills towards its left, so the overlay hangs off the right edge and the surface is on
  the left; a normal one is the mirror. ESO does not clip a child to its parent, so each band is
  given the width of its overlap with the filled part and the texture coordinates to match.

At 20 updates a second, and only while the HUD is up and the style is chosen: on Standard, the
default, nothing is built and no update is registered.

## 21. Every control needs the fallback, not most of them

1.3.0 shipped the liquid overlay as the only control without a plain-Lua fallback for a template
that did not build, and the shape of that bug is exactly what came back from the PS5: everything
else working, the liquid doing nothing, and nothing to read anywhere. The fallback list now
covers every template this add-on has, and `/pbhud liquid` prints the whole chain -- style, loop,
each bar control, each overlay, the fraction, and the alpha the game has the bar at.

The last of those is worth knowing on its own: the attribute bars fade themselves out while they
are full and the player is out of combat, and anything parented to them fades with them. A liquid
effect checked at full health outside a fight is invisible for a reason that has nothing to do
with the liquid.

## 22. A measurement must never be able to stop a write

Reported from a PS5: the attribute bars' position setting sometimes did not take effect. Nothing
in the client was moving them -- the attribute visualiser's modules (armour, possession,
unwavering, power shield, arrow regeneration) all anchor overlay controls **to** a bar and never
re-anchor the bar itself, and `ApplyStyle` only touches the group, the sub-bars and the textures.
It was this add-on's own doing.

`CaptureGame` did two jobs: remember the anchor the bar had (which has to succeed, or there would
be nothing to put back) and measure where the game draws it (which is only ever a nicety, because
the fallback is worked out from the client's own constants). It returned one answer for both, and
`ApplyBar` refused to write unless that answer was true:

```lua
local left, top, width, height = self:ScreenRect(control)
if not left then
    return false        -- and ApplyBar then wrote nothing at all
end
```

`ScreenRect` returns nothing while a control has no size on screen, which depends on how far the
UI has got when the first apply runs -- so the position applied on one login and not on the next.
The two are separate calls from 1.3.2: `CaptureAnchors` gates the write, `MeasureGame` is best
effort and is tried again on every HUD show.

## 23. Putting it back, and counting

Everything written is now checked once a second while the HUD is up, and written again if it is
no longer there -- the same watch PB's MiniMap has had since its first release. An anchor and a
scale read per control, nothing written while they match.

It counts what it had to put back, and `/pbhud status` prints that count. That is the measurement
that answers the next report of this kind: a count that climbs means something really is moving
the bars and the watch is fighting it; a count that stays at zero while the bars are wrong means
the write never landed at all, which is a different bug in a different place.

---

## Still to measure on a PS5

1. **Does writing the anchor work?** `SetAnchor` and `ClearAnchors` are marked
   `protected-attributes` in the API dump. PC add-ons re-anchor client controls routinely, and PB's
   ChatWindowCustomizer re-anchors a client top-level, but this is the first PB's add-on to
   re-anchor a client control *away from its own parent*. Move one slider, go back to the HUD and
   run `/pbhud status`: the bar's `anchor:` line must read `CENTER -> GuiRoot BOTTOM` with the new
   offsets, its `middle=` must match the settings, and there must be no `refused` line. If there
   is one, it names what was refused and why.
2. **Where does `SetScale` scale from?** `status` prints each bar's on-screen rectangle and the
   middle worked back out of it. At 150% the `middle=` must still equal the settings; if it has
   drifted by a quarter of the bar, the pivot is the control's top left and the anchor needs an
   offset of `(scale - 1) * size / 2`.
3. **Is the size really the whole bar?** At 200%, the frame arrows, the background and the
   resource numbers must all grow with the bar — nothing left at its old size, nothing clipped.
4. **Does the fade still work?** With "fade out of combat" on in Settings > Interface, a moved bar
   must still fade out with the other two, and still come back on damage. That is the check that
   re-anchoring did not take the container out of the HUD fragment's reach.
5. **Do the companions still line up?** Mount up (mount stamina under stamina), and at a scale
   other than 100%: the small bar must sit against its partner, not overlap it or float away.
6. **Does a buff still look right?** Eat a meal that raises maximum health. The bar must grow
   evenly both ways from where it was put and stay there, and `status` must still show the
   settings' `middle=`.
7. **Does the measurement come out right?** On a fresh install, before touching anything,
   `status` must show `game's: x=0 y=137 (measured)` for health and ±388/389 for the other two,
   and `differs=false written=false` on all three.
8. **Is the preview drawn above the settings panel?** It is `DL_OVERLAY` / `DT_HIGH`. If it is
   hidden behind the panel, that is the only thing to change.
9. **Does the skill bar move and scale?** Same two questions as 1 and 2, for `ZO_ActionBar1`:
   `/pbhud status` must show `CENTER -> GuiRoot BOTTOM` with the new offsets and no `refused`
   line, and at 80% the ultimate, the quickslot and the weapon swap marker must all come with it.
10. **Does the back row line up?** It is anchored `BOTTOM` on each button's `TOP`. Check the
    ultimate (slot 8, a taller button) sits level with the other five, that the row follows the
    bar when the bar is moved and scaled, and that swapping weapons swaps what it shows.
11. **Are the countdowns the same number the game shows?** Turn the game's own action bar timers
    on, set this add-on's countdown to Always, and cast a damage-over-time ability: the two
    numbers on the front bar must agree. Then swap weapons -- the number must carry on counting
    down on the row, which is the half the game does not draw.
12. **Is the target count right?** Hit three enemies with one damage-over-time ability: the icon
    must read 3, and fall to 2 as the first one dies or the effect drops. A self-buff must read 1
    and not the size of the group. If nothing is written at all, `/pbhud slots` says whether the
    effect is being tracked and under what name -- the name on the left of each slot has to
    appear in the tracked list, and on a Japanese client both are Japanese, so a mismatch there
    is the answer.
13. **Do the gaps come out right?** `/pbhud status` prints the three measured gaps next to the
    three in use. On a PS5 the measured ones should read 10 / 65 / (5 + the marker's width + 10);
    if the item one comes out at 5, the quickslot is not where this add-on thinks it is. Then
    pull all three in and check the row still reads left to right with no overlap, that the
    ultimate and the item are still hittable, and that the back bar row follows.
14. **And with a companion out?** Summon one: its ultimate appears between the item and the
    abilities, and both gaps on that side must take the item setting without the row jumping.
15. **Does the row go away with the Oakensoul Ring on?** Equip it: the back bar must disappear
    on its own and the setting must still say it is on. Take it off and it must come back.
    `/pbhud slots` prints `weapon swap available=false (locked)` while it is on.
16. **Does the text size actually bite?** `/pbhud slots` prints `h=` for each front label, the
    font height the client made of our descriptor. Move the countdown size slider and run it
    again: if `h=` does not move, `$(GAMEPAD_BOLD_FONT)|<n>|thick-outline` is not being
    understood and the face has to change. With the game's own action bar timers on, the default
    mode must also leave exactly one number on the icon, ours.
17. **Is the text legible over the icons?** The labels are `thick-outline` at the chosen size,
    the countdown gold and the count white, over the game's own icon art.
18. **Does the whole lot still fade out of combat?** The labels and the row are children of the
    action bar's buttons, so they should fade with it. If they stay solid over a faded bar, the
    parenting is wrong.
19. **Does the preview come and go with the panel?** Open the panel (the three outlines must
   appear straight away), back out to the list and open it again (they must appear again), open
   another add-on's panel (they must not), and leave with the menu button straight to the HUD
   (they must go). `/pbhud preview` on the HUD draws them over the real bars, which is the
   quickest way to see that the two agree.
