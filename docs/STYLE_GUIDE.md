# Tiny Compute Lab — Style Guide (Style Lock V1)

> **This current visual language is the canonical Tiny Compute Lab style. All future component and UI
> work must conform to it.**
>
> Canonical since 2026-09-23 (V2.1 machines + Signal System V1). Penpot source of truth:
> page **`12 Style Lock V1`**. Signal rules: page **`13 Signal System`**. Roadmap kit: page
> **`14 Roadmap Kit`**. Token source: `design/tokens.json`. Detailed specs: `docs/VISUAL_SYSTEM.md`.

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

## 3. What may vary

- **Chassis form** per family, but only from the existing forms, or a new form drawn with the same
  material layers, corner radii and frame weight.
- **Function region content**: operator text, readout mode, cell/lane patterns.
- **Port layout**: any tile-edge anchor (W, E, N, S). Control ports are always keyed diamonds on N or S.
- **Accent hue** for a brand-new *top-level* family, only if it is clearly separated from the data and
  state colours (see §6). Prefer a sub-family (segmented tab) first.
- **Silkscreen text**: short, ≤ 6 characters, 8 px, 55 % opacity, close zoom only.

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

**New family?** First try to make it a sub-family (segmented parent tab). A new top-level hue must
avoid cyan (174°), magenta (313°), amber (39°), red (354°) and green (140°), and stay at the existing
saturation and lightness.

## 7. Wires and data flow (Signal System V1, page `13`)

- A wire is an **embedded PCB trace**, not a pipe: trench edge, dark trench, thin core.
- **Idle** wires are quiet: dim datatype core. Direction comes from the port chevrons and the teardrops,
  not from arrows along the wire.
- **Active** (ActiveTransfer): core at 50 % datatype colour, plus a **comet** around each moving packet.
  The bright head is at the packet and the tail fades behind it. The comet follows the chamfered path.
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
- **Travel**: a faint datatype halo (14 %). **Entering** a port: 60 % opacity, no halo, shrinks into the
  socket. **Leaving**: brighter halo (32 %). **Inside a machine**: muted outline. **Queued/blocked at
  output**: amber outline + dashed amber queue ring.
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

## 13. How to add a new component (checklist)

1. Pick the family, or make a sub-family with a segmented parent tab.
2. Pick an existing chassis form and footprint (S 1×1, M 2×1, L 2×2).
3. Choose ONE function region (an existing `ActivityArea` kind, or a new kind drawn with the same weights).
4. Place ports on tile-edge anchors; use `BusPort` + `WidthTag` for buses.
5. Lay out on the machine-space grid; check port clearance and S clearance.
6. Test it in the **gameplay reference board** (page `12`) at 1:1 next to existing machines. Never judge
   it on a documentation board alone.
7. Add it to `docs/COMPONENT_ROADMAP.md` and export its assets (`assets/art`, `machine_layouts.json`).
