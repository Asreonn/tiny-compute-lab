# Tiny Compute Lab — Factory Systems (the growth overhaul)

> Status: **LOCKED 2026-09-26** (commit "Factory growth overhaul design locked").
> Source brief: `overhaulplan.md`. Levels: `docs/PROGRESSION.md`. Look: Penpot pages 21–24,
> summarised in `docs/STYLE_GUIDE.md §15`. Numbers marked *(cal.)* are calibration targets, tuned by
> tests rather than by eye.
>
> **2026-09-26 (data-factory revision, DRAFT for review):**
> - Compute and data content is redesigned in `docs/DATA_FACTORY.md` (primitive kit, records,
>   network, TEST/LIVE) and `docs/PROGRESSION.md` (the quest tree).
> - The capacity systems below stay in force. **Network** joins them as a fifth capacity
>   (DATA_FACTORY §6).
> - The level numbers quoted below (L4, L6, L16, L18, L22, …) belong to the superseded 31-level
>   plan. PROGRESSION §6 gives the new schedule.
> - §12's phases 13–16 are replaced by DATA_FACTORY §17 (C-phases).
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
| Power | source → conversion → distribution → pads | desk PSU + Lab Power Jack, Power Controller/VRM, planes, Distribution Boards, rails, chassis pads | adapter tier, VRM tier, plane/rail class, more boards/outputs, more pads |
| Thermal | capture → collection → transport → dissipation → airflow | chassis contacts, spreaders, manifolds, heat pipes/trunks, fin stacks/radiators, blowers, liquid loop | contact upgrade, wider pipe/trunk, more branches, bigger radiator, blowers up to need, exhaust placement, liquid |
| Network *(DATA_FACTORY §6)* | frames/s (16 bits per frame), shared by RX and TX | the Network Module on the laptop top edge | NIC Mk1 → Mk2 → Mk3 (more channels, more frames) |

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
- A wire is **saturated** in a tick in either case:
  - its entry refused a waiting packet while its head lane(s) delivered;
  - every lane took a value this tick and more still waits upstream (the output line, or a
    socket's FIFO, which overruns instead of blocking).
- Saturation, not length, is the bandwidth bottleneck signal (§7.4).

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

## 5. Power: one computer's power path (revised 2026-09-26, "hardware fantasy" brief)

Power works like a computer's power path, a chain of **stages**, each with its own capacity:

```
SOURCE            CONVERSION              DISTRIBUTION                              LOAD
desk adapter/PSU → Power Controller / VRM → Main Power Plane → Distribution Board → rails → pads → machines
(Lab Power Jack)   (fixed board module)     (flat copper embedded in the PCB)          (short local taps)
```

A machine runs slower when **the tightest stage on its path** is over capacity. Adding capacity to
any other stage does nothing. A bigger PSU behind a weak VRM or rail does not help; the player has
to find the bottleneck.

### 5.1 Parts by stage *(capacities are calibration targets)*

| Stage | Part | Id | Where / size | Capacity | Unlock |
|---|---|---|---|---|---|
| Source | Starter Adapter → Improved Adapter → Desktop PSU → High-Power PSU → Server PSU | desk item, plugs into the **Lab Power Jack** | desk | 8 / 16 / 32 / 64 / 128 | rewards (unchanged track) |
| Source | Lab Power Jack | `power_input` | fixed, west laptop edge at `power_input_row` | — | L12 |
| Conversion | Power Controller → Basic VRM → Efficient VRM → High-Current VRM | `power_controller` (tier param) | fixed L module beside the jack; outputs E and S | 12 / 32 / 32 (half the conversion heat) / 96 | L12 / L13 / L18 / L22 |
| Distribution | Main Power Plane | `power_plane` | S tiles, **linear chains** | 64 | L12 |
| Distribution | Heavy Power Plane | `power_plane_heavy` | S tiles, linear chains | 192 | L22 |
| Distribution | Distribution Board | `power_board` | M; 1 input (W) + up to 3 outputs (N/E/S), a breaker lamp per output | 48 | L12 |
| Distribution | Heavy Distribution Board | `power_board_heavy` (variant) | M | 144 | L22 |
| Distribution | Power Rail (the local branch along a machine row) | `power_rail` | S tiles, linear chains | 16 | L12 |
| Distribution | Heavy Rail | `power_rail_heavy` | S tiles, linear chains | 48 | L18 |
| Load | Power pads (built into the chassis) | — | south edge, one per tile of width | 8 per tapped pad | — |
| Later | Capacitor / Capacitor Bank (burst buffer), Priority Controller (priorities per output), local VRM | — | — | — | future |

**Topology rules** (they keep the base view readable):
- Planes and rails are **linear**. A tile never joins three copper neighbours. **Branching happens
  only at a Distribution Board** (or at the controller's two outputs). "Where does it split?" always
  has a visible answer.
- A **tap** is automatic. A machine pad that touches a rail or plane tile draws a short tap into it.
  There are no tap tiles and no long cables.
- **High-power machines need several pads.** Each tapped pad carries at most 8. For example, an
  8-lane Add (demand 8) is fine on one pad, but a Processor Mk2 (demand 16) needs both.
- Copper occupies floor tiles; no machine shares one. **A data wire may bridge a straight copper
  tile at a right angle** (`Router.CROSS_COST`), never along it and never at an end or board.
- Planes, rails and boards draw no power.
- **The VRM makes heat:** conversion heat = load / 8 per tick (Efficient VRM: / 16) on its own tiles.
  A hard-working VRM therefore wants a thermal branch too.

### 5.2 Flow (deterministic; rebuilt when the layout changes; `core/power/`)
1. **Tree.**
   - The source (the PSU) feeds the controller.
   - The controller's two outputs each start a chain.
   - A chain that ends on a Distribution Board's input side feeds that board, and each board
     output starts a new chain.
   - Chains are walked from the source end; tile order gives flow direction.
   - Copper not reachable from the controller is **dead**. Its hover reads "not connected to the
     Power Controller".
2. **Taps.**
   - A machine is fed at the first tapped tile, in path order, of the lowest-id live chain touching
     one of its pads.
   - All its tapped pads must be on that chain; pads on other chains are ignored and the hover says
     so.
   - An untapped machine draws from the **onboard traces**: a small implicit child of the controller
     with capacity 8, the early-game path.
3. **Load of every node** (each copper tile, board, controller, source) = Σ the demand fed at or
   downstream of it.
4. **Bottleneck.**
   - A machine's path is: source → controller → the chain tiles up to its tap → its pads (capacity
     8 × tapped pads).
   - Its bottleneck is the node with the smallest `cap / load` among overloaded nodes.
   - Work rate `r = max(1, r × cap_b / load_b)` (integer). Only the tightest stage counts, and
     slowdowns never compound.
5. **States:** normal < 75 %, near 75–100 %, over > 100 %.
6. **Gating:**
   - Before `power_level` everything is unlimited.
   - From L12 the chain applies.
   - `LabConfig.onboard_capacity` = 0 keeps the old campaign unlimited until the progression
     rewrite.
   - The tutorial missions stay unlimited.

### 5.3 What the player can do (no universal answer)
- Upgrade the adapter.
- Upgrade the VRM.
- Upgrade the plane or rail class.
- Split the load over another Distribution Board output or a second controller output.
- Tap a second pad.
- Lower the clock.
- Switch the machine to efficient.
- Later: capacitors for bursts.

### 5.4 Readouts
- **Normal board:** structure only. An overloaded node gets a 1 px amber edge (rail or plane
  segment) or its breaker lamp (board or controller). There are no numbers and no glow.
- **Power overlay (P):** one chip per node, plus a stage panel for the hovered or selected machine:
  `Adapter 120 · VRM 60 · Main Plane 40 ⚠ · Branch 40 · Pads 16 · Demand 52`.
- **Hover:** `Power 8 · Rail B (26/16 ⚠) · 2 pads`.
- **Top bar:** demand / source, plus a chip for the worst node.

## 6. Thermal: one computer's cooling path (revised 2026-09-26)

Heat has its own staged chain, and every stage has a capacity:

```
SOURCE       CAPTURE                 COLLECTION               TRANSPORT                  DISSIPATION           AIRFLOW
machine → integrated contact → Copper Spreader / Manifold → heat pipe / trunk → Fin Stack / Radiator → blower → exhaust (chassis edge)
```

- The temperature field, the heat generation and the stages with hysteresis stay as they are
  (`ThermalGrid`, SYSTEMS_EXPANSION §5). Density still matters: neighbours heat each other.
- **What changes is how heat leaves.** It no longer leaves through "coolers with a radius" next to
  the machines. It leaves through the machine's **thermal contact**, into a **thermal network**,
  out at a **radiator**, and into the air.
- Fans are no longer local props. They live in the cooling assembly and only feed airflow to
  radiators.

### 6.1 Parts by stage *(cal.; H = heat units per tick, tenths of °C as today)*

| Stage | Part | Id | Size | Capacity | Unlock |
|---|---|---|---|---|---|
| Capture | Integrated Thermal Contact | built into every heat-producing chassis (north edge) | — | S 600 · M 1200 · L 2400 | L14 |
| Capture | High-Capacity Contact | machine upgrade param `contact` = high | — | ×2.5 | L22 |
| Capture (liquid) | Cold Plate / Water Block | machine upgrade `contact` = liquid (coolant ports on the chassis) | — | ×4 | L24 |
| Collection | Copper Spreader | `thermal_spreader` | S tiles, linear; laid along a row's contact side; every touching contact feeds in | 2400 per chain | L14 |
| Collection | Thermal Manifold | `thermal_manifold` | M; sockets W/N/S in, E out | 4800 | L15 |
| Collection | Vapor Chamber | — | later | — | future |
| Transport | Copper Heat Pipe | `heat_pipe` | S tiles; joins any orthogonal neighbour (T-junctions allowed) | 800 | L14 |
| Transport | Heavy Heat Pipe | `heat_pipe_heavy` | S tiles | 2000 | L18 |
| Transport | Thermal Trunk | `thermal_trunk` | S tiles (a wide flat vapor-chamber bar) | 4800 | L22 |
| Dissipation | Passive Fin Stack | `fin_stack` | M; needs no airflow | 400 | L14 |
| Dissipation | Radiator | `radiator` | L; airflow need 40 | 1600 | L15 |
| Dissipation | Large Radiator | `radiator_large` | two L cores; airflow need 100 | 4800 | L24 |
| Airflow | Small Blower | `blower` | S; power 2 | airflow 25 | L15 |
| Airflow | High-Pressure Blower | `blower_hp` | M; power 4 | airflow 60 | L22 |
| Airflow | Fan Bank | `fan_bank` | L; power 6 | airflow 120 | L24 |
| Liquid | Coolant Pipe, Pump, Reservoir | `coolant_pipe`, `pump`, `reservoir` | S | pipe 3200 · pump flow 1200 (Pump II 2400) · reservoir buffer +4000 | L24 |
| Early option | Heatsink (clip-on) | `heatsink` | sits on a machine's contact (no network needed) | 120, dumps locally into the grid | L14 |
| Later | Thermal Mass / Heat Buffer | — | stores a burst | — | future |

### 6.1b Layers and crossings (one board, three layers)
- **Power** copper is embedded in the board: planes, rails and taps are the bottom layer.
- **Data** traces run on the board surface. A data wire may bridge a straight copper tile at a right
  angle (§5.1).
- **Thermal** hardware is raised and mounted on top: heat pipes, trunks, spreaders and coolant
  pipes. A heat-pipe or coolant tile may pass **over** a straight data wire or copper tile at a
  right angle. It never runs along one and never crosses at a junction or end.
- Machines, boards and assemblies block every layer.
- Two thermal tiles that touch join the same network (T-junctions). Spreaders are the exception:
  they are linear.

### 6.2 Network and flow (deterministic, integer)
1. **Network.**
   - A thermal network is a connected set of spreader, pipe, trunk and manifold tiles.
   - Pipes and trunks join any orthogonal neighbour, so **T-junctions are allowed**. Spreaders are
     linear.
   - A machine is **connected** when a network tile touches its contact edge.
   - A radiator or fin stack is connected when a network tile touches its **inlet side**. The inlet
     is the side opposite its exhaust; the exhaust is set by rotation.
2. **Tree.**
   - Each network is walked from its radiators outward, BFS in ascending tile order.
   - Every tile, manifold, spreader chain, contact and radiator is a node with a capacity (§6.1).
   - Its flow = the heat that passes through it towards a radiator.
3. **Each tick, after generation and diffusion:**
   - **Offer.** Each connected machine offers `min(contact cap, body heat × 1/4)` from its
     footprint tiles. A cool machine offers little; a hot one offers up to its contact capacity.
   - **Allocation.** Offers flow up the tree. At every node whose flow exceeds its capacity, all the
     offers through it are scaled down proportionally (integer, ascending id; the remainder goes to
     the lowest id).
   - **Radiator stage.** Radiators take `min(inflow, cap × min(1, airflow / need))`.
   - **Airflow.**
     - A blower counts for a radiator when it touches the radiator's inlet side with its outlet
       facing it.
     - Airflow is summed and **capped at the radiator's need**, so extra fans add nothing.
     - A blower whose intake side is blocked by a machine gives half.
     - Passive fin stacks need no airflow.
   - **Exhaust.**
     - A radiator whose exhaust side faces the board edge dumps the heat out of the computer.
     - Otherwise it **recirculates**: the dumped heat is added to the tiles in front of its
       exhaust, so a badly placed plant heats the board.
   - **Removal.** The allocated heat is taken from the machines' footprint tiles, in proportion to
     each machine's share.
4. **Exact conservation.** Heat leaves only through edge exhausts, ambient dissipation and the
   board edge, exactly as the grid does today.
5. **Liquid.**
   - A loop is a connected set of coolant pipe, pump, reservoir, radiator (liquid inlet) and
     liquid-contact machines.
   - The loop is the same chain: contact (cold plate) → pipe → **pump flow** → radiator → airflow.
     It is the same allocation with the pump as one more stage.
   - The reservoir buffers up to its size between ticks.
   - A loop without a running pump moves nothing. More fans never fix a weak pump.

### 6.3 What the player can do
- Tap more contacts into the network.
- Use High-Capacity Contacts.
- Add a second branch.
- Use a wider pipe or trunk.
- Place a manifold.
- Use a bigger radiator.
- Add blowers, only up to the radiator's need.
- Fix the airflow direction.
- Move the plant to the edge.
- Lower the clock or switch to efficient.
- Spread machines out (density).
- Later: liquid.

### 6.4 Readouts
- **Normal board:** structure only.
  - The copper path is continuous and visible: contact → branch → T-junction → trunk → manifold →
    transport → fin stack → blower → exhaust vent.
  - Hot parts warm subtly: amber sheen on pipes near hot machines, and on the fin-stack base.
  - A saturated stage gets a 1 px amber edge. There are no numbers.
- **Thermal overlay (T):** the heat map plus one chip per stage node, and a **stage panel** for the
  hovered machine: `Heat 52 · Contact 80 · Spreader 96 · Trunk 40 ⚠ · Radiator 80 · Airflow 90/40`.

### 6.5 Migration from the current model
- Heat pipes stay placeable tiles. They now join any neighbour and carry capped flow instead of
  isothermal conduction.
- The Heatsink becomes the clip-on early option.
- The Blower loses its dissipation radius and becomes an airflow part of a radiator.
- The Radiator keeps its L size and gains an inlet/exhaust by rotation.
- Old saves keep their parts. Layouts that relied on radius cooling will simply cool less; the
  progression rewrite re-tunes the thermal levels.
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
  - Power parts are siblings of the machine family: canonical shells with a gold tab and square
    gold terminals.
  - Copper is a dark, flush PCB pour with gold edge lines and via rows. Taps run to solder pads;
    contacts are gold teeth on the chassis.
  - Power is never teal, never a pipe, and never a bare PCB module (STYLE_GUIDE §15.3).
- **Thermal.**
  - The hardware is physical but flattened: soldered heat-pipe bands, vapor-chamber trunks, and
    spreaders in rail mounts.
  - Chassis parts use canonical shells with a copper tab and round copper sockets.
  - The radiator and its blowers form one shrouded cooling assembly under the chassis vent
    (STYLE_GUIDE §15.4).
- **Liquid.** The same chain: coolant tubes with copper fittings, and a pump and reservoir in
  canonical S shells. The hot/cold tint appears in the Thermal overlay only.
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

## 13. Future: composed hardware (compatibility requirement, not implemented now)

Primitive machines → saved groups (blueprints, §12.1) → a **composed block** (ALU, CPU core, GPU-like
array) that behaves as one high-demand machine.

So that power and thermal already scale to such blocks:
- `ComponentDef` carries **`pads`** (count and side), **`contact_cap`** and **`max_lanes`**. A big
  block simply declares many pads, a large contact and a wide data interface.
- A block's demand, heat and bandwidth come from the same formulas (lanes × width factor ×
  clock × efficiency).
- It therefore needs a heavy rail with several taps, a High-Capacity or liquid contact, and a wide
  bus.
- The staged power and thermal chains never special-case machine types. They read only those def
  fields, so a future block plugs in unchanged.
