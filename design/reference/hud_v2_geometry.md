# HUD V2 geometry (Penpot page `06 HUD Components`, canonical)

Extracted from Penpot. The Godot HUD reproduces these exactly: sizes, positions, fills, strokes, radii
and font sizes/weights. Font: JetBrains Mono (`TCLTheme.font("Medium" | "Bold" | "ExtraBold")`;
weight 800 = ExtraBold, 700 = Bold, 500/600 = Medium).

**Colours** (`Palette`):
- `#101c1a` SURFACE_PANEL · `#0a1311` SURFACE_SUNKEN · `#162522` SURFACE_RAISED
- `#243a36` SURFACE_BORDER · `#35524c` SURFACE_BORDER_STRONG
- `#e4efeb` TEXT_PRIMARY · `#93aba4` TEXT_SECONDARY · `#5e7771` TEXT_MUTED · `#081110` TEXT_INVERSE
- `#3ee0cf` DATA_NUMBER · `#1b5e57` DATA_NUMBER_DIM · `#57e389` STATE_VALID/SUCCESS/RUNNING
- `#ffb020` STATE_BLOCKED/PAUSED · `#ff4d5e` STATE_ERROR · `#f5d04a` FAMILY_ROUTING
- `#1f302c` MATERIAL_PLATE · `#4a6961` MATERIAL_FRAME

Reference render: `design/previews/ds_v2_hud.png`.

## TopBar: 1920×52 at the top, full width
Fill SURFACE_PANEL, plus a 1 px SURFACE_BORDER rule at y 51.

| part | pos | size | style |
|---|---|---|---|
| app icon (icon_components or the app glyph) | 18,14 | 24×24 | |
| mission pill | 58,8 | 300×36 | SUNKEN, r18. Text: `01  Plus Two  x → x + 010` (index muted 10/500, title 12/800, formula DATA_NUMBER 11/800), chevron-down at right |
| state badge (SimStateBadge) | 700,10 | 120×32 | SUNKEN, 1.5 px state-colour stroke, r16. Dot + `BUILD`/`RUNNING`/`PAUSED`/`FAILED`/`COMPLETE` 10/800 in the state colour (BUILD=STATE_BUILD, RUNNING=STATE_RUNNING, PAUSED=STATE_PAUSED, FAILED=STATE_ERROR, COMPLETE=STATE_SUCCESS) |
| controls (SimulationControls) | 836,8 | 132×36 | 3 icon buttons 36×36 (reset, step, play/pause) with a 12 px gap; the active one is DATA_NUMBER_DIM with a DATA_NUMBER stroke, r4 |
| speed (Segmented) | 984,10 | 120×32 | SUNKEN, r16. `1×` `2×` `4×`; the selected one is a RAISED pill, TEXT_PRIMARY 10/800; the others TEXT_MUTED |
| metric throughput | right −420 | 108×36 | SUNKEN, r18. Icon + value 13/800 + unit `/s` muted. Warning = 1 px STATE_BLOCKED stroke + amber value |
| metric power | right −304 | 108×36 | same, icon_power |
| metric latency | right −188 | 108×36 | same, icon_latency, unit `t` |
| menu button | right −56 | 36×36 | RAISED, 1 px BORDER, r4, icon_menu 24 |

Positions on the right are anchored to the right edge (Penpot: 1500/1616/1732/1864 on 1920).

## ToolRail: 56×236, left, 16 px from the edge, top 68
Fill PANEL, r10. Four tools, 48×48 at x 4, y 6 / 62 / 118 / 174, r6, icon 24 centred:
`select`, `wire`, `delete`, `rotate`. Active tool = fill DATA_NUMBER_DIM + 1 px DATA_NUMBER stroke.
Shortcuts: V, W, X, R.

## BuildPalette: 232×330, right of the ToolRail (x 88, y 68)
Fill PANEL, r10.
- **Category tabs:** 40×36 at y 8, x 8 / 52 / 96 / 140 / 184, r6. The selected tab is RAISED. Family icon; a disabled category is TEXT_MUTED.
- **Rule** at 8,50, 216×1, BORDER.
- **Items** (PaletteItem): 176×48 at x 8, y 60 + 56·i, r8.
  - Default: SUNKEN + 1 px BORDER.
  - Selected: RAISED + 1.5 px family-colour stroke.
  - New (just unlocked): SUNKEN + 1 px STATE_VALID stroke + green dot at the top right.
  - Locked: PANEL, muted text, lock icon.
  - Content: a 28×28 icon tile at left 8 (MATERIAL_PLATE fill, MATERIAL_FRAME stroke, r4, op_* icon), name 11/800 TEXT_PRIMARY at 44,8, and a sub-line 9/500 TEXT_MUTED at 44,26 (e.g. `1 tick · 1 power`).

