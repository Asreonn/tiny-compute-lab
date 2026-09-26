#!/usr/bin/env python3
"""Generate the primitive-kit art (C4) from the locked Penpot geometry (page 14 Compute Kit,
STYLE_GUIDE §15.7): one silhouette shell per part, the static face of its mechanism as an
ActivityArea (with state variants), the manifest entries and the machine_layouts.json entries.

The geometry below mirrors the Penpot helpers (plugin data tcl/lib16–lib19: L.SIL, L.FACE) one to
one, so the in-game art and the design file stay identical. Values that change at runtime (probe /
latch cells, constant DIP toggles, field-ruler cells and widths, tie caps) are NOT baked: the view
draws them. Re-run after editing: python3 tools/gen_primitive_art.py
"""
import json, math, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOK = json.loads((ROOT / "design/tokens.json").read_text())["color"]
ART = ROOT / "assets/art"


def C(name):
    grp, key = name.split(".", 1)
    return TOK[grp][key]


# ------------------------------------------------------------------ svg primitives
class Svg:
    def __init__(self):
        self.el = []

    def rect(self, x, y, w, h, r=0, fill=None, fo=1.0, stroke=None, sw=1.0):
        a = f'x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" ry="{r}"'
        a += f' fill="{C(fill)}" fill-opacity="{fo}"' if fill else ' fill="none"'
        if stroke:
            a += f' stroke="{C(stroke)}" stroke-width="{sw}"'
        self.el.append(f"<rect {a}/>")

    def line(self, pts, col, sw, op=1.0, dash=None):
        d = "M" + " L".join(f"{p[0]} {p[1]}" for p in pts)
        a = f'd="{d}" fill="none" stroke="{C(col)}" stroke-opacity="{op}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"'
        if dash:
            a += f' stroke-dasharray="{dash}"'
        self.el.append(f"<path {a}/>")

    def dot(self, cx, cy, r, fill, ring=False, fo=1.0):
        if ring:
            self.el.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{C(fill)}" stroke-width="1.2"/>')
        else:
            self.el.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{C(fill)}" fill-opacity="{fo}"/>')

    def route(self, pts, tok="material.copper", trench=6, w=2.0, op=1.0):
        self.line(pts, "material.vent", trench)
        self.line(pts, tok, w, op)

    def win(self, x, y, w, h, r=3):
        self.rect(x, y, w, h, r, fill="machine.screen", stroke="material.frame", sw=1)

    def raw(self, s):
        self.el.append(s)

    def out(self, w, h, pad):
        W, H = w + 2 * pad, h + 2 * pad
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="{-pad} {-pad} {W} {H}" fill="none" version="1.1">\n'
                + "\n".join(self.el) + "\n</svg>\n")


# ------------------------------------------------------------------ silhouettes (L.SIL / L.silD)
def rpath(pts, rd=3):
    n, d = len(pts), ""
    for i in range(n):
        p, a, b = pts[i], pts[(i - 1) % n], pts[(i + 1) % n]
        r = p[2] if len(p) > 2 else rd
        u1 = (a[0] - p[0], a[1] - p[1]); u2 = (b[0] - p[0], b[1] - p[1])
        l1, l2 = math.hypot(*u1), math.hypot(*u2)
        rr = min(r, l1 / 2, l2 / 2)
        s = (p[0] + u1[0] / l1 * rr, p[1] + u1[1] / l1 * rr); e = (p[0] + u2[0] / l2 * rr, p[1] + u2[1] / l2 * rr)
        d += ("M" if i == 0 else "L") + f"{s[0]:.2f} {s[1]:.2f}" + (f" Q{p[0]} {p[1]} {e[0]:.2f} {e[1]:.2f}" if rr > 0 else "") + " "
    return d + "Z"


