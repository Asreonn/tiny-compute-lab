// Tiny Compute Lab — SYSTEMS EXPANSION V1 geometry reference (LOCKED 2026-09-24)
// ------------------------------------------------------------------------------------------------
// Source: the Penpot drawers that produced pages 15–19 ("15 Systems · Infrastructure",
// "16 Systems · Machines", "17 Systems · VFX Language", "18 Systems · Interaction",
// "19 Systems · Gameplay Mockups"). The same source is stored in the Penpot file
// (shared plugin data "tcl" / lib…lib7) so the boards can be regenerated.
//
// This file is the implementation reference for Godot, exactly like signal_system_v1.js is for
// wires: port these drawers to GDScript `_draw()` code 1:1. Units are machine-local px at
// 1 tile = 64 px, unrotated. Colours are token names from core/visual/palette.gd
// (`L.C("family.io")` = Palette.FAMILY_IO etc.). `op` = node opacity, `so`/`fo` = stroke/fill alpha.
// rect({x,y,w,h,r,fill,stroke,sw}) · ellipse({x,y,w[,h]}) (x,y = top-left of the bounding box).
//
// Superseded designs (NOT to implement): USB stick V1–V3, USB connection options A/B,
// cartridge V2, the 18 px LED glow disc, 32 px port halo, packet halo, whole-body processing glow.
// ------------------------------------------------------------------------------------------------

// ================================ VFX LADDER (hard limits) ======================================
// L0 idle        nothing moves / glows
// L1 routine     packet travel · port contact · wire core segment   size ≤ 1 px ring / 2.5 px core  α ≤ 0.6  ≤ 120 ms
// L2 processing  function region only (ring, lane, valve, bays, LED) α ≤ 0.9  for the job
// L3 selection   1.5 px outline + canonical corner brackets         α 1.0    static
// L4 warning     amber: LED, thermal strip, 1.5 px underline/badge  ≤ 2 px   slow pulse ≥ 1.2 s (strip only)
// L5 critical    error · overload · critical heat · contract done   ≤ 2 px frame + badge, ≤ 2 pulses then steady
// No blobs, no halos, no bloom, no body tint for routine work.

// ================================ PORT CONTACT (L1) =============================================
// Canonical port (24x24) with the restrained Active state: no halo. Packet entering/leaving:
//   t 0 → 40 ms: "Contact": 1 px ring ellipse(x2,y2,w20) stroke text.primary op .8, core white
//   40 → 80 ms : "Active" : same ring in the datatype colour op .55, core text.primary
//   80 → 120 ms: back to "Connected"
drawPort = (b, dir, dt, st) => {
  const col = dt === "Number" ? "data.number" : "data.boolean", dim = dt === "Number" ? "data.number-dim" : "data.boolean-dim";
  let ring = col, core = null, pad = "material.copper-dim", chev = dim, contact = null;
  switch (st) {
    case "Idle": ring = dim; break;
    case "Connected": core = col; chev = col; break;
    case "Active": core = "text.primary"; chev = col; contact = col; break;
    case "Contact": core = "text.primary"; chev = col; contact = "text.primary"; break;
  }
  const isOut = dir === "Output";
  rect({ x: isOut ? 21 : 0, y: 11, w: 3, h: 2, fill: pad });                       // lead
  rect({ x: 3, y: 3, w: 18, h: 18, r: 4, fill: pad });                            // contact pad
  if (contact) ellipse({ x: 2, y: 2, w: 20, stroke: contact, sw: 1, op: st === "Contact" ? 0.8 : 0.55 });
  ellipse({ x: 5, y: 5, w: 14, fill: isOut ? ring : "material.die", stroke: ring, sw: 2.5 });  // body
  ellipse({ x: 9.5, y: 9.5, w: 5, fill: isOut ? "material.die" : (core || "material.vent") }); // core
  path("M1 1 L5 5 L1 9", { x: isOut ? 26 : -9, y: 7, stroke: chev, sw: 2 });                 // flow chevron
};
// Packet (Normal zoom) — NO halo. Wire behind it: a brighter core segment (α .9, 2.5 px) ~30 px long.
packet = (cx, cy) => {
  rect({ x: cx - 9, y: cy - 5, w: 18, h: 10, r: 3, fill: "material.die", stroke: "data.number", sw: 1.5 });
  rect({ x: cx - 11, y: cy - 3, w: 3, h: 6, r: 1, fill: "data.number" });
  rect({ x: cx + 8, y: cy - 3, w: 3, h: 6, r: 1, fill: "data.number" });
  rect({ x: cx - 4, y: cy - 1.5, w: 8, h: 3, r: 1, fill: "data.number" });
};
// Wire (unchanged Signal System V1): trench edge board.pad-edge 10 px, trench material.vent 8 px,
// core datatype colour 2.5 px α .5; active segment α .9. Raw links: same with core family.io α .35.

