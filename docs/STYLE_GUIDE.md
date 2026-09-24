# Tiny Compute Lab — Style Guide (Style Lock V1)

> **This current visual language is the canonical Tiny Compute Lab style. All future component and UI
> work must conform to it.**
>
> Canonical since 2026-09-23 (V2.1 machines + Signal System V1). Penpot source of truth:
> page **`12 Style Lock V1`**. Signal rules: page **`13 Signal System`**. Roadmap kit: page
> **`14 Roadmap Kit`**. Token source: `design/tokens.json`. Detailed specs: `docs/VISUAL_SYSTEM.md`.
>
> **Systems Expansion lock (2026-09-24)** extends the style, it does not replace it. Penpot pages:
> - **`15 Systems · Infrastructure`**: raw boundary, USB family, contract drive, PSU.
> - **`16 Systems · Machines`**: resource indicators, Encoder/Decoder, thermal family, Status LED.
> - **`17 Systems · VFX Language`**: the intensity ladder.
> - **`18 Systems · Interaction`**
> - **`19 Systems · Gameplay Mockups`**: 1:1 compositions.
>
> Implementation geometry: `design/reference/systems_v1.js`. §14 below is the summary.

The style has been through one rejected pivot: the "V3 game-asset" experiment, with a unique mechanical
silhouette per machine and chunky extruded bodies. It broke family cohesion. The lesson is built into the
rules below. **Polish, don't reinvent.**

---

## 1. The style in one paragraph

A dark PCB / motherboard board. Compact modular machines are installed into sockets on it: one shared
chassis language, a thin technical frame and a small family accent. Each machine has one clear function
region. Data runs through recessed PCB traces and is carried by small, lightweight data chips. Colour is
restrained: cyan means numeric data, magenta means boolean/control, amber means congestion and red means a
real error. Interaction is shown outside the machine (brackets, badges); computation is shown inside it
(the function region wakes up). Idle is quiet, and motion only happens when the simulation does something.

## 2. What must stay fixed (never change without a new style lock)

| Area | Fixed rule |
|---|---|
| Board | `bg.board` #0C1614, 64 px grid (`bg.grid`, every 4th `bg.grid-major`), sparse low-contrast decals. Machines and player wires always dominate. |
| Chassis | Shared `MachineShell` forms (Module, Chevron, Valve, EdgeIn/Out, Cartridge, Chip, Split/MergeWedge). Plate `material.plate`, 1.5 px `material.frame`, 3 px lip, bevel highlight. No new chassis material. |
| Family accent | One 24×3 `FamilyTab` per machine. Sub-families use the **parent hue as a segmented tab** (two 11 px pieces). |
| Function region | Exactly one primary `ActivityArea` per machine (a second one only as a clearly subordinate helper). |
| Ports | 24 px box, 18 px copper contact pad, 14 px body. Hollow = IN, solid = OUT. Circle = NUMBER, diamond = BOOLEAN, slot = BUS. Flow chevron on the wire side. |
| Wires | Recessed PCB trace: 10 px edge, 8 px trench, 2.5 px core; orthogonal routing with 45° chamfers (14 px); PCB teardrop into every port. |
| Packets | Lightweight chips: NUMBER capsule 24×16 with gold caps, BOOLEAN diamond 20×20; never larger than a port. |
| Colour semantics | cyan `data.number` = numeric data · magenta `data.boolean` = boolean/control · amber `state.blocked` = congestion/waiting · red `state.error` = real errors only · green `state.valid` = success/valid target · ice `state.select` = selection. |
| Typography | JetBrains Mono everywhere; ExtraBold for values/titles, Medium for body. Only the essential value lives on a machine. |
| Spacing | Machine-space grid XS 4 · S 8 · M 12 · L 16 (`tokens.json → machine-space`). |
| Interaction | Hover = 2 px `state.hover` outline + 12 % pad tint. Selected = external ice brackets + solid frame + base highlight. Blocked/Error = external corner badge + outline. |
| Motion | Tick-locked, one easing (cubic-out), no decorative loops; see `docs/MOTION_SYSTEM.md`. |
| Effect intensity | The **VFX ladder** (§14.1): routine activity is nearly invisible; only critical states and contract completion are strong. No glow blobs, halos, bloom or body glow. |
| Status LED | V2 lamp: a 6 px lamp in a dark well, no glow disc. Meaning is carried by colour AND form (ring = thermal, diamond = error). |
| Raw data | IO green `family.io`: RawPort receptacle, pill RawToken with its glyph. Never enters a compute machine. |
| USB | The locked USB Input/Output keep their look and carry a female USB-A **port face**. Devices are male **data modules**. |
| Thermal | Copper, board-mounted hardware on a PCB footprint: no chassis, data ports or LED. A heat pipe is never styled like a wire. |
| Power | Gold (`material.gold`): PSU gauge cells, power pips, the power tab. |

