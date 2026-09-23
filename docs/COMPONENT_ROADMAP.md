# Tiny Compute Lab — Component Roadmap

> The current visual language is the canonical Tiny Compute Lab style
> (`docs/STYLE_GUIDE.md`). Every component on this list must be built from the canonical
> primitives and tested on the gameplay reference board.

**Direction:** bit-based data processing → small integers → encoding/decoding → routing by type and
control → progressively wider buses → arithmetic/logic → text/cipher → memory and registers →
CPU-style systems → file/image processing.

**Data model implication:** every value is fundamentally a bit vector. Early machines hide this: a
NUMBER wire carries "a small integer". Later machines expose it through **View** machines, **BusPorts**
and **WidthTags**, without changing the chassis language.

Status legend:
- **MVP**: in the game (simulation + Penpot component).
- **Kit**: Penpot starter component on page `14 Roadmap Kit`.
- **Slot**: family rules defined, concept slot only.

## 1. MVP (in game)

| Component | Family | Size | Function region | Ports |
|---|---|---|---|---|
| Input | IO | M | Feed | out N |
| Output | IO | M | Bin | in N |
| Add | Math | M | Dial + `+` + value display | in N → out N |
| Multiply | Math | M | Dial + `×` + value display | in N → out N |
| Processor | Compute | L | Die (4 cores) | in N → out N |
| Compare | Logic | S | OpWindow (Comparator) `>`/`<`/`=` | in N → out B |
| Gate | Logic | S | Valve (blade) | in N, ctrl B (N) → out N |
| Splitter | Routing | L | Split lanes | in N → out N ×2 |
| Merger | Routing | L | Merge lanes | in N ×2 → out N |
| Buffer | Storage | M | Bank (4 bays) | in N → out N |
| Delay | Storage | S | Coil + ticks | in N → out N |
| Counter | Storage | S | Counter digits + tally | in N → out N |

N = NUMBER (circle), B = BOOLEAN (diamond), Bus = BusPort slot + WidthTag.

## 2. Roadmap starter kit (page `14`, component path `TinyCompute / Machines / Roadmap`)

### View *(IO sub-family, segmented green tab)*
Pass-through probes that re-interpret the bits flowing through them.

| Component | Status | Size | Region | Notes |
|---|---|---|---|---|
| Number Viewer | Kit | M | Readout `DEC` | inspector switches mode |
| Hex Viewer | Kit | M | Readout `HEX` | |
| Character Viewer | Kit | M | Readout `CHR` | CHR values in IO green |
| Type Viewer | Kit | M | Readout `TYPE` | shows datatype + width (`NUM·8`) |
| Bit Viewer | Kit | M | Bits (8 cells) | raw view, lit = 1 |
| Decoder / Display node | Slot | M | Readout + segment display | sink variant of a viewer (EdgeOut form) |

### Math *(solid blue)*
| Component | Status | Size | Region |
|---|---|---|---|
| Increment | Kit | S | OpWindow `+1` |
| Decrement | Kit | S | OpWindow `−1` |
| Subtract | Kit | M | Dial `−` + value |
| Modulo | Kit | M | Dial `%` + value |

### Logic, bitwise *(solid violet)*
| Component | Status | Size | Region | Ports |
|---|---|---|---|---|
| AND / OR / XOR | Kit | L | Merge lanes + OpWindow `&` `|` `^` | A, B (W) → Q (E row 0) |
| NOT | Kit | S | OpWindow `!` | in → out |
| Shift Left / Right | Kit | M | OpWindow `«`/`»` + Bits strip | in → out |
| Comparator variants (≥ ≤ ≠, range) | Slot | S | Comparator window, new operator text | in N → out B |

### Routing and control flow *(solid yellow)*
| Component | Status | Size | Region | Ports |
|---|---|---|---|---|
| Mux | Kit | L | Merge lanes | A, B (W), select B (N) → out |
| Demux | Kit | L | Split lanes | in, select B (N) → A, B |
| Conditional Router | Kit | L | Split lanes + OpWindow `>` | in → pass / fail |
| Type Switch | Kit | L | Split lanes + OpWindow `T?` | in → NUMBER lane / BOOLEAN lane |
| Selector | Slot | L | = Mux with N-way select (WidthTag on select) | |
| Router (addressed) | Slot | L | Split lanes + Readout (address) | |