// ================================ STATUS LED V2 (12x12, top-right) ==============================
// Replaces led_*.svg. No glow disc in any state. Colour AND form carry meaning.
const LED = { Off: ["machine.rail", 0], Idle: ["text.muted", 0], Receiving: ["data.number", 1], Processing: ["state.build", 1],
  OutputReady: ["state.valid", 1], Blocked: ["state.blocked", 1] /* shown as "Waiting" */, Throttling: ["state.blocked", 1],
  Overheated: ["state.error", 1], Error: ["state.error", 1] };
led = (st) => {
  ellipse({ x: 1, y: 1, w: 10, fill: "material.vent", stroke: "material.frame", sw: 0.75 });          // well
  const [tok, spec] = LED[st];
  if (st === "Error") rect({ x: 3.5, y: 3.5, w: 5, h: 5, r: 0.5, fill: tok, rot: 45 });               // red DIAMOND
  else ellipse({ x: 3, y: 3, w: 6, fill: tok, op: st === "Idle" ? 0.8 : 1 });                        // lamp
  if (st === "Throttling" || st === "Overheated") ellipse({ x: -1, y: -1, w: 14, stroke: tok, sw: 1, op: 0.9 }); // ring
  if (spec) ellipse({ x: 4.5, y: 4, w: 1.5, fill: "text.primary", op: 0.55 });                         // specular
};

// ================================ RESOURCE INDICATORS ===========================================
// Replace the "⏱4 ⚡1" silk text. M/L: bottom-right, right edge at (w-20), y = h-15. S: compact at top-right (58, 4).
// clock = silk dots (one per tick of job cost, max 6, then a '+'), power = gold pips (max 4).
// Clock mode: fast = 1 amber chevron, overclocked = 2, drawn before the dots.
RI = (xr, y, ticks, power, mode = "normal") => {
  const dots = Math.min(ticks, 6), plusT = ticks > 6, pips = Math.min(power, 4), chev = mode === "fast" ? 1 : mode === "overclocked" ? 2 : 0;
  const w = chev * 6 + (chev ? 2 : 0) + dots * 6 + (plusT ? 4 : 0) + 6 + (power > 0 ? pips * 5 : 5);
  let x = xr - w;
  for (let i = 0; i < chev; i++) { path("M1 1 L4 4 L1 7", { x, y, stroke: "state.blocked", sw: 1.5 }); x += 6; } if (chev) x += 2;
  for (let i = 0; i < dots; i++) { ellipse({ x, y: y + 1.5, w: 5, fill: "material.silk", op: 0.7 }); x += 6; }
  if (plusT) { rect({ x, y: y + 3.5, w: 3, h: 1, fill: "material.silk", op: 0.7 }); rect({ x: x + 1, y: y + 2.5, w: 1, h: 3, fill: "material.silk", op: 0.7 }); x += 4; }
  x += 3; rect({ x, y: y + 1, w: 1, h: 6, fill: "material.silk", op: 0.25 }); x += 3;                // divider
  if (power === 0) rect({ x, y: y + 1, w: 3, h: 6, r: 0.5, stroke: "material.silk", sw: 0.75, op: 0.35 });
  for (let i = 0; i < pips; i++) { rect({ x, y, w: 3, h: 8, r: 0.5, fill: "material.gold", op: 0.9 }); x += 5; }
};
RIs = (xr, y, ticks, power) => { // S-size machines
  const dots = Math.min(ticks, 6), pips = Math.min(power, 4); let x = xr - (dots * 4 + 5 + pips * 3.5);
  for (let i = 0; i < dots; i++) { ellipse({ x, y: y + 1.5, w: 3, fill: "material.silk", op: 0.7 }); x += 4; }
  x += 2; rect({ x, y: y + 1, w: 1, h: 4, fill: "material.silk", op: 0.25 }); x += 3;
  for (let i = 0; i < pips; i++) { rect({ x, y, w: 2, h: 6, r: 0.5, fill: "material.gold", op: 0.9 }); x += 3.5; }
};
// Progress (Add/Modulo): arc r 22 around the dial centre (38, 32), 2 px data.number, round caps, from 12 o'clock clockwise.
// Thermal strip: rect({ x: 8, y: 3, w: width-16, h: 2, r: 1 }) — WARM state.blocked op .3 · HOT state.blocked ·
//   THROTTLING state.blocked + LED Throttling + slow pulse (≥ 1.2 s, strip opacity .35↔1) · CRITICAL state.error +
//   1.5 px state.error frame (inset .75, r 7) + pause badge 16x16 r3 state.error at (w-12, -10) with two 2x8 text.inverse bars.
// Output blocked (L4): 1.5 px state.blocked underline at (8, h-6, w-16).