## 3. What may vary

- **Chassis form** per family, but only from the existing forms, or a new form drawn with the same
  material layers, corner radii and frame weight.
- **Function region content**: operator text, readout mode, cell/lane patterns.
- **Port layout**: any tile-edge anchor (W, E, N, S). Control ports are always keyed diamonds on N or S.
- **Accent hue** for a brand-new *top-level* family, only if it is clearly separated from the data and
  state colours (see §6). Prefer a sub-family (segmented tab) first.
- **Silkscreen text**: short, ≤ 6 characters, 8 px, 55 % opacity, close zoom only.
- **Resource indicators** (replace the 2026-09-24 `◷4 ⚡1` stats silk; there is no text on the chassis):
  - **Clock:** one 5 px silk dot (α .7) per tick of job cost, up to 6, then a `+`.
  - **Power:** one 3×8 gold pip per power unit, up to 4.
  - **Clock mode:** 1 amber chevron = fast, 2 = overclocked, drawn before the dots.
  - **Position:** M/L are right-aligned at (W − 20, H − 15). S uses the compact form at the top-right (58, 4).
  - Normal and close zoom only. Exact numbers live in the hover card and the Inspector.
  - Fixed infrastructure (USB, drive, PSU) shows none.

## 4. Line-weight scale

| Weight | Use |
|---|---|
| 1 px | hairlines, grid, idle cell outlines, bus lanes (1.4) |
| 1.5 px | chassis frame, detail strokes, selected-wire chevrons |
| 2 px | function-region frames (active), port rings (2.5), control stems |
| 2.5 px | idle wire core |
| 3 px | lit wire core (selected, blocked, error) |
| 3.5 px | comet head |
| 8 / 10 px | wire trench / trench edge |
| 14 / 16 px | bus trench / bus edge |

## 5. Machine anatomy rules (every new machine)

```
Machine  = InstallPad(size) + MachineShell(form,size) + FamilyTab(family)
         + ActivityArea(kind,state)            ← the ONE function region
         + [operator text | Readout(mode) | MiniDisplay+value | glyph]
         + [WidthTag…] + [StatusLED if M/L] + Ports/BusPorts on tile-edge anchors
StateLayer (hover/selected/processing/blocked/error) is runtime-only, never baked in.
```

1. Content stays out of the **port clearance** (anchor ± 12 px on the port row).
2. Unrelated elements keep **≥ S (8 px)** apart; related ones **XS (4 px)**.
3. Decoration (screws, pin-1, silk) goes only in corner zones with ≥ S clearance. If it doesn't fit,
   remove it.
4. Family tab: top-left, or above the display column. LED: top-right in the chassis bezel. S-size
   machines have **no LED**.
5. Operators are large (16–18 px text in a 30×24 `OpWindow`). Values use Readout/MiniDisplay, never
   loose text.
6. Two-input binary operators use L size with inputs on W rows 0/1 and the output on E row 0, like the
   Merger.

## 6. Families

| Family | Tab | Typical forms | Members (MVP → roadmap) |
|---|---|---|---|
| IO | solid green | EdgeIn / EdgeOut | Input, Output, USB Input, Terminal Output, File Input*, Logger* |
| View *(IO sub-family)* | segmented green | Module-M | Number / Hex / Char / Type / Bit Viewer, Decoder-Display* |
| Math | solid blue | Module-S/M | Add, Multiply, Subtract, Modulo, Increment, Decrement |
| Logic | solid violet | Chevron, Valve, Module | Compare, Gate, AND, OR, XOR, NOT, Shift L/R |
| Routing | solid yellow | Split/MergeWedge | Splitter, Merger, Mux, Demux, Conditional Router, Type Switch, Selector* |
| Conversion *(Routing sub-family)* | segmented yellow | Module-M, Wedges | Zero/Sign Extend, Truncate, Adapters, Bus Splitter/Combiner |
| Storage/Flow | solid orange | Cartridge, Module-S | Buffer, Delay, Counter |
| Memory *(Storage sub-family)* | segmented orange | Cartridge-M, Module-L | Register, Register Bank, RAM, ROM, Addressed Memory* |
| Compute | solid grey | Chip-L | Processor, ALU |
| Control *(Compute sub-family)* | segmented grey | Chip-L, Module-S | Program Counter, Instruction Decoder, Control Unit*, R/W Controller* |

