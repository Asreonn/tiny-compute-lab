# Tiny Compute Lab — Content assets

Everything the player builds with, plugs in or is asked to do is a **Godot Resource** under
`content/`. The registries (`Catalog`, `Devices`, `LabDef`) load them once at start-up, sorted by
path, so adding content never means editing a table in code.

```
content/
  components/<family>/<id>.tres   ComponentDef  — a machine type
  devices/<id>.tres               DeviceDef     — a USB stick / output device
  lab/levels/NN_<slug>.tres       LevelDef      — a Lab level (quest)
  lab/lab.tres                    LabConfig     — the campaign: level order + rules
  examples/*.tres                 ContentVariant samples used by tests (not loaded by the game)
```

The classes live in `core/content/`. `ContentDB` (`core/content/content_db.gd`) scans the folders.

## 1. Add a machine

1. Create `content/components/<family>/<id>.tres` (a `ComponentDef`) in the Godot editor, or copy a
   similar file. Its fields:

   | Field | Meaning |
   |---|---|
   | `id` | unique type id, used in saves |
   | `display_name`, `description` | shown in the palette, hover and Inspector |
   | `family` | one of `ComponentDef.FAMILIES`; sets the tab colour and the palette category |
   | `size` | S (1×1), M (2×1), L (2×2) |
   | `ticks`, `campaign_ticks` | job length on legacy / campaign boards |
   | `power` | rated power. Powered machines automatically get the Clock and Efficiency params (`Catalog._finish`) |
   | `heat` | heat per full-rate tick; `-1` derives it from the power (`Catalog.HEAT_PER_POWER`) |
   | `max_lanes` | how many parallel jobs an upgrade may give it (`docs/FACTORY_SYSTEMS.md §3`) |
   | `icon` / `glyph_text` | operation icon (`assets/art/icon/<icon>.svg`), or text when there is no icon |
   | `ports` | `PortDef`s: `id`, `dir` (in/out/ctrl), `role` (data/control/flag/raw), `width` (int, `W` = the instance width, `*` = any), `cell`, `side`, `label`, `bus` |
   | `params` | `ParamDef`s: `key`, `label`, `kind` (int/enum/text), `default_*`, `min`/`max`, `options` |
   | `logic` | the `ComponentLogic` script with its behaviour (`core/components/logic/`); empty = passive hardware (thermal and power parts) |
   | `menu_order` | position in the build menu |

2. **Behaviour.** Reuse a logic script and add a `match m.type` branch, or write a new
   `ComponentLogic`. Logic reads `inq` and `params`, computes with BitVector ops only, and calls
   `m.begin_job(...)`. It starts only when `m.has_free_lane()` is true.
3. **Art.** Add a layout for the id in `assets/art/machine_layouts.json` (shell form, areas, icon);
   `Art.layout` reads it. New art comes from Penpot first (`docs/STYLE_GUIDE.md`).
4. **Unlock.** List the id in a level's `unlocks` (`content/lab/levels/*.tres`). A machine no level
   unlocks is not shown in the Lab palette.
5. **Tests.** `tests/test_content.gd` checks every asset automatically (logic, layout, ports,
   param ranges). Add behaviour tests next to the family's existing tests.

## 2. Make a variant

A variant is a `ContentVariant` (`core/content/content_variant.gd`):

| Field | Value |
|---|---|
| `id` | the new id |
| `base` | the asset it derives from |
| `overrides` | a dictionary deep-merged into the base's data |

One class serves every registry:

| Registry | Example overrides |
|---|---|
| machine | `{"name": "Quick Add", "campaign_ticks": 2, "power": 2, "params": {"k": {"default": 3}}}` |
| stick | `{"name": "Thermo module", "glyph": "°C"}` |
| level | `{"title": "Plus Three", "contract": {"value": "101", "count": 30}}` |

**Rules:**
- A machine variant keeps its base's **shape**: size, ports and logic, and therefore its art. The
  Catalog refuses one that changes them.
- A placed variant has `Machine.type` = the base (behaviour and art) and `Machine.variant` = the
  variant id. Saves, copies and the palette use `def_id()`.
- Put the file next to its base, or anywhere under the registry's folder. A variant lists right
  after its base in the menu.
- **At run time:** `Catalog.register(res)`, `Devices.register(res)`, and a level variant goes into
  a `LabConfig.levels` list. `Catalog.reload()` and `Devices.reload()` rebuild from disk.

Samples live in `content/examples/`:
- `add_quick.tres`
- `sensor_hot.tres`
- `02b_plus_three.tres`

## 3. Add a stick (USB device)

Create `content/devices/<id>.tres` (a `DeviceDef`):

| Field | Meaning |
|---|---|
| `output` | false = input stick, true = output device |
| `out` | `bits` = already-encoded words; `raw` = semantic values that need an Encoder |
| `raw_kind` | `RawValue.Kind`, for raw sticks |
| `glyph` | the silk on the stick |
| `accent` | `data` or `io` |

`Devices.make_stream` builds the socket stream from a level's `streams[<id>]` spec:
- `values`, `width`, `interval`;
- `pattern` (bursts);
- `burst` (values per emission).

An id may not contain `@`: the quest-stick separator (`text@11`).

## 4. Add or change a level

Create `content/lab/levels/NN_<slug>.tres` (a `LevelDef`) and add it to `content/lab/lab.tres` →
`levels` in play order. Its fields:

| Field | Meaning |
|---|---|
| `id`, `title`, `brief` | identity and the quest card |
| `contract` | `{kind, count, ops, accept_format, accept_width, min_rate, sustain, max_power, max_heat, max_lost, max_latency, max_rejected, value, pair}` (`game/lab/contract.gd`) |
| `streams` | per-stick stream specs |
| `devices` | sticks handed to the player at this level |
| `unlocks` | machine ids unlocked when the level starts |
| `grow` | the new board size (`Vector2i.ZERO` = unchanged) |
| `view` | the default readout mode |
| `reward` | `{psu_tier: N}` |

Every level needs a reference solution in `tests/solutions.gd`: a test proves it is solvable with
only its unlocks. The design rules for levels are in `docs/PROGRESSION.md`.

## 5. The campaign (`content/lab/lab.tres`, a `LabConfig`)

| Field | Meaning |
|---|---|
| `levels` | the level order |
| `initial_size` | the first board |
| `port_rows`, `input_port_open`, `output_port_open` | which laptop edge rows get a port, and from which level (-1 = never) |
| `quest_window` | how many quests run at once |
| `power_level`, `heat_level`, `monitor_level` | when power, heat and the Monitor switch on |
| `psu_capacity`, `psu_names` | the adapter/PSU tiers |

`LabDef.use_config(cfg)` swaps the whole campaign (tests use it). `LabRun` reads the rules through
`LabDef.CONFIG`, so a mod or a test campaign changes them in one file.
