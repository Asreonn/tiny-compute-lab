// Reference implementation of Signal System V1 (Penpot page 13), as used to draw the canonical
// wires in Penpot. The Godot ConnectionView must reproduce this geometry and layer stack exactly.
// Colours: L.C(token) -> design/tokens.json colour tokens. Not executed by the game.
const L = storage.L;
const C = (t) => L.C(t);
// ================= SIGNAL SYSTEM V1 (canonical) =================
// Line-weight scale (px): hair 1 · detail 1.5 · core 2.5 · lit core 3 · pulse core 3.5 · trench 8 · trench edge 10 · bus trench 14 · bus edge 16
L.SIG = { edge: 10, trench: 8, core: 2.5, coreLit: 3, pulse: 3.5, glow: 10, busEdge: 16, busTrench: 14, chamfer: 14, teardrop: [6, 20] };
// ---- geometry helpers ----
L.parseD = (d) => { // absolute M/L/H/V -> array of polylines
  const out = []; let cur = null, x = 0, y = 0; const re = /([MLHV])\s*([-\d.]+)(?:[\s,]+([-\d.]+))?/g; let m;
  while ((m = re.exec(d))) { const c = m[1];
    if (c === "M") { x = +m[2]; y = +m[3]; cur = [[x, y]]; out.push(cur); }
    else if (c === "L") { x = +m[2]; y = +m[3]; cur.push([x, y]); }
    else if (c === "H") { x = +m[2]; cur.push([x, y]); } else { y = +m[2]; cur.push([x, y]); } }
  return out; };
L.chamferPts = (pts, c = 14) => { const o = [pts[0]];
  for (let i = 1; i < pts.length - 1; i++) { const [px, py] = pts[i - 1], [x, y] = pts[i], [nx, ny] = pts[i + 1];
    const d1 = [Math.sign(x - px), Math.sign(y - py)], d2 = [Math.sign(nx - x), Math.sign(ny - y)];
    if (d1[0] === d2[0] && d1[1] === d2[1]) { o.push([x, y]); continue; }
    const cc = Math.min(c, Math.hypot(x - px, y - py) / 2, Math.hypot(nx - x, ny - y) / 2); // short jogs: never overshoot
    o.push([x - d1[0] * cc, y - d1[1] * cc]); o.push([x + d2[0] * cc, y + d2[1] * cc]); }
  o.push(pts[pts.length - 1]); return o; };
L.dStr = (p) => "M" + p.map(([x, y]) => `${+x.toFixed(2)} ${+y.toFixed(2)}`).join(" L");
L.polyLen = (p) => p.slice(1).reduce((a, q, i) => a + Math.hypot(q[0] - p[i][0], q[1] - p[i][1]), 0);
L.sample = (p, t) => { let d = t * L.polyLen(p); for (let i = 1; i < p.length; i++) { const l = Math.hypot(p[i][0] - p[i - 1][0], p[i][1] - p[i - 1][1]);
  if (d <= l) { const k = l ? d / l : 0; return [p[i - 1][0] + (p[i][0] - p[i - 1][0]) * k, p[i - 1][1] + (p[i][1] - p[i - 1][1]) * k, (p[i][0] - p[i - 1][0]) / l, (p[i][1] - p[i - 1][1]) / l]; } d -= l; }
  const n = p.length - 1; const l = Math.hypot(p[n][0] - p[n - 1][0], p[n][1] - p[n - 1][1]); return [p[n][0], p[n][1], (p[n][0] - p[n - 1][0]) / l, (p[n][1] - p[n - 1][1]) / l]; };
