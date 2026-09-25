# Tiny Compute Lab — Systems Expansion (design)

> Status: **LOCKED 2026-09-24 (Checkpoint C)**. These are the game rules and numbers that the DS jobs
> implement (plan: `docs/IMPLEMENTATION.md`, "Systems Expansion").
> - Visual language: `docs/STYLE_GUIDE.md §14`, `docs/VISUAL_SYSTEM.md §21`, `docs/MOTION_SYSTEM.md §8`.
> - Penpot pages 15–19; geometry in `design/reference/systems_v1.js`.
> - Numbers marked as calibration targets are tuned by tests, not by eye.
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
| A11 | *(resolved)* The Penpot MCP was reconnected and the design phase completed. | 37 |

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
- **The Bit module** is the exception that keeps the opening simple: a device that emits *already
  encoded* 3-bit words (the "someone handed you raw bits" fantasy). Every later device emits raw values.

## 2. USB sockets and data modules (fixed infrastructure)

**Socket** (`usb_socket`, locked, never in the palette):
- M chassis, on the west board edge.
- One output port, which is `raw`, or `bits(w)` when a Bit module is plugged in.
- A **device slot**.

**Device inventory:**
- Devices are owned **data modules**: male USB-A plug, 96×56, each family with its own silhouette.
  They are items, not machines.
- The socket is the locked USB Input with a female USB-A port face.
- The HUD **Device Tray** (opened by clicking a socket) lists the owned modules. Plug one in with a
  click; the module sits flush in the port.
- Insert and remove are edits: they are undoable and saved.
- Removing a device leaves the socket's wire in place, with no data flowing.

| Device | Emits | Stream (configured by the current contract) | Unlock |
|---|---|---|---|
| Bit module | bits(3) (bits(5) later) | fixed or seeded word list | start |
| Number module | NUMBER raw | seeded ints in a range | L5 |
| Text module | TEXT raw | a phrase, looped | L6 |
| Key module | KEY raw (int) | constant, or changing every k values | L12 |
| Sensor module | SENSOR raw (int) | seeded noisy readings | L9 |
| File module | *(future)* | byte stream | post-MVP |

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


### 2.1 Laptop port racks (player request 2026-09-24; supersedes "one socket at (0,5)")

- The Lab board is a laptop's keyboard area, and each side has a **port rack of 4 USB ports**:
  - **left (input ports):** `usb_input` sockets in column 0;
  - **right (output ports):** `usb_output` ports in the last two columns.
- **Port rows are 1, 4, 7 and 10:** the racks sit at the top of the keyboard area. Ports open top
  first and later ones open downward. Board growth may add rows 13, 16 … below.
- **Open vs sealed:**
  - Port 1 on each side is open at the start.
  - The other ports are **sealed bays**: a reserved 2×1 footprint (not buildable, dashed silk outline,
    "USB n · opens at Lx") with a capped port face.
  - Opening schedule: input port 2 at L12 (Two Sticks), input port 3 at L18 (BYTE), output port 2 at L9,
    output port 3 at L12. The rest stay sealed.
- **Any module into any open port:**
  - Input modules (Bit, Number, Text, Key, Sensor) plug into any open input port and can be swapped at
    any time through the Device Tray.
  - The contract binds to a module kind, not to a port.
- **Output devices** (Drive Tray) plug into any open output port and can be swapped:
  - **Job drive:** the current contract. There is exactly one job drive for now, and it can be moved to
    any output port.
  - **Monitor:** shows what arrives (value + 10-sample history, in the chosen view mode) and judges nothing.
    It is owned from L9.
  - **Logger:** future.
  - An empty output port accepts nothing (wires into it stall), and a Monitor accepts everything.
- **Bigger laptop:** the grid starts at **28 × 16** and grows to 32 × 18 (L6), 36 × 20 (L9) and 40 × 22 (L11).
  - The board grows east/south only.
  - Output ports stay glued to the east edge and move with their wires.
  - Port rows never move.

**USB hubs (player request 2026-09-25; supersedes the fixed rim ports above).**
- Every port is now a **2×2 USB hub** (`usb_input` / `usb_output`, size L):
  - the chassis sits on the top row and keeps the port anchor;
  - the stick bay is the bottom row, with the female face at its east end (input) or west end
    (output).
