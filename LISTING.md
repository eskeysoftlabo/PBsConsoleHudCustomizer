# Store listing copy

Text for the Bethesda.net / ZOS Console AddOn Uploader entry. Plain text, no markdown —
paste as-is. The **name** field is what the in-game add-on browser shows, so it must read
`PB's ConsoleHudCustomizer` there; `## Title` in the manifest does not reach that screen.

---

## Name

PB's ConsoleHudCustomizer

## Overview (JP)

HUDの体力・マジカ・スタミナバーとスキルバーを、1つずつ好きな位置・好きな大きさにできます。
さらに、裏の武器セットのスキルを常時表示し、表裏どちらのスキルにも「効果切れまでの残り時間」と
「効果対象数」をアイコン上に表示します（文字サイズも調整可）。

## Overview (EN)

Moves and resizes the health, magicka, stamina and skill bars on the HUD, each one on its own.
Adds an always-there row for the weapon set you are not on, and writes the time left on each
ability's effect and how many targets are under it on the icons of both sets, at the text size
you choose.

---

## Description (JP)

コンソール版のリソースバーは、画面下部に3本並んだ固定の位置・固定の大きさで、ゲーム側に設定
項目はありません。このアドオンは、体力・マジカ・スタミナの3本を1本ずつ自由に配置・拡大縮小
できるようにします。

■ 設定できること（体力・マジカ・スタミナ・スキルバーの4つを個別に）

・左右の位置
　画面中央からバーの中心までの距離です。0で中央、マイナスで左、プラスで右へ移動します。
・高さ
　画面下端からバーの中心までの高さです。ゲーム本来のバーは下から137の位置にあります。
・大きさ
　ゲーム本来を100%とした倍率で、50〜200%。枠・背景・バー・数値がすべて同じ比率で拡大縮小し、
　バーは中心の位置を保ったまま大きさだけが変わります。

体力を画面中央上に、マジカとスタミナを左右下に、スキルバーはさらに上へ、といった配置が
できます。

■ 大きさが「倍率」である理由

バーの幅はゲーム側が管理しています。最大値を上下させる効果（料理、アンドーンテッドの
心構え、各種デバフ）が付くたび、ゲームはバーの幅を141／237／323へアニメーションで書き換え
ます。アドオンが幅を指定しても、次の食事で元に戻ってしまいます。
そのため大きさは倍率で扱います。枠の矢印部分まで含めて比率が保たれ、ゲーム側が幅を書き換え
ても、バーは置いた位置を中心に左右へ均等に伸びるだけです。

■ 付属の小さいバー

狼バー（マジカの下）、騎乗スタミナ（スタミナの下）、攻城兵器の体力（体力の下）は、ゲームの
XMLで各バーに固定されているため一緒に移動し、倍率も同じ値が適用されます。

■ バーの見た目（液体スタイル）

体力・マジカ・スタミナのバーに、標準に加えて「液体」スタイルを選べます。バーと枠はそのままに、
中身を液体のように描きます（下側ほど暗く、光が2つの速さで流れ、残量の先端に液面の光の線）。
強さは0〜200%で調整できます。

ゲーム側の描画の「上に」重ねる方式のため、ダメージシールドや防御力変化の表示、瀕死の警告、
戦闘外での自動フェードはすべてそのまま機能します。使用しているテクスチャはバーが元から
読み込んでいるものだけなので、コンソールの共有メモリを追加で消費しません（画像ファイルは
同梱していません）。

■ 使用中スキルの網掛け

スキルの効果が続いている間、アイコンを暗く網掛けし、残り時間に合わせて上から下へ網掛けが
消えていきます。数字を読まなくても残りが分かり、表バー・裏バーの両方で動作します。
濃さ、境界を光らせるか、消えていく向きを設定できます。

掃引はゲーム本体のクールダウン描画（Cooldownコントロール）そのものに、実際の効果時間を
渡して任せています。そのため効果時間と必ず一致し、毎フレームの処理も発生しません。

■ スキルバーの間隔

ゲーム本体はアルティメットとアイテムの周りを大きく空けています。3つのスライダーで詰められます。

・スキル同士の間隔（ゲーム本来10）
・アルティメットの手前（同65。アルティメットだけ離れている原因）
・アイテムの手前（同、見えない武器切替マーカーの幅＋15）

とくに最後の1つが大きく、コンソールでは描画されない武器切替マーカーがアイテムとスキルの間に
場所を取っています。このアドオンはアイテムを最初のスキルに直接くっつけるため、設定した数字が
そのまま画面上の間隔になります。仲間を連れているときは、仲間のアルティメットにも同じ間隔を
使います。

■ 裏バー（もう一方の武器セット）

スキルバーの上に、いま使っていない方の武器セットのスキルを常時表示します。ゲーム本体にも
裏バー表示はありますが、効果が続いているスロットだけが一時的に出るものです。こちらは常に
表示されるため、表裏6本ずつを一目で確認できます。スキルバーを動かせば裏バーも追従します。
表示のオン／オフ、空きスロットの表示、大きさ、バーとの間隔を設定できます。

