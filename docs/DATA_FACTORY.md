# Tiny Compute Lab — The Data Factory (compute / data / network MVP refoundation)

> Status: **LOCKED 2026-09-26** (user approval). Decisions made at the lock:
> - Distributor and Join are generic flow primitives. The legacy Splitter and Merger stay for save
>   compatibility; the new progression uses Distributor and Join.
> - The idle baseline is data-driven (`ComponentDef.idle_pct`, default 12, meant to be
>   rebalanced). It is not a fixed 20 %.
> - Penpot numbers are illustrative, not balance constants.
> - No custom module or blueprint authoring yet.
> - C3–C8 may start. The correlation/enrichment content (C9+) waits until the page 24 scenes (one
>   source live, three sources) are finished and locked.
>
> - Source brief: "COMPUTE / DATA / NETWORK MVP REFOUNDATION", 2026-09-26.
> - Quest content: `docs/PROGRESSION.md`. The four physical capacities (data, compute, power,
>   thermal) stay as in `docs/FACTORY_SYSTEMS.md`; this document adds the **network** capacity
>   and replaces its §12 phase list for compute/data work.
> - Numbers marked *(cal.)* are calibration targets. The reference-solution tests tune them.

## 0. The one idea

The player builds a computer that processes fictional compromised data. It is built from
**general bit hardware they wire themselves**.

```
bit primitives → logic circuits → word circuits → data circuits → analysis systems → one big factory
```

- **No domain machines.** There is no Parser, Validator, Firewall, Matcher, Scorer, Deduplicator
  or Enricher.
  - Each of those is a **graph** of Forks, Field Splitters, Compares, gates, Selectors, Adds and
    memory, and the player builds it.
  - If a system cannot be built, the question is which *general* primitive is missing (§15).
- **Everything inside compute is a BitVector.**
  - A source schema such as "bits 15–10 USER_TAG" is documentation shown to the human.
  - Nothing parses it automatically.
- **No primitive becomes obsolete.**
  - Early on, primitives build everything.
  - By midgame they are the glue between standard cells.
  - Late, they are the cheap specialised logic that beats a generic cell on area, power, heat
    or latency.
- **Topology carries the complexity, not visual noise.**
  - The endgame board is dense because it has many branches.
  - Routine activity stays calm (STYLE_GUIDE, VFX ladder).

The growth loop joins compute to the physical systems:

```
new source / contract → the graph grows → a throughput bottleneck → parallelise or widen
  → the power bottleneck → upgrade distribution → the thermal bottleneck → upgrade cooling
  → the network bottleneck → upgrade the card → the factory grows
```

## 1. Audit of the current compute kit (C0)

Classes:
- **PRIM** (primitive, taught first).
- **CELL** (standard cell, taught as a derived circuit, then kept as a practical part).
- **LATER** (moved behind the MVP).
- **LEGACY** (still loads and simulates; hidden from the build menu).
- **REDESIGN** (behaviour or name changes).

| Component (id) | Today | Class | Change |
|---|---|---|---|
| NOT (`not_gate`) | S, bitwise NOT | PRIM | Display name **Inverter**; unchanged logic |
| Gate (`gate`) | S, passes D while EN = 1, else drops | PRIM | "the valve": drops, whereas the Bit Switch zeroes |
| Delay (`delay`) | S, holds N ticks | PRIM | Default `ticks` 1 (was 3) |
| Compare (`compare`) | S, `in op k` → 1 bit | CELL + REDESIGN | New optional **B** input (N side); unconnected B is tied to `k` (§3.2) |
| AND / OR / XOR | L, a op b | CELL + REDESIGN | New `k` param; unconnected B is tied to `k`. **Mask** = AND with B tied |
| Add (`add`) | M, in + k | CELL | Unchanged |
| Adder (`adder`) | L, a + b, 1 lane | CELL | Taught as "Half Adder → Full Adder → N bits" (§4) |
| Multiply, Modulo | M | CELL | Unchanged; Modulo is reused by the fingerprint |
| Shift L / R | M | CELL | Unchanged |
| Splitter (`splitter`) | L, Alternate / Duplicate | LEGACY | Replaced by the S-size **Distributor** (deal) and **Fork** (copy); saves keep working |
| Merger (`merger`) | L, 2 inputs, fair | LEGACY | Replaced by the S-size **Join** (3 inputs, fair); saves keep working |
| Mux (`mux`) | L, only the selected input is taken | CELL + REDESIGN | Display name **Selector**. Adds `take` = both (default: consumes every connected input of the same record) or chosen (the old behaviour, which saves keep), plus tie-offs `a`/`b` |
| Demux | L | CELL | Routes by a flag |
| Cond Router | L | CELL | Documented as the fused Compare + Demux |
| Bit Splitter / Bus Combiner | L, 2 parts | LEGACY | Replaced by the **Field Splitter / Field Joiner** (4 fields). Existing ones keep working |
| Zero/Sign Extend, Truncate | M | CELL | Unchanged |
| Char/Number Encoder/Decoder | L | CELL | The raw-boundary lesson in Act I only |
| Buffer | M | CELL | The **Queue** of the brief |
| Counter | S | CELL | Group/aggregate work (side contracts) |
| Register | M, echo / on read | CELL | The word memory cell; feedback seed for stateful fingerprints |
| Register Bank, ROM | L | LATER | Lookup side contracts; CPU track |
| RAM | L, 16 cells | LATER + REDESIGN | Address width param 4 / 6 / 8 (16 / 64 / 256 cells) for dedup; C-late |
| ALU, Instruction Decoder, Program Counter, Processor | L / S | LATER | The CPU track becomes an optional branch after the MVP (PROGRESSION §5) |
| USB Input / Output, Terminal Output | sockets | keep | Act I–II I/O; audit outputs later |
| Legacy Input / Output | missions | keep | Regression missions only |

