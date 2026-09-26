// Tiny Compute Lab — factory growth overhaul: exact Penpot geometry (2026-09-26).
//
// These are the Penpot plugin helpers that drew pages 21–25 (plugin data tcl/lib12–lib14), kept here
// as the reference for the Godot views (docs/VISUAL_SYSTEM.md §22, docs/STYLE_GUIDE.md §15). Port the
// numbers, not the API:
// - L.rect({x,y,w,h,r,fill,fo,stroke,sw,so}) is a rounded rect.
// - fo/so are the fill/stroke opacities.
// - Colours are design tokens (core/visual/palette.gd names, e.g. "material.gold" → Palette.MATERIAL_GOLD).
// - L.svg(...) paths are strokes along a polyline (Line2D / draw_polyline).
// - L.shell() is the canonical MachineShell composition every machine already uses in Godot
//   (install pad + shell art + family tab + StatusLED); only the family-tab colour differs:
//   gold (power) and copper (thermal).
// A tile is 64 px. Machine sizes are S 64×64, M 128×64 and L 128×128.

// ---------------------------------------------------------------- shared geometry
L.offPoly = (pts, off) => { // miter offset of a polyline (lanes, rails)
  if (!off) return pts.map(p => [p[0], p[1]]);
  const n = pts.length, out = [];
  const nrm = (a, b) => { const dx = b[0]-a[0], dy = b[1]-a[1], l = Math.hypot(dx, dy) || 1; return [-dy/l, dx/l]; };
  for (let i = 0; i < n; i++) {
    if (i === 0) { const m = nrm(pts[0], pts[1]); out.push([pts[0][0]+m[0]*off, pts[0][1]+m[1]*off]); continue; }
    if (i === n-1) { const m = nrm(pts[n-2], pts[n-1]); out.push([pts[i][0]+m[0]*off, pts[i][1]+m[1]*off]); continue; }
    const a = nrm(pts[i-1], pts[i]), b = nrm(pts[i], pts[i+1]);
    const s = [a[0]+b[0], a[1]+b[1]], sl = Math.hypot(s[0], s[1]) || 1, u = [s[0]/sl, s[1]/sl];
    const cos = u[0]*a[0] + u[1]*a[1], k = off / Math.max(cos, 0.3);
    out.push([pts[i][0]+u[0]*k, pts[i][1]+u[1]*k]);
  }
  return out;
};
L.chamfer = (pts, r) => { if (pts.length < 3) return pts; const out = [pts[0]];
  for (let i = 1; i < pts.length-1; i++) { const a = pts[i-1], b = pts[i], c = pts[i+1];
    const d1 = Math.hypot(b[0]-a[0], b[1]-a[1]), d2 = Math.hypot(c[0]-b[0], c[1]-b[1]); const k = Math.min(r, d1/2, d2/2);
    out.push([b[0]+(a[0]-b[0])/d1*k, b[1]+(a[1]-b[1])/d1*k]); out.push([b[0]+(c[0]-b[0])/d2*k, b[1]+(c[1]-b[1])/d2*k]); }
  out.push(pts[pts.length-1]); return out; };

// ---------------------------------------------------------------- DATA: bus classes × lanes (STYLE_GUIDE §15.1)
L.BUS = { trace: 8, byte: 12, wide: 16, backbone: 22 };   // trench width by class (from width)
L.LANE_T = { 1: 8, 2: 12, 4: 16, 8: 22 };                  // trench width by lanes; trench = max(class, lanes)
L.LANE_W = { 1: 2.5, 2: 2, 4: 1.4, 8: 1 };                 // core width per lane
// Layers, bottom → top:
//   1. selected halo: state.select α .14, width E + 8 (E = trench + 2)
//   2. edge: board.pad-edge, width E (saturated in the Data overlay: state.blocked α .65, width E + 1)
//   3. trench: material.vent (wide/backbone: bg.trace), width T
//   4. class rails (byte/wide/backbone): two lines at ±(T/2 − 1.25), machine.frame-hover α .9, 1.25 px
//   5. backbone only: cross-bands every 16 px along the path, material.frame α .45, 1 px, span T − 3
//   6. lane cores: one per lane at offsets (k − (lanes−1)/2) × gap, where span = T − 5,
//      gap = span / (lanes − 1) (× 0.55 when lanes = 2); colour data.number (raw links family.io);
//      α .55 (idle .30, selected .80); width LANE_W
//   7. lane beads (lanes > 1): a tail of 26 px (18 px when lanes > 2) at α .35, width LANE_W + 1;
//      a head of 9 × 3.6 px (6 × 2.4 when lanes > 2) in text.primary with a data-colour centre
//      (width − 1.2)
// Chamfer: 14 on a 1-lane trace, 18 on every bus.
// Bus tag: `8b ×4` in a sunken 14 px-high chip, 9 px text, border surface.border-strong (amber when
// saturated).

