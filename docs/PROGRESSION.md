# Tiny Compute Lab — Progression (factory-growth eras)

> Status: **design, 2026-09-26**, locked with `docs/FACTORY_SYSTEMS.md`.
> - Replaces the level table of `docs/SYSTEMS_EXPANSION.md §10`. Contract kinds, ops and
>   constraints are unchanged, apart from the additions in FACTORY_SYSTEMS §4.
> - Levels are LevelDef assets in `content/lab/levels/`, and the order is in `content/lab/lab.tres`
>   (docs/CONTENT.md).
> - Rates are Lab values per second (10 ticks = 1 s).
> - Numbers marked *(cal.)* are tuned by the reference-solution tests.

## 1. The rule

**Learn → use → hit a capacity limit → optimise → combine with the previous mechanic → only then
unlock something new.**

- Most levels change the **workload** (rate, width, format, synchronisation), not the operation.
- The same **main line** runs through them: `stick → x + 2 → drive`. It grows lanes, then codecs,
  a modulo, a filter, branches, power, cooling, a second stick, BYTE and a backbone.
- New architecture arrives only when it is really needed (memory, ALU, CPU). The old line then
  keeps working as a subsystem.

## 2. Levels

Per-lane rates at the normal clock:
- Add and Modulo: 2.5/s.
- Codecs, Splitter and Merger: 5/s.
- Compare and Gate: 3.3/s.
- Multiply: 1.7/s.

**Reuse** says what already built on the board the level expects to be kept.

### Era 1 — Tiny Logic (3-bit, Bit stick)

| # | Title | Contract | New demand | Unlocks / rewards | Reuse |
|---|---|---|---|---|---|
| 1 | First Contact | deliver 10 × `010` (stick 2.5/s) | wires | — | — |
| 2 | Plus Two | deliver 20 × `100` from `010` | a transform | Add | L1 wire |
| 3 | Moving Target | map x + 2 over all eight 3-bit values (6, 7 wrap), count 24 | overflow is a transform | — | **unchanged L2 line** |

### Era 2 — Throughput (the same x + 2 line under load)

| # | Title | Contract | New demand | Unlocks | Reuse |
|---|---|---|---|---|---|
| 4 | Rush Hour | map x + 2, stick 5/s, `min_rate` 4/s | parallel compute | **lanes ×2**, Splitter, Merger | the line; upgrade the Add (or split it) |
| 5 | Burst | map x + 2, bursts of 11 then a pause, `max_lost` 0 | buffering | Buffer, Delay | the line + a Buffer in front |
| 6 | Line Rate | map x + 2, stick 12/s (`burst` 2 on some ticks) *(cal.)*, `min_rate` 9/s, `sustain` 10 s | bandwidth | **lanes ×4**, **bus lanes ×2** | the line; the wires become Trace ×2 |

### Era 3 — Representation (codecs join the line)

| # | Title | Contract | New demand | Unlocks | Reuse |
|---|---|---|---|---|---|
| 7 | Numbers | Number stick 5/s, accept number n + 2 (n ≤ 20: needs 5-bit) | encode/decode, width choice | Number stick, Number Encoder/Decoder | the Add, widened 3 → 5 |
| 8 | Letters | Text stick 5/s, Caesar + 2 with no wrap | characters | Text stick, Char Encoder/Decoder, Char Viewer | swap the codecs; Add k stays 2 |
| 9 | Past Z | Caesar + 2 with wrap | modulo | Modulo | + Modulo after the Add |

### Era 4 — Routing (the line branches but shares its infrastructure)

| # | Title | Contract | New demand | Unlocks | Reuse |
|---|---|---|---|---|---|
| 10 | Only Big | filter: letters > `K` → (x + 2) mod 26, others dropped, `max_rejected` 0 | predicate + gate | Compare, Gate | + Compare/Gate before the Add |
| 11 | Two Ways | map: A–M → x + 2, N–Z → x + 24 (i.e. −2) mod 26, merged | routing | Demux, Mux, Cond Router, Bit Splitter; reward **Improved Adapter (16)** | the Caesar line becomes one branch |

### Era 5 — Power (compute growth outruns the adapter)

| # | Title | Contract | New demand | Unlocks | Reuse |
|---|---|---|---|---|---|
| 12 | Power Cap | L11's map at 8/s (stick 10/s) *(cal.)* | distribution: demand ≈ 14 > Onboard 8 *(cal.)* | **Lab Power Input**, Power Rail, Distribution Board | the whole L11 factory; add a power district |
| 13 | Overclock | the same at 12/s | clock vs lanes vs power | clock modes | the same factory, retuned |

### Era 6 — Thermal (heat is simulated from L14)

| # | Title | Contract | New demand | Unlocks / rewards | Reuse |
|---|---|---|---|---|---|
| 14 | Heat | the same at 12/s, `max_heat` THROTTLING | cooling near the hot spots | Heatsink, Blower, Heat Pipe, Thermal Manifold; reward **Desktop PSU (32)** | the same factory |
| 15 | Cooling District | 16/s, `max_heat` HOT | move heat out to a cooling zone | Radiator | pipes + manifold to a radiator district |

