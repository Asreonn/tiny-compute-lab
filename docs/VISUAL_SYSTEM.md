# Tiny Compute Lab — Visual System (canonical: V2.1 machines + Signal System V1)

> **This current visual language is the canonical Tiny Compute Lab style. All future component and UI
> work must conform to it.** Rules, what is fixed and what may vary: `docs/STYLE_GUIDE.md` ·
> Penpot `12 Style Lock V1` · roadmap: `docs/COMPONENT_ROADMAP.md` / Penpot `14 Roadmap Kit`.

> **Physical compute modules installed into a miniature computer factory.**
> Not "UI boxes connected with lines".

Source of truth: the Penpot file (local Penpot, `localhost:9001`). Start at page
**`12 Style Lock V1`** (production reference). Wire/packet/bus rules: **`13 Signal System`**. Token values: `design/tokens.json` (mirrored into Penpot set
`tcl/core` and generated into Godot as `core/visual/palette.gd` by `tools/gen_palette.py`).

Reference renders are in `design/previews/` (`ds_v2_*.png`, `showcase_gameplay_v2.png`).

---

## 1. Design philosophy

| Principle | What it means in practice |
|---|---|
| **Shape before text** | A machine is recognised by silhouette + internal structure. Names live in hover/inspector. Hard test: `ds_v2_shape_test.png` (no labels, full grayscale). |
| **Installed, not drawn** | Every machine sits in an **InstallPad** socket and has physical layers: thickness lip + drop shadow, plate, frame, bevel highlight, screws, LED bezel, copper/gold contacts. |
| **Motion = computation** | Idle is quiet. Activity starts *inside* the machine (its ActivityArea) and on the wire *around the moving packet*. Nothing loops for decoration. |
| **Colour is reinforcement** | Datatype = shape first (circle / diamond / keyed diamond), colour second. Amber = warning/pressure. Red = real errors only. |
| **One ecosystem** | 11 chassis forms share one material stack. Future hardware extends existing forms instead of inventing new art. |
| **Evolution of V1** | Kept: dark PCB board, cyan NUMBER / magenta BOOLEAN, amber bottleneck, orthogonal 45° PCB routing, JetBrains Mono, compact modules. |

## 2. Visual hierarchy (what the eye should hit first)

1. **Board activity** — packets moving, active wire segments, processing dies.
2. **Machines** — silhouettes, ports, state (LED, external blocked/error badge).
3. **Player wires** — quiet embedded channels.
4. **Board substrate** — very low contrast zones/traces/silkscreen.
5. **HUD** — thin top bar, floating panels; never brighter than the board.

## 3. Tokens (additions in V2)

`color.material.*` — `plate #1F302C`, `plate-hi #2C433D`, `plate-lo #172622` (lip), `frame #4A6961`,
`copper #C08A52`, `copper-dim #5A432E`, `gold #D9B45B` (contacts), `vent #091210` (trenches/bays),
`silk #CFE0DA` (silkscreen, used at ~55 % opacity), `die #0C1614`.
`color.board.*` — `zone`, `zone-edge`, `pad`, `pad-edge`, `silk`.
`zoom` thresholds in `tokens.json`: FAR < 0.6×, CLOSE > 1.35×.
All V1 tokens are kept (see page `01 Foundations`).

## 4. Machine anatomy

Every machine component (Penpot page `05 Machines`) is composed, bottom → top, from shared primitives:

```
Machine
├─ InstallPad      (Size S|M|L × State)          board socket; hover/selection/placement live here
├─ MachineShell    (Form × Size)                  chassis: lip, plate, frame, bevel, screws, contacts, LED bezel
├─ FamilyTab       (Family)                        24×3 tab — the ONLY family colour on a machine
├─ ActivityArea    (Kind × State)                  PrimaryActivityArea: where computation is visible
├─ FunctionGlyph   (icon op_*)                     only where the area needs a symbol (Add, Multiply, Compare)
├─ MiniDisplay     (W28|W36|W44) + value text      only for the one essential value (+5, ×2, 3t); Compare uses a large operator + threshold text instead
├─ Silkscreen text (optional, close zoom)          e.g. ×12 remaining, 3/16, x², ALT
├─ StatusLED       (State)                         sits in the chassis bezel
├─ Ports           (Direction × Datatype × State)  on tile-edge anchors
└─ StateLayer      (State × Size)                  runtime overlay, form-independent (not part of the component)
```

