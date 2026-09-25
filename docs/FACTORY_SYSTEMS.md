# Tiny Compute Lab — Factory Systems (the growth overhaul)

> Status: **design, 2026-09-26.** It becomes LOCKED with the commit "Factory growth overhaul design
> locked". Source brief: `overhaulplan.md`. Levels: `docs/PROGRESSION.md`. Look: Penpot pages 20–26,
> summarised in `docs/STYLE_GUIDE.md §15`. Numbers marked *(cal.)* are calibration targets, tuned by
> tests rather than by eye.
>
> This document **extends** `docs/SYSTEMS_EXPANSION.md`. Everything there stays in force unless a
> section here replaces it.

## 0. The one idea

The factory does not grow because there are many jobs. It grows because **one computer keeps being
asked to do more**: wider values, more values per second, more operations. Those demands need more
bandwidth and more compute. More compute needs more power, and more power makes more heat.

```
wider / faster data → more compute (lanes, clock) → more power (supply + distribution)
      → more heat (transport + dissipation) → a physically larger, zoned factory
```

Every new level is **the existing factory plus a modification**. Aim for 60–80 % of levels to reuse
and expand what is already on the board.

**Kept as is:**
- The BitVector core and explicit widths.
- The deterministic tick.
- Continuous packet motion.
- Live-routed wires with atomic rewire.
- The persistent Lab.
- USB option C.
- Status LED V2.
- The VFX ladder.
- Hover, quick actions, undo, multi-select and connected move.

## 1. The four capacities

| System | Capacity | Where it lives | Upgrade |
|---|---|---|---|
| Data | width (bits) × bandwidth (values/tick) | wires (`Connection.lanes`), sockets | bus lanes 1/2/4/8 |
| Compute | lanes × work rate | machines (`lanes`, `clock`, `efficiency` params) | lanes 1/2/4/8, clock, efficiency |
| Power | supply × distribution | PSU on the desk, onboard traces, rails, distribution boards | PSU tier, rails, boards |
| Thermal | transport × dissipation | heat pipes, manifolds, heatsinks, blowers, radiators, liquid loop | pipes, manifolds, radiators, the loop |

**There are no hard component limits.** A player may place 40 Adds. What limits them is:
- board space;
- bandwidth;
- power distribution;
- heat;
- wire congestion.

## 2. Data: bus lanes

### 2.1 Width class and lanes
A wire (`Connection`) keeps its exact data `width`, and both endpoints must match it (unchanged).

It gains **`lanes`** ∈ {1, 2, 4, 8}: its bandwidth, in values per tick. The wire's *class* is
derived from its width and names what the player sees:

| Class | Width | Look (at 1 lane) | Unlock |
|---|---|---|---|
| **Trace** | 1–5 bits | a single 3 px trace | start |
| **Byte Bus** | 6–8 bits | a double trace | the BYTE era (L18) |
| **Wide Bus** | 9–32 bits | a 16 px ribbon | Infrastructure Scale (L22) |
| **Backbone** | 33–64 bits | a 24 px banded bus | Infrastructure Scale (L23) |

Lanes draw as parallel lane lines inside the class's footprint. A 1-lane Trace looks exactly like
today's wire. The name reads "Trace ×2" or "Byte Bus ×4".

The unlocked maximum is `LabRun.max_bus_lanes()`:
- 1 until L6 "Line Rate";
- 2 from L6;
- 4 from L18;
- 8 from L22.

Tutorial missions and tests may set any value.

### 2.2 Transport rule (replaces "one packet per slot" for lanes > 1)
- `Connection.lane_slots: Array` holds `lanes` slot arrays of equal length. `slots` stays as an alias
  of lane 0, so readers that only know lane 0 keep working until they are updated.
- **Push:** a packet enters the lowest-index lane whose entry slot is free. Up to `lanes` packets can
  enter per tick.