// ================================ RAW BOUNDARY ==================================================
// Raw = IO green (family.io). Raw ports only connect to raw ports.
rawPort = (dir, st) => { // 24x24, st: Idle | Connected | Active
  const isOut = dir === "Output", lit = st !== "Idle";
  rect({ x: isOut ? 21 : 0, y: 11, w: 3, h: 2, fill: "material.copper-dim" });
  rect({ x: 3, y: 3, w: 18, h: 18, r: 4, fill: "material.copper-dim" });
  if (st === "Active") rect({ x: 1.5, y: 1.5, w: 21, h: 21, r: 5, stroke: "family.io", sw: 1, op: 0.6 });   // contact ring (L1)
  rect({ x: 5, y: 7, w: 14, h: 10, r: 2, fill: "material.die", stroke: "family.io", sw: 2, op: lit ? 1 : 0.45 });
  rect({ x: 8, y: isOut ? 11.5 : 9.5, w: 8, h: 3, r: 1, fill: st === "Active" ? "text.primary" : "family.io", op: lit ? 1 : 0.45 });
  path("M1 1 L5 5 L1 9", { x: isOut ? 26 : -9, y: 7, stroke: "family.io", sw: 2, op: lit ? 1 : 0.45 });
};
rawToken = (zoom, st, glyph) => { // pill; NO halo. zoom Normal 24x16 (body 20x12, glyph 8 px) · Close 40x22 (36x18, 11 px) · Far 16x16 (dot 8x8 filled)
  const [W, H, bw, bh, fs] = { Normal: [24, 16, 20, 12, 8], Close: [40, 22, 36, 18, 11], Far: [16, 16, 8, 8, 0] }[zoom];
  const ox = (W - bw) / 2, oy = (H - bh) / 2;
  if (st === "Queued") rect({ x: ox - 2, y: oy - 2, w: bw + 4, h: bh + 4, r: (bh + 4) / 2, stroke: "family.io", sw: 1, dash: true, op: 0.5 });
  if (st === "Accepted") rect({ x: ox - 2, y: oy - 2, w: bw + 4, h: bh + 4, r: (bh + 4) / 2, stroke: "state.valid", sw: 1, op: 0.9 });
  rect({ x: ox, y: oy, w: bw, h: bh, r: bh / 2, fill: zoom === "Far" ? "family.io" : "material.die", stroke: "family.io", sw: zoom === "Close" ? 1.5 : 1.25 });
  if (zoom !== "Far") text(glyph, { centred in the body, size: fs, weight: 800, color: "family.io" });
  // Absorbing (entering an encoder): whole token op .45
};