Exact coordinates for every machine: **`design/machine_layouts.json`** (also copied to
`assets/art/machine_layouts.json` for Godot).

## 5. Chassis forms & sizes

Grid: 1 tile = 64 px. Footprints: **S 1×1**, **M 2×1**, **L 2×2**. Ports sit on tile-edge midpoints
(W = inputs, E = outputs, N = control). Rotation (R) rotates the footprint; content stays upright.

| Form | Size | Used by | Reads as | Future hardware |
|---|---|---|---|---|
| Module | S / M / L | Add, Multiply (M) · Delay, Counter (S) | chamfered chip plate | Register, ALU (L) |
| Chevron | S | Compare | arrow nose = decision | MUX select logic |
| Valve | S | Gate | control tower on top | Tri-state buffer |
| EdgeIn / EdgeOut | M | Input / Output | edge connector with gold fingers = board edge | Bus / IO ports |
| Cartridge | M | Buffer | RAM stick: bays + key notch + gold fingers | RAM, Cache |
| Chip | L | Processor | QFP package with pins + die | CPU core, Vector unit, Neural accelerator |
| SplitWedge / MergeWedge | L | Splitter / Merger | widening / narrowing trapezoid | DEMUX / MUX, Bus switch |

## 6. Machine families

Same ecosystem, different silhouettes (colour only on the tab):
**IO** (Input, Output) · **Math/Compute** (Add, Multiply, Processor) · **Logic** (Compare, Gate) ·
**Routing** (Splitter, Merger) · **Flow/Storage** (Buffer, Delay, Counter).

Roadmap sub-families use the **parent hue as a segmented tab**: **View** ⊂ IO · **Conversion** ⊂ Routing ·
**Memory** ⊂ Storage · **Control** ⊂ Compute (full list: `docs/COMPONENT_ROADMAP.md`).

## 7. ActivityArea (PrimaryActivityArea)

| Kind | Machine | States | What changes |
|---|---|---|---|
| Dial | Add, Multiply | Idle, Active | 40 px operation disc under a 24 px op glyph; ring + disc edge light cyan (V2.1: tick ring removed) |
| Die | Processor | Idle, Processing, Done | 48 px die, 4 × 16 px cores light progressively (sweep = ticks × tick); Done = green |
| Bank | Buffer | 0, 1, 2, 3, 4, Blocked | bays fill **from the OUT side** with vertical data cells; full = storage-orange bay edges; Blocked = amber |
| Split | Splitter | Idle, LaneA, LaneB, Dup | chosen lane core lights (9 px channel, 3.5 px core); V2.1: lane lamps removed |
| Merge | Merger | Idle, LaneA, LaneB | resolved lane + output lane light (same channel weights as Split) |
| Valve | Gate | Closed, Waiting, Open | blade drops across the data path (Closed) / lifts into the tower housing with a magenta key (Open); path core lights only when open |
| Comparator | Compare | Idle, True, False | 30×24 operator window (the big `>` / `<` / `=` sits in it); True = magenta edge + tint, False = dim magenta edge |
| Coil | Delay | Idle, Active | serpentine delay line lights |
| Counter | Counter | Idle, Tick | digit window flashes, tally advances |
| Feed | Input | Idle, Feeding, Empty | queued chips + chevrons pulse toward the output |
| Bin | Output | Idle, Ok, Error | validator ring shows ✓ / ✗ |

## 8. Ports

`Port` = contact pad + socket/plug + lead. Axes: **Direction** (Input, Output, Control) ×
**Datatype** (Number, Boolean) × **State** (Idle, Hover, TargetValid, TargetInvalid, Connected,
Active, Blocked, Error, Disabled). `TargetValid` is the spec's **Available**.

- Input = **socket** (hollow ring + dark hole). Output = **plug** (filled + pin). V2.1: body 14 px (was 12), 2.5 px ring, 18 px contact pad, and a **flow chevron on the wire side** (IN points into the socket, OUT points away, CONTROL points down) — direction reads while paused, without arrows on wires. Control = **keyed diamond** (key tab) on the north edge — a control port can never be mistaken for a data port.
- Shape encodes datatype: **circle = NUMBER, diamond = BOOLEAN** (future: capsule VECTOR, 2×2 MATRIX, square+bar TEXT, frame IMAGE, hexagon INSTRUCTION — page `02`).
- Idle ports use the *dim* datatype colour; Active lights the contact pad too.