SIL = {
    "bit_switch": dict(W=64, H=64, pts=[[6, 10], [27, 10], [27, 4, 2], [37, 4, 2], [37, 10], [58, 10], [58, 60], [34, 60], [34, 54, 0], [6, 54]], bevel="M9 9.5 L25 9.5 M39 9.5 L55 9.5"),
    "fork": dict(W=64, H=64, pts=[[4, 16], [8, 12], [24, 12, 0], [24, 4], [40, 4], [40, 12, 0], [44, 12, 0], [48, 16, 0], [48, 24, 0], [60, 24], [60, 40], [48, 40, 0], [48, 48, 0], [44, 52, 0], [40, 52, 0], [40, 60], [24, 60], [24, 52, 0], [8, 52], [4, 48]], bevel="M9 13.5 L22 13.5 M26 5.5 L38 5.5"),
    "distributor": dict(W=64, H=64, pts=[[14, 5], [50, 5], [59, 14], [59, 50], [50, 59], [14, 59], [5, 50], [5, 14]], bevel="M15 6.5 L49 6.5"),
    "join": dict(W=64, H=64, d="M6 10 Q6 6 10 6 L30 6 A26 26 0 0 1 30 58 L10 58 Q6 58 6 54 Z", bevel="M9 7.5 L29 7.5"),
    "latch": dict(W=64, H=64, pts=[[6, 8], [58, 8], [58, 54], [38, 54, 1], [38, 49, 1], [26, 49, 1], [26, 54, 1], [6, 54]], bevel="M9 9.5 L55 9.5"),
    "constant": dict(W=64, H=64, pts=[[14, 8, 0], [58, 8], [58, 56], [6, 56], [6, 38, 0], [11, 38, 0], [11, 26, 0], [6, 26, 0], [6, 16, 0]], bevel="M15 9.5 L55 9.5"),
    "probe": dict(W=64, H=64, d="M5 32 A27 27 0 1 0 59 32 A27 27 0 1 0 5 32 Z", bevel="M22 6.8 Q32 4.8 42 6.8"),
    "clock": dict(W=64, H=64, d="M24 14 L40 14 A18 18 0 0 1 40 50 L24 50 A18 18 0 0 1 24 14 Z", bevel="M22 15.5 L42 15.5"),
    "field_splitter": dict(W=128, H=128, pts=[[6, 6], [122, 6], [122, 57], [86, 57, 2], [86, 71, 2], [122, 71], [122, 122], [20, 122, 0], [6, 108, 0]], bevel="M9 7.5 L119 7.5"),
    "field_joiner": dict(W=128, H=128, pts=[[6, 6], [122, 6], [122, 108, 0], [108, 122, 0], [6, 122], [6, 71], [42, 71, 2], [42, 57, 2], [6, 57]], bevel="M9 7.5 L119 7.5"),
    "adder": dict(W=128, H=128, pts=[[6, 6], [122, 22], [122, 84], [6, 122], [6, 72, 0], [24, 64, 2], [6, 56, 0]], bevel="M9 7.9 L118 23"),
}
FORM = {"bit_switch": "Switch-S", "fork": "Hub-S", "distributor": "Rotor-S", "join": "Collector-S", "latch": "LatchCart-S",
        "constant": "KeyBlock-S", "probe": "Lens-S", "clock": "Crystal-S", "field_splitter": "CombSplit-L",
        "field_joiner": "CombJoin-L", "adder": "Ripple-L"}


def shell_svg(k):
    s = SIL[k]
    d = s.get("d") or rpath(s["pts"], 3)
    g = Svg()
    g.raw(f'<path d="{d}" transform="translate(0 3)" fill="{C("material.plate-lo")}"/>')
    g.raw(f'<path d="{d}" fill="{C("material.plate")}" stroke="{C("material.frame")}" stroke-width="1.5" stroke-linejoin="round"/>')
    g.raw(f'<path d="{s["bevel"]}" fill="none" stroke="{C("material.plate-hi")}" stroke-width="1" stroke-linecap="round"/>')
    return g.out(s["W"], s["H"], 4)


