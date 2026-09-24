# Tiny Compute Lab — Implementation Plan

> Code structure and rules: `docs/ARCHITECTURE.md`. Visuals: `docs/STYLE_GUIDE.md` (Style Lock V1,
> canonical, never redrawn). The Penpot roadmap kit (page 14, `docs/COMPONENT_ROADMAP.md`) is
> **future-ready design, not an implementation checklist.**

## Ground rules

- **BITVECTOR IS THE ONLY CORE VALUE MODEL.**
- **REPRESENTATION != DATA.** BIN, DEC, HEX and CHAR are views.
- **WIDTH IS GAMEPLAY.** Width is explicit on values, ports, component instances and missions.
- **NO GLOBAL DEFAULT 8-BIT MODEL.** **3-bit is the first playable width.** 5-bit comes with the
  character slice. **8-bit is a later BYTE milestone.**
- Do not start RAM, ALU, CPU or the full 34-component roadmap. Build only what the current slice needs.
- **Work split:** DS writes routine GDScript, logic, tests and scenes (`make test`). The
  orchestrator owns architecture, review, Godot runs, integration and visual fidelity.

## Direction change (player, 2026-09-24): one persistent Lab, not a series of puzzles

The main game is **one persistent board that the player keeps growing** (Shapez-style). A central
**Hub** asks for something to be delivered; when the request is met, the next request comes (and
unlocks new machines). The factory is never reset between requests. The separate from-scratch
missions (a1…b3) stay only as the **Tutorial**.

### Lab mode (decided with the player, 2026-09-24)
- **Tutorial:** the current missions (N results of a transformation, varied transformations).
- **Main game (Lab):** one persistent factory, never reset.
  - **Requests are "deliver N × value V":** V is an explicit BitVector (e.g. 20 × `100` 3-bit, 30 × `K` 5-bit, later 8-bit `A`).
  - **Validation:** only an exact match counts (width and bits); anything else is ignored with no penalty.
  - **Progression:** meeting a request unlocks machines, new data sources and board area.