## Inspector: 300×366, right edge, 16 px margin, top 68
Fill PANEL, r10.
- **Header:**
  - Module tile 40×40 at 16,16 (PLATE fill, FRAME stroke, r6, machine icon).
  - Name at 68,16, 15/800.
  - State pill at 68,38, 96×20 (SUNKEN, 1 px state-colour stroke, r10): dot + state text 9/800.
- **Sections** (InspectorSection, 280×28 at x 10): title 9/800 TEXT_SECONDARY, letter-spaced, with a chevron at the right. Expanded sections list their rows. Section y: CONFIGURATION 72, STATE 148, PERFORMANCE 234, STATISTICS 320 (collapsed).
- **Rows** (InspectorRow, 280×24): key 12/500 TEXT_SECONDARY at left 0, value 12/800 right-aligned (TEXT_PRIMARY; Warning = STATE_BLOCKED; Good = STATE_VALID).
- **Config control** (Stepper / Dropdown / Segmented) at x 150, 140×32, RAISED + 1 px BORDER_STRONG, r6.
- **Slice A rows:**
  - Add: `Constant` stepper (shown in the current view mode, e.g. `010`) and `Width` (locked `3-bit` chip).
  - State: `Job`, `Last carry` (1 = amber).
  - Performance: `Busy %`, `Time / job`.
  - `View as` Segmented BIN / DEC / HEX in CONFIGURATION for every machine; it sets `SimulationManager.set_view_mode`.

## MissionSummary: 320×232 (expanded) / 300×36 (collapsed), bottom-left, 16 px margins
Fill PANEL, 1 px BORDER, r10.

| part | pos | style |
|---|---|---|
| title | 18,16 | `01 · Plus Two`, 14/800 |
| collapse chevron | 286,14 | 20×20 |
| brief | 18,42 | 284 wide, 11/500 TEXT_SECONDARY |
| formula box | 18,72 | 284×30, SUNKEN, r6; text centred 12/800 DATA_NUMBER |
| input row | y 116 | cells 30×20, step 36 from x 18: RAISED + 1 px BORDER_STRONG, r4, value 10/700 TEXT_PRIMARY. Up to 7 cells, then `…` |
| output row | y 142 | same. Done correct = 1 px STATE_VALID stroke; wrong = STATE_ERROR stroke; pending = SUNKEN, TEXT_MUTED |
| progress track | 18,176 | 284×4 SUNKEN r2; fill STATE_VALID |
| progress text | 18,190 | `2 / 3` 11/800 |
| optional goals | 150,188 | star icon 16 + `n optional goals` |

Cells show the values in the current view mode (3-bit BIN: `010`). Widen the cells to fit, 30 px minimum.

## ResultPanel: 380×300, centred
Fill PANEL, 1 px BORDER_STRONG, r8. Accent bar 380×4 at the top (STATE_VALID for pass, STATE_ERROR for fail), r2.
- **Title** at 24,22, 20/800: `PASS` green or `VALIDATION FAILED` red. Pass shows three stars at the right.
- **Reason** at 24,58, 12/500 TEXT_SECONDARY.
- **Columns** at y 92: keys 10/500 TEXT_SECONDARY at x 24 / 140 / 256; values at y 106, 22/800.
  - Fail: Expected green, Received red, Packet TEXT_PRIMARY. Show `failure.expected` and `failure.received`; when the mode is not BIN, add the BIN bits beneath at 10/500 muted.
  - Pass: Accuracy / Throughput / Latency / Power.
- **Path** at 24,150, 11/600 TEXT_SECONDARY: `Path  USB Input → Add #3 → Output`.
- **Hint** at 24,172, 10/500 TEXT_MUTED.
- **Buttons** (104×32, r4, label 11/800):
  - Primary: DATA_NUMBER fill, TEXT_INVERSE label (`FIX & RETRY` / `CONTINUE`).
  - Secondary: RAISED + BORDER_STRONG stroke (`MISSIONS`, `RETRY`).
  - Row at y 240, x 24 / 140 / 256.

## Tooltip (kinds: Machine 168×60, Port 150×32, Wire 168×60, Packet 120×72, Simple 148×60 or less)
Fill SURFACE_RAISED, 1 px BORDER, r6. Title 11/800 (datatype-coloured dot for port/wire/packet), sub 9/500 muted.
- Machine: `Add` · `+010` · `1 tick · 1 power`.
- Port: `3-bit input`.
- Wire: `3-bit wire · 1 packet / tick`.
- Packet: `#12` then the value in large 16/800 (in the current view mode).
