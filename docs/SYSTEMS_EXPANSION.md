# Tiny Compute Lab — Systems Expansion (design)

> Status: **DRAFT (Checkpoint A → B)**. The rules and numbers below are the game-design contract that
> the Penpot boards (pages 15–18) draw and the DS jobs implement. At the design freeze (Checkpoint C)
> this document is folded into `ARCHITECTURE.md`, `STYLE_GUIDE.md`, `VISUAL_SYSTEM.md`,
> `MOTION_SYSTEM.md`, `COMPONENT_ROADMAP.md` and `IMPLEMENTATION.md`.
> Art direction: Style Lock V1 (`STYLE_GUIDE.md`) — **extended, never redrawn**.

## 0. Checkpoint A — audit (2026-09-24, HEAD 96b66d0)

**Baseline is green:**
- `make test`: 246 passed.
- `tools_smoke`, `motion_check` (worst step 3.9 px, dwell 4, progress 1.00), `menu_smoke` and
  `views_smoke` all PASS. No warnings.

**Working systems to preserve:**
- The BitVector core.
- Explicit widths.
- The deterministic central tick.
- Continuous packet motion with invisible-inside processing and the progress ring.
- Live-routed WYSIWYG wires with atomic `rewire`.
- The Lab: persistent, expanding, live editing, levels L1–L6, autosave.
- Canonical HUD V2, the main menu and the tutorial missions a1–b3.

**Gaps against the production brief:**

| # | Finding | Brief § |
|---|---|---|
| A1 | USB Input/Output are ordinary machines placed by the level. There is no socket/device split, no inventory, and no raw (non-bit) data. L4 adds a *second* input just to change data type. | 2–4 |
| A2 | Every request is "deliver N × constant V", so any constant generator satisfies it; there is no lineage or transformation check. Depth ends once the wiring is right. | 5, 34 |
| A3 | Power is a static number per machine (`Catalog.power`, stats silk text). There is no capacity, PSU or consequence. | 7, 8 |
| A4 | There is no thermal model. | 9–12, 16 |
| A5 | There is only one speed notion (playback). Machine clock and overclock are absent. | 13 |
| A6 | Processing feedback is the generic ring plus a body glow on every machine family. | 14, 15 |
| A7 | The palette shows Multiply as "Locked" with no requirement. The rail still has a Delete *mode*. The top bar keeps the mission-era reset/step controls in the Lab. | 18, 23 |
| A8 | Information needs a click (Inspector). There are no hover card, quick actions, duplicate, copy settings, undo, multi-select or palette search. | 22–31 |
| A9 | Wiring must start in Wire mode. Moving a wired machine is refused. The camera has no inertia, zoom-to-cursor or middle-drag. | 26–28 |
| A10 | Save `version: 1` has no migration path. | 49 |
| A11 | Penpot MCP is unauthenticated in this session. Penpot work is blocked until it is reconnected. | 37 |

## 1. The three layers

```
 PERIPHERAL (raw, semantic)        COMPUTE FABRIC (BitVector only)          CONTRACT (raw or bits)
 USB device → USB socket ─raw─▶ Encoder ─bits─▶ … machines … ─bits─▶ Decoder ─raw─▶ Contract Drive
```

- **The BitVector is still the only *compute* value.** Every machine that computes takes and
  produces BitVectors of explicit width. That is unchanged.
- **RawValue** is a new boundary type (`core/data/raw_value.gd`):
  - `{kind: TEXT | NUMBER | KEY | SENSOR, value}` (a char or an int).
  - It travels only on **raw links**. A raw link joins a USB socket or a Decoder output to an
    Encoder input or to the Contract Drive.
  - Ports carry a new `role: "raw"`, and a raw port only connects to a raw port.
  - A raw value can never enter a compute machine. `connect_error` states this as a reason:
    "Raw text must be encoded first".