- A plugged stick or drive lies in the bay, on the board. Nothing hangs off the laptop rim any more,
  and the rim has no ports.
- **Moving hubs.** Hubs move anywhere on the grid like components (drag the chassis):
  - They are never deleted or rotated.
  - A hub keeps its identity (`Machine.port_row`, the rack row it opened at). Saves, undo
    (`apply_layout`) and new ports respect where it stands.
  - When the board grows, only an output hub still on the old east edge follows the edge.
- **Sealed bays** are 2×2 reservations at the rack rows. The next hub opens there.
- **Encoders and decoders are 2×2 as well:** the chassis is on top, and a conversion screen below
  shows the last value turned (`U › 10100`, `00101 › F`).

### 2.2 Desk zones (player request 2026-09-24): the physical inventory

- Two **desk zones** lie beside the laptop, outside the board:
  - **left, INPUT MODULES:** a mat of slots where owned input modules lie (plug pointing east, toward
    the laptop);
  - **right, OUTPUT DEVICES:** the Job drive and the Monitor (plug pointing west).
- Each zone is a vertical column of slots, one module per slot. It has at least as many slots as owned
  devices, plus 2 spare.
- **Drag and drop:**
  - Drag a desk module onto an open port to plug it in. If that port already holds a module, the two
    swap: the old module goes to the slot the new one came from.
  - Drag a plugged module out of its port onto the desk to unplug it into that slot.
  - Drag between slots to rearrange.
  - Click a module, then click a port (or a slot): the same, without dragging.
  - Sealed ports and wrong-side drops are refused. A red slash shows the refusal, and the module snaps
    back.
- **Rules:**
  - An input module can only go to input ports; an output device only to output ports.
  - A module is always in exactly one place: a desk slot or a port.
  - Plugging still respects the wire rule (`insert_device` refuses a module that would break the port's
    wire; the module snaps back and the reason is shown).
- **State:** LabRun keeps `desk_inputs` / `desk_outputs` (slot index → module kind), saved in the lab
  section. Newly owned modules appear in the first free slot with the "New" pulse.
- The Device/Drive Tray popover stays only as a fallback, for clicking a port with no desk visible.

### 2.3 Quests (player request 2026-09-25): sticks and the COMPLETED tray

- **Several quests at once.** Up to `LabRun.QUEST_WINDOW` (2) unfinished quests are active: the
  lowest unfinished one (`level`) and the next. Each quest is one LabDef level.
- **Each quest brings its own USB stick(s).** A quest stick is a module kind bound to a quest:
  `"text@11"` is quest 12's Text stick (`Devices.stick` / `base` / `quest_of`).
  - It carries its quest's stream.
  - It stamps `quest` into every value's lineage (`origins[socket]["quest"]`).
  - Either Job drive (`job`, `job2`) judges a value against the quest it came from. A value that
    mixes two quests' data counts for neither.
  - Plain kinds (`"text"`) still work, for tests and old saves: they belong to `level`.
- **Filled → filed.**
  - A quest is **filled** once its count and constraints are met. Its sticks turn green: a success
    key bar and outline, a full store, and "Q12" in success colour.
  - The player unplugs one of its sticks, from a port or from the desk, and drops it into the
    **COMPLETED tray** under the input mat. The quest is then **filed** (`LabRun.file_quest`): it
    counts as done, its sticks leave, and the next quest arrives with its sticks.
  - Unlocks, the board size and the open ports follow the highest active quest (`frontier()`). The
    PSU tier follows `level`.
  - The tray refuses a quest that is not finished yet ("Not finished yet — d / n"), and anything
    that is not a quest stick.
- **Watchers.** The completion banner ("TASK COMPLETE"), the board sweep and the `job_complete` cue
  watch `LabRun.files`. `quest_ready` plays when a quest fills.
- **Tests and tools** set `auto_file = true`: a filled quest files itself, and an empty socket takes
  the next quest's stick of the same kind. The game sets `false`.
- **HUD.**
  - Quest cards (bottom left): one per active quest, showing the tag, title, request, progress and
    "✓ READY". Click a card to expand it with its brief and NEEDS / OUTPUT / RATE / LOST rows.
  - The title screen has a **Quests** page, and the in-game menu's Lab card lists the active quests.
