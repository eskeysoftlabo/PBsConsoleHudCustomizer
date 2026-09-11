local strings = {
	SI_PBSCHC_EXPLANATION = "HUDの体力・マジカ・スタミナバーの位置と大きさを変更します。ゲーム本体では3本とも画面下部の固定位置・固定サイズです。以下の項目はすべてゲーム本来の値から始まり、動かすまでは何も変更しません。このパネルを開いている間は、各バーの位置と大きさを色付きの枠で表示します。",

	SI_PBSCHC_ENABLED = "リソースバーを変更する",
	SI_PBSCHC_ENABLED_TOOLTIP = "以下の設定を適用します。オフにすると、3本ともすぐにゲーム本来の位置と大きさに戻します（設定内容は残るので、オンに戻せば再び適用されます）。",

	SI_PBSCHC_PREVIEW = "ここでプレビューを表示",
	SI_PBSCHC_PREVIEW_TOOLTIP = "バーはHUD上でしか描画されないため、このメニューからは見えません。オンの間は、各バーが表示される場所に、そのバーと同じ大きさの枠を表示します。",

	SI_PBSCHC_BAR_HEALTH = "体力",
	SI_PBSCHC_BAR_MAGICKA = "マジカ",
	SI_PBSCHC_BAR_STAMINA = "スタミナ",

	SI_PBSCHC_POSITION_X = "<<1>>：左右の位置",
	SI_PBSCHC_POSITION_X_TOOLTIP = "画面中央から、バーの中心までの左右の距離です。0でちょうど中央、マイナスで左、プラスで右へ移動します。",
	SI_PBSCHC_POSITION_Y = "<<1>>：高さ",
	SI_PBSCHC_POSITION_Y_TOOLTIP = "画面下端から、バーの中心までの高さです。ゲーム本来のバーは、スキルバーを避けて下から137の位置にあります。",

	SI_PBSCHC_SCALE = "<<1>>：大きさ",
	SI_PBSCHC_SCALE_TOOLTIP = "ゲーム本来の大きさを100%とした倍率です。枠・背景・バー・数値がすべて同じ比率で拡大縮小し、バーは中心の位置を保ったまま大きさだけが変わります。付属の小さいバー（マジカの上の狼、スタミナの下の騎乗スタミナ、体力の下の攻城兵器）も同じ倍率になります。",

	SI_PBSCHC_RESET_BAR = "<<1>>を初期設定に戻す",
	SI_PBSCHC_RESET_BAR_TOOLTIP = "このバーだけを、ゲーム本来の位置と大きさに戻します。",

	SI_PBSCHC_SECTION_GENERAL = "3本すべて",
	SI_PBSCHC_RESET = "すべて初期設定に戻す",
	SI_PBSCHC_RESET_TOOLTIP = "3本とも、ゲーム本来の位置と大きさに戻します。",
	SI_PBSCHC_RESET_BUTTON = "戻す",

	SI_PBSCHC_GAME_SETTINGS_HINT = "バーに数値を表示するか、戦闘していないときにバーを薄くするかはゲーム本体の設定です（設定 > インターフェース）。アドオンからは変更できないため、そちらで設定してください。",

	SI_PBSCHC_PREVIEW_CAPTION = "リソースバー（プレビュー）",
}

for stringId, stringValue in pairs(strings) do
	SafeAddString(_G[stringId], stringValue, 2)
end
