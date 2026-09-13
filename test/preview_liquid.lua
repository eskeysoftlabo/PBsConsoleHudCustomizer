-- Renders the Liquid style offline, so its look can be judged before a PS5 round.
--
--   lua test/preview_liquid.lua out.html
--
-- Runs the add-on in the harness with the console's 64-high status bars, plays five seconds
-- of a fight (a hit on health, a potion on magicka, a dodge roll's worth of stamina), and writes
-- every frame's controls -- position, size and colour, exactly as the add-on wrote them -- into
-- one HTML page that plays them back on a canvas. The game's own fill art is not available, so
-- it is drawn as its gradient in the 17-pixel band the art occupies; everything else on screen is
-- what the add-on itself produced.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/") or ".")
ADDON_DIR = HERE .. "/.."
dofile(HERE .. "/harness.lua")
local out = arg[1] or "liquid_preview.html"

BuildAttributeBars()
Fire(EVENT_ADD_ON_LOADED, "PBsConsoleHudCustomizer")
Fire(EVENT_PLAYER_ACTIVATED)
local addon = PBS_CONSOLE_HUD_CUSTOMIZER
addon:Account().enabled = true
addon:SetBarStyle("liquidflow")
SetPower(COMBAT_MECHANIC_FLAGS_HEALTH, 800, 1000)
SetPower(COMBAT_MECHANIC_FLAGS_MAGICKA, 880, 1000)
SetPower(COMBAT_MECHANIC_FLAGS_STAMINA, 900, 1000)
FireHud(SCENE_FRAGMENT_SHOWN)
addon:Refresh()

local FRAMES, STEP = 100, 50
local events = {
	[30] = function() SetPower(COMBAT_MECHANIC_FLAGS_HEALTH, 450, 1000) end,
	[75] = function() SetPower(COMBAT_MECHANIC_FLAGS_STAMINA, 600, 1000) end,
}
-- Magicka regenerates up to full the whole time: the moving end spends it near the full end,
-- which is where an upright surface used to stand out.
local magicka = 880
local function Regenerate()
	if magicka < 1000 then
		magicka = math.min(1000, magicka + 2)
		SetPower(COMBAT_MECHANIC_FLAGS_MAGICKA, magicka, 1000)
	end
end

local function Visible(control, stop)
	while control and control ~= stop do
		if control.hidden then return false end
		control = control.parent
	end
	return control == stop and not stop.hidden
end

-- Every add-on control is anchored TOPLEFT to its parent, so its place is the sum of offsets.
local function Offset(control, stop)
	local x, y = 0, 0
	while control and control ~= stop do
		local a = control.anchors[1]
		if a then x, y = x + a.offsetX, y + a.offsetY end
		control = control.parent
	end
	return x, y
end

local function Num(v) return string.format("%.3f", v or 0) end

local frames = {}
for frame = 1, FRAMES do
	if events[frame] then events[frame]() end
	Regenerate()
	AdvanceFrame(STEP)
	RunUpdates()
	local bars = {}
	for _, bar in ipairs(addon.plain.bars) do
		for index, entry in ipairs(bar.controls) do
			local native = _G[entry.name]
			local group = addon.plain.liquidRibbons and addon.plain.liquidRibbons[entry.name]
			local rects = {}
			if group then
				local function Walk(control)
					for _, child in pairs(CreatedControls) do
						if child.parent == control then
							if Visible(child, group.control) and child.kind == "texture" and child.color then
								local x, y = Offset(child, group.control)
								local c = child.color
								local v = child.vertices or {}
								local parts = { Num(x), Num(y), Num(child.width), Num(child.height) }
								-- top left, top right, bottom left, bottom right
								for _, corner in ipairs({ 1, 2, 4, 8 }) do
									local k = v[corner] or c
									for i = 1, 4 do parts[#parts + 1] = Num(k[i]) end
								end
								rects[#rects + 1] = "[" .. table.concat(parts, ",") .. "]"
							end
							Walk(child)
						end
					end
				end
				Walk(group.control)
			end
			local g = native.gradient or {}
			bars[#bars + 1] = string.format('{"key":"%s","half":%d,"halves":%d,"reverse":%s,"w":%s,"h":%s,"fraction":%s,"grad":[%s],"rects":[%s]}',
				bar.key, index, #bar.controls, tostring(entry.reverse), Num(native.width), Num(native.height),
				Num(addon.plain:Fraction(bar)), table.concat({ Num(g[1]), Num(g[2]), Num(g[3]), Num(g[4]), Num(g[5]), Num(g[6]), Num(g[7]), Num(g[8]) }, ","),
				table.concat(rects, ","))
		end
	end
	frames[#frames + 1] = "[" .. table.concat(bars, ",") .. "]"
end

local html = [[
<title>Liquid preview</title>
<style>
body{background:#1b1d22;color:#ddd;font:13px system-ui;margin:0;padding:16px}
canvas{display:block;background:#2a2d33;border-radius:6px;max-width:100%}
p{margin:6px 0 12px}
</style>
<p>PB's ConsoleHudCustomizer - Liquid, rendered from the add-on's own writes (x4). Magicka regenerates from 88% to full, health is hit at 1.5s, stamina drops at 3.75s. <span id="t"></span></p>
<canvas id="c" width="1000" height="330"></canvas>
<script>
const FRAMES=]] .. "[" .. table.concat(frames, ",") .. "]" .. [[;
const S=4, STEP=]] .. STEP .. [[;
const ctx=document.getElementById('c').getContext('2d');
const rgba=(r,g,b,a)=>`rgba(${r*255|0},${g*255|0},${b*255|0},${a})`;
function drawBar(entries, ox, oy){
  // The band the art occupies: 17 of 64, centred.
  const h=entries[0].h, bandTop=(h-17)/2;
  const total=entries.reduce((a,e)=>a+e.w,0), T=(oy+bandTop)*S, B=(oy+bandTop+17)*S, M=(T+B)/2, P=8.5*S;
  const shape=()=>{ ctx.beginPath(); ctx.moveTo(ox*S,M); ctx.lineTo(ox*S+P,T); ctx.lineTo((ox+total)*S-P,T); ctx.lineTo((ox+total)*S,M); ctx.lineTo((ox+total)*S-P,B); ctx.lineTo(ox*S+P,B); ctx.closePath(); };
  // The game's own track and fill live inside its pointed shape; the add-on's pieces do not get
  // this clip, so anything of theirs outside the shape would show.
  ctx.save(); shape(); ctx.clip();
  let x=ox;
  for(const e of entries){
    const w=e.w;
    // track
    ctx.fillStyle='#0c0d10'; ctx.fillRect(x*S, (oy+bandTop)*S, w*S, 17*S);
    // native fill, its gradient along the bar
    const filled=w*e.fraction, fx=e.reverse? x+w-filled : x;
    const gr=ctx.createLinearGradient(fx*S,0,(fx+filled)*S,0);
    const c1=rgba(e.grad[0],e.grad[1],e.grad[2],e.grad[3]), c2=rgba(e.grad[4],e.grad[5],e.grad[6],e.grad[7]);
    gr.addColorStop(0,e.reverse?c2:c1); gr.addColorStop(1,e.reverse?c1:c2);
    ctx.fillStyle=gr; ctx.fillRect(fx*S,(oy+bandTop)*S,filled*S,17*S);
    x+=w;
  }
  ctx.restore();
  x=ox;
  for(const e of entries){
    const w=e.w;
    // the add-on's controls
    for(const r of e.rects){
      const [rx,ry,rw,rh]=r, tl=r.slice(4,8), tr=r.slice(8,12), bl=r.slice(12,16), br=r.slice(16,20);
      const same=[tr,bl,br].every(k=>k.every((v,i)=>v===tl[i]));
      if(same){ ctx.fillStyle=rgba(...tl); ctx.fillRect((x+rx)*S,(oy+ry)*S,rw*S,rh*S); continue; }
      // Per-corner colours, interpolated the way a textured quad is.
      const N=8, cw=rw/N, ch=rh/N;
      for(let i=0;i<N;i++) for(let j=0;j<N;j++){
        const u=(i+.5)/N, v=(j+.5)/N, c=[0,1,2,3].map(k=>(tl[k]*(1-u)+tr[k]*u)*(1-v)+(bl[k]*(1-u)+br[k]*u)*v);
        ctx.fillStyle=rgba(...c); const px=Math.round((x+rx+i*cw)*S), py=Math.round((oy+ry+j*ch)*S); ctx.fillRect(px,py,Math.round((x+rx+(i+1)*cw)*S)-px,Math.round((oy+ry+(j+1)*ch)*S)-py);
      }
    }
    x+=w;
  }
  // the game's frame, on its pointed shape
  ctx.strokeStyle='rgba(220,210,180,.7)'; ctx.lineWidth=2; shape(); ctx.stroke();
}
let f=0;
function tick(){
  const frame=FRAMES[f]; ctx.clearRect(0,0,1000,360);
  const by={}; for(const e of frame){(by[e.key]=by[e.key]||[]).push(e);}
  drawBar(by.magicka, 12, -20); drawBar(by.health, 12, 10); drawBar(by.stamina, 12, 40);
  document.getElementById('t').textContent=`t=${(f*STEP/1000).toFixed(2)}s`;
  f=(f+1)%FRAMES.length;
}
setInterval(tick,STEP); tick();
</script>
]]
local file = assert(io.open(out, "w"))
file:write(html)
file:close()
print("wrote " .. out .. " (" .. FRAMES .. " frames)")