## 9. Datatypes

| Type | Shape | Colour | Wire core | Packet |
|---|---|---|---|---|
| NUMBER | circle | `data.number` cyan | solid | capsule chip with gold caps |
| BOOLEAN | diamond | `data.boolean` magenta | dashed | pointed capsule (close) / diamond token (normal) |

Grayscale-safe: shape + wire pattern survive without colour (proof on page `02` and page `10`).

## 10. Packets (Signal System V1)

`Packet` = **Datatype × Zoom (Close, Normal, Far) × State (Normal, Entering, Processing, Leaving, Queued, Error)**.
Packets are lightweight *data chips*, never larger than a port. Values are never baked into art; Godot renders them.

| State | Meaning | Treatment |
|---|---|---|
| Normal | travelling on a wire | faint datatype halo (14 %), 1.8 px outline, core bar (NUMBER) / lit core (BOOLEAN) |
| Entering | docking into an IN socket | 60 % opacity, no halo; Godot shrinks it into the port over 120 ms |
| Processing | held inside a machine | muted outline, no halo |
| Leaving | just emitted from an OUT socket | bright halo (32 %) |
| Queued | waiting at a blocked output | amber outline + dashed amber queue ring |
| Error | on the failure path | red |

- **Normal zoom**: NUMBER capsule 24×16 with gold caps + core bar; BOOLEAN diamond 20×20, **TRUE = lit core, FALSE = hollow core** (runtime).
- **Close**: capsule / pointed capsule with the value (`42`, `TRUE`). **Far**: 7 px dot / diamond.

## 11. Connections (Signal System V1)

`Wire` = **Shape (Straight, Corner, Junction, Stub) × Datatype × State**. In game, wires are procedural:
Penpot and Godot use the same renderer rules, `L.drawWire` in Penpot and `WireView` in Godot. Routing is
orthogonal on tile centres with **45° chamfers** (14 px; clamped to half the segment on short jogs).