# ------------------------------------------------------------------ faces (L.FACE), static parts only
def f_bit_switch(g, st):
    closed = st == "Closed"
    g.win(14, 17, 36, 28)
    g.route([[6, 32], [21, 32]], "data.number")
    g.line([[32, 10], [32, 17]], "data.boolean", 1.5)
    if closed:
        g.line([[21, 32], [43, 32]], "data.number", 3)
        g.line([[32, 17], [32, 30]], "data.boolean", 1.2)
    else:
        g.line([[21, 32], [39, 24]], "machine.frame-hover", 3)
        g.line([[32, 17], [32, 27]], "data.boolean", 1.2, dash="2 1.5")
    g.dot(21, 32, 3, "data.number"); g.dot(21, 32, 1.3, "machine.screen")
    g.dot(43, 32, 3, "data.number" if closed else "machine.frame-hover", ring=not closed)
    g.route([[46, 32], [58, 32]], "data.number" if closed else "data.number-dim", trench=4, w=1.5)
    g.line([[43, 35], [43, 44]], "material.frame", 1.2)
    g.line([[43, 45], [43, 55]], "material.gold", 1.2)
    g.rect(37, 55, 12, 1.6, 0.8, fill="material.gold"); g.rect(39.5, 57.4, 7, 1.4, 0.7, fill="material.gold", fo=0.8)


def f_fork(g, st):
    g.route([[4, 32], [38, 32]], trench=5)
    g.route([[32, 4], [32, 12], [38, 18], [38, 32]], trench=5)
    g.route([[38, 32], [60, 32]], trench=5)
    g.route([[38, 32], [38, 46], [32, 52], [32, 60]], trench=5)
    g.dot(38, 32, 5.5, "machine.screen"); g.dot(38, 32, 5.5, "family.routing", ring=True); g.dot(38, 32, 2, "family.routing")


def f_distributor(g, st):
    g.route([[5, 32], [23, 32]], trench=5)
    g.route([[32, 5], [32, 10], [36, 14], [36, 22]], trench=4, w=1.5)
    g.route([[48, 35], [52, 35], [55, 32], [59, 32]], trench=4, w=1.5)
    g.route([[36, 48], [36, 54], [32, 58], [32, 59]], trench=4, w=1.5)
    g.dot(36, 35, 13, "machine.screen"); g.dot(36, 35, 13, "material.frame", ring=True)
    live = {"A": "a", "B": "b", "C": "c"}[st]
    for x, y, n in [(36, 25, "a"), (46, 35, "b"), (36, 45, "c")]:
        g.dot(x, y, 2.3, "data.number" if n == live else "material.frame")
    tip = {"a": (36, 26), "b": (45, 35), "c": (36, 44)}[live]
    g.line([[36, 35], list(tip)], "data.number", 2.5)
    g.line([[23, 32], [30, 34]], "material.copper", 1.5)
    g.dot(36, 35, 3.4, "family.routing")


def f_join(g, st):
    g.route([[32, 6], [32, 9], [36, 13], [36, 24], [40, 28]], trench=5)
    g.route([[6, 32], [36, 32]], trench=5)
    g.route([[32, 58], [32, 55], [36, 51], [36, 40], [40, 36]], trench=5)
    g.route([[48, 32], [58, 32]], trench=5)
    g.dot(43, 32, 6, "machine.screen"); g.dot(43, 32, 6, "family.routing", ring=True)
    tip = {"A": (40.6, 27.6), "B": (38, 32), "C": (40.6, 36.4)}[st]
    g.line([[43, 32], list(tip)], "family.routing", 2)


def f_latch(g, st):
    g.rect(27, 14, 10, 3, 1, fill="data.boolean", fo=0.85)
    g.win(12, 19, 40, 20)
    for x in (41, 46, 51):
        g.rect(x, 47.5, 3, 4, 0.8, fill="material.gold")


def f_constant(g, st):
    g.win(16, 19, 34, 26)
    g.route([[50, 32], [58, 32]], "data.number-dim", trench=4, w=1.5)


def f_probe(g, st):
    g.route([[5, 32], [59, 32]], "data.number-dim", trench=4, w=1.5)
    g.dot(32, 32, 15, "machine.frame-hover", ring=True); g.dot(32, 32, 13.5, "machine.screen")
    g.line([[29, 52], [31, 54], [35, 50]], "state.valid", 1.5, op=1.0 if st == "Pass" else 0.35)


def f_clock(g, st):
    g.win(14, 24, 32, 18)
    g.line([[17, 37], [21, 37], [21, 29], [27, 29], [27, 37], [33, 37], [33, 29], [39, 29], [39, 37], [43, 37]], "data.boolean", 1.5, op=1.0 if st == "Pulse" else 0.45)
    g.rect(22, 50, 2.5, 7, 1, fill="material.gold"); g.rect(40, 50, 2.5, 7, 1, fill="material.gold")


