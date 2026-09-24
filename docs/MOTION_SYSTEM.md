# Tiny Compute Lab — Motion System (V2)

Motion explains computation. It never decorates. If nothing is happening in the simulation,
nothing moves on screen.

Penpot reference: page **`08 Motion`** — 7 storyboards, each a playable prototype flow
(open View mode → flow list → `Motion · processor`, `· buffer`, `· splitter`, `· merger`,
`· compare`, `· gate`, `· wire`). Frames auto-advance with a 140 ms dissolve so the sequence can be
judged in motion. Static render: `design/previews/ds_v2_motion.png`.

---

## 1. Rules

1. **Simulation-locked.** All data motion (packets, sweeps, lane lights) is driven by the tick.
   - **Playback:** 1× = 10/3 ticks/s (300 ms per tick), then 2× / 5× / 10×, on keys `1`–`4`.
   - Views interpolate between ticks with `alpha = accumulator / tick_duration`.
   - Playback speed is never gameplay. Machine clock modes change *work per tick*, not the tick.
2. **One easing.** Cubic-out (`Tween.TRANS_CUBIC, EASE_OUT`). No bounce, no overshoot, no elastic.
3. **No decorative loops.** Idle machines are static. The only persistent loop allowed is the
   `RUNNING` badge pulse in the HUD.
4. **Activity starts inside.** Processing is shown by the machine's ActivityArea, never by
   scaling, shaking or glowing the whole machine.
7. **VFX ladder.** Every effect names its level (L0–L5, `docs/STYLE_GUIDE.md §14.1`).
   Routine transfer (L1) stays below α .6 and 120 ms. Only L5 may pulse strongly, at most twice.
5. **Wires react locally.** Only the segment around a moving packet brightens; the rest of the wire
   stays at its quiet core.
6. **Reduced motion.** When enabled, keep state changes (texture swaps, colours), drop pulses/sweeps.

## 2. Motion tokens (`design/tokens.json → motion`)

| Token | Duration | Use |
|---|---|---|
| `motion.micro` | 100 ms | button press, toggle, port snap |
| `motion.hover` | 140 ms | pad/StateLayer hover fade, tooltip fade |
| `motion.select` | 150 ms | selection brackets draw-in |
| `motion.port-pulse` | 120 ms | port contact ring on receive/send (40 ms Contact α .8 → 40 ms Active α .55 → 40 ms fade) |
| `motion.packet-enter` | 120 ms | packet shrinks into a port (Entering) |
| `motion.panel` | 200 ms | inspector / mission panel slide |
| `motion.complete` | 450 ms | mission complete sweep |
| `motion.tick` | 100 ms ÷ speed | packet travel per slot; processing sweep = ticks × tick |

## 3. Sequences (Penpot state → Godot implementation)

### Processor (`Motion · processor`)
| # | Penpot frame | Godot |
|---|---|---|
| 1 | packet on input wire (Leaving), wire ActiveTransfer | PacketView lerps along wire arc-length; WireView pulse follows packet |
| 2 | input port contact ring, LED Receiving | on `deliver` event: 1 px contact ring for ≤ 120 ms (no halo, no StateLayer) |
| 3 | ActivityArea **Die: Processing**, LED Processing | die cores light as `progress = (total − ticks_left + alpha) / total` (0–4 cores); area texture swap Idle→Processing |
| 4 | Die **Done**, output port Active, LED OutputReady | on job complete: area → Done, output contact overlay on |
| 5 | packet leaves on output wire | on `emit` event: packet appears at the output anchor, OUT port contact ring ≤ 120 ms (no glow) |

### Buffer
| # | Frame | Godot |
|---|---|---|
| 1 | packet enters (Entering) | packet shrinks into the input port (120 ms) |
| 2 | bay fills (Bank 3) | `area_bank_{queued_count}` texture; new chip fades in 100 ms |
| 3 | near full (Bank 4) | full bank reads as pressure without inspector |
| 4 | blocked: Bank Blocked + external pause badge + output port Blocked | when output cannot emit: StateLayer Blocked alpha → 1 (150 ms), stays while blocked |
| 5 | released: slot clears | bay chip fades out 100 ms as packet leaves |

### Splitter
1 packet arrives → 2 chosen lane lights (`area_split_lanea|laneb|dup`) for the job duration →
3 packet leaves that branch. Godot: lane chosen from the job's result port.

### Merger
1 lane with a packet (wire pulse) → 2 junction resolves that lane (`area_merge_lanea|laneb`) →
3 output route activates as the packet leaves.