// ---------------------------------------------------------------- COMPUTE: lane slices (STYLE_GUIDE §15.2)
L.laneSlices = (h, size, lanes, prog = [], fam = "math") => {
  if (lanes <= 1) return null;
  const acc = L.FAMC[fam] || "family.math";
  let g, geo;
  if (size === "S") { geo = { x: 45, y: 16, w: 6, h: 31, sw: 6, sh: 3, gap: 1, vert: true }; }
  else if (size === "L") { geo = { x: 64, y: 98, w: 54, h: 14, sw: 5, sh: 14, gap: 2 }; }
  else { geo = { x: 64, y: 44, w: 46, h: 10, sw: 4, sh: 10, gap: 2 }; }
  g = L.board({ parent: h, name: `LaneSlices / ${lanes}`, x: geo.x, y: geo.y, w: geo.w, h: geo.h, clip: false });
  for (let k = 0; k < lanes; k++) {
    const x = geo.vert ? 0 : k * (geo.sw + geo.gap), y = geo.vert ? geo.h - (k + 1) * geo.sh - k * geo.gap : 0;
    L.rect({ parent: g, x, y, w: geo.sw, h: geo.sh, r: 0.5, fill: "material.die", stroke: "machine.frame-hover", sw: 0.75, so: 0.8, name: `slice-${k}` });
    const p = prog[k];
    if (p != null && p > 0) {
      if (geo.vert) L.rect({ parent: g, x: 0.75, y: y + 0.75, w: Math.max(0.5, (geo.sw - 1.5) * p), h: geo.sh - 1.5, fill: acc, fo: 0.85, name: `fill-${k}` });
      else { const fh = (geo.sh - 1.5) * p; L.rect({ parent: g, x: x + 0.75, y: geo.sh - 0.75 - fh, w: geo.sw - 1.5, h: fh, fill: acc, fo: 0.85, name: `fill-${k}` }); }
    }
  }
  return g;
};
// Mk silk: "MK" + (1/2/3/4 for 1/2/4/8 lanes), 7 px, material.silk α .5, at (18, 53) on M, (16, 110) on L.

// ---------------------------------------------------------------- canonical sibling chassis (power / thermal)
L.shell = (parent, name, x, y, size, form = "Module", o = {}) => {
  const dims = { S: [64, 64], M: [128, 64], L: [128, 128] }[size];
  const h = L.board({ parent, name, x, y, w: dims[0], h: dims[1], clip: false });
  L.V("InstallPad", { State: o.pad || "Default", Size: size }, h, 0, 0); L.V("MachineShell", { Size: size, Form: form }, h, 0, 0);
  const tab = o.tab || "material.gold";                      // power: gold, thermal: material.copper
  const tp = { S: [12, 9], M: [70, 12], L: [16, 10] }[size];  // family tab 24×3, r1
  L.rect({ parent: h, x: tp[0], y: tp[1], w: 24, h: 3, r: 1, fill: tab, name: "family-tab" });
  if (o.led) L.V("StatusLED", { State: o.led }, h, size === "L" ? 108 : size === "M" ? 110 : 46, size === "L" ? 8 : 6);
  return h;
};
L.window = (parent, x, y, w, h, name = "function-window") => L.rect({ parent, x, y, w, h, r: 3, fill: "machine.screen", stroke: "material.frame", sw: 1, name });
// POWER terminal: square body, gold core (data ports are round teal, thermal sockets round copper)
L.pwrPort = (parent, cx, cy, o = {}) => { const g = L.board({ parent, name: "power-port", x: cx - 12, y: cy - 12, w: 24, h: 24, clip: false });
  L.rect({ parent: g, x: 3, y: 3, w: 18, h: 18, r: 4, fill: "material.copper-dim", name: "contact-pad" });
  L.rect({ parent: g, x: 5, y: 5, w: 14, h: 14, r: 2.5, fill: "material.die", stroke: "material.gold", sw: 2, so: o.dim ? 0.45 : 0.85, name: "body" });
  L.rect({ parent: g, x: 9.5, y: 9.5, w: 5, h: 5, r: 1, fill: "material.gold", fo: o.dim ? 0.4 : 0.9, name: "core" }); return g; };