なお、オークンの魂の指輪など武器切り替えができない状態のとき、および武器切り替えを習得して
いないレベルのときは、裏バーは自動的に非表示になります（設定はそのまま。外せば戻ります）。

■ 残り時間と対象数

表バー・裏バーのどちらのスキルにも、アイコン上に次を表示できます。

・残り時間（アイコン下・金色）
　そのスキルの効果が切れるまでの時間です。1分以上は「1m」、10秒未満は「9.4」のように
　小数第1位まで（切り替え可）。
・対象数（アイコン上・白）
　その効果がかかっている対象の数です。既定は1体から表示（2体以上のときだけ表示にも変更可）。

文字サイズはそれぞれ12〜48で調整できます。

残り時間はゲーム本体が持っている値そのものです（GetActionSlotEffectTimeRemaining）。裏バー側
の値も同じ関数が答えるため、推測は一切していません。対象数だけはAPIがないため、自分がかけた
効果を数え、スキル名で対応付けています（効果名がスキル名と異なるモーフでは表示されません。
残り時間には影響しません）。

表バーについては、ゲーム側の「設定 > インターフェース > アクションバータイマー」がオンのとき、
サイズ変更できないゲーム側の数字が出ます。既定の「このアドオン」では、その数字を薄くしたうえで
このアドオンの数字を表示するため、文字サイズの設定が常に反映されます（「両方」「ゲームに任せる」
も選べます）。裏バーはゲーム側が数字を出さないため、どの設定でも常にこのアドオンが表示します。

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

/pbhud                             コマンド一覧
/pbhud status                      設定内容と、画面上の実際の位置
/pbhud pos <bar> <x> <y>           位置（中央からの左右、下端からの高さ）
/pbhud scale <bar> <n>             大きさ（50〜200）
/pbhud gap skill|ult|item <n>      スキルバーの間隔（0〜150）
/pbhud style standard|liquid       リソースバーの見た目
/pbhud shade [on|off|up|down|<n>]  使用中スキルの網掛け
/pbhud text timer|count <n>        スキルバーの文字サイズ（12〜48）
/pbhud timers addon|both|game      表バーの残り時間をどちらが出すか
/pbhud slots                       各スロットの状態（診断用）
/pbhud backbar [on|off|empty|<n>]  裏バーの表示・大きさ
/pbhud on | off                    変更のオン／オフ
/pbhud preview                     プレビュー枠の表示／非表示
/pbhud reset [bar]                 ゲーム本来の状態に戻す

<bar> は health / magicka / stamina / skillbar（hp、mag、stam、bar でも可）。
/pbhc も同じコマンドです。

設定パネルには LibHarvensAddonSettings が必要です（任意。なくてもチャットコマンドで操作
できます）。

---

## Description (EN)

On console the three resource bars and the skill bar are fixed at the bottom of the screen, at one
size, with no setting for any of it. This add-on lets you place and resize all four one at a time,
adds the weapon set you are not on, and writes the time left and the target count on the icons.

What you can set, for each of the four on its own:

- Sideways -- how far the middle of the bar is from the middle of the screen. 0 is dead centre,
  negative left, positive right.
- Height -- how far the middle of the bar is up from the bottom edge. The game's own bars sit
  137 up.
- Size -- 50% to 200% of the game's own. Frame, background, bar and numbers all together, and the
  bar keeps the position of its middle.

Health in the middle of the screen with magicka and stamina low in the corners, the skill bar
higher up, or the whole set moved out of the way of a minimap -- all of it is three sliders each.

A liquid look: the three resource bars, standard or with their fill drawn as something poured --
darker at the bottom, light drifting across, a bright surface line where the fill ends. Drawn over
the game's own fill, so shields and warnings still show, and built from textures the bars already
load, so it costs no extra memory.

A shade over a skill in use: while an ability's effect runs, its icon is shaded and the shade is
wiped away down the icon as the time runs out, on both weapon sets. The game's own cooldown
machinery does the sweep, with the effect's real length.

Spacing: three sliders for the gaps along the skill bar -- between the abilities, before the
ultimate, and before the item, where the console's own invisible weapon swap marker is eating the
room.

The other weapon set: a row of its abilities above the skill bar, always there rather than only
while a timer runs on one slot, following the skill bar wherever you put it, with its own size and
gap. It hides itself while you cannot swap weapons at all -- the Oakensoul Ring, or a character
that has not earned the second set yet.

Countdown and target count, on both sets: how long is left on each ability's effect (gold, under
the icon) and how many targets are under it (white, in the corner), each with its own text size
from 12 to 48. The countdown is the game's own number -- the same one its action bar timers use,
and it answers for the set you are not on as well. The target count has no API behind it and is
counted from the effects you apply, matched by the ability's name.

If the game is already drawing its own number on the bar you are on (Settings > Interface > Action
Bar Timers) -- at a size no add-on can change -- the default setting fades that one out of the way
and draws this add-on's instead, so the text size you pick always applies.

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