### Era 7 — Multi-input (a second socket; quest window 2 from here)

| # | Title | Contract | New demand | Unlocks | Reuse |
|---|---|---|---|---|---|
| 16 | Two Sticks | paired text + key (5): Caesar by key | a second stream | **input port 2**, Key stick, Adder | the Adder replaces the Add; the rest stays |
| 17 | Changing Key | the key changes every 8 letters, text in bursts, `max_lost` 0 | synchronisation | Counter | + Buffers to keep pairs in step |

### Era 8 — BYTE (8-bit, whole-factory upgrade)

| # | Title | Contract | New demand | Unlocks / rewards | Reuse |
|---|---|---|---|---|---|
| 18 | BYTE | paired ASCII AND key mask `0xDF` (lower → upper), 8/s | 8-bit everywhere: Byte Bus, 2× power | **8-bit**, AND/OR/XOR/NOT, Bus Combiner, **bus lanes ×4**; reward **High-Capacity PSU (64)** | the paired line, widened |
| 19 | Legacy Line | text Caesar (the 5-bit line) delivered as an ASCII byte (+65) | width conversion | Zero/Sign Extend, Truncate | the **5-bit line stays**, bridged into 8-bit |
| 20 | XOR Cipher | paired ASCII ⊕ a changing key | bitwise logic | Shift L/R, **output port 2** | the byte line |
| 21 | Cheap Multiply | map × 4 at 8/s (8-bit) *(cal.)* | shifts beat Multiply on power | Multiply | the byte line |

### Era 9 — Infrastructure Scale

| # | Title | Contract | New demand | Unlocks / rewards | Reuse |
|---|---|---|---|---|---|
| 22 | Datacenter | map × 3 at 24/s (`burst` 3), `max_heat` HOT *(cal.)* | heavy everything | **lanes ×8**, **bus lanes ×8**, Wide Bus, Heavy Power Rail, Heavy Distribution Board, Efficient chassis | the byte line scaled out |
| 23 | Backbone | two bytes → one 16-bit word (Bus Combiner) + key, 16/s, `sustain` 20 s | 16-bit buses | 16-bit, Backbone class | the paired byte lines feed a wide backbone |

### Era 10 — Liquid Cooling

| # | Title | Contract | New demand | Unlocks / rewards | Reuse |
|---|---|---|---|---|---|
| 24 | Liquid Loop | L22's workload at 32/s, `max_heat` HOT *(cal.)* | air cooling cannot keep up | Pump, Coolant Pipe, Cold Plate, Large Radiator, Reservoir, Power Backbone; reward **Server PSU (128)** | the datacenter, re-cooled |

### Eras 11–13 — Memory, ALU, CPU (as today, renumbered)

| # | Title | Contract (unchanged from the old level) | Unlocks |
|---|---|---|---|
| 25 | Running Sum | old L22 | Register |
| 26 | Lookup | old L23 | ROM |
| 27 | Tiny Memory | old L25 | RAM, Register Bank, Instruction Decoder |
| 28 | Calculator | old L24 | ALU |
| 29 | Playback | old L26 | Program Counter |
| 30 | Fetch & Execute | old L27 | — |
| 31 | Output Port | old L28 | — |

### Era 14 — Cluster (future)

After L31 the Lab is a **Free Build**: the last contract keeps judging. Cluster-scale workloads,
multiple computers and blueprints as modules are future work.

### Port schedule (`LabConfig`)

| Setting | Value |
|---|---|
| Input ports | row 1 from L1; row 4 from **L16**; row 7 from L23 |
| Output ports | row 1 from L1; row 4 from **L20** |
| Lab Power Input | from L12 at `power_input_row` |
| Quest window | 1 until L16, then 2 |
| Board growth | 28×16 (L1) → 32×18 (L7) → 36×20 (L10) → 40×22 (L12) → 44×24 (L15) → 48×26 (L22) → 52×28 (L24) *(cal.)* |

## 3. Save migration (old level index → new)

The old level in progress maps to the new level in progress. Everything before it counts as
completed.

| old | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| new | 1 | 2 | 3 | 3 | 7 | 8 | 9 | 11 | 11 | 11 | 11 | 16 | 17 | 17 |

| old | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| new | 19 | 19 | 19 | 19 | 20 | 21 | 22 | 25 | 26 | 28 | 28 | 29 | 30 | 31 |

- The layout is kept.
- PSU tier = max(the saved tier, the rewards of the levels now completed).

## 4. Proofs (in tests)

Each level needs:
1. A reference solution (`tests/solutions.gd`) that passes using only its unlocks, inside the board.
2. A **naive-layout fails** proof:
   - L4: 1-lane Add.
   - L6: 1-lane wires.
   - L12: everything on Onboard.
   - L13: normal clock.
   - L14: uncooled.
   - L15: heatsinks only.
   - L18: Trace wires.
   - L22: Heavy-less power.
   - L24: air cooling only.
3. A **reuse proof** for the levels marked "unchanged" or "the same factory": the previous level's
   reference solution, lightly modified by a scripted edit list, passes the new level.