- **Save.** `lab.quests = {completed: [q], progress: {q: {delivered, rejected, filled}}, files}`.
  Old saves get the defaults, and `LabRun.migrate_plain` turns plugged plain modules into the
  current quest's sticks.

### 2.4 Views (player request 2026-09-25): a main mechanic

The board has five **views**. The View dock at the bottom centre switches them; the keys are
N B F T P.

| View | Key | What it shows |
|---|---|---|
| Normal | N | the factory as it is |
| Data | B | every wire as a band in the colour of what it carries (bits: data.number; raw: family.io), with its width (`3b`, `RAW`); each stick names its stream |
| Flow | F | a busy / blocked bar on every machine (share of the run), the bottleneck outlined, stuck wires in state.blocked, wire load, values lost at a stick |
| Heat | T | the thermal overlay |
| Power | P | power pips per machine plus the PSU gauge |

- One view is shown at a time, with a 150 ms cross-fade. The machines fade to α .55 under it.
- The legend sits right above the dock.
- A thin frame in the view's colour rims the screen while a view is on.
- Code: `SimulationManager.VIEWS` / `set_overlay`, `world/overlays/systems_overlay.gd`,
  `ui/hud/view_dock.gd`, `ui/hud/overlay_legend.gd`.

## 3. Contract Drive and contracts

**Contract Drive** (`contract_drive`, replaces `usb_output`, locked, east board edge):
- It is the locked Output with a female port face on its east edge.
- The current job is a slanted, flipped data module plugged into it. Its 10×3 store fills with
  accepted values.
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
| `max_rejected` | wrong deliveries ≤ R during the window (a filter that must really filter) |

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
- **When:** the PSU comes online at L16 "Power Cap" (`LabRun.POWER_LEVEL`). Earlier levels have
  unlimited power (capacity 0), so the L1–L15 factories never brown out; the top bar shows plain
  demand until then and `demand/capacity` after. `psu_tier` is saved with the Lab.

## 5. Heat

**Field:**
- An integer grid, one cell per board tile.
- `t` is the temperature above ambient, in tenths of °C; the display value is 25 + t/10 °C.
- It is a data-oriented `PackedInt32Array` in `core/thermal/thermal_grid.gd`. There are no Nodes.

**Update order,** deterministic, once per tick after machines work (calibrated v2, E2):
1. **Generate:** a machine that did `w` work units this tick adds
   `heat × clock heat multiplier × w / clock rate` to its footprint (so a full-rate normal-clock tick
   adds exactly `heat`). The heat is split evenly, and the remainder goes to the lowest cell index.
   - Heat per full tick: **84 per rated power unit** (Add 84, Multiply 168), routing 42 per unit,
     **Processor 440**; IO, viewers and the thermal family 0.
2. **Diffuse:** per tile edge, `f = trunc((t_a − t_b) × k / 64)` moves heat a → b (exactly
   conservative). Board edges `k = 8`. A heat pipe conducts `k = 24` along its axis (to the next pipe
   and into the tile its end pad touches) and is **insulated across its axis** (`k = 0`). Every tile
   sums to ≤ 64/64, so the explicit step is stable.