\* concept slots on page `14`: not yet drawn as components.

**Infrastructure** is not a machine family and has no FamilyTab hue:
- **Power:** PSU, with a gold tab.
- **Thermal:** heatsink, blower, heat pipe, radiator. These use a copper PCB footprint with no chassis.
- **The USB port face and data modules.**

Encoders and decoders belong to Conversion (segmented yellow).

**New family?** First try to make it a sub-family (segmented parent tab). A new top-level hue must
avoid cyan (174°), magenta (313°), amber (39°), red (354°) and green (140°), and stay at the existing
saturation and lightness.

## 7. Wires and data flow (Signal System V1, page `13`)

- A wire is an **embedded PCB trace**, not a pipe: trench edge, dark trench, thin core.
- **Idle** wires are quiet: dim datatype core. Direction comes from the port chevrons and the teardrops,
  not from arrows along the wire.
- **Active** (ActiveTransfer): core at 50 % datatype colour, plus a short **brighter core segment**
  (2.5 px, α .9, about 30 px) behind each moving packet, following the chamfered path. Since the
  VFX ladder there is **no glow layer**: the old 10 px comet glow is retired.
- **Selected**: 14 px ice halo, lit core, and ice flow chevrons every 48 px. Direction is shown on demand.
- **Hover**: edge lifts to `state.hover`, core brightens to 80 %.
- **Blocked**: amber edge + amber core; the waiting packet sits at the OUT port with a dashed amber queue ring.
- **Error**: red edge + core.
- **Preview while dragging**: no trench, dashed `state.build` line, drag head dot.
  **Valid target**: solid green line + green target ring. **Invalid**: dashed red + red ×.
- **BOOLEAN / control** lines use a **dashed** magenta core. This distinction is readable in grayscale.
- **Port → wire**: every wire ends in a **PCB teardrop** that widens the trace into the port's contact
  pad. Port, teardrop and trench read as one part.

## 8. Packets

- Lightweight: packets never out-rank machines. NUMBER capsule 24×16 (gold caps, core bar);
  BOOLEAN diamond 20×20 (TRUE = lit core, FALSE = hollow core).
- **Packets have no halos** (VFX ladder L1).
  - **Travel:** the chip only.
  - **Entering** a port: 60 % opacity; it shrinks into the socket while the port shows a 1 px contact
    ring (≤ 120 ms).
  - **Leaving:** the same contact ring on the OUT port.
  - **Inside a machine:** not drawn. The machine's function region shows the work.
  - **Queued/blocked at output:** amber outline + dashed amber queue ring.
- **Raw tokens** (`family.io` pill, glyph inside) follow the same rules on raw links.
- **Zoom**: Far = 7 px dot/diamond · Normal = chip without value · Close = value text (`42`, `TRUE`).

## 9. Width classes and buses (future-facing)

| Class | Look | Port |
|---|---|---|
| Signal (1 bit, BOOLEAN) | single dashed magenta core | diamond |
| Value (NUMBER, small integer) | single solid cyan core | circle |
| Bus (explicit N bits, N ≥ 2) | 16 px ribbon, 4 thin lanes; wider buses still show 4 lanes + `WidthTag` | `BusPort` slot + `WidthTag` |

- A `WidthTag` sits on buses longer than ~80 px and next to every width-changing port.
- Bus split/combine uses the Routing wedges (Bus Splitter / Bus Combiner), with the lanes fanning in or out.
- Width conversion shows as a **Taper** region: lanes widen (extend) or narrow (truncate).

## 10. Interpretation (view modes)

All data is fundamentally bits. A **Readout** shows one interpretation, named by its mode chip:
`BIN 0000 1011` · `DEC 11` · `SDEC −5` · `HEX 0x0B` · `CHR 'K'` · `TYPE NUM·8`.