- **Advance:** each lane shifts independently, head first, exactly like today's single lane.
- **Deliver:** every tick, the heads of all lanes are offered to the target in ascending
  **packet id** order (oldest first) until the target refuses one.
- A wire is **saturated** in a tick when its entry was refused to a waiting packet while its head
  lane(s) delivered. Saturation, not length, is the bandwidth bottleneck signal (§7.4).

### 2.3 Sources
A USB socket pushes into its wire as many values per tick as the wire accepts.

A stream spec may now set **`burst`** (default 1): the number of values generated at each emission
(`interval` / `pattern` still space the emissions). The socket FIFO holds `2 × burst` values; the
oldest is dropped on overrun and counts as `lost`, exactly as today.

A 20 values/s stick is `interval 1, burst 2`. It needs a 2-lane wire, or it loses values.

## 3. Compute: lanes and upgrades

### 3.1 Upgrade axes (all are machine params, set in the Inspector or on the Upgrade card)

| Axis | Values | Effect | Cost |
|---|---|---|---|
| **Width** | the unlocked widths | the value width (today's width) | power × width factor |
| **Lanes** | 1 / 2 / 4 / 8 (≤ def `max_lanes`, ≤ unlock) | up to N jobs in parallel | power × N, heat × work |
| **Clock** | normal / fast / overclocked | work per tick 12 / 16 / 24 (unchanged) | power ×1 / ×1.5 / ×2, heat ×1 / ×2 / ×4 |
| **Efficiency** | standard / efficient | efficient: +1 processing tick | power × ¾ (round up), heat × ½ |

- **Width factor** (power and heat): 1–5 bits = 1, 6–8 = 2, 9–16 = 3, 17–32 = 4, 33–64 = 6.
  BYTE therefore doubles a machine's draw. That is intended: the whole factory feels it.
- **Power demand** = `ceil(power × lanes × width factor × clock power × efficiency)`, computed in
  integer quarters.
- **Heat** per full-rate job tick and lane = `heat × width factor × clock heat`, halved when efficient.
  As today, heat is proportional to the work actually done, summed over the lanes.
- **Mk label** (display only), from lanes: 1 = Mk1, 2 = Mk2, 4 = Mk3, 8 = Mk4. The hover card
  shows "Add Mk3 · 4 lanes · 8-bit".
- **Lane unlocks** (`LabRun.max_lanes()`): 1 until L4, 2 from L4, 4 from L6, 8 from L22.
  Efficiency unlocks at L22.
- **Footprints never change** with an upgrade, so routes stay valid.

### 3.2 Which machines have lanes
`ComponentDef.max_lanes` (default 1):

| max_lanes | Machines |
|---|---|
| 8 | single-input transforms: Add, Subtract, Increment, Decrement, Multiply, Modulo, AND/OR/XOR/NOT with a constant, Shift L/R, Zero/Sign Extend, Truncate, the four codecs, Compare, Viewers |
| 4 | routing pass-through: Splitter, Merger, Gate, Buffer (lanes = parallel transfers per tick) |
| 1 | everything with memory or synchronisation: Adder (pairs), Counter, Delay, Register, Register Bank, ROM, RAM, ALU, PC, Instruction Decoder, Mux, Demux, Cond Router, Bit Splitter, Bus Combiner, IO, thermal, power |

### 3.3 Lane rule (machine core)
- `Machine.jobs: Array` holds up to `lanes` running jobs. `job` stays a read alias of `jobs[0]`
  (or `{}`) for existing readers.
- Each tick every running job advances by the machine's work rate. Brownout and throttling apply
  per machine, so all lanes slow together.
- **Output backlog:** finished results wait in `outq[port]` (the head) plus
  `out_backlog[port]: Array`. The machine pushes the head, then the backlog, as many per tick as
  the wire accepts.
- A free lane may **start** a job only when `running jobs + waiting results < lanes`. A blocked
  output therefore stalls every lane: back-pressure stays physical.
- **Input capacity** of each data input = `max(1, lanes)`. A Buffer keeps its own capacity param.
- Throughput of one machine = `lanes × rate / (ticks × 12)` values per tick. A 4-lane Add
  (4 ticks) at normal clock handles 1 value/tick = 10/s.

## 4. Contracts: throughput, not job count

New contract constraints (they join `count`, `min_rate`, `max_power`, `max_heat`, `max_lost`,
`max_latency` and `max_rejected`):

| Constraint | Rule |
|---|---|
| `sustain` | `min_rate` must hold continuously for the last N Lab seconds (N × 10 ticks), not just once when the count is reached |
| `burst` | a stream may arrive in bursts (`pattern`); `max_lost 0` makes the player buffer it |

**Concurrent quests are demoted.** `LabConfig.quest_window` is **1** until the Multi-input era
(L16) and 2 after it (`quest_window_level`).

## 5. Power: a physical distribution network

### 5.1 Parts

| Part | Id | Size | Capacity *(cal.)* | Unlock | Notes |
|---|---|---|---|---|---|
| Lab Power Input | `power_input` | S, locked | = PSU supply | L12 | a fixture on the west board edge at `LabConfig.power_input_row`; the desk PSU plugs into it; its **terminal** is the tile east of it |
| Starter Adapter → Improved Adapter → Desktop PSU → High-Capacity PSU → Server PSU | desk item | — | 8 / 16 / 32 / 64 / 128 | rewards | supply, unchanged tiers plus Server PSU |
| Onboard traces | implicit | — | **8** | — | the laptop's own copper; feeds every machine that is not on a rail network |
| Power Rail | `power_rail` | S, chainable | 16 | L12 | tiles joined by any orthogonal adjacency, like a bus bar; no rotation needed |
| Heavy Power Rail | `power_rail_heavy` | S, chainable | 48 | L22 | |
| Power Backbone | `power_backbone` | S, chainable | 128 | L24 | |
| Distribution Board | `power_board` | M | 32 | L12 | a hub: it splits one incoming network into independent branch networks |
| Heavy Distribution Board | `power_board_heavy` | M | 96 | L22 | a variant of `power_board` |

Rails and boards occupy tiles. Nothing else may share a rail tile, and wires never cross rails.
They draw no power and make no heat.

### 5.2 The network (deterministic, rebuilt only when the layout changes)
1. **Rail networks.** A rail network is a maximal set of orthogonally adjacent rail tiles, of any
   class. Its id is its lowest tile index. **Its capacity is its weakest tile's class** (one Power
   Rail tile in a Heavy line caps it at 16).