// one SVG import per wire: layers = [{d, stroke, sw, op, fill, cap, join, dash, id}]
L.layers = (b, W, H, layers, name) => {
  const el = layers.map(l => `<path id="${l.id || "l"}" d="${l.d}" fill="${l.fill || "none"}" ${l.fill && l.fop != null ? `fill-opacity="${l.fop}"` : ""} stroke="${l.stroke || "none"}" stroke-width="${l.sw || 0}" ${l.op != null ? `stroke-opacity="${l.op}"` : ""} stroke-linecap="${l.cap || "round"}" stroke-linejoin="${l.join || "round"}"/>`).join("");
  const g = L.svg(`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${el}</svg>`, b, 0, 0, name);
  // dashed layers: Penpot import ignores dasharray -> set stroke style
  const paths = penpotUtils.findShapes(s => s.type === "path", g);
  layers.forEach((l, i) => { const p = paths[i]; if (!p) return; p.name = l.id || "layer"; if (l.dash) p.strokes = p.strokes.map(k => ({ ...k, strokeStyle: "dashed" })); });
  return g; };
// PCB teardrop: widens the trace into the port's contact pad so wire and socket read as one part
L.teardrop = (P, u, edge = true) => { const [px, py] = P, [ux, uy] = u, nx = -uy, ny = ux; const [a, b] = L.SIG.teardrop;
  const w0 = 8, w1 = 5;
  const q = (s, w) => [px + ux * s + nx * w, py + uy * s + ny * w];
  const A = q(a, w0), B = q(a, -w0), Cc = q(b, -w1), D = q(b, w1), Q1 = q(a + 9, w0 - 1), Q2 = q(a + 9, -(w0 - 1));
  return `M${A[0]} ${A[1]} Q${Q1[0]} ${Q1[1]} ${D[0]} ${D[1]} L${Cc[0]} ${Cc[1]} Q${Q2[0]} ${Q2[1]} ${B[0]} ${B[1]} Z`; };
L.wireLook = (dt, st) => {
  const col = dt === "Boolean" ? "data.boolean" : "data.number", dim = dt === "Boolean" ? "data.boolean-dim" : "data.number-dim";
  const s = { edge: "board.pad-edge", edgeOp: 1, trench: "material.vent", core: dim, coreW: L.SIG.core, coreOp: 1, dash: dt === "Boolean", halo: null, preview: false, chev: false, comet: null, endMark: null };
  switch (st) {
    case "Hover": s.edge = "state.hover"; s.edgeOp = 0.75; s.core = col; s.coreOp = 0.8; break;
    case "Selected": s.halo = "state.select"; s.core = col; s.coreW = L.SIG.coreLit; s.chev = true; break;
    case "ActiveTransfer": s.core = col; s.coreOp = 0.5; s.comet = col; break;
    case "Blocked": s.edge = "state.blocked"; s.edgeOp = 0.7; s.core = "state.blocked"; s.coreW = L.SIG.coreLit; break;
    case "Error": s.edge = "state.error"; s.edgeOp = 0.8; s.core = "state.error"; s.coreW = L.SIG.coreLit; break;
    case "ConnectionPreview": s.preview = true; s.core = "state.build"; s.dash = true; s.endMark = "cursor"; break;
    case "ValidTarget": s.preview = true; s.core = "state.valid"; s.coreW = L.SIG.coreLit; s.dash = false; s.endMark = "valid"; break;
    case "InvalidTarget": s.preview = true; s.core = "state.invalid"; s.dash = true; s.endMark = "invalid"; break;
  }
  return s; };