**Roadmap-only parts** (Penpot page 14, not in code): Subtract, Increment, Decrement, TypeSwitch,
the Viewers and Adapter4to8. They are **not** added for the MVP:
- Increment is an Add with k = 1.
- Subtract is an Add with the two's complement.
- The Viewers become the **Probe**.

## 2. The primitive kit (new parts)

All primitives are the smallest siblings of the canonical family:
- the same MachineShell, border, chamfer and FamilyTab;
- one recessed functional window;
- one physical LED.

Size follows the port count:
- one data input → **S**;
- three inputs → **L** (the Selector).

Rates are per lane at the normal campaign clock. Power is in the usual integer units, before the
width factor.

| Part (id) | Family | Size | Ports | Rule | Ticks | Power | Lanes |
|---|---|---|---|---|---|---|---|
| **Bit Switch** (`bit_switch`) | logic | S | D (W), EN (N, 1-bit control), Q (E) | Waits for one D and one EN. EN = 1 → Q = D; EN = 0 → Q = 0 of D's width. **Bit logic: it always answers** (one result per record) | 2 | 1 | 4 |
| **Inverter** (`not_gate`) | logic | S | in, out | Flips every bit (1-bit: the NOT) | 2 | 1 | 8 |
| **Fork** (`fork`) | routing | S | in (W); out A (N), B (E), C (S) | Duplicates each incoming value to every **connected** output: same bits, same record identity. It knows nothing about branches or priorities. A copy cannot enter a full branch, so a slow branch backs up into the Fork and then upstream: **fan-out is limited by the slowest required branch** (§11) | 1 | 0 | 4 |
| **Distributor** (`distributor`) | routing | S | in (W); out A (N), B (E), C (S) | Deals each value to the **next connected output** in A → B → C order. An output whose wire is full is skipped this tick; it stalls only when all are full. The manual-parallelism part | 1 | 0 | 4 |
| **Join** (`join`) | routing | S | in A (N), B (W), C (S); out (E) | Takes one value per step from the next non-empty connected input in turn (fair). Reconverges branches and parallel pipelines; it may reorder | 1 | 0 | 4 |
| **Selector** (`mux`, evolved) | routing | L | A (W top), B (W bottom), SEL (N, control), out (E) | take = both: waits for SEL and every connected data input, consumes them all and emits A when SEL = 0, B when SEL = 1. An unconnected A or B reads its tie param `a`/`b`. take = chosen: the old Mux | 2 | 1 | 1 |
| **Latch** (`latch`) | memory | S | D (W), EN (N, control), Q (E) | Waits for EN (and D when D is connected). EN = 1 → store D and emit it; EN = 0 → emit the stored value (D is consumed and ignored). An unconnected D reads the tie param `d` (default 1 → a "set" flag). `init` is the first state | 2 | 1 | 1 |
| **Delay** (`delay`) | storage | S | in, out | Holds each value `ticks` ticks (default 1); synchronisation | n | 1 | 1 |
| **Constant** (`constant`) | memory | S | out (E) | Emits `value` (set with bit cells, instance width) whenever its wire has room. Editing the value flushes its wire | — | 0 | 1 |
| **Probe** (`probe`) | view | S | in (W), out (E, optional) | Passes values through, or is a sink when out is unconnected. The face shows the last value as 0/1 cells (low 8 bits, then "…") and a pass tick. During a test run it tags the vector number. It **never counts** toward component budgets | 1 | 0 | 1 |
| **Clock** (`clock`) | control | S | out (E, 1-bit control) | Emits a 1 every `period` ticks (default 10 = 1/s). A pulse is skipped when the wire is full. It is separate from the playback speed | — | 0 | 1 |
| **Field Splitter** (`field_splitter`) | conversion | L | in (W, cell 0,0); f0 (N, cell 1,0), f1 (E, 1,0), f2 (E, 1,1), f3 (S, 1,1) | `fields` = widths MSB-first, e.g. `6 3 4 3` (≤ 4 fields, sum ≤ width, low leftover bits dropped). Unconnected field outputs are discarded, never blocking | 2 | 1 | 4 |
| **Field Joiner** (`field_joiner`) | conversion | L | f0 (N, 0,0), f1 (W, 0,0), f2 (W, 0,1), f3 (S, 0,1); out (E, 1,0) | `fields` widths; waits for every connected input; an unconnected field is 0 of its width; out = f0 · f1 · f2 · f3 (MSB first) | 2 | 1 | 1 |

Field order runs top to bottom on both parts, so a record fans out and folds back in visual bit
order.