2. **Nodes and tree.**
   - The nodes are the Input (root), Onboard, each rail network and each board.
   - The Input's only child networks are Onboard and the one rail network holding its terminal
     tile (the *feeder*).
   - A board is a child of the first network, in BFS order, that touches its footprint. Every
     other network touching the board is a child of that board: its branches.
   - The tree is found by BFS in ascending node id order. Nodes the BFS does not reach are
     **dead**: disconnected rails power nothing, and the hover says "Not connected to the Lab
     Power Input".
3. **Attachment.** A machine is fed by the lowest-id live network or board that touches any of
   its footprint tiles (orthogonal adjacency), and otherwise by Onboard. Locked IO draws nothing.
4. **Load** of a node = Σ the demand of the machines it feeds + Σ its children's loads.
5. **Work rate.** Walk the path root → the machine's node. At each node where `load > cap`, set
   `r = max(1, r × cap / load)` (integer floor). This is today's brownout rule applied per level
   of the tree. Nothing ever breaks, and "no path" never happens (Onboard is always there).
6. **States per node:** normal < 75 %, near 75–100 %, overloaded > 100 %. A machine's **power
   bottleneck** is the node on its path with the smallest `cap / load`.
7. **Gating.**
   - Before `LabDef.CONFIG.power_level` (L12), every capacity is unlimited: today's behaviour.
   - From L12 the Input, Onboard (8) and rails apply.
   - The tutorial missions stay unlimited.