- **ViewMode is untouched.** A Viewer only changes presentation. An Encoder or Decoder is a real
  boundary transformation: raw → bits, or bits → raw.
- **Bit Stick** is the exception that keeps the opening simple: a device that emits *already
  encoded* 3-bit words (the "someone handed you raw bits" fantasy). Every later device emits raw values.

## 2. USB sockets and devices (fixed infrastructure)

**Socket** (`usb_socket`, locked, never in the palette):
- M chassis, on the west board edge.
- One output port, which is `raw`, or `bits(w)` when a Bit Stick is inserted.
- A **device slot**.

**Device inventory:**
- Devices are owned items, not machines.
- The HUD **Device tray** (opened by clicking a socket) lists the owned devices. Insert one with a
  click; the socket shows the stick physically seated.
- Insert and remove are edits: they are undoable and saved.
- Removing a device leaves the socket's wire in place, with no data flowing.

| Device | Emits | Stream (configured by the current contract) | Unlock |
|---|---|---|---|
| Bit Stick | bits(3) (bits(5) later) | fixed or seeded word list | start |
| Number Stick | NUMBER raw | seeded ints in a range | L5 |
| Text Stick | TEXT raw | a phrase, looped | L6 |
| Key Stick | KEY raw (int) | constant, or changing every k values | L12 |
| Sensor Stick | SENSOR raw (int) | seeded noisy readings | L9 |
| File Stick | *(future)* | byte stream | post-MVP |

**Socket rules:**
- **The stream belongs to the contract.** The contract says what each device type carries. The
  player chooses *which device goes in which socket*. A wrong device gives no matches, which is
  non-fatal.
- **Overrun:** a socket has a 2-slot FIFO. When its wire is full the oldest value is **dropped** and
  counted as `lost`. Contracts may cap `lost`, which is what makes the Buffer meaningful.
- **Socket count:**
  - The Lab starts with **1 socket + 1 Contract Drive**.
  - Socket 2 unlocks at the **Two Sticks** milestone (L12).
  - Socket 3 unlocks with the BYTE milestone (L18), for a configuration/metadata stream.
  - Sockets never unlock as a plain throughput upgrade.

## 3. Contract Drive and contracts

**Contract Drive** (`contract_drive`, replaces `usb_output`, locked, east board edge):
- The current job is a USB drive seated in it.
- Its input port accepts `*`: the raw kinds or bits of any width. Validation decides what counts.
- It shows a **write LED**, an accepted flash (green) and a rejected flash (amber).
- Rejection is never fatal.

**Lineage.** Every packet carries `origin: {socket_id: {seq, value}}`.
- A source stamps its packet.
- A single-input machine copies the origin to its output.
- A machine that combines inputs *unions* the origins.
- This lets a contract check *transformations* instead of constants.

A contract (`game/lab/contract.gd`) is `{id, kind, accept, count, constraints, streams, rewards}`:

| kind | accepted when |
|---|---|
| `deliver` | value == V (the current L1–L3 behaviour) |
| `map` | value == f(origin values); f is a small declarative op chain evaluated with BitVector/Charset ops; the result must also have the declared format and width |
| `filter` | as `map`, but f may return *drop*; delivering a value that should have been dropped is rejected |
| `paired` | as `map` over several sockets **and** every contributing origin has the same `seq` (synchronisation) |

`accept.format` is `bits(w)`, `text` or `number`. A text contract therefore needs a Decoder in
front of the drive.

**Constraints** are all optional; a contract completes only once every one of them is met:

| Constraint | Rule |
|---|---|
| `count` | accepted values ≥ N |
| `min_rate` | accepted values per Lab second, rolling over the last 60 ticks, ≥ R when the count is reached (1 Lab second = 10 ticks; the HUD shows `/s`) |
| `max_power` | Lab power demand ≤ P during the whole counted window |
| `max_heat` | no machine reaches the given stage (e.g. `THROTTLING`) during the window |
| `max_lost` | socket overruns ≤ L during the window |
| `max_latency` | the median origin → drive latency ≤ T ticks |