RULER_TAPS = [33, 59, 81, 102]  # fan origins on the ruler edge (Penpot: the 6·3·4·3 group centres)


def f_field_splitter(g, st):
    m = RULER_TAPS
    g.route([[6, 32], [22, 32]], "data.number", trench=5)
    g.win(22, 14, 16, 104)
    g.route([[38, m[0]], [56, m[0]], [62, m[0] - 6], [62, 20], [90, 20], [96, 14], [96, 6]], "data.number-dim")
    g.route([[38, m[1]], [72, m[1]], [72, 38], [78, 32], [122, 32]], "data.number-dim")
    g.route([[38, m[2]], [72, m[2]], [72, 90], [78, 96], [122, 96]], "data.number-dim")
    g.route([[38, m[3]], [96, m[3]], [96, 122]], "data.number-dim")


def f_field_joiner(g, st):
    m = RULER_TAPS
    g.win(90, 14, 16, 104)
    g.route([[32, 6], [32, 14], [38, 20], [66, 20], [66, m[0] - 6], [72, m[0]], [90, m[0]]], "data.number-dim")
    g.route([[6, 32], [50, 32], [56, 38], [56, m[1]], [90, m[1]]], "data.number-dim")
    g.route([[6, 96], [50, 96], [56, 90], [56, m[2]], [90, m[2]]], "data.number-dim")
    g.route([[32, 122], [32, m[3]], [90, m[3]]], "data.number-dim")
    g.route([[106, 32], [122, 32]], "data.number", trench=5)


def f_adder(g, st):
    g.dot(50, 52, 16, "machine.screen"); g.dot(50, 52, 16, "material.frame", ring=True)
    g.rect(42, 50.25, 16, 3.5, 1.2, fill="text.primary"); g.rect(48.25, 44, 3.5, 16, 1.2, fill="text.primary")
    for i in range(3):
        x = 30 + i * 22
        g.rect(x, 82, 14, 10, 2, fill="machine.screen", stroke="material.frame", sw=0.75)
        if i < 2:
            g.line([[x + 14, 87], [x + 22, 87]], "data.number", 1.2, op=1.0 if st == "Active" else 0.6)
    g.rect(74, 44, 32, 16, 3, fill="machine.screen", stroke="material.frame", sw=1)


FACE = {  # part -> (area kind, states (first = idle), builder)
    "bit_switch": ("Blade", ["Open", "Closed"], f_bit_switch),
    "fork": ("Hub", ["Idle"], f_fork),
    "distributor": ("Rotor", ["A", "B", "C"], f_distributor),
    "join": ("Collector", ["A", "B", "C"], f_join),
    "latch": ("Hold", ["Idle"], f_latch),
    "constant": ("Dip", ["Idle"], f_constant),
    "probe": ("Lens", ["Idle", "Pass"], f_probe),
    "clock": ("Crystal", ["Idle", "Pulse"], f_clock),
    "field_splitter": ("RulerSplit", ["Idle"], f_field_splitter),
    "field_joiner": ("RulerJoin", ["Idle"], f_field_joiner),
    "adder": ("Ripple", ["Idle", "Active"], f_adder),
}