This produces the brief's "PSU installed, but the infrastructure limits delivery". Take a Desktop
PSU (32) where everything hangs off Onboard traces (8): the machines run at 8/demand. Adding a
feeder rail (16) and a board with two branches spreads the load.

### 5.3 Readouts
- **Top bar:** `Power 14 / 32` (demand / supply). When any node is overloaded, it adds a chip naming
  the worst node, e.g. `Onboard traces 11/8`.
- **Hover** on a machine: `Power 4 · Rail network #3 (12/16)`.
- **Hover** on a rail or board: `Heavy Power Rail · network 38/48 · 7 machines`.

## 6. Thermal: transport and dissipation capacities

The field, stages and hysteresis are unchanged (SYSTEMS_EXPANSION §5).

### 6.1 Capacities *(cal.)*
- **Heat Pipe chain transport cap: 320 per tick.** Each tick, sum the positive heat flow into a
  chain body from tiles outside it. If the sum exceeds the cap, scale every inflow edge by
  `cap / sum` (floor, in ascending edge order). Conservation holds exactly.
- **Thermal Manifold** (`thermal_manifold`, M, copper header, L14):
  - Every heat-pipe chain touching it, plus the manifold itself, forms **one** isothermal body.
  - Its transport cap is the sum of its pipes' caps.
  - It collects several machines' pipes into one run towards a cooling district.
- **Radiator dissipation cap: 600 per tick.** A cooler's bonus removal over its radius is summed. If
  the sum exceeds its cap, every tile's share is scaled down (floor, ascending tile order).
- **Heatsink cap: 160 per tick.**
- **Blower cap: 240 × rate / 12.**
- **Thermal contact** (visual and rules): the tile side of a machine that a heat-pipe end pad,
  manifold or cold plate touches draws a small copper contact pad on the chassis edge. Heat enters
  and leaves the body only through those contacts and the board, as today.

### 6.2 Liquid cooling (Era 10, L24)

| Part | Id | Size | Power | Rule *(cal.)* |
|---|---|---|---|---|
| Pump | `pump` | S | 2 | loop flow +400 × rate/12 per tick |
| Coolant Pipe | `coolant_pipe` | S, chainable | 0 | joins loop parts by orthogonal adjacency; insulated (no board exchange) |
| Cold Plate | `cold_plate` | S | 0 | takes `min(t × 32 / 64, 240)` per tick from each touching machine body |
| Large Radiator | `radiator_large` | L | 1 | dumps up to 900 × rate/12 per tick from the loop |
| Reservoir | `reservoir` | S | 0 | +1000 loop buffer |

- A **loop** is a connected set of coolant pipes, pumps, plates, large radiators and reservoirs.
- A loop **runs** when it has at least one pump and one large radiator.
- **Each tick:**
  - `pool += Σ plate intake`, capped by the loop flow (Σ pumps) and by the free buffer
    (base 200 + reservoirs).
  - `pool -= min(pool, Σ radiator dump)`.
- A loop that does not run takes nothing. It is deterministic and conservative.
- The Thermal overlay shows each loop's intake, flow and dump.

## 7. Information UX

### 7.1 The normal board stays calm
**Permanent chassis resource pips are removed:** the power pips, clock dots and tick pips
(`ResourceIndicators`). What stays on a chassis:
- the family tab, glyph, mini display and status LED;
- the **lane slices** (§8), which are real hardware, not a stat;
- the thermal strip only above WARM.

### 7.2 Hover card (~180 ms)
The card shows:
- Component name and Mk;
- width;
- lanes;
- rate (values/s at the current clock and power);
- power (and its network);
- heat and temperature;
- state;
- processing ticks.

It hides during a drag, a wire drag or a place (unchanged).