// ================================ USB FAMILY (final · option C) =================================
// The locked USB Input (EdgeIn) / Output (EdgeOut) components are UNCHANGED. A female USB-A PORT FACE is set into
// their edge; devices are DATA MODULES (96x56) with a male USB-A plug.
portFace = (x, y, plugged, lit, flip) => { // 16x36; input: (-6, 14) · output (contract drive): (118, 14, flip)
  rect({ x, y, w: 16, h: 36, r: 2, fill: "machine.frame-hover", stroke: "material.silk", sw: 1, so: 0.45 });      // frame
  rect({ x: x + 2.5, y: y + 2.5, w: 11, h: 31, r: 1, fill: plugged ? "material.plate-hi" : "material.vent" });   // opening (plug fills it)
  const tx = flip ? x + 3.5 : x + 7.5;
  rect({ x: tx, y: y + 4, w: 5, h: 28, r: 1, fill: "material.plate-lo", stroke: "machine.frame", sw: 0.5 });      // tongue
  for (let i = 0; i < 4; i++) rect({ x: flip ? tx + 2.5 : tx, y: y + 7 + i * 6.5, w: 2.5, h: 4, fill: "material.gold", op: plugged ? 0.5 : 0.95 });
  if (lit) rect({ x: flip ? x + 16 : x - 1.5, y: y + 3, w: 1.5, h: 30, fill: "text.primary", op: 0.55 });         // contact seam (L1)
};
const MOD = {
  bit:    { glyph: "010", acc: "data.number", out: "bits", end: "square" },   // emits pre-encoded bits (BusPort + WidthTag)
  number: { glyph: "42",  acc: "family.io",   out: "raw",  end: "chamfer" },
  text:   { glyph: "Aa",  acc: "family.io",   out: "raw",  end: "round" },
  key:    { glyph: "K#",  acc: "family.io",   out: "raw",  end: "notch" },
  sensor: { glyph: "∿",   acc: "family.io",   out: "raw",  end: "fins" },
  job:    { glyph: "<target>", acc: "family.io | data.number (bits contract)", end: "slant" },  // contract drive, flipped
};
modPath = (end) => ({ // outer end at x=0, docking face at x=96
  square: "M5 0 H96 V56 H5 Q0 56 0 51 V5 Q0 0 5 0 Z",
  chamfer: "M12 0 H96 V56 H12 L0 44 V12 Z",
  round: "M24 0 H96 V56 H24 C10.7 56 0 45.3 0 32 V24 C0 10.7 10.7 0 24 0 Z",
  notch: "M5 0 H96 V56 H5 Q0 56 0 51 V36 H7 V20 H0 V5 Q0 0 5 0 Z",
  fins: "M10 0 H96 V56 H10 Q5 56 5 51 V5 Q5 0 10 0 Z",
  slant: "M16 0 H96 V56 H0 V16 Z",
}[end]);
malePlug = (x, y, flip) => { // 22x28 metal shell, two square holes, dark collar line at the body side
  rect({ x, y, w: 22, h: 28, r: 1.5, fill: "machine.frame-hover", stroke: "material.silk", sw: 1, so: 0.35 });
  const hx = flip ? x + 13 : x + 4;
  rect({ x: hx, y: y + 6, w: 5, h: 5, r: 0.5, fill: "material.vent" }); rect({ x: hx, y: y + 17, w: 5, h: 5, r: 0.5, fill: "material.vent" });
  rect({ x: flip ? x : x + 20, y, w: 2, h: 28, fill: "material.vent", op: 0.6 });
};
dataModule = (kind, o) => { // 96x56. o.flip (plug on the west, contract drive), o.inserted (plug hidden), o.ghost,
                            // o.cursor = index 0..29 of the lit block (source), o.fill = 0..1 (contract progress)
  const m = MOD[kind], flip = !!o.flip, X = (px, w) => flip ? 96 - px - w : px;
  if (!o.inserted && !o.ghost) malePlug(flip ? -22 : 96, 14, !flip);
  path(modPath(m.end), { flipX: flip, fill: o.ghost ? null : "material.plate", stroke: o.ghost ? "state.hover" : "machine.frame", sw: o.ghost ? 1 : 1.5 });
  if (o.ghost) { rect({ x: flip ? -22 : 96, y: 14, w: 22, h: 28, r: 1.5, stroke: "state.hover", sw: 1, op: 0.8 }); return; }
  rect({ x: X(16, 60), y: 2, w: 60, h: 1, fill: "material.plate-hi" });                                  // bevel
  rect({ x: X(16, 22), y: 6, w: 22, h: 3, r: 1, fill: m.acc });                                         // family key bar
  rect({ x: X(16, 48), y: 12, w: 48, h: 18, r: 3, fill: "machine.screen", stroke: "material.frame", sw: 1 });  // window
  text(m.glyph, { box: [X(16, 48), 13, 48, 16], size: m.glyph.length > 2 ? 11 : 13, weight: 800, color: m.acc });
  for (let r = 0; r < 3; r++) for (let c = 0; c < 10; c++) {                                             // 10x3 data store
    const idx = r * 10 + c; let tok = "material.plate-hi", op = 1;
    if (o.fill != null) { if (idx < Math.round(o.fill * 30)) tok = o.fill >= 1 ? "state.success" : m.acc; }
    else { tok = m.acc; op = o.cursor === idx ? 1 : 0.28; }
    rect({ x: X(16 + c * 7, 5), y: 34 + r * 6, w: 5, h: 4, r: 0.5, fill: tok, op });
  }
  rect({ x: X(88, 8), y: 10, w: 8, h: 36, r: 1, fill: "material.plate-hi", stroke: "machine.frame", sw: 1 });  // plug collar
  if (m.end === "fins") for (const fy of [10, 38]) rect({ x: X(0, 6), y: fy, w: 6, h: 8, r: 1, fill: "material.plate-hi", stroke: "machine.frame", sw: 1 });
  if (m.end === "square") for (let i = 0; i < 3; i++) rect({ x: X(5 + i * 3, 1), y: 16, w: 1, h: 24, fill: "material.frame" });
};
// Socket states (USB Input host at its own origin; module y = 4):
//   Empty     portFace(-6,14,false) · Feed area op .45 · LED Off · output port Idle (raw port when no module)
//   Hover     + ghost module at x -128 + port hover outline rect(-8,12,20,40,r3, stroke state.hover 1 px, op .8)
//   Inserting module at x -146 (plug visible) + two 22x1 state.build guides at (-28,14) and (-28,49) op .7
//   Plugged   portFace plugged · module inserted at x -102 · LED Idle
//   Active    + contact seam · module cursor walks the store (one block per value read) · LED Receiving
//   Removing  module at x -150, op .5
//   Bit module → BusPort + WidthTag (width text = module width); raw modules → rawPort + IO-green Feed capsules.
// Contract drive (Output host): portFace(118,14,…,flip) · job module flipped at x 134 · o.fill = accepted/required
//   Empty (no module, area op .45, LED Off) · Idle · Writing (LED Receiving + seam text.primary .55) ·
//   Accepted (seam state.valid .9, LED OutputReady) · Rejected (seam + 80x1.5 underline state.blocked, LED Blocked) ·
//   Complete (store state.success + 1.5 px frame state.success around the module (132,2,100,60,r6))