- The mode chip is always on the left, and the value is right-aligned in `data.number` (CHR values in the IO green).
- Changing the mode never changes the chassis. It is a display setting of the same machine
  (Inspector → View as …).
- A Bit strip (8 cells) is the raw view: lit cell = 1.

## 11. HUD

The V2 HUD is canonical: quiet top bar, tool rail, compact build palette, 4-section inspector, short
tooltips. Planned extensions, in the same components:
- A **"View as" segmented control** (BIN / DEC / HEX / CHR) in the Inspector.
- A **width chip** in the tooltip for bus wires.
- **Palette categories** for the new families, using the family tab as the category marker.

## 12. What to avoid

- Bulky pipes, hoses, belts, cartoon conduits; arrows painted along every wire.
- New materials, gradients, textures, heavy shadows, or photoreal hardware.
- A different silhouette language per machine, and decorative mechanical parts with no function.
- Screws, silk or badges touching functional elements, ports or other decoration.
- Micro-text on machines. Tertiary info (ticks, power, IDs) belongs in the inspector.
- Colour as the only differentiator; red for anything that is not an error; constant idle animation.
- Packets larger than ports, and packets floating off a trace.
- Glow blobs, halos, bloom, thick glowing outlines and whole-body glow for routine work. Spending strong
  effects on routine actions.
- Consumer-gadget props: generic USB sticks, household fans, box-shaped "cooling machines".
- Heat pipes that look like wires: teal/pink/green cores, ports, or packets on a heat pipe.

## 13. How to add a new component (checklist)

1. Pick the family, or make a sub-family with a segmented parent tab.
2. Pick an existing chassis form and footprint (S 1×1, M 2×1, L 2×2).
3. Choose ONE function region (an existing `ActivityArea` kind, or a new kind drawn with the same weights).
4. Place ports on tile-edge anchors; use `BusPort` + `WidthTag` for buses.
5. Lay out on the machine-space grid; check port clearance and S clearance.
6. Test it in the **gameplay reference board** (page `12`) at 1:1 next to existing machines. Never judge
   it on a documentation board alone.
7. Add it to `docs/COMPONENT_ROADMAP.md` and export its assets (`assets/art`, `machine_layouts.json`).
   Parts of the systems expansion are drawn procedurally from `design/reference/systems_v1.js`.
8. Give it resource indicators (clock dots, power pips), and name the VFX-ladder level of every effect it uses.

## 14. Systems Expansion (locked 2026-09-24)

### 14.1 VFX intensity ladder (hard limits; Penpot page `17`)

| Level | What | Limits |
|---|---|---|
| L0 idle | nothing | — |
| L1 routine transfer | packet travel, 1 px port contact ring, brighter wire-core segment | ≤ 1 px ring / 2.5 px core, α ≤ .6, ≤ 120 ms |
| L2 processing | the function region only (ring, lane, valve, bays, Bits strip) + LED | inside the ActivityArea, α ≤ .9 |
| L3 selection | canonical brackets + 1.5 px outline, quick action bar | static |
| L4 warning | amber LED, thermal strip, 1.5 px underline, pause badge | ≤ 2 px, slow pulse ≥ 1.2 s on the strip only |
| L5 critical / complete | error, PSU overload, CRITICAL heat, contract complete | ≤ 2 px frame + badge, ≤ 2 pulses then steady |

### 14.2 Status LED V2 (page `16` · `led_*.svg`)
- Built from a 10 px dark well (`material.vent`, 0.75 px `material.frame` rim), a 6 px lamp and a 1.5 px
  specular. There is no glow disc in any state.
- States:

| State | Lamp |
|---|---|
| Off | `machine.rail` |
| Idle | `text.muted` |
| Receiving | cyan |
| Processing | blue |
| OutputReady | green |
| Waiting (`blocked`) | amber |
| **Throttling** | amber + 1 px amber ring |
| **Overheated** | red + 1 px red ring |
| **Error** | red *diamond* |

### 14.3 Raw boundary (page `15 / 01`)
- **RawPort:** a USB-style receptacle (14×10) with a tongue on the copper pad.
- **RawToken:** a `family.io` pill (Normal 20×12, Close 36×18) with its glyph. Queued = dashed ring;
  accepted = thin green ring.