### 7.3 Upgrade card (quick action "Upgrade")
The quick bar gains **Upgrade** (between Rotate and Copy settings). It opens a small card with one
segmented row per axis (Width, Lanes, Clock, Efficiency):
- Locked steps show a lock and "Unlocks at L6 · Line Rate".
- A preview line reads `Rate 2.5 → 10 /s · Power 1 → 4 · Heat 84 → 336`.
- Applying is one undo step.

A **wire** clicked in Select mode opens the same card with a single Lanes row.

### 7.4 Overlays (at most one at a time; the View dock keys stay N B F T P, plus C)

| Overlay | Shows |
|---|---|
| **Data** (B) | per wire: class, lanes, utilisation (packets / slot capacity); **saturated wires** (§2.2) get an amber edge and a "bandwidth" tag |
| **Flow** (F) | unchanged |
| **Thermal** (T) | the heat map, plus pipe/manifold flow vs cap, radiator dump vs cap, loop state |
| **Power** (P) | networks tinted by load state, the Onboard load shown on the laptop frame, the bottleneck node outlined, dead rails hatched |
| **Compute** (C, new) | per machine: lanes busy/idle as slices, utilisation %; a machine whose lanes are all busy with a full input queue is marked "compute-bound" |

**Bottleneck rules:**
- A wire is **bandwidth-bound** when saturated in ≥ 50 % of the last 60 ticks.
- A machine is **compute-bound** when all lanes were busy and its inputs full for ≥ 50 % of the
  last 60 ticks.
- A node is **power-bound** when its load exceeds its capacity.
- A machine is **heat-bound** at THROTTLING or above.

The contract pane names the first bound it finds on the path to the drive.

## 8. Visual language (summary; the Penpot pages are canonical)

- **Bus classes.** A trace stays 3 px. A Byte Bus is a double trace (2 × 2 px, 3 px gap). A Wide Bus
  is the Style Lock 16 px ribbon. A Backbone is a 24 px banded bus. Lanes are hairlines inside the
  class footprint. All use the data colours; width is never shown by colour.
- **Lane slices.** Beside the glyph sit 1/2/4/8 vertical die slices (4 × 12 px, 2 px gap) in
  `MATERIAL_DIE` with a `MATERIAL_FRAME` hairline. A busy lane fills bottom-up with its progress in
  the family accent at 60 %. The single progress ring remains only on 1-lane machines.
- **Power.**
  - Rails are brass bus bars (`MATERIAL_GOLD` core on a `MATERIAL_PLATE_LO` insulator, 10 / 14 /
    20 px wide by class) with bolt dots at joints.
  - Boards are a dark panel with breaker slots.
  - The Lab Power Input is a keyed barrel-jack fixture on the laptop edge.
  - Power is never teal and never a wire.
- **Thermal.**
  - Copper, unchanged.
  - The manifold is a copper header block with pipe stubs.
  - Contacts are 6 × 3 px copper pads.
- **Liquid.**
  - Coolant pipes are dark tubes (`MATERIAL_PLATE_HI` walls, `MATERIAL_VENT` bore) with copper
    fittings.
  - Flow chevrons are shown only in the Thermal overlay.
  - The hot line is tinted amber only in the Thermal overlay.
  - No new colours.
- **VFX ladder** unchanged (L0 routine … L5 critical). Lane fills are L1. Saturation and
  power-bound marks are L3 (warning, amber), shown only in overlays or on the failing path.

## 9. Removed or superseded
- **Removed:**
  - Permanent power pips, clock dots and tick pips on chassis.
  - Large activity glow and port blobs (already gone).
  - Any mandatory thermal plate under machines.
  - Hard component-count limits.
  - Placeable USB Input machines (already sockets only).
  - "Every job builds a separate line".
- **Demoted:** concurrent quests (window 1 until L16).
- **Replaced:** the single global brownout (SYSTEMS_EXPANSION §4) → the §5 network. Heat pipes
  gain a transport cap. The Radiator gains a dissipation cap.

## 10. Save v3

