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

## Post-MVP polish phase (player request, 2026-09-24)
Starts once the MVP content is complete. Everything must stay inside the canonical style (Style Lock V1).
- **VFX and shaders** in the design language:
  - trace glow and comet shaders
  - holographic placement and wire previews
  - processing / level-complete / USB delivery effects
  - subtle board ambience
- **Animations:** machine place/remove (build and removal bars), port pulses, LED transitions,
  level-up and board-expansion reveal, HUD panel transitions.
- **QoL and controls:**
  - Speed on number keys: `1` = 1×, `2` = 2×, `3` = 5×, `4` = 10×.
  - Tools: `Q` select, `W` wire, `E` build the last component, `R` rotate the hovered/selected/ghost machine.
    Delete moves to the quick action bar (`X`/`Del`). See the control map in `docs/SYSTEMS_EXPANSION.md §9`.
  - Smoother camera (inertia, zoom to cursor, edge pan), smoother drag/placement feel.
  - Copy/paste, undo/redo, multi-select, and similar conveniences.

## Systems Expansion (production brief 2026-09-24): design locked, implementation plan

**Documents:**
- Game rules: `docs/SYSTEMS_EXPANSION.md`.
- Visuals: `docs/STYLE_GUIDE.md §14`, `docs/VISUAL_SYSTEM.md §21`, `docs/MOTION_SYSTEM.md §8`.
- Geometry: `design/reference/systems_v1.js`. Penpot pages 15–19.

**Work split:**
- **DS** implements scoped jobs: exact files, constraints, tests, acceptance criteria and non-goals.
- **The orchestrator** reviews every diff, runs `make test` and the smoke/motion scripts, renders
  screenshots against Penpot pages 15–19 and commits one checkpoint at a time.

**DS model choice:**
- `ds hard` for architecture: raw boundary, contracts, power/work units, thermal, undo, connected move.
- `ds submit` for views, HUD and component batches.

### Checkpoint D: USB, encoding, contracts
| Job | Route | Scope |
|---|---|---|
| D1 | hard | **Raw boundary + lineage.**<br>• `core/data/raw_value.gd` (kind TEXT/NUMBER/KEY/SENSOR + value); `Packet.raw`.<br>• Port role `raw`, with raw ↔ raw only (`connect_error` reason).<br>• Encoder/Decoder logic (number/char; width param; TCL-5 ≤ 6 bits, ASCII ≥ 7; overflow flag).<br>• `Packet.origin` lineage: sources stamp it, single-input machines copy it, combining machines union it.<br>• Tests. |
| D2 | submit | **USB sockets + data modules.**<br>• `usb_socket` fixed infrastructure with a `device` slot and a 2-slot FIFO (overrun counts as `lost`).<br>• Device registry (bit/number/text/key/sensor) whose streams are configured by the contract.<br>• `Simulation.insert_device / remove_device`.<br>• Tests. |
| D3 | hard | **Contracts + contract drive + save v2.**<br>• `game/lab/contract.gd` kinds deliver/map/filter/paired; accept formats bits(w)/text/number.<br>• Constraints count/min_rate/max_power/max_heat/max_lost/max_latency, with soft window resets.<br>• `contract_drive` replaces `usb_output`; LabDef levels L1–L12.<br>• Save `version: 2` with a v1 migration + backup.<br>• Tests. |
| D4 | submit | **Views.**<br>• Port face + data modules on the locked USB Input/Output (all socket/drive states).<br>• RawPort / RawToken / raw link rendering; Encoder/Decoder views.<br>• Device Tray popover; contract panel (constraints with pass/fail). |
| D5 | submit | **VFX-ladder conformance.**<br>• Remove packet halos, the port halo and the comet glow; add the 1 px port contact ring (≤ 120 ms).<br>• Remove the StateLayer processing underglow.<br>• LED V2 states wired (throttling/overheated).<br>• `motion_check` still PASS. |