**Constraint failures are soft.** Breaking a constraint resets only the *window* (accepted counts
keep accumulating as "total"). The HUD shows which constraint broke, and why.

## 4. Power

- **PSU** (`psu`, locked infrastructure, board corner):
  - Capacity by tier: Starter Adapter **8** → Improved Adapter **16** → Desktop PSU **32** →
    High-Capacity PSU **64**.
  - Tiers are contract rewards; there is no fuel, mining or inventory.
- **Demand** = Σ rated power of every placed machine × its clock multiplier. It is static, so it
  reads as "demand/capacity".
  - Rated values: Add/Modulo/Compare/Gate/Encoder 1; Multiply 2; Processor 4; routing 1;
    IO/Viewers/Heatsink/Heat Pipe 0; Fan 2; Radiator 1.
- **Overload** (demand > capacity) causes a brownout: every machine's work per tick is scaled by
  `capacity/demand`, using integer work units (§6). Nothing breaks. The PSU pulses amber-red and
  the power overlay explains why.
- **States:** normal (< 75 %), near capacity (75–100 %), overloaded (> 100 %).

## 5. Heat

**Field:**
- An integer grid, one cell per board tile.
- `t` is the temperature above ambient, in tenths of °C; the display value is 25 + t/10 °C.
- It is a data-oriented `PackedInt32Array` in `core/thermal/thermal_grid.gd`. There are no Nodes.

**Update order,** deterministic, once per tick after machines work:
1. **Generate:** a machine that did `w` work units this tick adds `heat × w / 12` to its footprint.
   The heat is split evenly, and the remainder goes to the lowest cell index.
2. **Diffuse:** `t' = t + Σ₄(t_n − t) × 8 / 64`, which is stable. Board edges are insulated.
   Heat-pipe cells use the conductance `16/64` along their axis.
3. **Dissipate:** `t' -= t × d / 1024`, where `d` = 8 (ambient) plus cooling bonuses.
   - Heatsink: +24 within Chebyshev radius 1.
   - Fan, while running and powered: +64 within radius 2.
   - Radiator: +96 within radius 2.

**Machine temperature** = the max over its footprint cells. Stages use hysteresis, so each
stage exits 50 lower than it enters:

| Stage | Enter at | Effect |
|---|---|---|
| NORMAL | < 250 (< 50 °C) | none, and the indicator is nearly invisible |
| WARM | 250 | indicator only |
| HOT | 450 | amber indicator; the drive notes it if a contract has `max_heat` |
| THROTTLING | 600 | work × ½ |
| CRITICAL | 750 | the machine pauses (its job is kept) until it cools below 600 |

Nothing is ever destroyed.

**Calibration targets** (tests, not guesses; the heat values per machine are tuned to hit them):
- An isolated Add at 100 % duty settles in NORMAL.
- Four Adds packed edge to edge at 100 % reach HOT.
- An isolated Processor at 100 % reaches THROTTLING without cooling.
- A Processor with a Fan beside it stays ≤ WARM.
- A Heat Pipe chain of 3 cells from a hot cluster to a Heatsink lowers the cluster by ≥ 1 stage.

**Cooling family** (Group G). These are placeable machines with no data ports:

| Machine | Size | Power | Effect | Unlock |
|---|---|---|---|---|
| Heatsink | S | 0 | +24 dissipation, r1 | L17 |
| Fan | S | 2 | +64 dissipation, r2; states idle/running/high load | L17 |
| Heat Pipe | S (chainable, axis = rotation) | 0 | high conductance along its axis | L21 |
| Radiator | L | 1 | +96 dissipation, r2 | L21 |

## 6. Clock: machine speed ≠ playback speed

- **Playback** (1×/2×/5×/10×; keys `1`–`4`) only changes how fast ticks are shown. It is never
  gameplay.
