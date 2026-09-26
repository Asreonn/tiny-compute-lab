# Tiny Compute Lab — Progression (the data-factory MVP)

> Status: **LOCKED 2026-09-26** with `docs/DATA_FACTORY.md`. The content for Q22–Q30 (correlation
> and enrichment) is built only after the page 24 scenes are locked.
> - Replaces the 31-level factory-growth table (the previous P13 plan, never built). Its growth
>   principles stay: a persistent Lab, reuse, rising throughput, Data → Compute → Power → Thermal
>   pressure, width milestones, infrastructure growth.
> - Quests are LevelDef assets in `content/lab/levels/`. From now on they are addressed by **id**,
>   and their order and tree live in `content/lab/lab.tres` (docs/CONTENT.md).
> - Rates are Lab values per second (10 ticks = 1 s). Numbers marked *(cal.)* are tuned by the
>   reference-solution tests.

## 1. The rule

Each quest follows one path: **learn one part → use it → combine it with what is on the board →
hit a capacity → optimise → only then something new.**

- After Act I, a quest almost never asks for a new line. It asks for:
  - a branch off a bus that already exists;
  - a new source attached to a refinery that already exists;
  - more throughput from the same graph.
- The acceptance tests the arc must pass are in brief §56–§59:
  - the early player says "I have bits → I can switch → branch → compare → store → combine".
  - the midgame player says "I built a validator, attached a live source to it, duplicated a
    section, paid in power and heat, then refactored the shared logic".
  - the late player sees a dense graph that they understand, because they built every piece.

## 2. The tree

```
                         ACT I  BITS  (Q1–Q10, USB)
                                   │
                         ACT II  RECORDS  (Q11–Q15, Database USB)
                                   │
                         ACT III  NETWORK · FORUMCACHE  (Q16–Q21)
                                   │
                    ┌──────────────┴──────────────┐          quest window 2 from here
              Q22s SHOP FRONT               Q22a ARCHIVE FRONT      (either first; both later)
                    │                             │
              Q23 MATCH (Forum+Shop)       Q24 FRESHNESS (Forum+Archive)
                    └──────────────┬──────────────┘
                         Q25 ENRICHED PROFILE (3 sources)
                    ┌──────────────┴──────────────┐
              Q26 SCORE                     Q28 INTEGRITY
                    │                             │
              Q27 PREMIUM                         │
                    │                             │
              Q29 LEAN MACHINE                    │
                    └──────────────┬──────────────┘
                         Q30 PREMIUM FEED  (final MVP contract) → Free Build
                                   │
                         Architecture branch (the CPU track, optional, §5)

   Side CONTRACTS (§4) open from Q17 and run beside the tree; they never block it.
```

- **Branching** is expressed with `requires`: a quest becomes available once every quest it
  requires is filed.
- **Access choice:** ShopMirror and ArchiveNode become accessible together after Q21. The one
  taken first grants NIC Mk3, so the second one never waits for hardware.

## 3. Quests

Per-lane rates at the normal clock:
- Fork and Probe: 10/s.
- Distributor and Join: 10/s.
- Bit Switch, Latch, Selector, AND/OR/XOR, Field Splitter/Joiner and codecs: 5/s.
- Compare and Gate: 3.3/s.
- Add, Adder and Modulo: 2.5/s.

**Reuse** says what is already on the board that the quest expects to be kept.

### Act I — Bits (USB sticks, 1–5 bit; quest window 1)

| # | Title | Contract | Unlocks | Reuse |
|---|---|---|---|---|
| Q1 | First Contact | deliver 10 × `010` (Bit stick, 2.5/s) | wires, **Probe** | — |
| Q2 | Flip | map NOT x over the looping 3-bit stick, count 16 | **Inverter** | the Q1 wire, cut once |
| Q3 | Switch | paired DATA (3b) + ENABLE (1b, pattern `11010011`): EN ? D : `000`, count 16 | **Bit Switch**, Enable stick, input port 2 | the Q2 stick |
| Q4 | Branch | one stick, two jobs: out A = x, out B = NOT x, 12 each | **Fork**, output port 2 | the Q2 Inverter becomes branch B |
| Q5 | Test a Bit | map x → [x ≥ 4] (1 bit), count 16 | **Compare** | — |
| Q6 | Only Big | filter: keep x ≥ 4, `max_rejected` 0, count 16 | **Gate** | the Q5 Compare drives Gate EN through a Fork: the first real graph |
| Q7 | Hold | readings where `000` = "no reading": deliver each reading, a `000` replaced by the last non-zero one, count 20 | **Latch**, **Clock** | Fork + Compare ≠ 0 → Latch (forward fill) |
| Q8 | Half Adder | 1-bit sticks A, B: out A = SUM (A XOR B), out B = CARRY (A AND B), 12 each | **XOR**, **AND**, **OR**, tie-offs | 2 Forks from Q4's idea |
| Q9 | Adder | two 3-bit sticks → a + b (wraps), count 16 | **Adder** (the cell: "a Full Adder is two of your Half Adders + an OR; three of them are this"), **Add**, **Constant** | the Q8 sockets |
| Q10 | Letters | Text stick: Caesar + 2 with wrap (5-bit), count 20 | Char Encoder/Decoder, **Modulo**, Text stick, 5-bit | the Adder idea as Add + Modulo |