Anatomy, bottom → top: `select-halo` (14 px, selected only) · **teardrop** (PCB landing that widens the
trace into the port's contact pad; start 6 px, end 20 px from the anchor; half-width 8 → 5) ·
`trench-edge` 10 px `board.pad-edge` · `trench` 8 px `material.vent` · `core` 2.5 px ·
`comet` (glow 10 px @20 %, tail 3 px @35 %, head 3.5 px) · `flow-chevrons` (selected only).

| State | Edge | Core | Extra |
|---|---|---|---|
| Idle | pad-edge | datatype-dim 2.5 | quiet; direction from port chevrons + teardrops |
| Hover | `state.hover` 75 % | datatype 80 % | |
| Selected | pad-edge + ice halo | datatype 3 | ice flow chevrons every 48 px |
| ActiveTransfer | pad-edge | datatype 50 % | **comet** at each packet: bright head at the packet, fading tail, follows the path |
| Blocked | amber 70 % | amber 3 | queued packet at the OUT port |
| Error | red 80 % | red 3 | |
| ConnectionPreview | — (no trench) | dashed `state.build` | drag-head dot |
| ValidTarget | — | solid green 3 | green target ring at the end |
| InvalidTarget | — | dashed red | red × at the end |

BOOLEAN / control wires use a **dashed** magenta core in every state (grayscale-safe).

## 11b. Width classes and buses

| Class | Wire | Port | Tag |
|---|---|---|---|
| Signal (BOOLEAN) | dashed magenta core | diamond | — |
| Value (NUMBER) | solid cyan core | circle | — |
| Bus (N bits) | 16 px ribbon, 14 px trench, 4 lanes at 1.4 px (> 4 bits still 4 lanes) | `BusPort` slot with lane contacts | `WidthTag` on buses > 80 px and next to width-changing ports |

Bus splitting/combining uses the wedge forms (Bus Splitter / Bus Combiner). Width conversion uses the
`Taper` region.

## 11c. Interpretation (view modes)

`Readout` (Mode: BIN, DEC, SDEC, HEX, CHR, TYPE): same bits, different view. Mode chip on the left,
value right-aligned. Examples: `0000 1011` · `11` · `−5` · `0x0B` · `'K'` · `NUM·8`. `Bits` region:
8 cells, lit = 1. Changing the mode is a display setting (Inspector → View as), never a new chassis.

## 12. Runtime states (machines)

| State | Where it shows | Treatment |
|---|---|---|
| Idle | — | nothing moves; LED dim |
| Hover | InstallPad Hover + StateLayer Hover | 2 px `state.hover` outline + 12 % pad tint; temporary |
| Selected | InstallPad Selected + StateLayer Selected | **outside** the footprint: 14×3 px ice corner brackets (5 px out), solid 1.5 px frame, 10 % base highlight; persistent and layered over any runtime state |
| Receiving | input side contacts + input port Active + LED | cyan contacts flash |
| Processing | **ActivityArea** (die/dial/coil/…) + LED; StateLayer only a faint underglow | internal activity |
| OutputReady | output side contacts + output port Active + LED green | |
| Blocked | amber 18 px pause badge **outside** the top-right corner + solid amber outline + output port Blocked + LED amber | "I have data but cannot send it" — never a red wash |
| Error | red outline + ! badge (same external corner slot as Blocked) + LED red | only for real errors (mission failure path) |
| Disabled | veil 60 % | |

## 13. Zoom-level rules

| Level | Camera zoom | Show | Hide |
|---|---|---|---|
| FAR | < 0.6× | silhouettes, wires, activity (ActivityArea, pulses), LEDs, hazard/error tags, Far packets | all text, packet values, silkscreen |
| NORMAL | 0.6–1.35× | + function glyphs, MiniDisplay values, ports, Normal packets (no numbers) | silkscreen, packet values |
| CLOSE | > 1.35× | + silkscreen, queue numbers, Close packets with values | — |

## 14. Hover, selection, warning, error

- **Hover** = fast context via `Tooltip` (Machine / Port / Wire / Packet / Simple), compact and subordinate. Machine: name, the key value, `ticks · power`. Port: `Number input`. Wire: `Number wire · 1 packet / tick`. Packet: `#143 · 42`.
- **Selection** = deep info in the `Inspector` (Configuration, State, Performance expanded; Statistics collapsed).
- **Warning** (amber): pressure, bottleneck, blocked, throughput below target.
- **Error** (red): only mission failures and invalid actions.

## 14b. V2.1 readability refinement (Penpot page `11 V2 Refinement`)

A refinement of V2, not a new art direction: the V2 chassis, palette, PCB look and component
structure are unchanged (~85 % of the appearance). Only readability, spacing and state clarity moved.
A rejected "V3 game-asset" experiment (mechanical silhouettes per machine) was dropped before it
reached Penpot — it broke family cohesion.

**Evidence frames** on page `11`: `V2 READABILITY REFINEMENT` (left = frozen V2, right = live
refined components, 1:1), `ORIGINAL V2 GAMEPLAY TEST` (frozen) and `REFINED V2 GAMEPLAY TEST`
(live) — identical layout, wires, packet positions and zoom.

**Machine spacing grid** (`tokens.json → machine-space`): XS 4 (chassis inset, related gap) ·
S 8 (min clearance between unrelated elements, decoration clearance) · M 12 (content margin, port
clearance half-width) · L 16 (gap between functional sections). Rules:
- Content never enters the port clearance zone (anchor ± 12 px on the port row).
- One primary function region per machine gets the strongest contrast; everything else is secondary.
- Decoration (screws, pin-1, silkscreen) only in corner zones with ≥ S clearance — if it does not fit it is removed.
- Family tab and LED sit at fixed slots (tab top-left / above the display column, LED top-right in the bezel).

**What changed**
| Area | V2 | V2.1 |
|---|---|---|
| Ports | 12 px body, in/out look alike | 14 px body, hollow IN / solid OUT, wire-side flow chevron |
| Add / Multiply | 36 px dial with tick ring, glyph 20 px | 40 px operation disc, 24 px glyph, display column aligned with the family tab; vents removed |
| Compare | `>|` icon + `> 10` display + result lamp next to the out port | one large operator in a 30×24 window, threshold below; result = window colour + BOOLEAN out port |
| Gate | thin stem, small blade, empty body | blade housing above the path, blade clearly crosses the data path when closed; tab bottom-left, no LED |
| Splitter / Merger | 7 px channels, lane lamps near the LED | 9 px channels, 3.5 px lit core, larger switch, lamps removed; `ALT` moved clear of lane B |
| Buffer | small pill chips, bays touching the tab | vertical cells fill from OUT side, full/blocked bay edges, 6 px clearance to tab, `×4` clear of bays |
| Processor | 44 px die, 12 px cores | 48 px die, 16 px cores, idle cores outlined, `x²` clear of the die |
| Input / Output | screws touching `×12` / `3/16` | screws removed on edge-connector forms; silkscreen left-aligned with the tray |
| S-size machines | LED squeezed in | no LED (StateLayer + function region carry state) |
| Hover / Selected | 1 px / dashed | see §12 (external brackets, base highlight) |
| Blocked / Error | tag inside the chassis over the LED | external corner badge, solid outline |
| Wires | 2 px core | 3 px core (ValidTarget 3.5) |
| Packets (Normal) | 16×16 | NUMBER 24×16 capsule, BOOLEAN 20×20 diamond — still lighter than machines |

## 15. HUD primitives (page `06`, V2 sections)

`MetricChip` (Normal/Warning/Good) · `SimStateBadge` (Build/Running/Paused/Failed/Complete) ·
`SimulationControls` (Build/Running/Paused) · `Segmented` (speed 1×/2×/4×) · `Toggle` · `Stepper` ·
`Dropdown` · `PaletteItem` (Default/Hover/Selected/Locked/New) · `InspectorRow` (Value/Warning/Good) ·
`InspectorSection` (Expanded/Collapsed) · `MissionSummary` (Collapsed/Expanded) · `Tooltip` (5 kinds) ·
`ContextMenu` (Machine/Wire) · `ResultPanel` (Pass/Fail — failure says WHY: expected / received / packet / path) ·
`MissionCard` (Locked/Available/Completed) · panels `TopBar`, `ToolRail`, `BuildPalette`, `Inspector`.

**TopBar (player mode)** shows only Mission · Sim state · Controls · Speed · Throughput · Power · Latency.
Exact ticks, IN/OUT rates, component counts and IDs belong in a debug overlay / inspector.

## 16. Board substrate

`BoardDecal` (Zone, TraceBundle, Vias, Fiducial, MountHole, SilkMark) — scattered sparsely and
deterministically per mission (seed = mission id). Contrast stays below player wires at all times.
Grid lines: minor `bg.grid`, every 4th `bg.grid-major`.

## 17. Penpot naming

Components live under `TinyCompute / <Group>`: `Ports`, `Connectors`, `Packets`, `Machine`,
`MachineStates`, `Machines`, `Icons`, `HUD`, `Board`. Variant properties use PascalCase names
(`Direction`, `Datatype`, `State`, `Size`, `Form`, `Kind`, `Zoom`, `Family`, `Width`).
Runtime-only overlays (StateLayer) are never baked into machine components.

## 18. Penpot → Godot mapping

Assets are exported by the Penpot MCP exporter (`generateMarkup` → cleaned SVG) into `assets/art/`.
`assets/art/manifest.json` lists each file's un-padded size `w,h` and `pad` (extra margin for
halos/shadows); place a sprite at `origin - pad`. SVGs contain **no dynamic text**.