### Checkpoint E: power and heat
| Job | Route | Scope |
|---|---|---|
| E1 ✓ | hard | **Power + work units + clock.** *(done: `tests/test_power.gd`; PSU gated to L16+)*<br>• Jobs cost `campaign_ticks × 12` work units; normal/fast/overclocked = 12/16/24 per tick.<br>• PSU fixed infrastructure with tiers 8/16/32/64; demand = Σ rated power × clock multiplier.<br>• Brownout = work × capacity/demand (integer); the progress ring stays smooth.<br>• Tests, with existing timings unchanged at normal clock. |
| E2 ✓ | hard | **Thermal grid + cooling.** *(done: `core/thermal/thermal_grid.gd`, `tests/test_thermal.gd`; model v2 in SYSTEMS_EXPANSION §5)*<br>• `core/thermal/thermal_grid.gd` (PackedInt32Array): generate/diffuse/dissipate.<br>• Stages with hysteresis; THROTTLING ×½, CRITICAL pause.<br>• Heatsink / blower / heat pipe / radiator simulation.<br>• Calibration tests (SYSTEMS_EXPANSION §5 targets). |
| E3 ✓ | submit | **Views.** *(done: thermal family views, ThermalStrip + LED Throttling/Overheated, SystemsOverlay T/P + legend, top-bar power chip; visual check `tools/systems_shot.gd`. The PSU board machine moves to H with L16.)*<br>• Resource indicators replace the stats silk; thermal strip; thermal family views (blower rotates).<br>• PSU gauge; thermal (`T`) and power (`P`) overlays; top-bar power chip. |

### Checkpoint F: QoL interaction overhaul
| Job | Route | Scope |
|---|---|---|
| F1 ✓ | submit | Hover card (180 ms, follows the pointer, hidden during drag/wire/place). |
| F2 ✓ | submit | Quick action bar + duplicate (Ctrl+D, Alt+drag) + copy/paste settings; the Delete mode leaves the rail. |
| F3 ✓ | submit | Smart wiring: drag from a port in Select mode, edge assist, body snap / candidate rings. |
| F4 ✓ | hard | Connected move: live hologram reroute, atomic commit, snap back on failure (replaces the "Would cut the wire" refusal). |
| F5 ✓ | hard | Undo/redo (layout snapshots per frame of edits; `Simulation.apply_layout` restores in place, keeping untouched machines/wires and their packets) command history (place, delete, move, rotate, wire, rewire, param, device, duplicate, paste). |
| F6 ✓ | submit | Camera: middle-drag / Space-drag pan with inertia, smooth zoom to cursor.<br>Hotkeys: `1`–`4`, Q/W/E/R, T/P, X/Del, Esc.<br>Palette QoL: search, favourites, recents, honest locks with requirements. |

### Checkpoints G–J
- **G:** remaining components in batches (Groups A–F of SYSTEMS_EXPANSION §11). Each ships with its
  logic, ports/widths, power/cost/heat, its function-region visual, hover/Inspector content and tests.
  Nothing appears in the palette before its group ships.
- **H:** the progression table (SYSTEMS_EXPANSION §10), with the Two Sticks and BYTE milestones.
  Every contract gets a reference solution and a solvability test.
- **I:** VFX / shader / animation polish inside the ladder. Audio hooks (`AudioBus.event`).
- **J:** full regression, a screenshot pass against pages 15–19, and a docs sweep.

## Status

| Item | State |
|---|---|
| Core: BitVector / ViewMode / Charset; explicit widths; deterministic sim | done |
| Tutorial missions a1, a2 (3-bit), b1–b3 (5-bit characters, Caesar) | done |
| Views: machines from Penpot exports, Signal V1 wires, continuous packet motion, progress ring, stats silk, MSDF text | done |
| Tools: place / live-routed WYSIWYG wires / rewire / move / delete / rotate; canonical HUD V2 | done |
| Lab (main game): persistent expanding factory, USB in/out, "deliver N × value" levels L1–L6, live editing, save | done |
| Lab HUD: request panel, level banner, main menu (Lab + tutorial) | done |
| Components: Add, Modulo, Bit Splitter, Demux (+ legacy machines) | done |
| Checks | `make test` (246) + `tools/{tools_smoke,motion_check,menu_smoke,views_smoke}.gd` |
| Systems expansion design | **locked 2026-09-24** (Penpot pages 15–19, `systems_v1.js`, STYLE_GUIDE §14); Status LED V2 assets regenerated |
| Next | Checkpoint D (USB, encoding, contracts) through scoped DS jobs D1–D5, then E (power/heat) and F (QoL) |