### Act II — Records (the Database Dump USB, 16-bit)

The **Forum Dump** stick streams ForumCache records 0–63, looping, at 2.5/s, with a schema card
(DATA_FACTORY §5).

| # | Title | Contract | Unlocks | Reuse |
|---|---|---|---|---|
| Q11 | Database Dump | map each record → its REGION (3-bit), count 20 | **Field Splitter**, Forum Dump stick, schema card, 16-bit; grow 32×18 | — |
| Q12 | Two Checks | map record → VALID bit = REGION < 6 AND INVALID = 0, count 20 | (the AND-mask tie-off) | the Q11 splitter feeds two Compares |
| Q13 | Clean Records | filter: deliver only VALID records (all 16 bits), `max_rejected` 0, count 20 | — | the **Q12 checker unchanged**; a Fork sends the record to checker + Gate |
| Q14 | Audit Trail | route: valid (TAG ≠ 0, REGION < 6, ACTIVITY ≥ 8, INVALID = 0) → out A; invalid → out B; 24 in total | **Demux** | the checker grows to the 4-rule **validation tree** (~11 parts) |
| Q15 | Test Bench | `test`: RUN TEST SET on the dump socket: ① valid ② REGION 6 ③ INVALID ④ ACTIVITY = 8 → 4/4 PASS | **TEST mode** | the Q14 validator untouched (debug it if it fails) |

### Act III — Network (ForumCache; the refinery goes live)

| # | Title | Contract | Unlocks / rewards | Reuse |
|---|---|---|---|---|
| Q16 | Network Card | NIC Mk1 appears on the top edge; ForumCache **accessible** → ACQUIRE ACCESS → bind RX A; `test` 4/4 PASS with ForumCache's set | **NIC Mk1**, ForumCache; grow 36×20 | **the Q14 validator**: rewire its input from the dump socket to RX A |
| Q17 | Go Live | OPEN LIVE FEED (3/s); route valid → TX A (buyer "Bulk list", value 1), invalid → USB out (audit); 40 at TX A, `max_rejected` 0 | standing product **Verified Users**; side contracts open | the same graph |
| Q18 | Rush Hour | "full mirror" 6/s; `min_rate` 5/s valid, `sustain` 20 s | **lanes ×2**, **Distributor**, **Join** | naive fail: the 1-lane validator (Compare 3.3/s). Two answers: 2 lanes everywhere (compact) or two validators between a Distributor and a Join (explicit) |
| Q19 | Power Cap | the same 5/s under the PSU: the refinery draws ≈ 20 *(cal.)* > Onboard 8 | Lab Power Input, Power Rail, Distribution Board, clock modes; reward **Improved Adapter 16** | the same factory + a power district |
| Q20 | Heat | 6/s, `max_heat` THROTTLING | contacts, spreader, heat pipe, manifold, radiator, blower; reward **Desktop PSU 32** | the same factory + a cooling path |
| Q21 | Uplink | 10/s, `min_rate` 8/s: RX 10 + TX 8 = 18 frames/s > Mk1 12, and the 1-lane record bus saturates | **NIC Mk2**, **bus lanes ×2** | the card and the wires upgraded; the graph kept |

### Act IV — Second source (branch; quest window 2)