- **Machine work** is integer: 12 work units per tick at full speed. A job costs
  `campaign_ticks × 12` units.
- **Clock modes,** an Inspector parameter unlocked after L16:

| Mode | Work per tick | Power | Heat |
|---|---|---|---|
| normal | 12 | ×1 | ×1 |
| fast | 16 | ×1.5 (rounded up) | ×2 |
| overclocked | 24 | ×2 | ×4 |

- **Brownout and throttling** multiply the work per tick (floor, minimum 1).
- **The progress ring** shows `done/cost` units, so it stays smooth at any rate.

## 7. Encoder / Decoder / Viewer family (Group D)

| Machine | In → Out | Params | Notes |
|---|---|---|---|
| Number Encoder | raw NUMBER → bits(w) | width | a value that does not fit sets the overflow LED and the result is truncated (teaches width) |
| Number Decoder | bits(w) → raw NUMBER | signed? | |
| Character Encoder | raw TEXT → bits(w) | width 5 (TCL-5) / 8 (ASCII, after BYTE) | an unencodable char is dropped and flagged |
| Character Decoder | bits(w) → raw TEXT | width | |
| Viewers (Bin/Dec/Hex/Char) | bits(w) → bits(w) | — | pass-through, 0 power, 1 tick; the readout shows the last value in its mode |

## 8. Visual language additions (drawn in Penpot, pages 15–18)

**ResourceIndicators** replace the stats silk text (A3).
- They sit in the chassis's bottom-right silk zone and are drawn in silk ink.
- **Power pips** ▮▮▯▯ show rated power 0–4+.
- **Clock segments** ◔◔◔▯ show the job cost in ticks, as quarters of 4, then as a filled row.
- Exact numbers appear only in the hover card and the Inspector.

**Thermal strip:**
- A 2 px bar along the chassis's top edge (N). It is invisible when NORMAL and faint when WARM.
- HOT is amber. THROTTLING is amber plus a slow pulse. CRITICAL is red and blinks.
- The body is never tinted.

**Function-specific processing** replaces body glow (A6):

| Family | Processing visual |
|---|---|
| Add/Modulo | keep the ring |
| Splitter/Demux | the in-lane plus the chosen out-lane light up |
| Merger | the converging lanes light up |
| Gate | the blade opens or closes |
| Buffer | the bays fill |
| Register | a latch pulse |
| Encoder | the raw token is absorbed and bit cells scan in |
| Decoder | the bit cells scan, then the token appears |
| USB socket | the port LED only |
| Contract Drive | the write LED plus an accept/reject flash |

Idle is quiet. Selection is a restrained outline. Amber means warning; red means real errors only.

**Raw links** use the same PCB trace, with a *token* packet: a rounded capsule carrying the glyph
(`H`, `42`, `K5`) instead of bit chips. They are visually distinct but in the same family.

**Overlays** are HUD toggles, at most one at a time, and the normal board stays clean:
- **Thermal:** a heat-map on the board tiles, using the palette's cool → amber → red ramp, plus
  cooling radii.
- **Power:** a PSU gauge, a demand badge on each machine, and overload highlights.

## 9. Interaction overhaul (Group F QoL)

**Hover card:**
- Appears after 180 ms, offset +16/−16 px (upper-right of the pointer) and clamped to the viewport.
- It follows the pointer and hides during a drag, wire drag or place.
- It shows name, function, state, power, cost, temperature, port widths and key parameters.
- Click still selects and opens the Inspector.

**Quick action bar:**
- Shown beside the selected machine: Move · Duplicate · Rotate · Copy settings · Delete.
- Delete gets a danger hover state and needs a single deliberate click.
- **The Delete tool mode is removed from the rail.**

**Duplicate and settings:**
- Duplicate: `Alt`+drag drags a duplicate; `Ctrl+D` duplicates in place and picks it up.
- Copy settings: `Ctrl+Shift+C` / `Ctrl+Shift+V`. Only compatible parameters are copied, never
  position or wires. A toast confirms: "Pasted k=5, width 5 → Add #7".

