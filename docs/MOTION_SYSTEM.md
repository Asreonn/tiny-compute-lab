# Tiny Compute Lab — Motion System (V2)

Motion explains computation. It never decorates. If nothing is happening in the simulation,
nothing moves on screen.

Penpot reference: page **`08 Motion`** — 7 storyboards, each a playable prototype flow
(open View mode → flow list → `Motion · processor`, `· buffer`, `· splitter`, `· merger`,
`· compare`, `· gate`, `· wire`). Frames auto-advance with a 140 ms dissolve so the sequence can be
judged in motion. Static render: `design/previews/ds_v2_motion.png`.

---

## 1. Rules

1. **Simulation-locked.** All data motion (packets, sweeps, lane lights) is driven by the tick:
   `1 tick = 100 ms` at 1×; 50 ms at 2×; 25 ms at 4×. Views interpolate between ticks with
   `alpha = accumulator / tick_duration`.
2. **One easing.** Cubic-out (`Tween.TRANS_CUBIC, EASE_OUT`). No bounce, no overshoot, no elastic.
3. **No decorative loops.** Idle machines are static. The only persistent loop allowed is the
   `RUNNING` badge pulse in the HUD.
4. **Activity starts inside.** Processing is shown by the machine's ActivityArea, never by
   scaling or shaking the whole machine.
5. **Wires react locally.** Only the segment around a moving packet brightens; the rest of the wire
   stays at its quiet core.
6. **Reduced motion.** When enabled, keep state changes (texture swaps, colours), drop pulses/sweeps.

## 2. Motion tokens (`design/tokens.json → motion`)

| Token | Duration | Use |
|---|---|---|
| `motion.micro` | 100 ms | button press, toggle, port snap |
| `motion.hover` | 140 ms | pad/StateLayer hover fade, tooltip fade |
| `motion.select` | 150 ms | selection brackets draw-in |
| `motion.port-pulse` | 160 ms | port Active flash on receive/send |
| `motion.packet-enter` | 120 ms | packet shrinks into a port (Entering) |
| `motion.panel` | 200 ms | inspector / mission panel slide |
| `motion.complete` | 450 ms | mission complete sweep |
| `motion.tick` | 100 ms ÷ speed | packet travel per slot; processing sweep = ticks × tick |

## 3. Sequences (Penpot state → Godot implementation)

### Processor (`Motion · processor`)
| # | Penpot frame | Godot |
|---|---|---|
| 1 | packet on input wire (Leaving), wire ActiveTransfer | PacketView lerps along wire arc-length; WireView pulse follows packet |
| 2 | input port **Active**, LED Receiving, StateLayer Receiving | on `deliver` event: port texture → active for 160 ms, contact overlay alpha 1→0 over 160 ms |
| 3 | ActivityArea **Die: Processing**, LED Processing | die cores light as `progress = (total − ticks_left + alpha) / total` (0–4 cores); area texture swap Idle→Processing |
| 4 | Die **Done**, output port Active, LED OutputReady | on job complete: area → Done, output contact overlay on |
| 5 | packet leaves on output wire | on `emit` event: packet spawns at output anchor, Leaving glow 120 ms |

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
| Idle → Receiving | 160 ms pulse | contact overlay flash, port Active |
| → Processing | ticks × tick | ActivityArea progress; StateLayer Processing underglow alpha 0.6 |
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