| # | Title | Requires · access | Contract | Unlocks / rewards | Reuse |
|---|---|---|---|---|---|
| Q22s | Shop Front | Q21 · ShopMirror | normalize Shop records (REGION·TAG·SPEND·CAT → TAG·REGION·VALUE·FLAGS=`000`) and **merge them into the existing validator**; TX A now sells verified users from both sources; 30 Shop-origin, `max_rejected` 0 | **Field Joiner**, **lanes ×4**; reward **NIC Mk3** | the validator becomes **shared**: 10 + 4 /s into one stage, the shared-stage bottleneck |
| Q22a | Archive Front | Q21 · ArchiveNode | 32-bit records; the frontend keeps TAG·FRESHNESS·QUALITY and drops ARCHIVE_ID; filter fresh (FRESHNESS ≥ 12, STALE = 0) → TX B (13-bit product), count 30 | **32-bit**; reward **NIC Mk3** | 2 frames per record on the card |
| Q23 | Match | Q22s | `correlate` Forum + Shop: TAG ≠ 0, equal TAG, equal REGION → **MATCH** = TAG·ACTIVITY·SPEND·CAT (17 bits) → TX B, value 3, count 30, `max_rejected` 0 | **Compare B** (stream compare); reward **High-Capacity PSU 64** | both frontends; record identity pairs Forum s with Shop s, and the waiting costs are real |
| Q24 | Freshness | Q22a | `correlate` Forum + Archive: equal TAG, FRESHNESS ≥ 12 → **FRESH USER** = TAG·ACTIVITY·FRESHNESS·QUALITY (17 bits), value 2, count 30 | reward **High-Capacity PSU 64** | the Archive frontend |

### Act V — Enrichment and value

| # | Title | Requires | Contract | Unlocks / rewards | Reuse |
|---|---|---|---|---|---|
| Q25 | Enriched Profile | Q23, Q24 | `correlate` three sources → **PROFILE** (26 bits) = TAG·ACTIVITY·SPEND·CAT·FRESHNESS·QUALITY·CONF. CONF (2 bits) = [shop REGION = forum REGION] + [QUALITY ≥ 4] + [STALE = 0]; value 6, count 20 | **bus lanes ×4**, VRM·E; grow 48×26 | the matcher and both frontends: **new sources enrich old ones** |
| Q26 | Score | Q25 | map PROFILE → PROFILE·SCORE (30 bits): +1 ACTIVITY ≥ 8, +3 SPEND ≥ 16, +2 FRESHNESS ≥ 12, +4 CONF = 3; count 20 | **Selector** (take both, ties 0 / w) | the profile bus |
| Q27 | Premium | Q26 | `route` by SCORE: HIGH ≥ 7 → TX B (value 10), MEDIUM 4–6 → TX A (value 4), LOW dropped; 20 HIGH | **Cond Router** | the scorer |
| Q28 | Integrity | Q25 | route Archive records: CHECK = (TAG ⊕ zext FRESHNESS ⊕ zext QUALITY + 5) mod 16 → VALID continue into enrichment, CORRUPT → USB audit; 20 corrupt caught, `max_rejected` 0 | **Shift L/R**, Truncate, Zero Extend | the Archive frontend gains a gate in front of the enricher |
| Q29 | Lean Machine | Q27 | the premium line ≥ 4 HIGH/s with `max_power` 48 and `max_components` 60 *(cal.)* | **Efficiency**, **lanes ×8**, **bus lanes ×8**, VRM·HC | forces sharing (one REGION compare forked) or efficient parts |
| Q30 | Premium Feed | Q27, Q28, Q29 | FINAL: `sustain` 6 HIGH integrity-valid profiles/s for 60 s, `max_rejected` 2, `max_heat` HOT; all three sources LIVE | reward **Server PSU 128**, then Free Build | everything on the board |

Record identity and waiting, network capacity, Data, Power and Thermal all bind somewhere in Q30. It has two
reference layouts:
- a wide, explicit, parallel one;
- a compact one with lanes and sharing.

## 4. Side contracts (`side = true`, at most 2 active; brief §32–§35, §59)

| # | Title | Requires | Goal | Stresses | Reward |
|---|---|---|---|---|---|
| S1 | Compact Validator | Q17 | Forum valid ≥ 3/s, `max_components` 9 | area / count | value ×1.25 on Verified Users |
| S2 | Fast Lane | Q18 | 4/s with `max_latency` 20 ticks | latency | — |
| S3 | Low Power | Q19 | 5/s with `max_power` 14 | power | clock mode *efficient* early |
| S4 | Cool Running | Q20 | 6/s, `max_heat` WARM | thermal | — |
| S5 | Burst | Q21 | ForumCache **realtime** bursts (20 records in 2 s every 10 s), `max_lost` 0 | buffering | — |
| S6 | Bot Audit | Q17 | two products from one feed: verified → TX A, BOT-flagged → USB audit | multi-product | — |
| S7 | Region Desk | Q23 | MATCH with REGION = 2 only, `sustain` 4/s | reuse of the match bus | — |
| S8 | Category Counts | Q25 | running count per CATEGORY (Demux + 4 Counters) | group / aggregate | — |
| S9 | Dedup | Q25 | each USER_TAG at most once per 64 records (RAM, 6-bit address) | state / memory | — |
| S10 | Chain Seal | Q28 | a stream fingerprint with Register feedback | stateful graph | — |

