# Store listing copy

Text for the Bethesda.net / ZOS Console AddOn Uploader entry. Plain text, no markdown —
paste as-is. The **name** field is what the in-game add-on browser shows, so it must read
`PB's ConsoleHudCustomizer` there; `## Title` in the manifest does not reach that screen.

---

## Name

PB's ConsoleHudCustomizer

## Overview (JP)

HUDの体力・マジカ・スタミナバーを、1本ずつ好きな位置・好きな大きさにできます。左右の位置、
画面下端からの高さ、50〜200%の倍率を、3本それぞれ個別に設定できます。設定中はプレビュー枠で
仕上がりを確認できます。

## Overview (EN)

Moves and resizes the health, magicka and stamina bars on the HUD, each one on its own: sideways
from the middle of the screen, up from the bottom edge, and from half size to double. A preview
outline shows the result while you adjust it.

---

## Description (JP)

コンソール版のリソースバーは、画面下部に3本並んだ固定の位置・固定の大きさで、ゲーム側に設定
項目はありません。このアドオンは、体力・マジカ・スタミナの3本を1本ずつ自由に配置・拡大縮小
できるようにします。

■ 設定できること（3本それぞれ個別）

・左右の位置
　画面中央からバーの中心までの距離です。0で中央、マイナスで左、プラスで右へ移動します。
・高さ
　画面下端からバーの中心までの高さです。ゲーム本来のバーは下から137の位置にあります。
・大きさ
　ゲーム本来を100%とした倍率で、50〜200%。枠・背景・バー・数値がすべて同じ比率で拡大縮小し、
　バーは中心の位置を保ったまま大きさだけが変わります。

体力を画面中央上に、マジカとスタミナを左右下に、といった配置も、3本まとめて別の場所へ、
という配置もできます。

■ 大きさが「倍率」である理由

バーの幅はゲーム側が管理しています。最大値を上下させる効果（料理、アンドーンテッドの
心構え、各種デバフ）が付くたび、ゲームはバーの幅を141／237／323へアニメーションで書き換え
ます。アドオンが幅を指定しても、次の食事で元に戻ってしまいます。
そのため大きさは倍率で扱います。枠の矢印部分まで含めて比率が保たれ、ゲーム側が幅を書き換え
ても、バーは置いた位置を中心に左右へ均等に伸びるだけです。

■ 付属の小さいバー

狼バー（マジカの下）、騎乗スタミナ（スタミナの下）、攻城兵器の体力（体力の下）は、ゲームの
XMLで各バーに固定されているため一緒に移動し、倍率も同じ値が適用されます。

■ プレビュー

バーはHUD上でしか描画されないため、設定メニューからは見えません。このアドオンの設定パネルを
開いている間は、各バーの位置と大きさを色付きの枠で表示します。スライダーの操作にその場で
追従し、パネルを離れると消えます。パネル内でオフにもできます。
「/pbhud preview」でHUD上にも表示できます。実際のバーに重ねて表示されるので、ずれがないか
すぐ確認できます。

■ そのほか

・すべての項目はゲーム本来の値から始まります。しかもその値は実際のバーから実測したものです。
　何も動かさなければ何も書き換えないので、入れただけの状態は入れていないのと同じです。
・オフにする／リセットすると、ゲーム本来の位置と大きさに正確に戻ります。
・ゲームのUIコードをフックしたり呼び出したりはしていません（コンソールで致命的になるため）。
・バーに数値を表示するか、戦闘外でバーを薄くするかはゲーム本体の設定です
　（設定 > インターフェース）。

■ チャットコマンド

/pbhud                    コマンド一覧
/pbhud status             設定内容と、画面上の実際の位置
/pbhud pos <bar> <x> <y>  位置（中央からの左右、下端からの高さ）
/pbhud scale <bar> <n>    大きさ（50〜200）
/pbhud on | off           変更のオン／オフ
/pbhud preview            プレビュー枠の表示／非表示
/pbhud reset [bar]        ゲーム本来の状態に戻す

<bar> は health / magicka / stamina（hp、mag、stam でも可）。/pbhc も同じコマンドです。

設定パネルには LibHarvensAddonSettings が必要です（任意。なくてもチャットコマンドで操作
できます）。

---

## Description (EN)

On console the three resource bars are fixed side by side at the bottom of the screen, at one
size, with no setting for any of it. This add-on lets you place and resize health, magicka and
stamina one at a time.

What you can set, for each bar on its own:

- Sideways -- how far the middle of the bar is from the middle of the screen. 0 is dead centre,
  negative left, positive right.
- Height -- how far the middle of the bar is up from the bottom edge. The game's own bars sit
  137 up.
- Size -- 50% to 200% of the game's own. Frame, background, bar and numbers all together, and the
  bar keeps the position of its middle.

Health in the middle of the screen with magicka and stamina low in the corners, all three stacked,
or the whole set moved out of the way of a minimap -- all of it is three sliders per bar.

Why size is one number: the bar's width belongs to the game. It stretches a bar to 323, or shrinks
it to 141, every time a buff or debuff moves one of your maximums, and animates it there. A width
written by an add-on would last until your next meal. A scale is never touched by the game, and it
keeps the arrow-shaped frame ends the right shape.

The werewolf, mount stamina and siege health bars are anchored to their partner in the game's own
XML, so they move with it, and are given the same size.

The bars are only drawn on the HUD, so while the settings panel is open an outline the size of
each bar is drawn where it will sit, in that bar's colour, following every slider. "/pbhud
preview" draws the same outlines on the HUD, over the real bars.

Every setting starts at the game's own value, measured off the real bars rather than assumed, and
nothing is changed until you move something: installed and left alone, the add-on is
indistinguishable from not having it. Switching it off, or resetting, puts the game's own anchors
and sizes back exactly. Nothing in the game's UI is hooked or called.

Whether the numbers are shown on the bars, and whether the bars fade out of combat, are the game's
own settings under Settings > Interface.

Chat commands: /pbhud (and /pbhc). The settings panel needs LibHarvensAddonSettings; the commands
work without it.