// ================================ ENCODER / DECODER =============================================
// M Module chassis, FamilyTab conversion at (16,10). Encoder: raw in (W) → bits out (E). Decoder mirrors.
codec = (kind, st, glyph, width) => { // st: Idle | Absorbing | Active (encoder) · Emitting (decoder)
  const enc = kind.endsWith("Encoder");
  const slotX = enc ? 14 : 88, bitsX = enc ? 58 : 16, chevX = enc ? 45 : 75;
  rect({ x: slotX, y: 23, w: 26, h: 18, r: 9, fill: "machine.screen", stroke: "family.io", sw: 1, so: 0.55 });  // token slot
  if (st !== "Idle") text(glyph, { box: [slotX, 24, 26, 16], size: glyph.length > 1 ? 10 : 12, weight: 800, color: "family.io", op: st === "Absorbing" ? 0.5 : 1 });
  path("M1 1 L5 5 L1 9", { x: chevX, y: 27, stroke: "material.silk", sw: 1.5, op: 0.5 });
  activityArea("Bits", st === "Idle" ? "Idle" : "Active", bitsX, 25);                                     // existing asset
  silkText(kind.startsWith("Char") ? "CHR" : "NUM", 16, 47);
  statusLed(st === "Idle" ? "Idle" : "Processing", 110, 6);
  RI(92, 50, 2, 1); widthTag(width, 98, 46);
  rawPort(enc ? "Input" : "Output", "Connected") /* at (enc ? -12 : 116, 20) */; busPort(enc ? "Output" : "Input") /* at (enc ? 116 : -12, 20) */;
};