`version: 3`. New fields:

| Where | Fields |
|---|---|
| machine `params` | `lanes`, `efficiency` (`clock` exists) |
| connection | `lanes` |
| lab | `power_input_row`, `psu_tier` (exists), `quest_window` state |

Rails, boards, manifolds and loop parts are ordinary machines in the layout.

**Migration 2 → 3:**
- `lanes 1` everywhere and `efficiency standard`.
- The old lab level index is mapped through `PROGRESSION.md §3` (the table of old → new).
- Any machine now standing on the Lab Power Input tile moves to the nearest free tile.
- `save.v2.json` is backed up.

## 11. Tests (each DS phase adds its own)

| Area | Tests |
|---|---|
| Data | width match (unchanged); 1-lane wire caps a socket at 1/tick; 2-lane wire carries 2/tick; oldest-first delivery; saturation detection; burst + FIFO overrun counts `lost` |
| Compute | 4-lane Add = 1 value/tick at normal clock; lanes stall on a blocked output; power/heat formulas for lanes, width factor, clock and efficiency |
| Power | Onboard cap 8 browns out a 12-demand board; feeder rail 16 + board 32 with two 16 branches carries 30; weakest-link rail; dead rail; new PSU limited by the old distribution (the §5.2 example); determinism |
| Thermal | pipe transport cap; manifold joins chains; radiator cap; blower rate scaling; throttling (unchanged); the liquid loop runs only with pump + radiator; loop conservation |
| Gameplay | every level solvable with only its unlocks (`tests/solutions.gd`); each level's "naive layout fails" proof; the same-line reuse proofs of `PROGRESSION.md §2` |
| Save | v2 → v3 migration; round-trip lanes, wire lanes and rails |
| Interaction | the upgrade card applies as one undo step; wire lane change; the overlays read only |

## 12. DS phases (the implementation order)

Each phase is one bounded DS job, or two, with exact files, tests and acceptance criteria. Claude
reviews each before the next starts.

| # | Phase | Scope |
|---|---|---|
| 1 | Capacity model | `Connection` lanes (§2.2), socket burst (§2.3), `Machine` lanes/backlog (§3.3), `ComponentDef.max_lanes`, power/heat formulas (§3.1) |
| 2 | Upgradeable components | params lanes/efficiency, `Simulation.set_lanes`, `set_wire_lanes`, unlock gates, Mk labels |
| 3 | Bottlenecks | saturation, compute-bound and power-bound metrics (§7.4) |
| 4 | USB / codecs | burst streams through codecs; the codecs get lanes |
| 5–6 | Power | the §5 parts, network, tree, brownout; the Lab Power Input fixture |
| 7–9 | Thermal | pipe cap, manifold, radiator/heatsink/blower caps, liquid loop |
| 10 | Upgrade UI + visuals | the upgrade card, lane slices, bus-class wires, rails/boards/liquid art, pip removal |
| 11 | Overlays | Data/Power/Thermal/Compute per §7.4 |
| 12 | QoL | wire card, blueprints (§12.1), palette groups for the new families |
| 13 | Progression | `PROGRESSION.md` as LevelDef assets, reference solutions, migration |
| 14 | Compute components | Subtract, Increment, Decrement, Queue, Signed Decimal Viewer, Width Converter |
| 15 | Memory/advanced | memory latency and bandwidth (RAM 1 read/tick, ROM 2); the Control Unit stub |
| 16 | VFX polish | function-specific processing per §8 and SYSTEMS_EXPANSION §8 |

### 12.1 Blueprints (the "compressed module" of the brief)
- Select a group, then **Save as blueprint** and name it ("CAESAR UNIT").
- It appears in the palette's **Blueprints** tab. Placing it drops the whole group with its internal
  wires (it reuses `copy_group`).
- Blueprints are saved with the Lab.
- **Not in this overhaul:** a collapsed single-box module that hides its internals. That needs
  hierarchical simulation and is future work.