// pts: array of [x,y] (flow order: from OUT port to IN port) or a d string; o: {pulse:[t0,t1] fraction of length | [[x,y],[x,y]], terminals:[startIsPort,endIsPort]}
L.drawWire = (b, ptsOrD, W, H, dt, st, o = {}) => {
  const s = L.wireLook(dt, st);
  const lines = typeof ptsOrD === "string" ? L.parseD(ptsOrD) : [L.chamferPts(ptsOrD, L.SIG.chamfer)];
  const D = lines.map(L.dStr).join(" ");
  const lay = [];
  const term = o.terminals || [false, false];
  const ends = [];
  if (!s.preview) { const p = lines[0]; if (term[0]) ends.push([p[0], [(p[1][0] - p[0][0]), (p[1][1] - p[0][1])]]);
    const q = lines[lines.length - 1], n = q.length - 1; if (term[1]) ends.push([q[n], [(q[n - 1][0] - q[n][0]), (q[n - 1][1] - q[n][1])]]); }
  const unit = (v) => { const l = Math.hypot(v[0], v[1]) || 1; return [v[0] / l, v[1] / l]; };
  if (s.halo) lay.push({ id: "select-halo", d: D, stroke: C(s.halo), sw: 14, op: 0.9, cap: "butt", join: "miter" });
  if (!s.preview) {
    for (const [P, v] of ends) lay.push({ id: "teardrop-edge", d: L.teardrop(P, unit(v), true), fill: C(s.halo ? "board.pad-edge" : s.edge), stroke: "none" });
    lay.push({ id: "trench-edge", d: D, stroke: C(s.edge), sw: L.SIG.edge, op: s.edgeOp, cap: "butt", join: "miter" });
    lay.push({ id: "trench", d: D, stroke: C(s.trench), sw: L.SIG.trench, cap: "butt", join: "miter" });
  }
  lay.push({ id: "core", d: D, stroke: C(s.core), sw: s.coreW, op: s.coreOp, cap: "butt", join: "miter", dash: s.dash });
  // comet: glow + bright head around the moving packet, fading toward the tail (shows direction without arrows)
  if (s.comet && o.pulse) { const p = lines[0]; let t0, t1;
    if (Array.isArray(o.pulse[0])) { t0 = L.project(p, o.pulse[0]); t1 = L.project(p, o.pulse[1]); } else { t0 = o.pulse[0]; t1 = o.pulse[1]; }
    const sub = (a, b) => L.dStr(L.subPoly(p, t0 + (t1 - t0) * a, t0 + (t1 - t0) * b));
    lay.push({ id: "comet-glow", d: sub(0.35, 1), stroke: C(s.comet), sw: L.SIG.glow, op: 0.2, join: "round" });
    lay.push({ id: "comet-tail", d: sub(0, 0.4), stroke: C(s.comet), sw: L.SIG.coreLit, op: 0.35, join: "round" });
    lay.push({ id: "comet-core", d: sub(0.4, 1), stroke: C(s.comet), sw: L.SIG.pulse, op: 1, join: "round" }); }
  // selected: ice flow chevrons inside the trench every 48 px (direction on demand, never on idle wires)
  if (s.chev) { const p = lines[0]; const len = L.polyLen(p); const k = Math.max(1, Math.floor(len / 48));
    let d = ""; for (let i = 1; i <= k; i++) { const t = (i - 0.5) / k; const [x, y, ux, uy] = L.sample(p, t); const nx = -uy, ny = ux;
      d += `M${x - ux * 2.5 + nx * 3} ${y - uy * 2.5 + ny * 3} L${x + ux * 1.5} ${y + uy * 1.5} L${x - ux * 2.5 - nx * 3} ${y - uy * 2.5 - ny * 3} `; }
    lay.push({ id: "flow-chevrons", d, stroke: C("state.select"), sw: 1.5, op: 0.9 }); }
  if (s.endMark) { const q = lines[lines.length - 1], [ex, ey] = q[q.length - 1];
    if (s.endMark === "valid") lay.push({ id: "target-ring", d: `M${ex - 11} ${ey} a11 11 0 1 0 22 0 a11 11 0 1 0 -22 0`, stroke: C("state.valid"), sw: 2 });
    if (s.endMark === "invalid") lay.push({ id: "invalid-x", d: `M${ex - 6} ${ey - 6} L${ex + 6} ${ey + 6} M${ex + 6} ${ey - 6} L${ex - 6} ${ey + 6}`, stroke: C("state.invalid"), sw: 2.5 });
    if (s.endMark === "cursor") lay.push({ id: "drag-head", d: `M${ex - 4} ${ey} a4 4 0 1 0 8 0 a4 4 0 1 0 -8 0`, fill: C("state.build"), stroke: C("state.build"), sw: 1 }); }
  return L.layers(b, W, H, lay, "wire-art");
};
// legacy entry point (motion, DS pages, variant mains) -> canonical renderer
L.drawWireV2 = (b, d, W, H, dt, st, pulseD) => L.drawWire(b, d, W, H, dt, st, pulseD ? { pulse: L.parseD(pulseD)[0].slice(0, 2).length === 2 ? [L.parseD(pulseD)[0][0], L.parseD(pulseD)[0][L.parseD(pulseD)[0].length - 1]] : null } : {});
// ---- buses (explicit bit width) ----
L.drawBus = (b, pts, W, H, width, st = "Idle", o = {}) => {
  const p = L.chamferPts(pts, 18), D = L.dStr(p); const lit = st === "ActiveTransfer" || st === "Selected";
  const lay = [];
  if (st === "Selected") lay.push({ id: "select-halo", d: D, stroke: C("state.select"), sw: 20, op: 0.9, cap: "butt", join: "miter" });
  lay.push({ id: "bus-edge", d: D, stroke: C(st === "Blocked" ? "state.blocked" : "board.pad-edge"), sw: L.SIG.busEdge, op: st === "Blocked" ? 0.7 : 1, cap: "butt", join: "miter" });
  lay.push({ id: "bus-trench", d: D, stroke: C("material.vent"), sw: L.SIG.busTrench, cap: "butt", join: "miter" });
  // ribbon: 4 lanes (a width > 4 still shows 4 lanes + a width tag)
  const lanes = 4, gap = 2.6; const col = st === "Blocked" ? "state.blocked" : (lit ? "data.number" : "data.number-dim");
  for (let i = 0; i < lanes; i++) { const off = (i - (lanes - 1) / 2) * gap; const q = L.offsetPoly(p, off);
    lay.push({ id: "lane", d: L.dStr(q), stroke: C(col), sw: 1.4, op: lit ? 0.9 : 1, cap: "butt", join: "miter" }); }
  if (o.pulse && st === "ActiveTransfer") { const A = L.sample(p, o.pulse[0]), Z = L.sample(p, o.pulse[1]);
    lay.push({ id: "comet-glow", d: `M${A[0]} ${A[1]} L${Z[0]} ${Z[1]}`, stroke: C("data.number"), sw: 16, op: 0.18 }); }
  return L.layers(b, W, H, lay, "bus-art"); };
