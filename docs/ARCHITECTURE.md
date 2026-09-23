# Tiny Compute Lab — Architecture

> Godot 4.7, GDScript. Visual source of truth: `docs/STYLE_GUIDE.md` (Style Lock V1) and the Penpot
> exports in `assets/art/`. This document is the source of truth for code structure.
> Delivery order and slice scope: `docs/IMPLEMENTATION.md`.

## 0. Non-negotiable rules

1. **BITVECTOR IS THE ONLY CORE VALUE MODEL.** Every value in the simulation is a BitVector
   (`width` + `bits`). There are no NUMBER, CHARACTER, TEXT or IMAGE runtime types.
2. **REPRESENTATION != DATA.** BIN, DEC, HEX, CHAR, SDEC and TYPE are *view modes*. They format
   bits for display and never create, convert or modify data.
3. **WIDTH IS GAMEPLAY.** Width belongs to the value, the port, the component instance and the
   mission. It decides masking, overflow/carry and connection compatibility. It is always explicit.
4. **NO GLOBAL DEFAULT 8-BIT MODEL.** No code may assume a "normal" width. Nothing is promoted to 8
   or 64 bits at the gameplay-model level. Native ints are only the storage for a BitVector, and
   `width` decides every observable result.
5. **3-bit is the first playable width.** 5-bit comes with the character/Caesar slice. **8-bit
   (BYTE) is a later progression milestone.**
6. **Boolean/control is not a separate type.** It is a width-1 BitVector used as a control signal
   (Compare output, Gate enable).

## 1. What this looks like in play

```
3-bit   010 + 010 = 100      011 + 010 = 101      100 + 010 = 110
        111 + 001 = 000   carry = 1            (real 3-bit overflow)
8-bit   01000001  →  BIN 0100 0001 · DEC 65 · HEX 0x41 · CHR A      (same bits, four views)
```

A 3-bit output cannot connect to a 5-bit or 8-bit input. Only a conversion component
(Zero Extend, Truncate, …; a later slice) changes width.

## 2. Layers (strict separation)

```
core/            pure data + deterministic simulation. No Node, no rendering, no _process.
  data/          BitVector, ViewMode, Charset, Packet
  components/    Catalog (ComponentDefinition + PortDefinition), Machine (ComponentInstance),
                 logic/* (ComponentLogic)
  connections/   Connection (ConnectionModel), Router
  simulation/    Simulation (the board + tick)
game/            MissionDef (MissionDefinition), MissionRun (MissionRuntime), Missions, save
autoload/        SimulationManager: the ONLY node that advances the simulation
world/           Node2D views: BoardView, MachineView, ConnectionView, PacketView, camera, tools
ui/              HUD (Control nodes), theme
```

| Concept | Code |
|---|---|
| BitVector | `core/data/bit_vector.gd`: immutable value (`width`, `bits`) |
| Interpretation | `core/data/view_mode.gd`: `ViewMode.format(bv, mode)` / `parse` |
| Character sets | `core/data/charset.gd`: TCL-5 (5-bit) and ASCII (7/8-bit) tables |
| DataPacket | `core/data/packet.gd`: `Packet` (id, `data: BitVector`, created_tick, origin, path, meta) |
| ComponentDefinition / PortDefinition | `core/components/catalog.gd` |
| ComponentInstance | `core/components/machine.gd`: `Machine` (placement, width, queues, job, state) |
| ComponentLogic | `core/components/logic/*.gd`: per-type behaviour, stateless |
| ConnectionModel | `core/connections/connection.gd`: slot conveyor, 1 slot per tile, fixed `width` |
| MissionDefinition / Runtime | `game/missions/mission_def.gd` / `mission_run.gd` |
| ComponentView / ConnectionView / PacketView | `world/…`: **read-only** over the models |

**Rules:**
- Views never write simulation state. All edits go through `Simulation` methods (place, remove,
  rotate, connect, set_param, set_width), called by the tools and the HUD.
- Nothing under `core/` or `game/` extends `Node` or uses `_process`. Both run headless with no SceneTree.
- Iteration order is always ascending id. No dependence on Dictionary order, and no RNG without a
  seed stored on the Simulation.

## 3. Data model

### 3.1 BitVector (`core/data/bit_vector.gd`)
- `width: int` (1…64) and `bits: int` (always masked to `width`). Storage is one native int. The API
  hides it, so widths above 64 can later use chunked storage without changing callers.