### Compare
1 number arrives → 2 operator window lights (`area_comparator_true|false`: magenta edge + tint = TRUE, dim edge = FALSE) as the job completes →
3 BOOLEAN packet exits (diamond token; filled = TRUE, hollow = FALSE).

### Gate
1 data waits at the blade (`area_valve_waiting`, LED amber) → 2 control arrives on the keyed port
(port Active, BOOLEAN wire pulse) → 3 blade lifts (`area_valve_open`, 150 ms cubic-out) →
4 data leaves. If control is FALSE: blade stays down, the data chip fades out in place (discard, 160 ms).

### Wire / packet
1 packet enters the trace → 2 moves 1 slot per tick → 3 passes the 45° chamfer at constant speed
(no stop at corners; position is sampled by arc length on the chamfered polyline) → 4 reaches the
port and shrinks in (Entering, 120 ms).

## 4. State transitions (machines)

| From → To | Duration | Implementation |
|---|---|---|
| any → Hover | 140 ms | InstallPad Hover + StateLayer Hover alpha 0→1 |
| Hover → idle | 140 ms | alpha 1→0 |
| any → Selected | 150 ms | external brackets + solid frame + base highlight alpha 0→1 (persistent, layered over runtime states) |
| Idle → Receiving | ≤ 120 ms | 1 px port contact ring, LED Receiving |
| → Processing | ticks × tick | ActivityArea progress (ring / lanes / valve / bays), LED Processing; **no underglow** |
| → OutputReady | 150 ms | output contacts on, LED green |
| → Blocked | 150 ms | amber tag + outline; stays until emit succeeds |
| → Error | 150 ms, then static | red outline + badge (only on mission failure path) |

## 5. Packets and zoom

LOD switches on camera zoom thresholds (`tokens.json → zoom`): FAR < 0.6× shows Far markers,
NORMAL shows capsules, CLOSE > 1.35× shows value text. Cross-fade LOD swaps over 100 ms to avoid popping.

## 6. Mission complete / fail

- **Complete** (450 ms): board sweep of `state.success` at 12 % opacity left→right, then the
  ResultPanel slides in (200 ms). Output bin shows ✓.
- **Fail**: simulation pauses, the failing packet's path machines get StateLayer **Error**, the
  packet pulses twice (2 × 160 ms), ResultPanel (Fail) explains expected / received / packet / path.

## 7. Godot implementation notes

- `SimulationController` owns the tick accumulator and emits `ticked(events)`; views read the
  simulation, never drive it.
- Use `create_tween()` for UI/state fades (cubic-out). Use per-frame interpolation (`_process`)
  for packets and progress, because they must stay locked to the tick alpha.
- `PacketView` pools by packet id; entering/leaving/queued are texture swaps from
  `packet_*_{state}.svg`, not new nodes.
- `WireView` draws the channel procedurally (trench `material.vent` 8 px, edge `board.pad-edge` 10 px,
  core 2 px) and a pulse segment (±24 px along the arc) centred on each packet on that wire.

## 8. Systems Expansion motion (locked 2026-09-24; Penpot pages `15`–`19`)

All motion uses cubic-out unless stated. The effect level is given in brackets.

| Event | Motion | Level |
|---|---|---|
| USB module plugged in | The module slides from 44 px out to flush over 180 ms, and the plug disappears into the port face. The port-face opening fills and a 1.5 px contact seam flashes (120 ms). The LED goes Idle. | L1 |
| USB module removed | It slides 48 px out while fading to α .5 over 160 ms, then is removed. The opening goes dark. | L1 |
| Hover over a socket | A ghost module outline and the port hover outline fade in over 140 ms. | L3 |
| Source reads a value | The data-store cursor steps one block per value; the Feed area shows `Feeding`. | L1 |
| Contract accepts | The seam flashes green (150 ms) and one more store block fills. | L1 |
| Contract rejects | The seam and underline flash amber for 150 ms, once. | L4 |
| Contract complete | The store turns green, then a 1.5 px green frame pulses twice (2 × 200 ms) and stays. | L5 |
| Encoder working | The token dims to α .5 in the slot (absorbing) while the Bits strip is Active; the bits leave on the bus. | L2 |
| Blower running | The impeller rotates at 1 turn/s (Running) or 2 turns/s (HighLoad). Hairline airflow is static. At Idle it stops, with a 400 ms ease-out. | L2 |
| Thermal strip | Stage changes cross-fade over 200 ms. THROTTLING pulses the strip between α .35 and 1 over 1.2 s. CRITICAL is steady red, with the frame and badge pulsing twice. | L4 / L5 |
| Heat-pipe flow | The warmth gradient follows the heat of the hot end (smoothed over 500 ms). No moving particles. | L2 |
| PSU near capacity / overload | The gauge cell colour cross-fades over 200 ms. Overload pulses the overflow chevrons twice, then holds. | L4 / L5 |
| Hover card | Appears after 180 ms (α 0→1, +4 px rise, 120 ms) and follows the pointer every frame. It hides instantly on drag, wire or place. | L3 |
| Quick action bar | Fades in over 150 ms with the selection brackets. The Delete hover turns red instantly. | L3 |
| Connected move | Wire holograms re-plan every frame while dragging. On release they commit (100 ms solidify); if a route fails, the machine snaps back over 180 ms. | L3 |
| Overlays | `T`/`P` toggle with a 150 ms cross-fade; machines fade to α .55 underneath. | — |
| Status LED | Instant texture swap (no fade). | per state |