// THERMAL socket: round body with a copper ring and a dark bore
L.thmPort = (parent, cx, cy, o = {}) => { const g = L.board({ parent, name: "thermal-port", x: cx - 12, y: cy - 12, w: 24, h: 24, clip: false });
  L.rect({ parent: g, x: 3, y: 3, w: 18, h: 18, r: 4, fill: "material.copper-dim", name: "contact-pad" });
  L.ellipse({ parent: g, x: 5, y: 5, w: 14, fill: "material.die", stroke: "material.copper", sw: 2, so: 0.9, name: "body" });
  L.ellipse({ parent: g, x: 9, y: 9, w: 6, fill: "material.vent", stroke: "material.copper", sw: 0.8, so: 0.6, name: "bore" }); return g; };
// Machine contacts (every chassis): thermal pickup (north edge) and power teeth (south edge)
L.thermalPickup2 = (h, o = {}) => { const cx = h.width === 128 && h.height === 128 ? 64 : 32;
  const g = L.board({ parent: h, name: "thermal-pickup", x: cx - 14, y: 2, w: 28, h: 7, clip: false });
  L.rect({ parent: g, x: 0, y: 0, w: 28, h: 7, r: 1.5, fill: "material.vent", stroke: "material.frame", sw: 0.75, name: "recess" });
  L.rect({ parent: g, x: 2, y: 1.5, w: 24, h: 4, r: 1, fill: "material.copper", fo: o.hot ? 0.95 : 0.75, name: "copper" });
  if (o.hot) L.rect({ parent: g, x: 2, y: 1.5, w: 24, h: 4, r: 1, fill: "state.blocked", fo: o.hot * 0.4, name: "warmth" }); return g; };
L.powerPads2 = (h, tapped = []) => { const n = Math.round(h.width / 64);
  for (let k = 0; k < n; k++) { const cx = 32 + k * 64, on = tapped.includes(k);
    const g = L.board({ parent: h, name: `power-contact-${k}`, x: cx - 8, y: h.height - 5, w: 16, h: 5, clip: false });
    for (let i = 0; i < 3; i++) L.rect({ parent: g, x: 1 + i * 5.5, y: 0, w: 3.5, h: 4, r: 0.5, fill: "material.gold", fo: on ? 0.95 : 0.4, name: "tooth" }); } };

