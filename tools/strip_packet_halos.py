#!/usr/bin/env python3
"""Remove the datatype halo from packet sprites (VFX ladder L1, docs/STYLE_GUIDE.md §14.1).

The Penpot export wraps each halo in its own low-opacity group (<g style="opacity:0.14|0.24|0.32">)
holding one datatype-coloured shape (NUMBER #3ee0cf, BOOLEAN #f46bd6). Only the routine states
(normal, leaving) are stripped; error keeps its L5 treatment. Idempotent.
"""
import pathlib, re, sys
import xml.etree.ElementTree as ET

SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")
DATA = ("#3ee0cf", "#f46bd6")
root_dir = pathlib.Path(__file__).resolve().parent.parent / "assets/art/packet"


def is_halo_group(g) -> bool:
    m = re.match(r"opacity:([0-9.]+)(;|$)", g.get("style", "").strip())
    if not m or float(m.group(1)) >= 0.5:
        return False
    shapes = [e for e in g.iter() if e.tag.split("}")[1] in ("rect", "ellipse", "circle", "path")
              and "fill:none" not in e.get("style", "")]
    return len(shapes) == 1 and any(c in shapes[0].get("style", "") for c in DATA)


changed = 0
for f in sorted(root_dir.glob("packet_*_*_*.svg")):
    if not (f.stem.endswith("_normal") or f.stem.endswith("_leaving")):
        continue
    tree = ET.parse(f)
    parents = {c: p for p in tree.iter() for c in p}
    halos = [g for g in tree.iter(f"{{{SVG}}}g") if is_halo_group(g)]
    for g in halos:
        parents[g].remove(g)
    if halos:
        tree.write(f, encoding="unicode")
        changed += 1
        print(f"{f.name}: removed {len(halos)} halo group(s)")
print(f"{changed} files changed", file=sys.stderr)