## 9. HUD motion and board ambience (player request 2026-09-24: smooth, minimal, futuristic)

UI motion is cubic-out, short, and never bouncy. Nothing in the HUD glows. Everything is disabled under reduced motion.

| Element | Motion |
|---|---|
| **Speed selector** (1× 2× 5× 10×) | A selection pill (`surface.raised`, 1 px `surface.border-strong`, radius `control`) slides its x/width to the chosen segment in 180 ms. Labels cross-fade over 120 ms (selected `text.primary`, others `text.muted`). Keys `1`–`4` drive the same animation. |
| Mode pill (BUILD / RUNNING / PAUSED) | Colour cross-fade 200 ms. The RUNNING dot breathes (α .6 ↔ 1, 1.6 s). This is the only permanent HUD loop. |
| Buttons (all `IconButton`s) | Hover: the background fades to `surface.raised` + 1 px `border-strong` over 120 ms, and the icon goes `text.secondary` → `text.primary`. Press: scale .96 for 80 ms. Selected: an accent underline (2 px, `state.build`) slides between siblings in 160 ms. |
| Tool rail | The selection highlight slides between tools (160 ms) instead of jumping. |
| Palette cards | Hover: 2 px lift + border to `border-strong` (120 ms). An unlock pulses the "New" dot twice (2 × 300 ms), then it holds. |
| Panels (inspector, request, device tray, hover card) | Open: 12 px slide + fade over 180 ms. Close: 140 ms. |
| Numbers (counters, rate, power) | Values roll to the new number over 200 ms. Progress bars tween width over 250 ms. |
| Level banner | Enters from the top (24 px + fade, 260 ms), holds, exits in 200 ms. |
| Menu cards | Staggered entrance, 40 ms apart (fade + 12 px). |

**Board ambience** ("a livelier background"; below L1, α ≤ .1, never over machines or wires):
- **Trace sweep.** Every 8–12 s a soft band travels along one decal `TraceBundle` line at 120 px/s:
  `data.number` α .06, 24 px long, round ends. At most one sweep at a time.
- **Via twinkle.** Decal vias occasionally brighten α .04 → .1 → .04 over 1.2 s, every 3–6 s.
- **Vignette.** A radial vignette of `bg.void` α .35 at the viewport edges gives depth. It is static.
- **Timing.** It is driven by a seed (board size + level), not the simulation, and never changes
  gameplay. It runs slightly more often while the simulation is running.

## 10. Intro: the laptop (Penpot page `20 Intro · Laptop`)

About 5 s, played on game launch only (not on every board load). Any click or key skips to the end state.

| t | Beat |
|---|---|
| 0.0 s | A top-down laptop sits on `bg.void`: lid at the top with a screen wordmark (`TINY COMPUTE LAB` + a boot bar that fills over 1.6 s), and a deck whose **realistic US ANSI laptop keyboard** (function row, number row, QWERTY rows with real key widths, 5.5 u space bar, inverted-T arrows) plus palm rest and trackpad cover exactly the current grid. The deck's side USB ports sit on the rows of the locked USB Input (west) and Contract Drive (east). |
| 0.3–3.8 s | The camera slowly eases (cubic in-out) from the whole laptop to the gameplay framing. |
| 0.6–2.0 s | The lid slides out of the top and fades. |
| 1.8–3.4 s | The keyboard and palm rest dissolve in a left → right sweep (each key and each tile strip over 300 ms), revealing the PCB board underneath. The factory is live underneath. |
| 3.1–4.0 s | The deck housing thins to the board edge and fades out. |
| 4.2–5.0 s | The HUD enters: every panel slides 24 px in from its docking side (fade + slide, 220 ms, 60 ms stagger). |

**Board edges** (laptop illusion): the locked USB Inputs sit in column 0 and the Contract Drive in
the last two columns. Their modules protrude past the board edge, through the laptop's side ports.