// ---------------------------------------------------------------- POWER parts (STYLE_GUIDE §15.3)
L.vrm = (parent, x, y, o = {}) => { // power_controller, L Module; tier ctrl/basic/eff/hc = 12/32/32/96
  const tier = o.tier || "basic", nPh = { ctrl: 2, basic: 3, eff: 3, hc: 5 }[tier], cap = { ctrl: 12, basic: 32, eff: 32, hc: 96 }[tier];
  const names = { ctrl: "PWR CTRL", basic: "VRM", eff: "VRM·E", hc: "VRM·HC" };
  const h = L.shell(parent, `PowerController / ${names[tier]} ${cap}`, x, y, "L", "Module", { led: o.led || "Idle" });
  L.window(h, 16, 22, 96, 44, "phase-bank");
  const cw = (96 - 8 - (nPh - 1) * 4) / nPh;
  for (let i = 0; i < nPh; i++) { const px = 20 + i * (cw + 4); const load = (o.load ?? 0.5);   // load = node load / cap, 0..1
    L.rect({ parent: h, x: px, y: 26, w: cw, h: 36, r: 2, fill: "material.die", stroke: "material.frame", sw: 0.75, name: `phase-${i}` });
    L.rect({ parent: h, x: px + cw / 2 - 5, y: 30, w: 10, h: 10, r: 2.5, stroke: "material.copper", sw: 1, so: 0.7, name: "choke" });
    L.rect({ parent: h, x: px + 3, y: 58 - 14 * load, w: cw - 6, h: 14 * load, r: 1, fill: o.over ? "state.blocked" : "material.gold", fo: 0.55, name: "phase-load" }); }
  L.V("MiniDisplay", { Width: "W36" }, h, 16, 74); L.text({ parent: h, x: 16, y: 76, text: String(cap), size: 10, weight: 800, color: "data.number", w: 36, align: "center", name: "value" });
  L.text({ parent: h, x: 58, y: 80, text: names[tier], size: 7, weight: 800, color: "material.silk", op: 0.5, ls: 1, name: "silk" });
  if (tier === "eff" || tier === "hc") L.thermalPickup2(h);
  L.pwrPort(h, 0, 32, { side: "W" }); L.pwrPort(h, 128, 32, { side: "E" }); L.pwrPort(h, 96, 128, { side: "S" });
  return h;
};
L.distBoard2 = (parent, x, y, o = {}) => { // power_board, M Module; lamps per output: ok | near | over | "" (unused)
  const heavy = !!o.heavy, lamps = o.lamps || { N: "ok", E: "ok", S: "ok" };
  const worst = Object.values(lamps).includes("over") ? "Error" : Object.values(lamps).includes("near") ? "Blocked" : "Idle";
  const h = L.shell(parent, `DistributionBoard${heavy ? "Heavy" : ""}`, x, y, "M", "Module", { led: worst });
  L.window(h, 16, 18, 84, 34, "breaker-window");
  ["N", "E", "S"].forEach((side, i) => { const st = lamps[side]; const bx = 21 + i * 26;
    L.rect({ parent: h, x: bx, y: 21, w: 22, h: 28, r: 2, fill: "material.die", stroke: "material.frame", sw: 0.75, name: `breaker-${side}` });
    if (!st) { L.rect({ parent: h, x: bx + 4, y: 32, w: 14, h: 2, fill: "material.frame", name: "unused" }); return; }
    L.rect({ parent: h, x: bx + 6, y: st === "over" ? 35 : 25, w: 10, h: 9, r: 1.5, fill: st === "over" ? "state.blocked" : "text.secondary", fo: st === "over" ? 0.9 : 0.55, name: "lever" });
    L.ellipse({ parent: h, x: bx + 9, y: 44, w: 4, fill: st === "over" ? "state.error" : st === "near" ? "state.blocked" : "material.gold", fo: st === "ok" ? 0.55 : 1, name: "lamp" }); });
  L.pwrPort(h, 0, 32, { side: "W" }); L.pwrPort(h, 32, 0, { side: "N", dim: !lamps.N }); L.pwrPort(h, 128, 32, { side: "E", dim: !lamps.E }); L.pwrPort(h, 32, 64, { side: "S", dim: !lamps.S });
  return h;
};
L.jack = (parent, x, y, o = {}) => { // power_input, M EdgeIn (locked, west laptop edge)
  const h = L.shell(parent, "LabPowerJack", x, y, "M", "EdgeIn", { led: o.plugged === false ? "Off" : "Idle" });
  L.rect({ parent: h, x: -6, y: 14, w: 18, h: 36, r: 3, fill: "machine.frame-hover", stroke: "material.silk", sw: 1, so: 0.45, name: "jack-frame" });
  L.ellipse({ parent: h, x: -3, y: 21, w: 14, fill: "material.vent", stroke: "material.frame", sw: 1, name: "bore" });
  L.ellipse({ parent: h, x: 2, y: 26, w: 4, fill: "material.gold", op: 0.9, name: "pin" });
  if (o.plugged !== false) L.ellipse({ parent: h, x: -1, y: 23, w: 10, stroke: "material.copper", sw: 1.6, op: 0.85, name: "plug" });
  L.window(h, 26, 20, 54, 24, "input-window");
  L.path("M4 12 L10 12 L13 6 L18 18 L23 6 L28 18 L31 12 L50 12", { parent: h, x: 26, y: 20, w: 54, h: 24, stroke: "material.gold", sw: 1.2, op: 0.55, name: "input-filter" });
  L.text({ parent: h, x: 84, y: 26, text: "DC IN", size: 7, weight: 800, color: "material.silk", op: 0.5, name: "silk" });
  L.pwrPort(h, 128, 32, { side: "E" });
  return h;
};
// Copper runs (tiles, centre → edge segments with square caps). Widths: rail 10, hrail 16, main 22, heavy 32.
L.PLANE2 = { tap: { w: 4 }, rail: { w: 10 }, hrail: { w: 16 }, main: { w: 22 }, heavy: { w: 32 } };
L.plane2 = (parent, ox, oy, cells, cls = "main", o = {}) => {
  const P = L.PLANE2[cls], T = 64, has = new Set(cells.map(c => c[0] + "," + c[1]));
  const minC = Math.min(...cells.map(c => c[0])), minR = Math.min(...cells.map(c => c[1])), maxC = Math.max(...cells.map(c => c[0])), maxR = Math.max(...cells.map(c => c[1]));
  const W = (maxC - minC + 1) * T, H = (maxR - minR + 1) * T, segs = [];
  for (const [c, r] of cells) { const cx = (c - minC) * T + 32, cy = (r - minR) * T + 32; let n = 0;
    for (const [dc, dr] of [[1,0],[-1,0],[0,1],[0,-1]]) if (has.has((c+dc)+","+(r+dr))) { segs.push([cx, cy, cx + dc * 32, cy + dr * 32]); n++; }
    if (!n) segs.push([cx - 24, cy, cx + 24, cy]); }
  if (o.stubs) for (const s of o.stubs) segs.push(s);          // extra segments into terminals
  const d = segs.map(s => `M${s[0]} ${s[1]} L${s[2]} ${s[3]}`).join(" ");
  const off = (k) => segs.map(s => { const dx = Math.sign(s[2]-s[0]), dy = Math.sign(s[3]-s[1]); return `M${s[0] - dy * k} ${s[1] + dx * k} L${s[2] - dy * k} ${s[3] + dx * k}`; }).join(" ");
  const la = o.overlay ? 0.95 : 0.62, tint = { near: "state.blocked", over: "state.error" }[o.state];
  const lay = [];
  if (o.overlay && tint) lay.push(`<path d="${d}" stroke="${C(tint)}" stroke-opacity="0.22" stroke-width="${P.w + 10}" stroke-linecap="square" fill="none"/>`);
  lay.push(`<path d="${d}" stroke="${C('board.pad-edge')}" stroke-width="${P.w + 2}" stroke-linecap="square" fill="none"/>`);
  lay.push(`<path d="${d}" stroke="${C('board.pad')}" stroke-width="${P.w}" stroke-linecap="square" fill="none"/>`);
  lay.push(`<path d="${d}" stroke="${C('material.gold')}" stroke-opacity="${o.overlay ? 0.22 : 0.1}" stroke-width="${P.w}" stroke-linecap="square" fill="none"/>`);
  if (cls === "rail") lay.push(`<path d="${d}" stroke="${C('material.gold')}" stroke-opacity="${la}" stroke-width="1.4" stroke-linecap="square" fill="none"/>`);
  else for (const k of [-(P.w / 2 - 2), P.w / 2 - 2]) lay.push(`<path d="${off(k)}" stroke="${C('material.gold')}" stroke-opacity="${la}" stroke-width="1.3" stroke-linecap="square" fill="none"/>`);
  if (cls !== "rail" && cls !== "tap") { const vias = []; const rows = cls === "heavy" ? [-5, 5] : [0];
    for (const s of segs) { const len = Math.hypot(s[2]-s[0], s[3]-s[1]); if (len < 20) continue; const ux = (s[2]-s[0])/len, uy = (s[3]-s[1])/len;
      for (let t = 10; t < len; t += 16) for (const r2 of rows) vias.push(`<circle cx="${(s[0] + ux * t - uy * r2).toFixed(1)}" cy="${(s[1] + uy * t + ux * r2).toFixed(1)}" r="1.5" fill="${C('bg.void')}" stroke="${C('material.gold')}" stroke-opacity="${o.overlay ? 0.8 : 0.45}" stroke-width="0.8"/>`); }
    lay.push(vias.join("")); }
  if (o.over && o.over.length) { /* overloaded run: 1 px state.blocked α .8 line along both edges at ±(w/2 + 2) */ }
  return lay;
};
L.tap2 = (x, y1, y2, o = {}) => { // contact → rail: dark seat w+2 (board.pad-edge), gold trace w (3, heavy 5) α .6, solder pad r 3.4 gold α .55 + 1 px pad-edge ring + 1.2 bore
  const w = o.heavy ? 5 : 3; return { x, y1, y2, w };
};
L.termPad = (cx, cy) => ({ x: cx - 13, y: cy - 9, w: 26, h: 18, r: 3, fill: "material.gold", fo: 0.22, stroke: "material.gold", sw: 1, so: 0.35 }); // where copper meets a terminal