S8–S10 need the C-late memory changes (DATA_FACTORY §17), so they arrive with the Architecture
branch.

## 5. The Architecture branch (the CPU track, optional; after Q30)

The old L22–L28 contracts are kept as assets and re-parented. They are no longer the main line:

| # | Title (old level) | Unlocks |
|---|---|---|
| A1 | Running Sum (old L22) | Register |
| A2 | Lookup (old L23) | ROM |
| A3 | Tiny Memory (old L25) | RAM, Register Bank, Instruction Decoder |
| A4 | Calculator (old L24) | ALU |
| A5 | Playback (old L26) | Program Counter |
| A6 | Fetch & Execute (old L27) | — |
| A7 | Output Port (old L28) | — |

## 6. Schedule (`LabConfig`)

| Setting | Value |
|---|---|
| Input ports | rows 1 and 4 from Q1 (Q3, Q8, Q9 use two) |
| Output ports | rows 1 and 4 from Q1 (Q4 uses two); USB audit outputs stay useful all game |
| NIC | Mk1 Q16 · Mk2 Q21 · Mk3 on filing Q22s or Q22a |
| Machine lanes | ×2 Q18 · ×4 Q22s · ×8 Q29 |
| Bus lanes | ×2 Q21 · ×4 Q25 · ×8 Q29 |
| Efficiency | Q29 |
| Power / heat | power from Q19; heat from Q20 |
| VRM tier | ctrl Q19 · basic Q20 · eff Q25 · hc Q29 |
| PSU | Starter 8 → Improved 16 (Q19) → Desktop 32 (Q20) → High-Capacity 64 (Q23/Q24) → Server 128 (Q30) |
| Quest window | 1 until Q21, 2 from Q22 |
| Widths | 1/3 bits (Act I) · 5 (Q10) · 16 (Q11) · 17 (Q23) · 32 (Q22a) · 26–30 (Q25–Q26) |
| Board growth | 28×16 → 32×18 (Q11) → 36×20 (Q16) → 40×22 (Q19) → 44×24 (Q22) → 48×26 (Q25) → 52×28 (Q29) *(cal.)* |

## 7. Save migration (old level in progress → new quest in progress)

The quests before the target count as filed. The layout is kept. Unlocks are the union of the old
and the new. PSU tier = max(saved, rewards).

| old | 1 | 2 | 3 | 4 | 5 | 6–7 | 8–21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 | done |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| new | Q1 | Q2 | Q3 | Q4 | Q5 | Q10 | Q11 | Q11 + A1 | Q11 + A2 | Q11 + A4 | Q11 + A3 | Q11 + A5 | Q11 + A6 | Q11 + A7 | Q11 + A done |

- An old player keeps their factory and their power/thermal hardware.
- They enter the new core at Act II, the Database Dump.
- Their CPU progress lands in the Architecture branch.

## 8. Proofs (in tests)

Every main quest needs three proofs:
1. **A reference solution** in `tests/solutions.gd`. It passes using only its unlocks, inside the
   board. It records its component count, rate, power and heat.
2. **A naive layout fails:**
   - Q13: a Gate with no checker.
   - Q18: the 1-lane validator.
   - Q19: everything on Onboard.
   - Q20: uncooled.
   - Q21: NIC Mk1 or 1-lane wires.
   - Q22s: an unshared 1-lane validator at 14/s.
   - Q23: a region-only matcher, which gets rejected.
   - Q23 drop-before-join: a Gate on one side creates ORPHANS (counted) and lowers the yield; it never passes wrong values.
   - Q29: the Q27 layout, over budget.
3. **A reuse proof** for every quest marked "the same" or "unchanged": the previous quest's
   solution, changed by a scripted edit list, passes. The key ones:
   - Q13 from Q12.
   - Q16 from Q14 (one rewire).
   - Q22s from Q21 (frontend + merge).
   - Q25 from Q23 + Q24.

**Design proofs of DATA_FACTORY §11:** Q18, Q22s and Q30 each have **two** valid reference
layouts with different trade-offs.