- **Immutable:** every operation returns a new BitVector. Invalid widths `push_error` and clamp.
- **Construct:**
  - `of(value, width)`: masks the value; negative values become two's complement.
  - `from_bin("010")`: the width is the digit count; spaces, `_` and a `0b` prefix are ignored.
  - `from_bool(b)` (width 1), `zero(width)`.
- **Read:** `unsigned()`, `signed()`, `as_bool()`, `bit(i)`, `with_bit(i, v)`, `popcount()`,
  `is_zero()`, `equals(other)` (width **and** bits), `_to_string()` → `3'b010`.
- **Compare:** `ucmp(other)` / `scmp(other)` → −1/0/1. Operands must have equal width; an int operand
  is converted with `of(int, width)`.
- **Arithmetic** (wraps at `width`, operand = same-width BitVector or int):
  - `add`, `sub`, `mul`, `neg`.
  - `add_carry(other) -> {"value": BitVector, "carry": int}`: carry out of the top bit.
  - `sub_borrow(other) -> {"value", "borrow"}`.
  - `umod(k)` and `udiv(k)`: unsigned; k = 0 → `push_error`, returns zero.
- **Bitwise:** `band`, `bor`, `bxor`, `bnot`, `shl(n)`, `shr(n)` (logical), `sar(n)` (arithmetic).
- **Width** (the only way width changes; later exposed by conversion components):
  `zero_extend(w)`, `sign_extend(w)`, `truncate(w)`, `slice(lo, count)`, `concat(high)` (self =
  low bits).
- **Mismatched widths** in binary ops are a programming error: `push_error`, and the operand is
  masked to `self.width`. Gameplay never reaches this, because connections are width-checked.

### 3.2 ViewMode (`core/data/view_mode.gd`)
`enum Mode { BIN, UDEC, HEX, CHAR, SDEC, TYPE }`. Chip labels: `BIN DEC HEX CHR SDEC TYPE`
(the Penpot `Readout` variants).

| Mode | 3-bit `100` | 8-bit `01000001` | Rule |
|---|---|---|---|
| BIN | `100` | `0100 0001` | all `width` digits, grouped in 4 from the LSB (`1 0110` for w 5) |
| UDEC | `4` | `65` | |
| HEX | `0x4` | `0x41` | ceil(w/4) upper-case digits |
| CHAR | `E` (TCL-5) | `A` (ASCII) | charset chosen by width, see 3.3 |
| SDEC | `−4` | `65` | two's complement, U+2212 minus |
| TYPE | `BITS·3` | `BITS·8` | `BIT·1` for width 1; a packet `meta.hint` replaces `BITS` (e.g. `CHR·5`) |

- `ViewMode.parse(text, mode, width) -> BitVector` returns `null` when the text doesn't fit.
- The view mode is **display state**: Inspector "View as", a viewer machine's param, or a
  mission's preferred mode for its I/O. It is never stored on the data.
- **Exposed first:** BIN, UDEC, HEX. **Later:** CHAR (5-bit slice); SDEC and TYPE (implemented,
  hidden).

### 3.3 Charset (`core/data/charset.gd`)
Characters are just an interpretation of bits, and the charset depends on the width:

| Width | Charset | Table |
|---|---|---|
| 1–6 | **TCL-5** (low 5 bits) | 0–25 = `A`–`Z`, 26 = space, 27 `.`, 28 `,`, 29 `!`, 30 `?`, 31 `-` |
| 7–64 | **ASCII** (low 8 bits) | 32–126 printable; otherwise `\xNN` |

A = 0 makes a Caesar shift `(x + k) mod 26`. Plain 5-bit addition wraps at 32 and turns `X+3`
into punctuation: the player *sees* why a Modulo 26 is needed.

### 3.4 Packet (`core/data/packet.gd`)
- `id`, `data: BitVector`, `created_tick`.
- `origin_id`: lineage. `path`: the machine labels it passed through.
- `meta: Dictionary`: presentation hints only, e.g. `{"hint": "CHR"}`; component logic never reads it.
- `derive(new_id, new_data)` keeps the lineage.

## 4. Components and ports

### 4.1 PortDefinition
```
{ id, dir: in|out|ctrl, role: data|control|flag, width: <int> | "W", bus: bool, cell, side, label }
```
- `width` is an explicit int (for example `1` for control/flag ports), or `"W"`: the owning
  instance's width (`Machine.width`).
- **role:** `data` = the payload stream; `control` = a width-1 enable/select input (keyed diamond
  on N/S); `flag` = a width-1 status output (for example carry; roadmap).
- **Visual class** (derived, never stored in the data): width 1 → diamond; `bus` → BusPort slot +
  WidthTag; otherwise circle + WidthTag when the board has more than one width.