### 2.0 Taxonomy (explains the hierarchy; the look of the parts is unchanged)

| Group | Parts | Meaning |
|---|---|---|
| **ATOMS** (low-level primitives) | Bit Switch, Inverter, Fork, Latch, Delay, Constant, Probe, Clock | the smallest pieces of logic, state and debugging |
| **FLOW / BUS PRIMITIVES** | Gate, Field Splitter, Field Joiner, Distributor, Join | move, filter, slice and assemble bits; no arithmetic |
| **STANDARD CELLS** (derived) | Selector (Mux), AND, OR, XOR, Compare, Add, Adder, Modulo, Shifts, Demux, Cond Router, Register, … | circuits the player learned (or could build) from atoms, kept as practical parts. They are never removed just because they are derivable |

**Bit Switch vs Gate — not duplicates** (the labels, tooltips and Q3/Q6 briefs say this):
- **Bit Switch** is *bit logic*. EN = 0 still produces a deterministic result (0). Use it to
  build logic.
- **Gate** is *stream flow*. EN = 0 means the value does not pass and nothing is emitted. Use it to
  filter a stream.

**Field Splitter / Joiner are pure bit slicing.**
- The Field Splitter knows bit ranges only: `16 bits → 6 | 3 | 4 | 3` = bits 15..10 · 9..7 ·
  6..3 · 2..0.
- The Field Joiner concatenates configured widths. It never builds a "UserRecord".
- Names such as USER_TAG, REGION, ACTIVITY and FLAGS are schema labels in the UI (schema card,
  Inspector ruler, hover). The simulation never reads them.
- The Inspector always shows the raw split next to any label.

### 2.0b Every part is physical (power, heat, capacity, area)

Every primitive and standard cell uses the locked systems of FACTORY_SYSTEMS §3, §5 and §6. There
are no special cases:

- **Power** is drawn per provisioned lane: `power × lanes × width factor × clock × efficiency`.
  - It flows through the part's chassis **power contacts**, via automatic taps, from the rail or
    plane under its row.
  - That rail is fed by the one chain: Lab Power Input → PSU → VRM → backbone → branches.
- **Heat** follows the work actually done: `heat × width factor × clock heat` per job.
  - It leaves through the part's **integrated thermal pickup** into the shared spreader, then the
    manifold, the heat pipe / trunk, the radiator and the blowers.
  - There is never a local PSU or fan per part.
- **Idle baseline** (locked; data-driven, `ComponentDef.idle_pct`, default **12**, per-asset
  override):
  - **Heat** per tick is `heat × clock heat × (idle_pct % × lanes + (100 − idle_pct) % ×
    work done / clock rate)`. Full load is unchanged; an idle powered part still warms by idle_pct.
  - **Power draw** (`Machine.power_draw()`) is the same blend of `power_demand()`. It feeds the
    readouts (hover card, Lab draw).
  - The **rails stay sized for peak** `power_demand()`. The locked power network is unchanged, so
    brownout still means the peak cannot be supplied.
  - Over-provisioned copies therefore cost peak capacity (rails), a baseline draw and baseline
    heat.