// ================================ PSU / POWER ===================================================
// M Module chassis, gold power tab (16,8,24x3), icon_power at (14,18), gauge at (40,18,72 wide), silk "PSU · <cap>" (16,47).
// LED: Idle / Blocked (≥ 75 %) / Error (> 100 %). Tiers: 8 · 16 (2 rows) · 32 · 64 (L chassis, 4 / 8 rows).
gauge = (x, y, w, cap, used, rows) => {
  const per = Math.ceil(cap / rows), cw = (w - 6 - (per - 1) * 2) / per;
  const over = used > cap, near = !over && used / cap >= 0.75, lit = over ? "state.error" : near ? "state.blocked" : "material.gold";
  rect({ x, y, w, h: rows * 9 + 6, r: 3, fill: "machine.screen", stroke: "material.frame", sw: 1 });
  for (let i = 0; i < cap; i++) { const r = Math.floor(i / per), c = i % per; rect({ x: x + 3 + c * (cw + 2), y: y + 3 + r * 9, w: cw, h: 7, r: 1, fill: i < used ? lit : "material.plate-lo" }); }
  if (over) path("M1 1 L5 5 L1 9 M7 1 L11 5 L7 9", { x: x + w + 4, y: y + (rows * 9 + 6) / 2 - 5, stroke: "state.error", sw: 2 });
};

// ================================ THERMAL FAMILY (board-level copper hardware) ==================
// NOT machines: no chassis, no data ports, no LED. Copper = heat. Warmth = faint amber gradient only.
footprint = (w, h) => {
  rect({ x: 2, y: 2, w: w - 4, h: h - 4, r: 4, fill: "board.pad", stroke: "material.copper-dim", sw: 1 });
  path(`M2 8 V2 H8 M${w - 8} 2 H${w - 2} V8 M${w - 2} ${h - 8} V${h - 2} H${w - 8} M8 ${h - 2} H2 V${h - 8}`, { stroke: "board.silk", sw: 1.5 });
};
const WARMTH = { Cool: 0, Warm: 0.3, Hot: 0.75 };
heatsink = (st) => { // S 64x64, passive, r1
  footprint(64, 64);
  rect({ x: 7, y: 7, w: 50, h: 50, r: 3, fill: "material.copper-dim", stroke: "material.copper", sw: 1, so: 0.7 });
  for (let i = 0; i < 11; i++) { rect({ x: 12 + i * 4, y: 11, w: 2, h: 42, r: 0.6, fill: "material.plate-hi" }); rect({ x: 12 + i * 4, y: 11, w: 2, h: 1.2, fill: "material.copper", fo: 0.8 }); }
  if (WARMTH[st]) linearGradientRect({ x: 11, y: 11, w: 44, h: 42, color: "state.blocked", from: WARMTH[st], to: 0, stop: 0.45, dir: "down" });
  for (const [sx, sy] of [[9, 9], [51, 9], [9, 51], [51, 51]]) ellipse({ x: sx, y: sy, w: 4, fill: "material.frame", stroke: "material.vent", sw: 0.5 });
};
blower = (st) => { // S 64x64, active (2 power), r2. st: Idle | Running | HighLoad. The impeller ROTATES in Godot while running.
  footprint(64, 64);
  path("M30 8 A23 23 0 1 0 53 31 L53 18 L58 18 L58 8 Z", { fill: "machine.screen", stroke: "material.frame", sw: 1.5 });  // volute
  rect({ x: 53, y: 8, w: 5, h: 10, fill: "material.copper-dim" });                                                 // outlet lip
  const run = st !== "Idle";
  for (let i = 0; i < 18; i++) { const a = i / 18 * 2 * Math.PI, a2 = a + 0.35;                                // impeller blades
    line([30 + 7 * Math.cos(a), 31 + 7 * Math.sin(a)], [30 + 16 * Math.cos(a2), 31 + 16 * Math.sin(a2)], { stroke: "material.silk", so: run ? 0.4 : 0.6, sw: 1.2, cap: "round" }); }
  ellipse({ x: 24, y: 25, w: 12, fill: "material.plate-hi", stroke: "material.copper", sw: 1, so: 0.8 });          // hub
  if (run) for (let i = 0; i < (st === "HighLoad" ? 3 : 2); i++) line([60, 10 + i * 3], [70 + i * 2, 10 + i * 3], { stroke: "material.silk", so: 0.35, sw: 1 }); // airflow
  for (let i = 0; i < 3; i++) rect({ x: 8 + i * 4, y: 55, w: 2, h: 3, fill: "material.gold", op: run ? 0.95 : 0.6 });   // 3-pin power header
};
heatPipe = (pts, heat) => { // placed per tile but drawn as one routed conduit; chamfered corners like traces
  polyline(pts, { stroke: "material.vent", sw: 12 });
  polyline(pts, { stroke: "material.copper-dim", sw: 9 });
  polyline(pts, { stroke: "material.copper", sw: 2.5, so: 0.85 });
  polyline(pts.map(p => [p[0], p[1] - 2.5]), { stroke: "material.gold", sw: 0.8, so: 0.35 });                     // highlight
  if (heat) polylineGradient(pts, { color: "state.blocked", from: heat, to: 0, stop: 0.6, sw: 3 });              // warmth from the hot end
  for (const e of [pts[0], pts[pts.length - 1]]) {                                                                 // square thermal pads
    rect({ x: e[0] - 8, y: e[1] - 8, w: 16, h: 16, r: 3, fill: "material.copper-dim", stroke: "material.copper", sw: 1.2 });
    ellipse({ x: e[0] - 3, y: e[1] - 3, w: 6, fill: "material.copper", op: 0.9 });
  }
  // HEAT PIPE ≠ DATA WIRE: copper only (never teal/pink/IO green) · 9 px body · square pads, never ports ·
  // occupies tiles: wires and heat pipes never share or cross a tile · no packets, no comets.
};
radiator = (st) => { // L 128x128, edge panel, r2
  footprint(128, 128);
  rect({ x: 10, y: 22, w: 108, h: 84, r: 2, fill: "machine.screen", stroke: "material.frame", sw: 1 });
  for (let i = 0; i < 26; i++) rect({ x: 13 + i * 4, y: 24, w: 1.6, h: 80, fill: "material.plate-hi" });
  if (WARMTH[st]) linearGradientRect({ x: 12, y: 24, w: 104, h: 80, color: "state.blocked", from: WARMTH[st] * 0.8, to: 0, stop: 0.35, dir: "down" });
  for (const my of [12, 106]) rect({ x: 8, y: my, w: 112, h: 10, r: 3, fill: "material.copper-dim", stroke: "material.copper", sw: 1, so: 0.8 }); // manifolds
  for (const ix of [20, 44]) { ellipse({ x: ix, y: 10, w: 12, fill: "material.copper", stroke: "material.vent", sw: 1 }); ellipse({ x: ix + 3.5, y: 13.5, w: 5, fill: "material.vent" }); }
  for (const [bx, by] of [[2, 2], [118, 2], [2, 118], [118, 118]]) rect({ x: bx, y: by, w: 8, h: 8, r: 2, fill: "material.frame" });
};