### 4.2 ComponentInstance width
- A width-generic component (Add, Compare's input, Gate data, Splitter, Merger, Buffer, …) has an
  instance `width`.
- A newly placed instance takes the **mission's `default_width`**, which is mission configuration,
  not a global constant.
- The player can change it in the Inspector through `Simulation.set_width(id, w)`. Doing that
  removes wires whose width no longer matches and reports them in an event.
- Constants (`k` on Add/Compare) are masked to the instance width at use.
- IO (USB Input, Output/Terminal) takes its width from the mission and cannot be changed.

### 4.3 Compatibility
`connect_error` rejects any pair of ports with different effective widths:
*"3-bit output cannot connect to a 5-bit input. Use a width converter."* No implicit conversion
exists anywhere.

### 4.4 ComponentLogic
- `Machine` holds instance state only.
- Behaviour lives in `core/components/logic/`, one script per type, looked up by
  `ComponentLogic.for_type(type)`. A logic script reads `inq` and `params`, computes with BitVector
  ops only, and calls `machine.begin_job(results, input, ticks)`.
- **Add** records `last_carry` on the instance for the view and inspector. A carry-out `flag`
  port is a roadmap item.

## 5. Deterministic tick (`Simulation.step()`)

`SimulationManager` (an autoload Node) accumulates real time and calls `Simulation.step()` at a fixed
`TICKS_PER_SEC × speed`. It is the **only** node that advances the simulation. Views interpolate
between ticks using `SimulationManager.alpha`, for animation only.

| # | Phase | Implementation |
|---|---|---|
| 0 | — | clear per-tick flags and events |
| 1 | advance connection transfers | `Connection.advance()` shifts packets one slot |
| 2 | deliver arriving values | the head slot hands its packet to the target port if `can_accept` (runs before the shift, so trains move together) |
| 3 | update component queues | accepted packets are appended to `inq` (capacity from the def) |
| 4 | advance jobs | busy machines count `ticks_left` down |
| 5 | finish jobs | finished results move to `outq` |
| 6 | generate outputs | each `outq` packet enters its wire if the entry slot is free, otherwise the machine is BLOCKED |
| 7 | start eligible jobs | idle machines with inputs and free outputs run their ComponentLogic |
| 8 | mission validation | `MissionRun.after_tick` |
| 9 | metrics | rate windows, latency, bottleneck |

## 6. Missions

`MissionDef` carries explicit widths:
- `default_width`
- `inputs[i].width`, with values given as BitVectors or `"010"` strings
- `outputs[i].width` and `expected`
- `view_modes`: the modes the HUD offers, e.g. `[BIN, UDEC]`

Validation compares with `BitVector.equals`: width **and** bits. The failure text uses the output's
preferred view mode, with BIN as a second line, e.g.:

```
Expected 110 (6)
Received 101 (5)
```

The original ten "factory" missions are **legacy**. They stay as mechanics regression tests with an
explicit per-mission `default_width` and are not part of the campaign; they will be redesigned
later (see `docs/IMPLEMENTATION.md` slice E).

## 7. Views (canonical Penpot style)

- **Machines:** composed from the exported assets exactly as in Penpot:
  `InstallPad + MachineShell + FamilyTab + ActivityArea(state) + content + LED + Ports/BusPorts
  + WidthTags`. Positions come from `assets/art/machine_layouts.json`; sizes and pads come from
  `manifest.json`.
- **Wires:** procedural (Signal System V1): trench edge 10, trench 8, core 2.5, 14 px chamfers,
  teardrops into ports, a comet around moving packets, dashed cores for width 1, and a bus ribbon
  for `bus` ports.
- **Packets:** `assets/art/packet/*` at far, normal and close zoom. The close-zoom label is
  `ViewMode.format(packet.data, current_mode)`, so a 3-bit packet reads `010` in BIN.
- **Readouts:** the `signal/readout_*` chips, with the text drawn by Godot.
- **Tokens:** colours and sizes come only from `core/visual/palette.gd` (generated from
  `design/tokens.json`). No art-direction changes: Style Lock V1 is canonical.

## 8. Tests

Run with `make test` (imports, then runs `tests/run_tests.gd` headless). Everything in `core/` and
`game/` is covered headless:
- BitVector and ViewMode at widths 3, 5 and 8
- slice missions pass with their reference solutions
- determinism (identical event logs)
- failure reasons
- width-mismatch rejection
- router and rotation
- save round-trip
- legacy mechanics regression
