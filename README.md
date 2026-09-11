# PB's ConsoleHudCustomizer

Moves and resizes the health, magicka and stamina bars on the HUD, in The Elder Scrolls Online on
console.

- **Author:** PinkBanther
- **Version:** 1.0.0
- **Optional:** `LibHarvensAddonSettings` >= 20106 (for the settings panel; the chat commands work
  without it)

## What it does

The game pins all three resource bars to the bottom of the screen, side by side, at one fixed
size, and offers no setting for any of it. This add-on gives each bar three of its own:

| | |
| --- | --- |
| **Sideways** | How far the middle of the bar is from the middle of the screen. 0 is dead centre, negative left, positive right. |
| **Height** | How far the middle of the bar is up from the bottom edge. The game's own bars sit 137 up. |
| **Size** | 50% to 200% of the game's own size. Frame, background, bar and numbers all together. |

The three are independent, so health can sit in the middle of the screen with magicka and stamina
low in the corners, or all three can be stacked, or moved out of the way of a minimap.

Every setting starts at the game's own value, **measured off the real bars** rather than assumed,
and nothing is changed until you move something. Installed and left alone, the add-on is
indistinguishable from not having it.

### Size is one number, on purpose

The bar's width is not the add-on's to keep. The game stretches a bar to 323 wide, or shrinks it
to 141, every time a buff or debuff moves one of your maximums — food, Undaunted Mettle, a
debuff — and animates it there. A width written by an add-on would survive until your next meal.

So "size" is a scale: 100% is the game's own, and everything in the bar grows and shrinks in
proportion, which is also the only way the arrow-shaped frame ends stay the right shape. The bar
keeps the position of its **middle**, so it grows evenly both ways and stays where you put it —
including when the game stretches it for a buff.

### The small bars follow

The werewolf bar lives under magicka, mount stamina under stamina and siege health under health.
Each one is anchored to its partner in the game's own XML, so it moves with it, and this add-on
gives it the same size so the pair still lines up.

### Preview

The bars are only drawn on the HUD, so they cannot be seen from the settings menu. While this
add-on's panel is open, an **outline the size of each bar**, in that bar's colour, is drawn where
it will sit. It follows every slider as you move it, and goes away when you leave the panel. It
can be switched off in the panel.

`/pbhud preview` shows the same outlines anywhere — on the HUD they sit on top of the real bars,
which is the quickest way to check the two agree.

## Chat commands

```
/pbhud                        this list
/pbhud status                 settings, and where the bars really are on screen
/pbhud pos <bar> <x> <y>      x from the middle of the screen, y up from the bottom
/pbhud scale <bar> <n>        size in per cent (50-200)
/pbhud on | off               switch every change on or off
/pbhud preview                show or hide the preview outlines
/pbhud reset [bar]            back to the game's own
```

`<bar>` is `health`, `magicka` or `stamina` (`hp`, `mag`, `stam` also work). `/pbhc` is the same
command.

## How it works

Nothing in the attribute bars is hooked, wrapped or called. The add-on only **writes to
controls**, and lets the bars carry on running their own code:

- **Position** is the anchor of each container — `ZO_PlayerAttributeHealth`, `...Magicka`,
  `...Stamina` — re-pointed from the group they were built in to `GuiRoot`: `CENTER` of the bar on
  `BOTTOM` of the screen. They stay children of `ZO_PlayerAttribute`, so the HUD fragment still
  fades and hides them, and the game's "fade out of combat" setting still works.
- **Size** is `SetScale` on that container, and on its small companion.

These controls run combat code — power updates, the attribute visualiser, the warners — on every
frame of a fight, and an add-on frame near client code is how private-function errors start. See
FINDINGS.md.

The game's own anchors and scales are read off the controls before the first write of each
session. Reset, the on/off switch, and a slider moved back to the default all put exactly those
back.

## What it does not touch

- **The bar's own width** — the game's, see above.
- **Whether the numbers are shown on the bars**, and **whether the bars fade out of combat** —
  the game's settings under Settings > Interface.
- **The order or the colours of the bars**, the werewolf / mount / siege bars' own positions, and
  anything else on the HUD.

## Tests

```
lua test/run.lua
```

from the add-on folder, with any Lua 5.1 or later. `test/harness.lua` stubs the three attribute
bar containers with the game's own anchors, a layout resolver that turns an anchor into a
rectangle, and the attribute visualiser's habit of writing 141 / 237 / 323 onto a bar's width —
so a build that measured the game's position off a stretched bar, or that fought the visualiser
for the width, would fail here rather than on a PS5.

## Licence

This Add-On is not created by, affiliated with or sponsored by ZeniMax Media Inc. or its
affiliates. The Elder Scrolls® and related logos are registered trademarks or trademarks of
ZeniMax Media Inc. in the United States and/or other countries. All rights reserved.