// ---------------------------------------------------------------- THERMAL parts (STYLE_GUIDE §15.4)
// Flattened heat pipe (w 10; heavy 14), mitred corners, drawn ABOVE data and copper:
//   seat board.pad-edge w + 3 (saturated: state.blocked α .8) → copper α .9 w → copper-dim w − 2.4 → gold sheen α .3, 1.2 px
//   heat wash: a gradient from the hot end, state.blocked α heat → 0 at 75 %, width w − 3
// Vapor-chamber trunk (w 22): the same seat, face, and two pillar rows at ±w/4 (copper α .35, 1.6 px, dash 1.6/5 round), gold α .25 centre line
// Copper spreader: 18 px rail mount (machine.body, 1 px machine.frame, r4) with an 8 px copper bar (α .85, 1 px copper-dim edge, r2.5),
//   a gold sheen of 1.2 px, and screws every half tile; it hugs the SOUTH edge of its tile (y = tileY + 64 − 19) so it sits on the contacts below
// Pipe clamp: a machine.body block (8 × span) with a machine.frame border and two 3 px screws
// T-junction: a 26×26 machine.body block (r4, machine.frame border) with a 14 px copper-dim disc (copper ring 1.2) and four 3.5 px screws
L.manifold2 = (parent, x, y, o = {}) => { // thermal_manifold, M Module, copper tab; sockets W/N/S in, E out
  const h = L.shell(parent, "ThermalManifold", x, y, "M", "Module", { tab: "material.copper", led: o.led || "Idle" });
  L.window(h, 16, 18, 84, 30, "header-window");
  L.rect({ parent: h, x: 20, y: 26, w: 76, h: 14, r: 5, fill: "material.copper-dim", stroke: "material.copper", sw: 1.2, so: 0.9, name: "header" });
  L.rect({ parent: h, x: 24, y: 28.5, w: 68, h: 1.3, r: 0.6, fill: "material.gold", fo: 0.35, name: "sheen" });
  for (const sx of [32, 58, 84]) L.rect({ parent: h, x: sx - 3, y: 20, w: 6, h: 6, r: 1, fill: "material.copper", fo: 0.6, name: "stub" });
  L.thmPort(h, 0, 32, { side: "W" }); L.thmPort(h, 32, 0, { side: "N" }); L.thmPort(h, 32, 64, { side: "S" }); L.thmPort(h, 128, 32, { side: "E" });
  return h;
};
L.finCore = (h, x, y, w, hh, heat = 0) => { // window + vertical fins every 3.4 px (1.5 wide, material.plate-hi); heat wash bottom-up state.blocked α heat → 0 at 60 %
  L.window(h, x, y, w, hh, "fin-window"); };