**Smart wiring:**
- Dragging from any port in Select mode starts a wire.
- In Wire mode, a click near a machine edge picks the nearest compatible port.
- Dropping on a machine body snaps when exactly one compatible port exists; otherwise the
  candidates are highlighted.
- Rewire behaviour is unchanged: the old wire fades, and the replacement commits atomically.

**Connected move:**
- Dragging a wired machine live-routes every attached wire as a hologram.
- Valid (all routes succeed): release commits the move and all routes atomically.
- Invalid: the failed routes show red dashes, and release snaps the machine back with the
  original wires untouched.
- This replaces the "Would cut the wire" refusal.

**Camera:**
- Middle-drag or `Space`+drag pans, with inertia (exponential damping).
- The wheel zooms smoothly toward the cursor.
- Arrow keys pan. Edge pan is an option, off by default.

**Undo/redo:**
- The command history records place, delete, move, rotate, wire, rewire, param, device insert,
  duplicate and paste settings.
- Each command stores do/undo layout deltas.
- Undoing an edit re-applies layout state only. Packets in affected machines and wires are cleared
  (the same rule as live edit today), so determinism holds.
- Keys: `Ctrl+Z` undoes; `Ctrl+Y` or `Ctrl+Shift+Z` redoes.

**Multi-select** (after the single-object UX is stable):
- Box select with a left-drag on an empty board.
- A group can be moved, duplicated or deleted.

**Palette:**
- Search, favourites, recently used and category filters.
- A locked item shows its requirement: "Unlocks at L9 · Sorting".
- Items that are not implemented are **not shown at all**.

**Control map:**

| Key | Action |
|---|---|
| `1` `2` `3` `4` | playback 1× / 2× / 5× / 10× |
| `Space` (tap) | pause/play |
| `Space` (hold + drag) | pan |
| `Q` | select |
| `W` | wire |
| `E` | build the last component (ghost on the cursor) |
| `R` | rotate the hovered/selected/ghost machine (no rotate mode) |
| `X` / `Del` | delete the selection |
| `Ctrl+D` | duplicate |
| `Ctrl+Z` / `Ctrl+Y` | undo / redo |
| `Ctrl+Shift+C` / `Ctrl+Shift+V` | copy / paste settings |
| `T` | thermal overlay |
| `P` | power overlay |
| `Esc` | cancel, then deselect |

## 10. Progression

Each level adds exactly one architectural demand, and every level reuses the factory already built.