- **Capacity** is `lanes × rate` (the §2 table's ticks). **Area** is the footprint in tiles, plus
  the wires and the space the power and thermal hardware need.

| Part | Power / lane | Heat / job | Rate / lane | Footprint |
|---|---|---|---|---|
| Fork, Distributor, Join, Probe, Constant, Clock | 0 | 0 | 10/s | S · 1 tile |
| Bit Switch, Gate, Inverter, Latch, Delay | 1 | 1 | 3.3–5/s | S · 1 tile |
| Compare | 1 | 1 | 3.3/s | S · 1 tile |
| Field Splitter / Joiner | 1 | 1 | 5/s | L · 4 tiles |
| AND / OR / XOR, Selector | 1 | 1 | 5/s | L · 4 tiles |
| Add, Modulo | 1 | 1 | 2.5/s | M · 2 tiles |
| Multiply | 2 | 3 | 1.7/s | M · 2 tiles |
| Buffer | 1 | 0.5 | 5/s | M · 2 tiles |

Everything is × the width factor: a Gate or splitter on a 16-bit record draws 3.

### 2.1 Why these and no more
- The **Bit Switch** is the transistor-like atom.
  - AND with a broadcast bit is a Bit Switch.
  - A Selector is two Bit Switches plus an OR.
- The **Gate** is its dropping sibling: filtering.
- The **Fork** is how shared results feed several consumers. Its siblings the **Distributor**
  (deal) and **Join** (collect) are the manual-parallelism pair: all three have the same shell and
  the same N/E/S ports.
- The **Latch** turns a stream into state.
- **Constant, Probe and Clock** make circuits testable and self-contained.
- The **Field Splitter/Joiner** are what make records physical.
  - Without them a 16-bit record needs a tree of three 2-way splitters.
  - With them one part fans a record into its fields (field-level parallelism, brief §10).

## 3. Rules the primitives introduce

### 3.1 Record identity is safe; timing is physical (the one rule players must learn)
- **Every value carries a record context.**
  - It is the source's **session sequence** `s` plus the set of sources it came from.
  - Sources stamp it. Single-input parts keep it. Combining parts union it (lineage,
    `Packet.origins`).
- **A part with several data inputs combines only values of the same record.**
  - Those parts are Bit Switch, Gate (D + EN), Latch, Selector, Compare with B, AND/OR/XOR,
    Adder and Field Joiner.
  - Two values match when their session sequence `s` is equal. Two sources' records with the
    same `s` were captured in the same session window (§5.3).
  - Constants and tie-offs have no context and fit any record.
- **Records never mix because of timing.** A fast value never meets the wrong partner.
- **Waiting is not free.**
  - If a required input has not received its value for that record yet, the part **waits**.
  - The early value sits in the input queue (capacity = lanes + 1).
  - A full queue refuses the next value and backs up its branch.
  - The part fires on the oldest record present on all required inputs.
- **So branch depth matters.**
  - A long branch adds latency to every record.
  - Branches of different speed cost queue space or throughput.
  - Buffer, Delay, Latch/Register, duplicated compute and changed topology are the tools. None of
    them is always right (§11).
- **Routing parts** may emit nothing (Gate, Demux, Cond Router) or reorder (Distributor →
  pipelines → Join). Reordering is safe, because pairing is by record, not by arrival order.
- **Orphans (exact, no timeouts).** A waiting value of record `s` is discarded as an **ORPHAN**
  when a required partner input can no longer receive `s`:
  - no value of `s` exists anywhere upstream of that input (wires, queues, jobs, backlogs,
    FIFOs);
  - and every source upstream of it has already emitted `s`.
  - Orphans are counted and named in the part's hover card and Inspector.
  - The usual design is to combine first and filter after, or to zero with a Bit Switch instead of
    dropping.
- **Context-free values** (`ctx = -1`) fit any record:
  - Constants, Clock pulses and tie-offs;
  - **stored state**: the Register's output (echo and read).
  - State is not a record, so accumulator and feedback loops (Running Sum, the CPU branch) keep
    working.
  - A Latch output belongs to its EN's record.
  - A RAM or Register Bank read belongs to its address's record.

### 3.2 Tie-offs
- A data input marked `tie` in its PortDef may be left unconnected. It then reads the component's
  constant param every step and never waits.
  - Compare.B ← `k`; AND/OR/XOR.B ← `k`; Selector.A/B ← `a`/`b`; Latch.D ← `d`.
- This is ordinary hardware ("tie high / tie low"). It keeps scorers and masks from turning into
  Constant spam.
- The Constant part still exists: a shared value is **one Constant forked** to many consumers.
- In the view, a tied port shows a tiny tie cap with the value's bits in silk. It is not a port
  ring.

### 3.3 Standard cells are derived circuits (brief §5)
- Each CELL's hover card and Inspector name its derivation:
  - Adder = Full Adders;
  - Compare = bit tests plus a combine;
  - Selector = 2 Bit Switches + OR;
  - Mask = AND tied;
  - Cond Router = Compare + Demux.
- **Act I teaches three derivations by hand** (PROGRESSION Q3, Q8, Q9):
  1. the Bit Switch;
  2. the Half Adder;
  3. the Adder, after "you built one bit of this".
- **Compatibility:** an "open module / inspect internals" feature and player-made reusable modules
  (FACTORY_SYSTEMS §12.1 blueprints → §13 composed blocks) must be able to use the same
  derivations.
  - A CELL def may name `derived_from` (a blueprint id). Nothing simulates through it yet.

## 4. Primitive → standard cell (the taught hierarchy)

```
A ─┬─────────────┐                    A ─┐        ┌─ SUM
   │   ┌─ XOR ── SUM                     HALF ─┬─┤
B ─┼─┬─┘                              B ─┘      │ └─ c1 ─┐
   └─┼── AND ── CARRY                           HALF ─ SUM  OR ── CARRY
     └─┘                              Cin ──────┘  └ c2 ─┘
 Half Adder (2 Forks, XOR, AND)       Full Adder (2 Half Adders + OR)

 3 × Full Adder (ripple)  ═══►  Adder cell (L)  "a + b · wraps at W bits"
```

Equality of two streams (for correlation) is taught the same way:
- `a XOR b → Compare (= 0)`. Then Compare with a connected **B** is the cell.

## 5. Records and sources (brief §12–§17, §46)

### 5.1 A record is a BitVector with a documented layout
- The **schema card** (source UI, stick label, Inspector of a wire that carries it) shows the
  field ranges.
- The Field Splitter's Inspector shows a bit ruler. The player types the widths; the schema is
  shown beside the ruler for reference only.

### 5.2 The three fictional compromised sources (persistent resources, not per-quest generators)

| Source | Width | Layout (MSB → LSB) | Purpose | Live rate *(cal.)* |
|---|---|---|---|---|
| **ForumCache** | 16 | USER_TAG 6 · REGION 3 · ACTIVITY 4 · FLAGS 3 (b2 MOD, b1 BOT, b0 INVALID) | identity / activity baseline | 3/s, then 6/s ("full mirror"), then 10/s |
| **ShopMirror** | 16 | REGION 3 · USER_TAG 6 · SPEND 5 · CATEGORY 2 | commercial value (a different field order, so its frontend matters) | 4/s |
| **ArchiveNode** | 32 | USER_TAG 6 · FRESHNESS 4 · QUALITY 3 · FLAGS 3 (b2 REDACTED, b1 DUP, b0 STALE) · ARCHIVE_ID 12 · CHECK 4 | quality / freshness enrichment; the integrity check | 3/s |

**Stable schemas.** A source never changes its layout. The values change; the ore stays the same
ore.

**USER_TAG** comes from one shared fictional population, so the sources correlate:
- 63 identities (1–63; 0 = anonymous).
- Each identity has fixed attributes: home region, activity level, spend tier, category, quality.

### 5.3 Deterministic generation (`core/network/source_stream.gd`, pure)
- `record(def, seq)` is a pure function of `(def.seed, seq)`: splitmix hashes, no RNG state.
  The stream state is only the next `seq`.
- There is a shared session sequence `U(seq)`.
  - Record `seq` of every source is about identity `U(seq)` with probability `p_same`:
    - Forum 1.0;
    - Shop 0.70;
    - Archive 0.80 *(cal.)*.
  - Otherwise it is about another identity.
- Field noise *(cal.)*:
  - REGION differs from home 8 %;
  - USER_TAG = 0 5 % (Forum);
  - INVALID 10 %; BOT 6 %;
  - STALE 12 %;
  - CHECK wrong 10 % (a corrupt record).
- The **Database Dump USB** (Act II) is a stick whose stream is `record(forumcache, 0..63)`,
  looping.
  - It is the same schema as the live ForumCache, so the refinery built on USB later takes the
    live feed unchanged.

### 5.4 `RemoteSourceDef` (content, `content/network/sources/<id>.tres`)

```
id, display_name, glyph, width
fields     [{name, width, desc, kind: id|enum|range|flags, labels?}]   # MSB first
rate       records/s when LIVE          realtime  false (paused when full) | true (drops)
remote_buffer  records held remotely before pausing or dropping (default 32)
seed, p_same, noise {field: probability}
test_vectors   [{seq, note}]            # the source's default test set
value      base sale value per accepted record (1)
```
The population is `content/network/population.tres` (count, attribute ranges, seed).

## 6. The Network Module (brief §14–§15, §45)

### 6.1 The part
- A **locked chassis-edge fixture** on the laptop's **top edge**, where laptop antennas live.
  - It is a 5×1 module with the canonical EdgeIn shell turned to face the lid.
  - Two thin antenna leads run off the top edge.
  - Ports sit on its board side (S), left to right: **RX A, RX B, RX C, TX A, TX B**.
  - A recessed status window shows the TEST/LIVE lamp and a split RX|TX load bar.
  - FamilyTab io (green).
- It never understands data; it only moves bits.

| Tier | Ports open | Capacity *(cal.)* | Power | Unlock |
|---|---|---|---|---|
| NIC Mk1 | RX A, TX A | 12 frames/s | 2 | Q16 |
| NIC Mk2 | RX A–B, TX A–B | 24 frames/s | 4 | Q21 |
| NIC Mk3 | RX A–C, TX A–B | 48 frames/s | 6 | Q26 |

- Sealed ports carry caps, like sealed laptop ports.
- The footprint never changes with the tier.

### 6.2 Capacity (the fifth capacity, same language as the other four)
- **A frame is 16 bits.** A record costs `ceil(width / 16)` frames: a 32-bit record costs 2.
  Bandwidth is bits.
- Allowance per tick: the module keeps a credit bucket of `+cap/10` per tick, capped at
  `max(4, cap / 2)`. It spends credits:
  1. **TX first**, channels A then B (so the factory always drains);
  2. then **RX**, round-robin starting at `tick mod open_rx`.
  - A record moves only when its whole frame cost is available.
- RX sockets work like USB sockets: the remote source queues records in `remote_buffer`.
  - A normal source **pauses** when the buffer is full (no loss, lower rate).
  - A `realtime` source **drops** the oldest (it counts as `lost`, for the no-loss contracts).
  - So a starved channel shows as a falling rate, never as silent corruption.
- **Readouts:**
  - the fixture's load bar;
  - the Network overlay (a chip "RX 6 + TX 5 = 11/12"; amber ≥ 75 %, red when a channel waited
    this second);
  - the hover card;
  - the stage-panel row "Network".
- Network saturation is a bottleneck kind next to bandwidth, compute, power and heat
  (FACTORY_SYSTEMS §7.4). The View dock gains **Network (W)**.

### 6.3 Binding
- Each **RX channel** binds one COMPROMISED source.
- Each **TX channel** binds one buyer:
  - an active quest (its Job, as USB outputs do);
  - or, after that quest is filed, its **standing product** (§9).
- Binding is set in the Network Inspector (§8) and saved.

## 7. Access (brief §18–§19)

Source state: `locked → accessible → compromised`.
- A quest's `access` list makes sources **accessible** when the quest becomes active.
- **ACQUIRE ACCESS** plays a short fictional sequence in the Network panel (about 3 s: "handshake ·
  mapping schema · access granted"). The source is then **compromised for good**.
  - There is no minigame, no real technique and no real target names.
- After the Forum era, **two** sources become accessible at once, and the player picks which to
  take first. The other stays available (PROGRESSION §2, branch).

## 8. TEST before LIVE (brief §16)

Every **source socket** (a USB input or a NIC RX channel) has a mode: **TEST** or **LIVE**. A new
binding starts in TEST.

### 8.1 Test sets
- The **active quest** that consumes the socket supplies the test set (`LevelDef.tests`: `[{seq |
  value, note}]`). Otherwise the source's default `test_vectors` are used.
  - Example: ① valid record · ② wrong region · ③ invalid flag · ④ boundary ACTIVITY = 8.
- **SEND TEST FRAME** emits the next vector.
- **RUN TEST SET** emits every vector, one per second.
- Test packets carry lineage `{source, seq: vector index, test: true}` and meta `test`.
  - They draw as **hollow beads**, with bits readable at close zoom.
  - They never count toward contracts or sales.

### 8.2 Verdict (exact, no timeouts)
- A vector is **pending** while any packet with its test origin exists anywhere: wires, queues,
  jobs, output backlog.
- When none remains, it **resolves**. It passes iff its deliveries equal the quest's expectation:
  - exactly one delivery of the expected value at the expected output channel;
  - or zero deliveries when the contract expects DROP.
- A vector still pending after 150 ticks shows **STALLED at \<machine\>**.
- The result is shown as "3 / 4 PASS", one line per vector. A failure says what happened, never
  how to fix it.
  - Example: "③ invalid flag — arrived at TX A, expected: not delivered".
- Probes tag the vector number they last saw, so a failing vector can be traced through the
  circuit.

### 8.3 Going live
- **OPEN LIVE FEED** is always allowed.
  - If the last full run was not all-pass, the button reads "⚠ 3/4 PASS · open anyway".
- A quest may `require_test`: it files only after one all-pass run on its current circuit.
- **Network Inspector** (a fixture click, 340 px):
  - SOURCE (per RX channel);
  - STATUS (COMPROMISED · CONNECTED);
  - SCHEMA (field ranges);
  - MODE (TEST | LIVE);
  - RATE (records/s);
  - NETWORK LOAD (RX / TX / total bar);
  - actions SEND TEST FRAME · RUN TEST SET · OPEN LIVE FEED;
  - the last test result.
- Only compromised sources can be selected.

## 9. Contracts, products and sale (brief §21–§35)

### 9.1 Lineage carries provenance (brief §47)
- Remote and dump records stamp `origins["src:<id>"] = {seq, value}`.
- Combining parts already union origins (`Packet.merge_origins`). An enriched record therefore
  proves it came from ForumCache **and** ShopMirror.
- A value with no source origin (built from Constants) cannot be judged and is rejected. Nothing
  can be fabricated.

### 9.2 New contract kinds and constraints (the existing ones stay)

| Kind | Rule |
|---|---|
| `route` | `outputs: {A: ops, B: ops, …}`: every record must reach the channel whose ops accept it (and only that one); DROP everywhere is allowed per `drop_ok` |
| `correlate` | origins must include one record of every source in `sources`, all with the same session `s` (the combining parts guarantee it); `match` ops (e.g. equal USER_TAG ≠ 0 and equal REGION) decide; a non-match must not arrive (DROP); `compose` builds the expected product from the named bit ranges |
| `test` | files after an all-pass test run (§8), plus `count` live deliveries if set |

| Constraint | Rule |
|---|---|
| `max_components` | components **upstream** of the quest's output channel(s), counted by graph reachability. IO, Probe, NIC, power and thermal parts are excluded. An upgraded machine counts once: lanes are compact but concentrate power and heat |
| `max_latency` (exists) | ticks from socket emission to delivery |
| `value` | sale value per accepted record (the product's worth) |

New ops (on origin values):
- `field(src, name)` — slice by that source's schema.
- `all(conds)` / `any(conds)` — combine conditions.
- `weight(cond, w)` / `sum` — score terms.
- `compose([[src, field] | [const, bits]])` — build a product.
- `fingerprint` — §10 Q29 formula.

The existing `slice`, `keep_if`, `if_bit`, `add`, `mod`, `zext`, … stay.

### 9.3 Standing products and continuous sale (economy deferred)
- When a quest files, its TX channel keeps selling that product, judged by the same contract.
- Each accepted record adds its `value`. The Lab shows **VALUE x/s** and a running total.
  - Correlated products are worth more *(cal.)*: Forum valid 1, Shop normalized 1,
    Forum + Archive fresh 2, Forum + Shop match 3, three-source profile 6, HIGH-score profile 10.
  - **New sources increase the value of old sources.**
- There is nothing to spend yet. Value/s is the running score the player optimises between
  quests, and the future economy's input.

### 9.4 Side contracts (the "no waiting" layer, brief §32–§33, §59)
- `LevelDef.side = true` quests appear on a separate **CONTRACTS** list once their `requires` are
  filed. At most 2 are active; they never block the main tree.
- Kinds of goal: throughput, efficiency (`max_power`), thermal (`max_heat`), compact
  (`max_components`), latency, quality (`max_rejected 0` on a correlated product), no-loss
  (realtime burst), multi-product, correlation.
- Rewards: a value bonus on the standing product, and a few tier unlocks (PROGRESSION §4).

## 10. Worked player-built systems (the design proofs for the MVP)

The names are the player's. None of them is a part.

| System | Built from (typical) | Count |
|---|---|---|
| **Validation tree** (Forum) | Field Splitter; Compare TAG ≠ 0, REGION < 6, ACTIVITY ≥ 8; AND-mask FLAGS & 001 → Compare = 0; 3 AND; Fork (record → checker + gate); Demux valid/invalid | 11 |
| **Shop frontend** | Field Splitter (REGION·TAG·SPEND·CAT); Shift R SPEND 1; Field Joiner → normalized TAG·REGION·VALUE·FLAGS(tied 000) | 3–4 |
| **Identity matcher** | 2 Field Splitters; Compare(B) TAG; Compare(B) REGION; AND; Fork ×2; Bit Switch or Gate; Field Joiner (TAG·ACT·SPEND·CAT) | 9–10 |
| **Value scorer** | Field Splitter; 4 Compares; 4 Selectors (tie 0 / w); 3 Adders; Cond Router ×2 → LOW · MED · HIGH | 14 |
| **Integrity check** | Field Splitter; Zero Extend ×2; XOR ×2; Add 5; Truncate 4; Compare(B) CHECK; Fork; Demux VALID / CORRUPT | 10 |
| **Dedup** (side, C-late) | Fork; RAM (6-bit address) lookup of TAG; Compare; Demux; write-back | 6–8 |

Each proof is in `tests/solutions.gd` with its component count, rate, power and heat. There must
be at least two valid layouts with different trade-offs for Q18, Q22 and Q30.

## 11. Parallelism and sharing (brief §8–§9, §35)

**Manual parallelism:** Distributor → N identical pipelines → Join.
- Throughput × N.
- Components, bandwidth, power, heat and area × N.
- Results may come back out of order. The next combining part still pairs them by record.
- Machine lanes are the compact alternative:
  - the same count and footprint;
  - power × lanes;
  - heat concentrated in one part, so it needs a stronger contact and cooling.

**Sharing:** one Compare → Fork → three consumers.
- It saves 2 components, their power and their heat.
- It costs backpressure. Every consumer is a required branch of the Fork, so when one branch's
  queue is full the next copy cannot leave, and **upstream stalls on that branch's capacity**.
- Fan-out throughput is therefore limited by the slowest required branch.

**Share the cheap part, duplicate only the bottleneck** (the main midgame pattern):
- Shared field extraction → shared cheap test → Distributor → 3 × the expensive stage → Join →
  control back to the record.
- It beats "3 × the whole validator" on parts, power and heat.
- The bottleneck then moves to the shared stage, which gets lanes or is split next.

**Uneven branch depth** (a fast Compare next to a slow multi-step branch feeding one AND):
- Fast results wait at the AND and fill its queue. The slow branch sets the latency, and its rate
  sets the throughput.
- The answers:
  - **A** Buffer the fast branch: cheap, adds area, rate unchanged.
  - **B** Parallelise the slow stage: more rate, more power, heat and parts.
  - **C** Change the topology, doing less work in the slow branch or reordering the tests.

**Measured example** (Penpot page 21, frame 08): the validator with the ×3 check, at 5 records/s.

| | A · 3 × whole pipeline | B · shared cheap stages + 3 × Multiply |
|---|---|---|
| throughput | 5 /s | 5 /s |
| parts | 26 | 12 |
| power (distribution load) | 36 → 3 rail branches | 21 → 2 rail branches |
| heat (cooling load) | ≈ 24 | ≈ 21.5 |
| area | ≈ 68 tiles | ≈ 34 tiles |

- Heat drops only by the idle leakage of the extra copies, because both do the same work per
  record.
- Where work was **duplicated** (the shared Compare of frame 06), sharing removes whole jobs and
  heat drops with them.

There is **no universally best layout**. Contracts choose which axis matters.

### 11.1 Bottlenecks name their cause (overlay, hover, Inspector; the normal view stays calm)

| Cause | Label on the limiting stage (example) |
|---|---|
| compute capacity | `COMPARE · capacity 3.3/s ← CURRENT BOTTLENECK` |
| branch latency / depth | `AND · waiting on input B · +0.9 s branch depth` |
| queue / backpressure | `BRANCH C · queue full ← BACKPRESSURE` · `upstream stalled by branch capacity` |
| bus capacity | `WIRE · 1 lane · saturated` |
| combine / join waiting | `JOIN · waiting on A` |
| downstream output capacity | `TX A · full` / `OUTPUT · blocked` |
| network / power / heat | `NIC 24/24` · `RAIL 16/16` · `THROTTLING` (FACTORY_SYSTEMS §7.4) |

Only the one limiting stage is marked. Everything upstream of it is simply "waiting".

## 12. Persistence (save v3; FACTORY_SYSTEMS §10 is extended)

| Where | New fields |
|---|---|
| lab | `quests_done: [ids]` (quests are ids from now on, not indices), `side_done`, `sources {id: state}`, `nic {tier, rx: [source ids], tx: [bindings], modes}`, `sales {product: total}`, `value_total` |
| machine params | tie params, `take` (Selector), `fields`, `value`, `period`, `init`/`d` |

Not saved: test verdicts, which are recomputed by running again. Source streams resume at their
saved `seq`.

**Migration** (v2 index-based saves):
- The old level index maps to new quest ids through PROGRESSION §6.
- The layout is kept.
- Unlocks = the old unlocks ∪ the new completed quests.
- PSU tier = max(saved, rewards).
- Old `mux` instances get `take = chosen`. Old Splitters in Duplicate mode keep working.

## 13. Views and UX (calm board, brief §44)

- New parts use the art pipeline: Penpot component → `assets/art/machine/*` + `machine_layouts.json`.
  - Their faces are change-driven like the other parts.
  - Probe cells and Latch state redraw only on a new value.
- The NIC fixture draws its load bar at 10 Hz and its TEST/LIVE lamp.
  - Antenna leads are static art.
- Test packets draw as hollow beads. Routine packets are unchanged.
- Hover card rows gain FIELD (for a Field Splitter port: "REGION · bits 9–7"), NETWORK (for the
  NIC) and TIE (for tied inputs).
- A **schema card** is attached to sticks and RX channels: the source glyph plus field ranges as a
  bit ruler.

## 14. Penpot (revised in place — no new pages)

| Design | Page · board |
|---|---|
| Compute taxonomy (atoms / flow-bus / standard cells) · primitive → standard cell (Half Adder → Full Adder → Adder) · audit badges | `14 Roadmap Kit` · **Compute Kit** (sections 01–03) |
| Record → bit ranges → parallel checks → control bit → route the original record (payload vs control) | `21 Factory · Data & Compute` · 03 |
| Uneven branch depth: waiting, queue, backpressure + fixes A buffer / B parallelise / C topology, with costs | 21 · 04 |
| One pipeline vs three (manual parallelism) + share-cheap / duplicate-bottleneck variant | 21 · 05 |
| Shared condition vs duplicated (backpressure: fan-out limited by slowest required branch) | 21 · 06 |
| Forum + Shop: source-specific frontend, the same validator blueprint, Compare(B) match tree, enrichment as bit composition + bit-origin map | 21 · 07 |
| Duplicate everything vs only the bottleneck — with the power rails and cooling each needs (throughput · parts · power · heat · area) | 21 · 08 |
| Network Module on the laptop top edge; tiers, TEST/LIVE lamp, load | `15 Systems · Infrastructure` · 02c Laptop Port Racks (extended) |
| Network Inspector in TEST, probe-driven debugging, TEST → LIVE | `23 Factory · Information UX` · 06 |
| Full MVP lab: NIC → validation tree → ×3 slow stage → TX, on the locked power chain and the shared cooling path, all traceable without overlays | `25 Factory · Hardware Scenes` · **Scene G** (rebuilt in place) |
| *Pending after review:* one source live / three sources (enrichment + scoring) | `24 Factory · Data Scenes` (to be revised in place) |

## 15. Guardrail: before adding a part

Stop if the proposal is a "Database Analyzer / Firewall / Matcher / Scorer". Ask which small
**general** bit part is missing. Add it only if it is reusable across at least three systems in
§10. If existing parts can already express the system, add nothing.

## 16. Deferred

Not part of the MVP:
- a hacking minigame, real exploits, targets or passwords;
- real SQL or real cryptography;
- server racks, cloud, GPU clusters, AI/ML;
- a market economy or cryptocurrency;
- a custom module editor;
- large graph databases.

## 17. Implementation phases (DS: bounded Flash jobs; Claude designs, reviews and commits)

| # | Phase | Scope |
|---|---|---|
| C3a | Primitive logic | `bit_switch`, `fork`, `distributor`, `join`, `latch`, `constant`, `clock`, `probe`: defs, logic, truth-table tests |
| C3b | Tie-offs + Selector | PortDef `tie`; Compare.B; AND/OR/XOR `k`; `mux` → Selector (`take`, `a`/`b`); Inverter name; Splitter/Merger/Bit Splitter/Bus Combiner hidden from the menu (legacy); Delay default |
| C3c | Fields | `field_splitter`, `field_joiner` (+ port widths from `fields`), tests |
| C4 | Primitive views | Penpot art export, layouts, faces (Probe cells, Latch state, Fork topology, Switch lever), tie caps |
| C5 | Records | `RemoteSourceDef`, population, `source_stream.gd`, the Database Dump stick, the schema card |
| C6 | Network sim | the NIC fixture, RX/TX sockets, frame budget, tiers, pause/drop, metrics |
| C7 | TEST/LIVE | socket modes, the test tracker (pending/resolve/stall), `require_test` |
| C8 | Network UI | the Network Inspector, access sequence, overlay (W), hover rows |
| C9 | Contracts | `route`, `correlate`, `test`, `max_components`, new ops, `value`, standing products + sale |
| C10 | Quest tree | `requires`, `side`, `access`, `tests`, `outputs` in LevelDef; LabRun tree window; save v3 + migration |
| C11a–c | Content | PROGRESSION Acts I–II, III–IV, V + side contracts as `.tres`, with reference solutions and naive-fail proofs |
| C12 | Regression | screenshots of every act's reference board, perf probe, smoke parse checks |

Each phase is inlined in its job text (no reading of docs or packet.json by the worker), applies the
typing rule (no `:=` from a Variant), and keeps `make check` green. The views get Claude's
screenshot review.