| Penpot component | Asset pattern | Godot node (MachineView etc.) |
|---|---|---|
| InstallPad | `machine/pad_{state}_{s,m,l}.svg` | `MachineView/Pad` (texture swap; placement ghost reuses PlaceValid/PlaceInvalid) |
| MachineShell | `machine/shell_{form}_{size}.svg` | `MachineView/Body/Shell` |
| FamilyTab | `machine/tab_{family}.svg` | `Body/FamilyTab` |
| ActivityArea | `machine/area_{kind}_{state}.svg` | `Body/Activity` (texture swap per state; Die/Dial progress tweened) |
| MiniDisplay | `machine/display_w{28,36,44}.svg` + Label | `Content/Display` + `Content/Value` |
| StatusLED | `machine/led_{state}.svg` | `Content/LED` |
| StateLayer | `machine/state_{state}_{size}.svg` | `Body/StateLayer/<state>` alpha-tweened |
| Port | `port/port_{dir}_{type}_{state}.svg` | `PortView` (texture swap + pulse) |
| Packet | `packet/packet_{type}_{close,normal,far}_{state}.svg` + Label (close) | `PacketView` (LOD by camera zoom) |
| Wire | *(procedural)* | `WireView`: teardrops + trench + core + comet + chevrons with `draw_polyline` / `draw_colored_polygon`, chamfer 14 px (§11) |
| Bus | *(procedural)* | `BusView`: 16 px ribbon, 4 lanes, WidthTag sprite at the midpoint |
| BusPort | `port/busport_{in,out}_{state}.svg` | `PortView` (bus) |
| WidthTag | `signal/widthtag_{n}.svg` | sprite |
| Readout | `signal/readout_{mode}.svg` + Label | `Content/Readout` + `Content/Value` |
| BoardDecal | `board/decal_{kind}.svg` | `BoardView` scatter |
| Icons | `icon/*.svg` (white; tint with `modulate`) | HUD + FunctionGlyph |