3. **Equalise:** every multi-tile machine footprint and every heat-pipe chain is one isothermal body
   (its total is spread evenly, remainder to the lowest indices). Chains join straights and elbows
   (an edge along either pipe's axis).
4. **Dissipate:** `t' -= ceil(t × d / 1024)`, where `d` = 8 (ambient) + 32 per board side the tile lies
   on (the chassis leaks a little, so edge builds are not punished) + cooling bonuses:
   - Heatsink: +128 within Chebyshev radius 1.
   - Blower (the Fan): +160 × (its work rate / 12) within radius 2, so a browned-out blower moves less
     air and a fast-clocked one more.
   - Radiator: +256 × (rate / 12) within radius 2.
- Why v2: with the v1 numbers (+24 heatsink, pipe 16/64 with open sides) a heat pipe could not move
  a cluster by a stage — a single tile edge cannot carry enough heat. Isothermal bodies and pads let
  a pipe draw from a whole machine, which is also how real heat pipes behave.
- Heat is simulated only when the run asks for it: the Lab from L17 "Heat" (`LabRun.HEAT_LEVEL`),
  never in the tutorial missions. It resets with the run and is not saved.

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

**Calibration targets** (all asserted in `tests/test_thermal.gd`, 100 % duty on a 40×22 board):
- An isolated Add at 100 % duty settles in NORMAL.
- Four Adds packed edge to edge at 100 % reach HOT.
- An isolated Processor at 100 % reaches THROTTLING without cooling.
- A Processor with a Fan beside it stays ≤ WARM.
- A Heat Pipe chain of 3 cells from a hot cluster to a Heatsink lowers the cluster by ≥ 1 stage.

**Cooling family** (Group G). These are placeable machines with no data ports:

| Machine | Size | Power | Effect | Unlock |
|---|---|---|---|---|
| Heatsink (`heatsink`) | S | 0 | +128 dissipation, r1 | L17 |
| Blower / Fan (`blower`) | S | 2 | +160 × rate/12 dissipation, r2; states idle/running/high load | L17 |
| Heat Pipe (`heat_pipe`) | S (chainable, axis = rotation) | 0 | k 24 along its axis, insulated sides, isothermal chain | L21 |
| Radiator (`radiator`) | L | 1 | +256 × rate/12 dissipation, r2 | L21 |

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

## 8. Visual language (locked; see `docs/STYLE_GUIDE.md §14`)

The final look is drawn on Penpot pages 15–19 and specified in `STYLE_GUIDE §14` (summary),
`VISUAL_SYSTEM §21` (Godot mapping) and `MOTION_SYSTEM §8` (motion), with exact geometry in
`design/reference/systems_v1.js`. Key decisions:

- **Resource indicators:** clock dots and power pips replace the stats silk text.
- **Status LED V2:** a lamp in a well with no glow disc. Throttling = amber + ring, Overheated = red +
  ring, Error = red diamond.
- **Thermal strip:** a 2 px bar inside the top edge; the body is never tinted.
- **VFX ladder L0–L5:** function-specific processing, and no glow blobs, halos or body glow.
- **Raw data:** IO green, with a RawPort receptacle and a pill RawToken.
- **USB (option C):** a port face on the locked IO, with male data modules.
- **Thermal family:** copper board-level hardware on a PCB footprint (no chassis or ports). Heat pipes
  never look like, share tiles with or cross data wires.
- **Overlays:** thermal tile heat map and power; at most one at a time.

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

**Multi-select** (as built):
- Box select with a left-drag on an empty board (every player machine the marquee touches).
- A group can be moved (drag a member; hologram routes, all or nothing), duplicated (Alt+drag or
  Ctrl+D — the wires between its members are copied too) or deleted (X / Del); the quick bar has
  a group mode. Each is one undo step.

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
| 1 | First Contact | deliver 10 × `010` (Bit module, 3-bit) | wires | — |
| 2 | Plus Two | deliver 20 × `100` | a constant transform | Add |
| 3 | Over the Top | deliver 20 × `001` | overflow | — |
| 4 | Moving Target | map: in + 3 (3-bit), varying stick | real transform, no constants | — |
| 5 | Numbers | map: enc3(n) + 1, Number module | encoding and width choice | Number module, Number Encoder/Decoder |
| 6 | Letters | map text: Caesar +3 (no wrap), Text module → TEXT | encode → compute → decode | Text module, Char Encoder/Decoder, Char Viewer |
| 7 | Past Z | map text: Caesar +3 with wrap | modulo arithmetic | Modulo |
| 8 | Payload | map: low 3 bits of tagged 5-bit words | bit fields | Bit Splitter |
| 9 | Sorting | filter: sensor > 4 | predicate + gating | Sensor module, Compare, Gate |
| 10 | Burst | map, bursty stick, `max_lost` 0 | buffering | Buffer, Delay |
| 11 | Rush Hour | map ×3 via Multiply, `min_rate` 4/s | parallelism | Multiply, Splitter, Merger |
| 12 | **Two Sticks** | paired: text + constant key (5), Caesar with wrap | second stream | **Socket 2**, Key module, Adder (2-input) |
| 13 | Changing Key | paired, key changes every 8; text in bursts of 36, `max_lost` 0 | synchronisation (a lost letter shifts every later pair) | Counter |
| 14 | Mixed Traffic | map by tag: bit 4 set → payload + 1, else payload × 2, merged | routing | Demux, Mux, Conditional Router |
| 15 | Wider | map: 3-bit n → 5-bit n × 5 | width conversion | Zero/Sign Extend, Truncate |
| 16 | Power Cap | map × 2, `min_rate` 4/s, `max_power` 8 | efficiency (Adder doublers beat Multiply) | reward: Improved Adapter (16), clock modes |
| 17 | Heat | map + 1, `min_rate` 8/s, `max_heat` THROTTLING | overclocking + cooling layout | Heatsink, Blower |
| 18 | **BYTE** | paired: 8-bit ASCII AND the key-stick mask 0xDF (lower → upper) | 8-bit buses, bitwise logic | **8-bit**, AND/OR/XOR/NOT, Bus Combiner, Socket 3; reward: Desktop PSU (32) |
| 19 | XOR Cipher | paired: ASCII ⊕ a changing key, delivered as raw bytes | bitwise logic | Shift L/R |
| 20 | Cheap Multiply | map × 4, `min_rate` 4/s, `max_power` 6 | shifts beat Multiply | — |
| 21 | Datacenter | map × 3, `min_rate` 8/s, `max_heat` HOT | a thermal redesign (Radiators fit the PSU, Blowers do not) | Heat Pipe, Radiator; reward: High-Capacity PSU (64) |
| 22 | Running Sum | map: the running total (5-bit), one value per 36 ticks | memory (a feedback loop) | Register |
| 23 | Lookup | map: a 3-bit substitution table | table memory | ROM (typed table) |
| 24 | Calculator | paired over three sticks: number ± key, the bit stick picks ADD / SUB | control-selected compute | ALU |
| 25 | Tiny Memory | filter: run WE / address / value instructions on RAM, deliver the reads | programmable memory | RAM, Register Bank, Instruction Decoder |
| 26 | Playback | map: the n-th clock pulse plays note n of a table | sequencing | Program Counter |
| 27 | Fetch & Execute | map: the accumulator after each instruction of a typed 8-instruction program (ADD k / SUB k) | a CPU: fetch (PC → ROM), decode, execute (ALU + ACC register) | — |
| 28 | Output Port | filter: only OUT instructions show the accumulator, `max_rejected` 0 | selective output (Gate on the OUT line) | — |
| 29+ | jumps, loops, a register file … | — | — | Free Build until then |

- **Migration:** the saved Lab levels L1–L3 keep their index. Saved L4–L6 map to the new L6, L7
  and L8, which cover the same content. See §12.
- **As built (2026-09-25):** L12–L28 are implemented; each level's demand is proven by a test
  that the naive layout fails (L13 unbuffered, L16/L20 Multiplies, L17 uncooled or at the normal
  clock, L21 Blower-cooled). Rewards are level data (`reward: {psu_tier}`) and a board never has
  less than the levels earned. After L21 the Lab is a **Free Build** (the last contract keeps
  judging) after L28. History-dependent contracts (running sum, memory program, playback) are
  judged from the origin's `seq` and the level's stream (O(cycle) via periodicity). The PSU is the laptop's adapter lying on the desk under the output
  mat (not a grid tile, so no save can collide with it).
- **Tuning:** every contract has a reference solution in `tests/solutions.gd`. A test proves each
  one is solvable with *only* the machines unlocked by then, and inside the board area.

## 11. Component groups and the definition of done per component

Each component needs simulation behaviour, port and width rules, power, cost, heat, a visual state
with its function-specific processing visual, hover and Inspector content, and tests.

All groups below are implemented (2026-09-25).

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
- Converts the placed `usb_input` machines at source cells into socket 1, with a Bit module
  inserted. Extra L4–L6 inputs become sockets only if the new level has unlocked them; otherwise
  their wires are dropped with a notice.
- Converts `usb_output` to the Contract Drive.
- Keeps every other machine and wire.

A backup `save.v1.json` is written before the migration.

## 13. Audio hooks

`AudioBus.event(name)` is an autoload: it emits `fired(name)` for listeners and plays a tiny
synthesized cue (generated at startup, no asset files, rate-limited per event, master volume from
Settings → Sound). Events come from the views and the manager, never from `core/`. Events:
- USB: `usb_insert`, `usb_remove`
- Wires: `wire_connect`, `wire_disconnect`
- Machines: `machine_place`, `machine_delete`
- Contracts: `job_accept`, `job_reject`, `job_complete`
- Warnings: `fan_start`, `thermal_warning`, `power_overload`
- Progression: `unlock`

No per-packet sounds.