- **No central Hub.** Data arrives through **USB Input** ports ("someone plugs in a stick of raw
  data") and leaves through a **USB Output** port ("the processed data is handed back").
  - USB Output is a new canonical component, to be designed in Penpot as the mirror of the USB
    Input kit (EdgeOut chassis, USB silk, BusPort, width tag). Until then it reuses the Output
    composition with USB silk.
  - The USB Output port accepts any width: it validates width and bits against the request. This
    is the one documented exception to the width-match rule.
- **Expanding board:** the Lab starts small; each level can grow the board and add USB Inputs in
  the new area. Existing machines and wires never move.
- **Live editing:** the simulation keeps running while the player builds (no reset on edit).
- **Content:** the machines of slices C–E arrive as Lab unlocks.

## Slice order

| Slice | Goal | Width | New components | New views/HUD |
|---|---|---|---|---|
| **A** | 3-bit USB → Add +2 → Output | 3 | USB Input, Add, Output | board, machine, wire, packet, minimal HUD, View as BIN/DEC/HEX |
| **B** | 5-bit characters, Caesar shift | 5 | Modulo, Terminal Output, (Char Viewer) | CHAR view mode, TCL-5 charset |
| **C** | Mixed TYPE + PAYLOAD routing | 5 (2+3) | Bit Slice/Split, Type Switch or Demux, Compare, Gate | bit-field display in Readout/Bits |
| **D** | Width conversion and buses; **BYTE milestone** | 3/5 → 8 | Zero Extend, Truncate, Bus Splitter/Combiner | BusPort, WidthTag, bus ribbon, ASCII CHAR |
| **E** | Broader factory optimisation | mixed | Buffer, Delay, Splitter/Merger, Processor | metrics HUD, goals; legacy missions redesigned |

### Slice A: first playable (3-bit)

**Missions** (`default_width = 3`, view modes `[BIN, UDEC, HEX]`, BIN by default):

| id | Title | Input | Expected | Teaches |
|---|---|---|---|---|
| `a1_plus_two` | Plus Two | `010, 011, 100` | `100, 101, 110` | wires, Add, reading bits |
| `a2_wrap` | Wrap Around | `101, 110, 111` | `111, 000, 001` | 3-bit overflow is real; the carry LED lights on `110+010` and `111+010` |

**Components:**
- **USB Input** (IO, EdgeIn + Feed, BusPort + WidthTag 3, width locked by the mission).
- **Add** (Math, M, Dial `+`, constant `k`, instance width, `last_carry`).
- **Output** (IO, EdgeOut + Bin + Readout, validates).

**Acceptance:**
- Headless: both missions pass with reference solutions.
- `111 + 001 = 000, carry 1` holds in the BitVector tests.
- A 3→5 connection is rejected with a reason.
- The runs are deterministic.
- Visual: the board screenshot at 1:1 matches Penpot `12 Style Lock V1`, gameplay reference board
  (same assets, wire look and packet look).

**DS jobs (in order):**
1. **A1 core types:** BitVector, ViewMode, Charset and their tests. New files only.
2. **A2 simulation migration:**
   - `Packet.data`; PortDefinition with `role`/`width`; `Machine.width`, `set_width`, width checks.
   - The `logic/` split and Add carry.
   - `MissionDef` widths; the legacy flag on the old ten missions; slice A missions, solutions and tests.
3. **A3 runtime:** `SimulationManager` autoload (fixed ticks, speed, pause/step, `alpha`,
   signals) and save/load of layouts per mission.
4. **A4 world views:**
   - `BoardView` (grid, decals).
   - `MachineView` rebuilt from `machine_layouts.json` (V2.1 assets, states, LED, WidthTag).
   - `ConnectionView` (Signal System V1 procedural trace), `PacketView` (zoom tiers, BIN label).
   - Camera.
5. **A5 tools + HUD:**
   - Place, wire, select, rotate and delete tools.
   - Top bar (mission, run/step/reset, speed), build palette, Inspector (width, `k`, View as),
     mission panel (expected vs received per packet, in the chosen view mode).
   - Result dialog.
6. **Orchestrator:** integration pass, screenshot comparison against Penpot, fixes, and docs.

### Slice B: 5-bit characters (after A is playable)
- Charset TCL-5: `A`=0 … `Z`=25, space 26, `.` 27, `,` 28, `!` 29, `?` 30, `-` 31.
- **Missions:**
  - "Read the signal": pass-through, with CHAR view introduced.
  - "Shift by 3": plain 5-bit Add wraps at 32, so X/Y/Z become punctuation.
  - "Caesar": Add 3 → Modulo 26.
- **Components:** Modulo (Math, M), Terminal Output (EdgeOut + Readout `CHR`).

### Slice C: TYPE + PAYLOAD
- A word = tag bits + payload bits, e.g. 5-bit = 2-bit type + 3-bit payload.
- Routing by tag uses Slice, then Compare/Type Switch, then Gate/Demux.
- The detailed design is made at the start of the slice. It reuses the kit's Split lanes, OpWindow and
  Bits regions.

### Slice D: width conversion, buses, BYTE
- Zero Extend (3→5, 5→8) and Truncate.
- Bus Splitter/Combiner, BusPort + WidthTag, and the procedural bus ribbon.
- 8-bit ASCII CHAR: `01000001` → `A`.

### Slice E: factory optimisation
- Buffer, Delay, Splitter/Merger, Processor, throughput/latency/power goals.
- The ten legacy missions are redesigned on explicit widths.
- Until then they remain mechanics regression tests only.

## Status

| Item | State |
|---|---|
| A1 core types: BitVector, ViewMode, Charset | done |
| A2 sim on BitVector with explicit widths; slice A missions a1_plus_two, a2_wrap; legacy missions as regression | done |
| A3 SimulationManager autoload + SaveStore | done |
| A4 board, MachineView (Penpot exports), Signal V1 wires, packets with view-mode labels, camera | done |
| A5 tools (place/wire/move/delete/rotate) + canonical HUD V2 | done |
| Tests | 191 headless checks + `tools/tools_smoke.gd` (SMOKE PASS) |
| Previews | `design/previews/godot/` |
| Open for slice A | manual playtest with real mouse input; mission select (Menu/MISSIONS); tooltip visual check; a2_wrap carry LED on the Add |
| Next | slice B (5-bit characters, TCL-5 CHAR view, Modulo, Terminal Output) |