### Conversion *(Routing sub-family, segmented yellow tab)*
| Component | Status | Size | Region | Ports |
|---|---|---|---|---|
| Zero Extend (3→4) | Kit | M | Taper *widen* + `ZX` | Bus 3 → Bus 4 |
| Sign Extend (4→8) | Kit | M | Taper *widen* + `SX` | Bus 4 → Bus 8 |
| Truncate (8→4) | Kit | M | Taper *narrow* + `TR` | Bus 8 → Bus 4 |
| Adapter 4→8 | Kit | M | Taper *widen* + `AD` | Bus 4 → Bus 8 |
| 3→4 Adapter / Width Converter | Slot | M | = Zero Extend with other WidthTags | |
| Bus Splitter | Kit | L | Split lanes + WidthTags | Bus 8 → Bus 4 ×2 |
| Bus Combiner | Kit | L | Merge lanes + WidthTags | Bus 4 ×2 → Bus 8 |

### Memory *(Storage sub-family, segmented orange tab)*
| Component | Status | Size | Region | Ports |
|---|---|---|---|---|
| Register | Kit | M | Readout `DEC` | D (W), WE B (N) → Q (E) |
| Register Bank | Kit | L | Cells (4×4) + `REG ×4` | D, addr (W), WE (N) → Q |
| RAM block | Kit | L | Cells, Write state | D, addr (W), WE (N) → Q |
| ROM block | Kit | L | Cells, Read state | addr (W) → Q |
| Addressed Memory | Slot | L | Cells + address Readout | |
| Read/Write Controller | Slot | M | *(Control)* R/W toggle region | |

### Compute core and Control
| Component | Status | Family | Size | Region |
|---|---|---|---|---|
| ALU | Kit | Compute | L | Chip + OpWindow `ALU`, op-select ctrl (N) |
| Instruction Decoder | Kit | Control | L | Chip + Bits strip, B outputs |
| Program Counter | Kit | Control | S | Counter digits |
| Control Unit | Slot | Control | L | Chip + multiple B outputs |
| Bus Interface block | Slot | Control | M | BusPort ↔ Port bridge |

### Interface *(IO)*
| Component | Status | Size | Notes |
|---|---|---|---|
| USB Input | Kit | M | EdgeIn + Feed, **Bus 8** output (raw bytes) |
| Terminal Output | Kit | M | EdgeOut + Readout `CHR` |
| File Input | Slot | M | EdgeIn + Feed + file silk; Bus output |
| Storage Output / Logger | Slot | M | EdgeOut + Bin + log lines |

## 3. How families extend

- **Sub-family:** parent hue as a segmented tab (View ⊂ IO, Conversion ⊂ Routing, Memory ⊂ Storage,
  Control ⊂ Compute).
- **Size by arity:** 1-in/1-out → S (simple) or M (with a display). 2-in or 2-out → L, with wedges for
  routing and a Module for logic.
- **Control inputs** are always keyed BOOLEAN ports on N (or S), never on the data edge.
- **Width** is shown only where it matters: BusPort + WidthTag on the port, a WidthTag on long buses,
  and a Taper region on converters.

## 4. New primitives added for the roadmap

| Primitive | Where | Variants |
|---|---|---|
| FamilyTab sub-families | `04 Machine Shell` | view, memory, conversion, control (segmented) |
| ActivityArea `OpWindow` | `04` | Idle, Active (generic operator window) |
| ActivityArea `Bits` | `04` | Idle, Active (8-cell bit strip) |
| ActivityArea `Taper` | `04` | Widen, Narrow, Active (width conversion) |
| ActivityArea `Cells` | `04` | Idle, Read, Write (4×4 memory array) |
| `Readout` | `13 Signal System` | Mode: BIN, DEC, SDEC, HEX, CHR, TYPE |
| `BusPort` | `13` | Direction (Input/Output) × State (Idle/Connected/Active) |
| `WidthTag` | `13` | Width: 1, 2, 3, 4, 8, 16 |

## 5. Next steps (implementation order suggestion)

1. Simulation: add a bit-vector value type (`width`, `bits`) under NUMBER. NUMBER stays the
   default 8-bit unsigned.
2. View machines + Readout modes (cheap; teaches representation early).
3. Bitwise logic (AND/OR/XOR/NOT/shift): needs 2-input L machines in the catalog.
4. Mux/Demux/Type Switch: control ports reuse Gate's N control.
5. Buses + conversion (BusPort, WidthTag, procedural bus renderer).
6. Memory (Register → RAM/ROM), then ALU/Decoder/PC for CPU-style missions.