- **Raw link:** the same PCB trench with an IO-green core (α .35).
- Raw values never enter compute machines. Encoders and decoders are the boundary.

### 14.4 USB family (page `15 / 02`, option C)
- **Locked components:** USB Input (EdgeIn) and Output (EdgeOut) are unchanged, plus a female USB-A
  **port face** (16×36): metal frame, dark opening, tongue with 4 gold contacts.
- **Data modules** (96×56, male USB-A plug 22×28 with two square holes).
  - The outer silhouette is the family key: Bit square · Number chamfered · Text rounded · Key notched ·
    Sensor finned · Contract slanted and flipped.
  - Each module has a key bar, a screen window with its glyph and a 10×3 data store (read cursor or
    fill progress).
  - Plugged in, the plug fills the port opening and the module sits flush at the board edge.
- **Port racks (page `15 / 02c`):**
  - There are 4 ports per side at rows 1/4/7/10, the top open first.
  - A **sealed bay** is a dashed `board.silk` 2×1 footprint with "USB n · opens at Lx" silk and a
    capped port face (a `material.plate` cap + 2 screws in the port frame).
  - The output side takes a **Job drive** or a **Monitor**. The Monitor is a bezel-silhouette module,
    `state.select` key bar, a wide screen with the last value, and a 10-sample history strip.
  - The **Drive Tray** mirrors the Device Tray for output ports.
- **Desk zones (page `15 / 02d`):**
  - A `surface.sunken` mat (r10, `surface.border`) with a 9 px "INPUT MODULES" / "OUTPUT DEVICES"
    header.
  - Slots are 148×68 (r6, 1 px `board.silk` α .5; empty slots are dashed).
  - Modules lie with their plug facing the laptop.
  - Dragging shows a module ghost at α .7 and the canonical 1.5 px `state.valid` target ring on the
    port (a red slash when refused).
- **Device Tray** (fallback): a world-anchored popover with module thumbnails, available/in-use/hover/locked rows
  (locked rows state their unlock) and Unplug.

### 14.5 Encoder / Decoder (page `16 / 06`)
- M Module chassis with a segmented Conversion tab.
- Layout: raw token slot (pill) → chevron → canonical `Bits` strip. The decoder mirrors it.
- Silk `CHR`/`NUM`, plus a WidthTag on the bus side.

### 14.6 Power (page `15 / 04`)
- **PSU:** M Module chassis with a gold tab, `icon_power` and a gauge with one cell per power unit.
- **Gauge colours:** gold, then amber at ≥ 75 %, then red plus an overflow chevron above 100 %.
- Tiers: 8 · 16 · 32 · 64.

### 14.7 Thermal family (page `16 / 07`)
- **Board-level copper hardware on a PCB footprint** (`board.pad` fill, `material.copper-dim` outline,
  silk corner marks): **no chassis, no data ports, no LED.**
- **Heatsink:** copper spreader, 11 dense fins, 4 screws.
- **Blower:** a volute housing with an 18-blade impeller (it rotates while running), an outlet with
  hairline airflow, and a 3-pin gold power header.
- **Heat pipe:** a routed copper conduit (12 px vent, 9 px copper-dim, 2.5 px copper, gold highlight)
  with square thermal pads.
- **Radiator:** an L edge panel with 26 fins between copper manifolds, inlets and brackets.
- **Warmth:** only a faint amber gradient on fin tips or along copper. The thermal overlay carries the
  full picture.
- **Heat pipe ≠ data wire:**
  - Copper only.
  - A 9 px body and square pads, never ports.
  - No packets or comets.
  - Wires and heat pipes never share or cross a tile.

### 14.8 Thermal strip
A 2 px bar just inside the chassis top edge:
- **NORMAL:** absent.
- **WARM:** amber α .3.
- **HOT:** amber.
- **THROTTLING:** amber + LED Throttling + a ≥ 1.2 s pulse.
- **CRITICAL:** red + a 1.5 px red frame + the canonical pause badge.

The body is never tinted.

### 14.9 Interaction and overlays (pages `18`, `19`)
Hover card, quick action bar, smart-wire targets, connected-move hologram, palette QoL, and the thermal
and power overlays. Exact numbers are in `docs/VISUAL_SYSTEM.md §21` and `systems_v1.js`.