L.subPoly = (p, t0, t1) => { const L0 = L.polyLen(p); const a = t0 * L0, b = t1 * L0; const o = []; let acc = 0;
  for (let i = 1; i < p.length; i++) { const l = Math.hypot(p[i][0] - p[i - 1][0], p[i][1] - p[i - 1][1]); const s0 = acc, s1 = acc + l;
    const at = (d) => [p[i - 1][0] + (p[i][0] - p[i - 1][0]) * (d - s0) / l, p[i - 1][1] + (p[i][1] - p[i - 1][1]) * (d - s0) / l];
    if (s1 >= a && s0 <= b && l > 0) { if (!o.length) o.push(at(Math.max(a, s0))); o.push(at(Math.min(b, s1))); }
    acc = s1; }
  return o.length > 1 ? o : [L.sample(p, t0).slice(0, 2), L.sample(p, t1).slice(0, 2)]; };
L.project = (p, q) => { let best = 0, bd = 1e9, acc = 0; const T = L.polyLen(p);
  for (let i = 1; i < p.length; i++) { const [ax, ay] = p[i - 1], [bx, by] = p[i]; const l = Math.hypot(bx - ax, by - ay); if (!l) continue;
    let k = ((q[0] - ax) * (bx - ax) + (q[1] - ay) * (by - ay)) / (l * l); k = Math.max(0, Math.min(1, k));
    const d = Math.hypot(ax + (bx - ax) * k - q[0], ay + (by - ay) * k - q[1]); if (d < bd) { bd = d; best = (acc + k * l) / T; } acc += l; }
  return best; };
L.offsetPoly = (p, off) => p.map((pt, i) => { const a = p[Math.max(0, i - 1)], c = p[Math.min(p.length - 1, i + 1)];
  let ux = c[0] - a[0], uy = c[1] - a[1]; const l = Math.hypot(ux, uy) || 1; ux /= l; uy /= l;
  // miter-ish: for 45° chamfer joints scale offset slightly
  return [pt[0] - uy * off, pt[1] + ux * off]; });
return "sig_lib ok";