# ------------------------------------------------------------------ layouts (ports in PortDef order)
P = lambda d, t, x, y: {"dir": d, "type": t, "anchor": [x, y]}
LAYOUT = {
    "bit_switch": dict(family="logic", tab=[9, 48], led=None, ports=[P("Input", "Number", 0, 32), P("Control", "Boolean", 32, 0), P("Output", "Number", 64, 32)]),
    "fork": dict(family="routing", tab=[7, 16], led=None, ports=[P("Input", "Number", 0, 32), P("Output", "Number", 32, 0), P("Output", "Number", 64, 32), P("Output", "Number", 32, 64)]),
    "distributor": dict(family="routing", tab=[7, 15], led=None, ports=[P("Input", "Number", 0, 32), P("Output", "Number", 32, 0), P("Output", "Number", 64, 32), P("Output", "Number", 32, 64)]),
    "join": dict(family="routing", tab=[7, 12], led=None, ports=[P("Input", "Number", 32, 0), P("Input", "Number", 0, 32), P("Input", "Number", 32, 64), P("Output", "Number", 64, 32)]),
    "latch": dict(family="memory", tab=[9, 42], led=None, ports=[P("Input", "Number", 0, 32), P("Control", "Boolean", 32, 0), P("Output", "Number", 64, 32)], cells=dict(x=16, y=24, w=32, h=10)),
    "constant": dict(family="memory", tab=[16, 12], led=None, ports=[P("Output", "Number", 64, 32)], silk={"text": "K", "pos": [16, 47]}, cells=dict(x=19, y=22, w=28, h=20)),
    "probe": dict(family="view", tab=[20, 10], led=None, ports=[P("Input", "Number", 0, 32), P("Output", "Number", 64, 32)], cells=dict(x=20, y=28, w=24, h=8)),
    "clock": dict(family="control", tab=[16, 18], led=None, ports=[P("Output", "Boolean", 64, 32)]),
    "field_splitter": dict(family="conversion", tab=[46, 10], led=[110, 18], ports=[P("Input", "Number", 0, 32), P("Output", "Number", 96, 0), P("Output", "Number", 128, 32), P("Output", "Number", 128, 96), P("Output", "Number", 96, 128)], ruler=dict(x=22, y=14, w=16, h=104, labels="left")),
    "field_joiner": dict(family="conversion", tab=[58, 10], led=[18, 114], ports=[P("Input", "Number", 32, 0), P("Input", "Number", 0, 32), P("Input", "Number", 0, 96), P("Input", "Number", 32, 128), P("Output", "Number", 128, 32)], ruler=dict(x=90, y=14, w=16, h=104, labels="left")),
    "adder": dict(family="math", tab=[14, 14], led=[104, 36], ports=[P("Input", "Number", 0, 32), P("Input", "Number", 0, 96), P("Output", "Number", 128, 32)], silk={"text": "a+b", "pos": [80, 47]}),
}


def main():
    man_p, ly_paths = ART / "manifest.json", [ART / "machine_layouts.json", ROOT / "design/machine_layouts.json"]
    man = json.loads(man_p.read_text())
    written = []
    for k, s in SIL.items():
        slug = FORM[k].lower().replace("-", "_")
        rel = f"machine/shell_{slug}.svg"
        (ART / rel).write_text(shell_svg(k)); man[rel] = {"h": s["H"], "pad": 4, "w": s["W"]}; written.append(rel)
        kind, states, fn = FACE[k]
        for st in states:
            g = Svg(); fn(g, st)
            rel = f"machine/area_{kind.lower()}_{st.lower()}.svg"
            (ART / rel).write_text(g.out(s["W"], s["H"], 12)); man[rel] = {"h": s["H"], "pad": 12, "w": s["W"]}; written.append(rel)
    man_p.write_text(json.dumps(dict(sorted(man.items())), indent=1, ensure_ascii=False))
    for p in ly_paths:
        txt = p.read_text(); trail = "\n" if txt.endswith("\n") else ""
        d = json.loads(txt)
        for k, s in SIL.items():
            slug = FORM[k].lower().replace("-", "_")
            size = "S" if s["W"] == 64 else "L"
            d["forms"][FORM[k]] = {"size": size, "w": s["W"], "h": s["H"], "led": None, "asset": f"machine/shell_{slug}.svg"}
            kind, states, _ = FACE[k]
            d["areas"][kind] = {"w": s["W"], "h": s["H"], "states": states}
            L = LAYOUT[k]
            entry = {"form": FORM[k], "family": L["family"], "area": {"kind": kind, "idle": states[0], "pos": [0, 0]},
                     "glyph": None, "display": None, "digits": None, "operator": None, "param": None,
                     "silk": L.get("silk"), "led": L["led"], "tab": L["tab"], "ports": L["ports"]}
            for extra in ("cells", "ruler"):
                if extra in L:
                    entry[extra] = L[extra]
            d["machines"][k] = entry
        for key in ("FieldSplitter", "FieldJoiner"):
            d.get("roadmap", {}).pop(key, None)  # placeholders from C3c; machines[] has the real art now
        p.write_text(json.dumps(d, indent=1, ensure_ascii=False) + trail)
    print(f"{len(written)} svgs, {len(SIL)} layouts")


if __name__ == "__main__":
    main()