L.exhaustMark = (h) => { /* exhaust side (N): 4×4 vent slots every 8 px from x = 20, y = 1, material.vent */ };
L.finStack = (parent, x, y, o = {}) => { const h = L.shell(parent, "PassiveFinStack", x, y, "M", "Module", { tab: "material.copper", led: o.led || "Idle" });
  L.finCore(h, 30, 16, 72, 34, o.heat || 0); L.rect({ parent: h, x: 26, y: 48, w: 80, h: 5, r: 2, fill: "material.copper-dim", stroke: "material.copper", sw: 0.8, name: "base" });
  L.thmPort(h, 0, 32, { side: "W" }); L.exhaustMark(h); return h; };
L.radiatorL = (parent, x, y, o = {}) => { const h = L.shell(parent, "Radiator", x, y, "L", "Module", { tab: "material.copper", led: o.led || "Idle" });
  L.finCore(h, 22, 22, 90, 72, o.heat || 0); L.rect({ parent: h, x: 18, y: 96, w: 98, h: 8, r: 3, fill: "material.copper-dim", stroke: "material.copper", sw: 1, name: "base" });
  L.rect({ parent: h, x: 22, y: 98, w: 90, h: 1.2, r: 0.6, fill: "material.gold", fo: 0.35, name: "sheen" });
  L.thmPort(h, 0, 32, { side: "W" }); L.thmPort(h, 0, 96, { side: "W" }); L.exhaustMark(h); return h; };