// ================================ OVERLAYS ======================================================
// THERMAL (T): per tile rect(x*64+2, y*64+2, 60, 60, r4). WARM state.blocked α .12 · HOT α .26 · THROTTLING α .42 ·
//   CRITICAL state.error α .38. Machines drawn at op .55 above it. Cooling coverage = Chebyshev squares, dashed
//   material.copper 1 px op .7 with a 9 px label ("blower r2"). Heat-pipe flow = 6x10 material.gold chevrons op .8.
//   Legend panel (264x64) top-right. At most one overlay at a time.
// POWER (P): PSU gauge enlarged in the legend; per-machine demand badge = its RI power pips on a surface.sunken chip;
//   overloaded: gauge red + overflow chevrons; all machines' work is scaled (brownout) — no per-machine red.

// ================================ INTERACTION (page 18) =========================================
// Hover card: panel 232x150 (surface.panel, border-strong, r8, canonical tooltip shadow) at pointer +16/−16, clamped;
//   appears after 180 ms (α 0→1 over 120 ms, +4 px rise), follows the pointer, hidden during drag/place/wire.
//   Rows: family chip + name + function · state chip · POWER · CLOCK · TEMP (amber when ≥ WARM) · PORTS; RI top-right.
// Quick action bar: panel 176x36, 8 px below the selection brackets: Move · Duplicate · Rotate · Copy settings | Delete.
//   Buttons 32x28, hover = surface.raised + border-strong; Delete hover = state.error icon + state.error border α .6;
//   label tooltip below with the shortcut.
// Smart wiring: preview = trench material.vent α .6 8 px + 2.5 px state.build dashed (6/5); valid = state.valid solid;
//   candidate port = 12 px state.valid ring 1.5 px; edge zone 16 px.
// Connected move: origin ghost = dashed state.hover outline α .6; hologram machine op .6 on InstallPad PlaceValid /
//   PlaceInvalid; routes previewed per wire; failed route = state.error dashes + 12 px X at the failing cell.