| L | Title | Contract | New demand | Unlocks / rewards |
|---|---|---|---|---|
| 1 | First Contact | deliver 10 × `010` (Bit Stick 3-bit) | wires | — |
| 2 | Plus Two | deliver 20 × `100` | a constant transform | Add |
| 3 | Over the Top | deliver 20 × `001` | overflow | — |
| 4 | Moving Target | map: in + 3 (3-bit), varying stick | real transform, no constants | — |
| 5 | Numbers | map: enc3(n) + 1, Number Stick | encoding and width choice | Number Stick, Number Encoder/Decoder |
| 6 | Letters | map text: Caesar +3 (no wrap), Text Stick → TEXT | encode → compute → decode | Text Stick, Char Encoder/Decoder, Char Viewer |
| 7 | Past Z | map text: Caesar +3 with wrap | modulo arithmetic | Modulo |
| 8 | Payload | map: low 3 bits of tagged 5-bit words | bit fields | Bit Splitter |
| 9 | Sorting | filter: sensor > 4 | predicate + gating | Sensor Stick, Compare, Gate |
| 10 | Burst | map, bursty stick, `max_lost` 0 | buffering | Buffer, Delay |
| 11 | Rush Hour | map ×3 via Multiply, `min_rate` 4/s | parallelism | Multiply, Splitter, Merger |
| 12 | **Two Sticks** | paired: text + constant key, Caesar | second stream | **Socket 2**, Key Stick, 2-input Add |
| 13 | Changing Key | paired, key changes every 8 | synchronisation | Counter |
| 14 | Mixed Traffic | map by tag: two transforms, merged | routing | Demux, Mux, Conditional Router |
| 15 | Wider | map: 3-bit n → 5-bit n×5 | width conversion | Zero/Sign Extend, Truncate |
| 16 | Power Cap | map, `min_rate` 5/s, `max_power` 8 | efficiency | Improved Adapter (16), clock modes |
| 17 | Heat | map, `min_rate` 8/s, `max_heat` THROTTLING | cooling layout | Heatsink, Fan |
| 18 | **BYTE** | map text: 8-bit ASCII lower → upper | 8-bit buses | **8-bit**, Bus Splitter/Combiner, AND/OR/XOR/NOT, Socket 3, Desktop PSU (32) |
| 19 | XOR Cipher | paired: ASCII ⊕ key | bitwise logic | Shift L/R |
| 20 | Cheap Multiply | map ×4, `max_power` 12 | shifts beat Multiply | — |
| 21 | Datacenter | map, `min_rate` 12/s, `max_heat` HOT | a thermal redesign | Heat Pipe, Radiator, High-Capacity PSU (64) |
| 22+ | Register, Memory, ALU … | running sums, ROM lookup, programmable | memory and compute (Groups E–F) | Register, Register Bank, ROM, RAM, ALU, PC, Instruction Decoder |

- **Migration:** the saved Lab levels L1–L3 keep their index. Saved L4–L6 map to the new L6, L7
  and L8, which cover the same content. See §12.
- **Tuning:** every contract has a reference solution in `tests/solutions.gd`. A test proves each
  one is solvable with *only* the machines unlocked by then, and inside the board area.

## 11. Component groups and the definition of done per component

Each component needs simulation behaviour, port and width rules, power, cost, heat, a visual state
with its function-specific processing visual, hover and Inspector content, and tests.

| Group | Components |
|---|---|
| A — done | Add, Modulo, Bit Splitter, Demux |
| A — still to meet the definition of done | Subtract, Multiply, Compare, Gate, Buffer, Delay, Counter, Splitter, Merger |
| B | AND, OR, XOR, NOT, Shift L/R |
| C | Mux, Conditional Router, Selector (Type Switch folds into Demux on a tag) |
| D | the §7 family; Zero/Sign Extend, Truncate, Width Converter, Bus Splitter/Combiner |
| E | Register, Register Bank, ROM, RAM |
| F | ALU, Program Counter, Instruction Decoder |
| G | PSU, Heatsink, Fan, Heat Pipe, Radiator |

A component is visible in the palette only after its group ships.

## 12. Save v2

`version: 2`. The `lab` section gains:
- `sockets`: `[{id, cell, device}]`
- `devices`: the owned devices
- `contract`: the current index plus the window state
- `psu_tier`
- `unlocked` and `level_map_version`

Cooling machines and clock modes live in the layout.

The migration `1 → 2` does the following:
- Maps the lab level index.
- Converts the placed `usb_input` machines at source cells into socket 1, with a Bit Stick
  inserted. Extra L4–L6 inputs become sockets only if the new level has unlocked them; otherwise
  their wires are dropped with a notice.
- Converts `usb_output` to the Contract Drive.
- Keeps every other machine and wire.

A backup `save.v1.json` is written before the migration.

## 13. Audio hooks

`AudioBus.event(name)` is a signal-only autoload for now. Events:
- USB: `usb_insert`, `usb_remove`
- Wires: `wire_connect`, `wire_disconnect`
- Machines: `machine_place`, `machine_delete`
- Contracts: `job_accept`, `job_reject`, `job_complete`
- Warnings: `fan_start`, `thermal_warning`, `power_overload`
- Progression: `unlock`

No per-packet sounds.