L.fanWindow = (h, cx, cy, r) => { // round recessed window; 14 impeller strokes from 0.35 r to 0.85 r at +0.4 rad, material.silk α .5, 1.1 px; hub 0.6 r plate-hi, copper ring
};
// Blowers: S (fan r 18 at 30,36) · M (two fans r 19 at 40,38 and 86,38) · L (four fans r 24 at 40/90, 44/96); exhaust N; power teeth S
// Pump: S, fan window r 17 at (30,36), thermal sockets W and E, power teeth. Reservoir: S, a 22×40 window at (20,16), coolant text.secondary α .25.
// COOLING ASSEMBLY (drawn when blowers feed a radiator): a shroud around the radiator core(s) + blowers:
//   machine.body α .55, 1.5 px machine.frame, r8, inset 6 px around (x − 6, y − 4, w + 12, h + 10), 5 px corner screws;
//   a dark duct material.vent 8 px between the fins and the blowers (x + 4, y + 124, w − 8).
// Laptop rear edge: an 18 px frame-hover bar above the board; vent slots 4×9 every 7 px over each radiator.

// ---------------------------------------------------------------- stage panel (STYLE_GUIDE §15.5)
L.stagePanel = (parent, x, y, title, rows, o = {}) => {
  const w = o.w || 250, h = 34 + rows.length * 18 + 8;
  const g = L.panel(parent, x, y, w, h, "StagePanel / " + title);
  L.text({ parent: g, x: 12, y: 10, text: title, size: 10, weight: 800, color: "text.primary", ls: 0.5, name: "title" });
  L.rect({ parent: g, x: 12, y: 27, w: w - 24, h: 1, fill: "surface.border", name: "rule" });
  rows.forEach(([k, v, tone], i) => { const yy = 34 + i * 18; const col = { ok: "text.primary", near: "state.blocked", over: "state.error", muted: "text.muted", good: "state.valid" }[tone || "ok"];
    L.text({ parent: g, x: 12, y: yy, text: k, size: 9, weight: 700, color: "text.muted", name: "stage" });
    L.text({ parent: g, x: w - 12 - v.length * 6.1, y: yy, text: v, size: 9.5, weight: tone === "over" ? 800 : 600, color: col, name: "value" });
    if (tone === "over") { L.rect({ parent: g, x: 6, y: yy - 2, w: 2, h: 14, r: 1, fill: "state.error", name: "flag" }); } });
  return g;
};