Composition coordinates: `assets/art/machine_layouts.json`. A file-level composition test
(`design/previews/ds_v2_composed_from_exports.png`, built only from the exported layers) confirms they line up.

**Godot status:** `world/machines/machine_view.gd` was written against V1 assets (`machine_shell_*`,
`screen_*`, `*_decor.svg`) and must be updated to the table above before use. Simulation core,
missions and tests (`core/`, `game/`, `tests/`) are unaffected by the visual revision.

## 19. Library audit (V1 → V2)

**Retained (KEEP):** tokens `tcl/core` · 45 icons · FamilyTab · StatusLED · Button · IconButton ·
ToolbarItem · CategoryTab · grid/footprint foundations · motion tokens.

**Modified in place (REFINE)** — existing instances inherit V2 automatically:
- `MachineShell` — new **Form** axis, 11 chassis forms, material layers.
- `Port` — physical socket/plug on a contact pad; keyed CONTROL.
- `Packet` — data-chip capsule; **Near → Close**, new **Normal** zoom.
- `Wire` — embedded channel; states renamed *Active → ActiveTransfer, PreviewFree → ConnectionPreview, PreviewValid → ValidTarget, PreviewInvalid → InvalidTarget*.
- `StateLayer` — footprint-level V2 treatments.
- 12 machine components — recomposed from the V2 anatomy (no titles on the chassis).
- `Screen / Gameplay — Showcase (V2)` — reference composition updated to V2 parts.

**Deprecated:** `Screen (deprecated)` → MiniDisplay + ActivityArea · `ActivityBar (deprecated)` →
ActivityArea states · machine titles on chassis · V1 decor exports (`*_decor.svg`, `screen_*.svg`).

**New shared primitives:** InstallPad · ActivityArea · MiniDisplay · BoardDecal · MetricChip ·
SimStateBadge · SimulationControls · MissionSummary · Segmented · Toggle · Stepper · Dropdown ·
PaletteItem · InspectorRow · InspectorSection · Tooltip · ContextMenu · ResultPanel · MissionCard ·
TopBar · ToolRail · BuildPalette · Inspector.

## 20. Quality checklist (V2 self-review)

| # | Question | Result |
|---|---|---|
| 1 | Game rather than monitoring software? | Yes — HUD reduced to 3 metrics, physical modules, board dominant (`showcase_gameplay_v2.png`). |
| 2 | Still technical / computer-related? | Yes — PCB substrate, chips, RAM cartridge, edge connectors, silkscreen. |
| 3 | Miniature hardware, not UI boxes? | Yes — pads, lips, screws, pins, contacts, trenches. |
| 4 | Recognisable without labels? | Yes — grayscale/no-label test on page 10. |
| 5 | NUMBER vs BOOLEAN without colour? | Yes — circle vs diamond; solid vs dashed; keyed control. |
| 6 | Idle quiet? | Yes — dim cores, no looping motion. |
| 7 | Computation visibly alive? | Yes — ActivityArea states + localized wire pulses + motion storyboards. |
| 8 | Board is the hero? | Yes — thin top bar, floating panels. |
| 9 | Scales to RAM/ALU/CPU? | Yes — Cartridge / Module-L / Chip forms. |
| 10 | Truly modular? | Yes — machines are instances of ~8 shared primitives; exports are layers, not flattened art. |

Known gaps: Penpot's plugin API cannot rename the file ("New File 1"); rename it in the Penpot UI.
BOOLEAN FALSE packet is described (hollow diamond) but not a separate variant — Godot draws it by
swapping the core fill. Mission-select and result *screens* are composed from V2 components but no
full-screen V2 mock was produced (by request, the focus was the shared system).
