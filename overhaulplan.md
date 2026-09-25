Evet. Şu an konuştuğumuz şey artık birkaç feature eklemek değil; **Tiny Compute Lab’ın macro-gameplay’ini baştan oturtan kapsamlı bir overhaul**. En kritik değişiklik şu:

> **Fabrika, çok görev olduğu için büyümeyecek. Tek ana bilgisayar/data hattı giderek daha fazla bit genişliği, bandwidth, compute, power ve cooling istediği için büyüyecek.**

Aşağıdaki planı doğrudan Claude Opus’a verebilirsin. Penpot tasarımını Claude yapacak; tasarım kilitlendikten sonra Godot implementasyonunu DS’ye bölerek yaptıracak.

---

# TINY COMPUTE LAB — FACTORY GROWTH OVERHAUL MASTER PLAN

## 0. Ana tasarım hedefi

Mevcut persistent Lab korunacak ancak progression mantığı değiştirilecek.

Şu an oluşabilecek kötü yapı:

```text
Mission 1 → Line A
Mission 2 → Line B
Mission 3 → Line C
Mission 4 → Line D
```

Board büyür ama gerçek bir fabrika/computer büyümesi hissi oluşmaz.

Yeni hedef:

```text
Tiny input line
      ↓
Better pipeline
      ↓
Wider data infrastructure
      ↓
Parallel compute
      ↓
Power infrastructure
      ↓
Thermal infrastructure
      ↓
High-bandwidth backbone
      ↓
Memory / ALU
      ↓
Computer-scale system
```

Her progression aşaması mümkün olduğunca **önceki fabrikanın üzerine kurulmalı**.

Oyuncunun birkaç saat sonra gördüğü sistem, ilk `USB → Add → Output` hattının evrimleşmiş hali olmalı.

---

# 1. Yeni ana oyun döngüsü

```text
Contract arrives
        ↓
Current factory attempts workload
        ↓
Find current bottleneck
        ↓
Data / Compute / Power / Thermal capacity insufficient
        ↓
Upgrade or expand existing infrastructure
        ↓
Reroute / rebalance / parallelize
        ↓
Meet required correctness + throughput
        ↓
Unlock new capability / width / infrastructure
        ↓
Next workload stresses the SAME factory harder
```

Oyunun temel sorusu:

> “Bu puzzle'ın cevabı hangi component?”

olmaktan çıkacak.

Yeni soru:

> **“Mevcut bilgisayarımı bu workload'u kaldıracak hale nasıl getiririm?”**

---

# 2. Fabrikanın dört ana kapasitesi

Bütün macro progression dört bağlı sistem etrafında kurulacak:

| Sistem      | Ana kısıt                       |
| ----------- | ------------------------------- |
| **Data**    | Bit width + bandwidth           |
| **Compute** | Operations/tick + lanes + clock |
| **Power**   | Supply + distribution capacity  |
| **Thermal** | Heat transport + dissipation    |

Bunların bağlantısı:

```text
Wider / Faster Data
        ↓
More Compute required
        ↓
More Power required
        ↓
More Heat generated
        ↓
More Cooling required
        ↓
Larger physical factory
```

**Fabrikanın büyümesini sağlayacak ana mekanizma bu olacak.**

---

# 3. DATA INFRASTRUCTURE OVERHAUL

Bit width ile data amount/bandwidth birbirinden ayrılmalı.

`8-bit`, `16-bit`, `32-bit` bir value/interface width.

`KB`, `MB`, vb. ise veri miktarı veya throughput tarafında kullanılabilir.

Bir kablonun kapasitesi iki ayrı özellik taşıyabilir:

```text
WIDTH
8-bit

BANDWIDTH
4 values/tick
```

## Progression

Başlangıç:

```text
1-bit control trace
3-bit data trace
5-bit data trace
```

Sonra:

```text
8-bit BYTE bus
16-bit wide bus
32-bit data bus
High-bandwidth backbone
```

Görsel olarak da büyümeli.

3-bit:

```text
────
```

8-bit:

```text
════
```

32-bit/high bandwidth:

```text
████████
```

Ama bu kalınlık yalnız dekorasyon değil; gerçekten farklı infrastructure class göstermeli.

---

# 4. Data hatları component gibi upgrade edilebilmeli

İlk trace:

```text
Trace Mk1

Width: up to 5 bit
Bandwidth: 1/tick
```

Sonra:

```text
Byte Bus

Width: 8 bit
Bandwidth: 4/tick
```

Daha sonra:

```text
Wide Bus

Width: 16/32 bit
Bandwidth: much higher
```

Yeni bir component upgrade ettiğinde eski kablo artık bottleneck olabilir.

Örneğin:

```text
Processor capacity     8/tick
Wire capacity          2/tick   ← bottleneck
```

Bu factory expansion yaratır.

---

# 5. MAIN DATA BACKBONE

Orta oyunda oyuncunun fabrikanın ana omurgasını oluşturması teşvik edilmeli.

Başlangıç:

```text
USB → Add → Output
```

Orta oyun:

```text
USB
 ↓
Encoder
 ↓
════ MAIN DATA BUS ═══════════
       │
       ├→ Arithmetic
       ├→ Logic
       ├→ Buffer
       └→ Routing
                     ↓
             ══ OUTPUT BUS ══
                     ↓
                  Output
```

Yeni sistemler tamamen yeni fabrika olmamalı.

Ana backbone'a bağlanmalı.

---

# 6. EXTERNAL DATA / ENCODING

BitVector core architecture korunacak.

Compute fabric içinde temel value:

```text
BitVector
```

olarak kalacak.

Fakat external USB dünyası semantic veri taşıyabilir.

Örneğin:

```text
TEXT USB
"H"
 ↓
Character Encoder
 ↓
00111
 ↓
Compute
 ↓
Character Decoder
 ↓
"K"
```

Yeni boundary component family:

* Number Encoder
* Number Decoder
* Character Encoder
* Character Decoder
* ileride Byte/Text/File/Image encoder-decoder family

Viewer yine yalnız temsil değiştirir.

Encoder/Decoder gerçek gameplay transformation boundary'sidir.

---

# 7. USB SİSTEMİ

Başlangıçta:

```text
1 physical USB Input socket
1 physical Job/Output socket
```

olacak.

Bunlar normal placeable component olmayacak.

Lab infrastructure olacak.

Input USB cihazları inventory/peripheral sistemi üzerinden takılacak.

Örneğin:

* Numeric USB
* Text USB
* Key USB
* Sensor USB
* ileride File USB
* ileride Image USB

İlerleyen progression'da yeni **physical USB sockets** açılabilir.

Ama ekstra USB sayısı fabrikanın büyümesinin ana sebebi olmayacak.

Multi-input daha çok yeni computational capabilities için kullanılacak.

---

# 8. USB TASARIMI

Penpot'taki yeni USB seçeneklerinden **C direction canonical**:

* female USB-like port component chassis/board edge'e gömülü
* metal frame
* dark cavity
* internal tongue/contacts
* inserted device fiziksel olarak içine oturur

Generic USB stick görünümü kullanılmasın.

USB'ler daha çok:

> modular lab peripheral / data cartridge

gibi görünmeli.

---

# 9. COMPUTE COMPONENT OVERHAUL

Oyuncunun throughput ihtiyacını yalnız component spam ile çözmesini istemiyoruz.

Her temel compute component **upgradeable capacity** kazanacak.

Örneğin:

```text
ADD UNIT Mk1

Width: 3-bit
Lanes: 1
Rate: 1 op/tick
```

upgrade:

```text
ADD UNIT

Width: 5-bit
Lanes: 2
Rate: 2 op/tick
```

daha sonra:

```text
ADD UNIT

Width: 8-bit
Lanes: 4
Rate: 4 op/tick
```

---

# 10. MULTI-LANE COMPUTE

“Bir component aynı anda birkaç iş yapabilsin” sistemi **multi-lane architecture** üzerinden uygulanmalı.

Bu genellikle aynı operation'ın paralel execution'ı demek.

Örneğin 4-lane Add:

```text
Input
 ↓
┌─────────────┐
│ ADD         │
│ lane 1      │
│ lane 2      │
│ lane 3      │
│ lane 4      │
└─────────────┘
 ↓
Output
```

Bu component:

```text
4 values/tick
```

işleyebilir.

Daha sonraki ALU gibi component'lar gerçekten farklı operations destekleyebilir.

Ama primitive Add'i gereksiz yere general-purpose ALU yapma.

---

# 11. COMPONENT UPGRADE FİZİKSEL GÖRÜNMELİ

Upgrade yalnız Inspector'da sayı değiştirmemeli.

Chassis de evrimleşmeli.

Örneğin:

```text
Mk1

┌───────┐
│ ADD   │
└───────┘
```

2 lane:

```text
┌──────────┐
│ ADD  ▌▌  │
└──────────┘
```

4 lane:

```text
┌─────────────┐
│ ADD ▌▌▌▌   │
└─────────────┘
```

Bu `▌▌` bir stat indicator değil.

Bunlar **gerçek compute hardware slices**.

Component fiziksel footprint'i bile bazı upgrade'lerde büyüyebilir.

---

# 12. COMPONENT UPGRADE AXES

Her component her şeyi upgrade etmek zorunda değil.

Ama sistem desteklemeli:

### Interface Width

```text
3-bit
5-bit
8-bit
16-bit
32-bit
```

### Parallel Lanes

```text
1
2
4
8
```

### Clock

```text
Normal
Fast
Overclock
```

### Efficiency

ileri progression:

```text
lower power/op
lower heat/op
```

Upgrade tradeoff yaratmalı.

---

# 13. CLOCK / OVERCLOCK

Simulation playback speed ile machine clock kesinlikle ayrılmalı.

Simulation:

```text
1×
2×
5×
10×
```

yalnız oyuncunun oyunu izleme hızıdır.

Machine clock gameplay'dir.

Overclock:

```text
Compute ↑
Power ↑
Heat ↑↑
```

Dolayısıyla:

```text
             SPEED
             /   \
          POWER—HEAT
```

ana optimization triangle olur.

---

# 14. HARD COMPONENT LIMIT KULLANMA

Şunu yapma:

```text
Maximum 2 Add units
```

veya:

```text
Only one Processor allowed
```

Bu yapay hissettirir.

Bunun yerine **soft constraints** kullan:

* board space
* data bandwidth
* power distribution
* heat generation
* cooling capacity
* wire congestion
* compute efficiency

İsterse oyuncu 40 Add koyabilsin.

Ama bunun fiziksel bedeli olsun.

---

# 15. POWER OVERHAUL

Power yalnız:

```text
Power 38 / 50
```

şeklinde global bir HUD barı olarak kalmamalı.

Başlangıçta Lab'ın sabit bir:

```text
LAB POWER INPUT
```

noktası olacak.

Buraya fiziksel bir adapter/PSU sistemi bağlanacak.

Başlangıç:

```text
Lab Power Input
       ↓
Starter Adapter
       ↓
Small Power Rail
       ↓
Components
```

---

# 16. POWER DISTRICT

Oyun ilerledikçe power kendi fiziksel fabrika bölgesine dönüşmeli.

Örneğin:

```text
┌──── POWER DISTRICT ────┐

Lab Input
   ↓
PSU
   ↓
Distribution Board
   ↓
Main Power Backbone

└────────────────────────┘
       │
       ├→ Compute
       ├→ Memory
       ├→ Cooling
       └→ I/O
```

Satisfactory'deki power generation/distribution area hissinin compute-lab karşılığı.

---

# 17. POWER COMPONENTS

Yeni power family:

### Fixed infrastructure

* Lab Power Input

### Insertable/upgradable supply

* Starter Adapter
* Mid Capacity Adapter
* High Capacity PSU

### Distribution

* Power Distribution Board
* Power Rail
* Heavy Power Rail
* Main Power Bus
* Local Power Branch

İleri oyun gerekirse:

* regulator
* transformer/converter

Ama MVP'de gereksiz elektrik mühendisliği karmaşasına girme.

---

# 18. PSU UPGRADE TEK BAŞINA YETMEMELİ

Önemli sistem:

```text
New PSU capacity: 120

Old main rail capacity: 40
```

Yeni PSU takılabilir.

Ama:

```text
USABLE CAPACITY: 40
```

çünkü distribution bottleneck var.

Oyuncu:

```text
PSU
↓
Distribution Board
↓
Main Rail
```

sistemini birlikte büyütmek zorunda.

Bu çok iyi factory progression yaratır.

---

# 19. POWER UYUMSUZLUĞU HARD LOCK OLMASIN

Şöyle deme:

> New PSU incompatible. Cannot install.

Bunun yerine:

> PSU installed, but current infrastructure limits delivery.

Bu daha doğal.

Örneğin:

```text
PSU output        120
Distribution       60
Main rail          40 ← bottleneck
Actual usable      40
```

---

# 20. POWER VİZÜEL DİLİ

Normal gameplay'de machine chassis üzerinde permanent:

```text
••••••
```

power indicators KULLANMA.

Bu sistem iptal edildi.

Çünkü scale etmiyor ve fake max-value hissi yaratıyor.

Yeni information hierarchy:

### Normal board

temiz.

### Hover

exact values.

### Inspector

full breakdown.

### Build card

cost/comparison.

### Power Overlay

whole-factory analysis.

---

# 21. PROCESSING COST INDICATOR DA CHASSIS'TEN KALDIRILACAK

Permanent tick pips kaldırılacak.

Processing süresi ana olarak:

* progress animation
* runtime motion
* hover details

ile anlatılacak.

Exact:

```text
Processing: 4 ticks
```

hover/Inspector'da görülecek.

---

# 22. COOLING / HEAT OVERHAUL

Eski fikir:

> Her component altına thermal plate/heatsink yerleştir.

ANA MEKANİK OLMAYACAK.

Bu repetitive ve görsel olarak kötü.

Cooling ayrı bir infrastructure network olacak.

---

# 23. COMPONENT THERMAL CONNECTION

Isı üreten relevant component'larda küçük bir:

```text
THERMAL CONTACT
```

bulunabilir.

Bu data port gibi görünmemeli.

Bakır / thermal hardware dili kullanmalı.

Buradan heat infrastructure bağlanabilir.

---

# 24. EARLY THERMAL NETWORK

İlk thermal gameplay:

```text
Processor
    │
    ╰══ Copper Heat Pipe ══→ Heatsink / Radiator
```

Birden fazla machine:

```text
ADD ──╮
MOD ──┼══ THERMAL HEADER ══→ Radiator
ALU ──╯
```

Bu, cooling'i fiziksel factory network haline getirir.

---

# 25. COOLING DISTRICT

Orta oyunda oyuncu ayrı cooling zone oluşturmalı.

Örneğin:

```text
┌────── COOLING DISTRICT ──────┐

Thermal Manifold
      ↓
Heat Pipes
      ↓
Blower / Radiator

└──────────────────────────────┘
```

Compute area başka yerde olabilir.

Bakır heat pipes compute cluster ile cooling district'i bağlar.

---

# 26. COOLING COMPONENTS

### Early

* Heatsink
* Blower/Fan
* Copper Heat Pipe
* Thermal Header / Manifold
* Radiator

### Mid/Late

* Pump
* Water Block / Cold Plate
* Coolant Pipe
* Reservoir
* Large Radiator

Gerekirse ileri oyunda:

* dual-loop systems
* advanced cooling

Ama bunları erken oyuna yığma.

---

# 27. LIQUID COOLING MILESTONE

Liquid cooling gerçek bir progression milestone olmalı.

```text
Radiator
   ↓
Pump
   ↓ cold line
┌──┼────────────┐
▼  ▼            ▼
ALU Memory   Processor
│  │            │
└──┴────────────┘
      ↓ hot line
    Radiator
```

Bu noktada cooling gerçekten kendi factory subsystem'i olur.

---

# 28. THERMAL CAPACITY

Cooling system yalnız görsel olmayacak.

Her thermal transport parçasının capacity'si olacak.

Örneğin:

```text
Heat Pipe capacity: 20 heat/tick
Radiator dissipation: 40 heat/tick
Pump flow: 30 heat-equivalent/tick
```

Ama normal board'da sayıları yazma.

Hover + Thermal Overlay kullan.

---

# 29. HEAT CONSEQUENCES

State ladder:

```text
NORMAL
WARM
HOT
THROTTLING
CRITICAL
```

NORMAL:
full performance.

WARM:
mostly visual warning.

HOT:
efficiency penalty başlayabilir.

THROTTLING:
clock düşer.

CRITICAL:
component temporarily stops until temperature falls.

Random explosion / permanent destruction kullanma.

---

# 30. THERMAL FAMILY VISUAL LANGUAGE

Canonical direction:

* copper
* dark PCB-compatible metals
* restrained amber
* board-level thermal infrastructure
* real heat-pipe / radiator / blower language

Thermal parts compute machines gibi görünmemeli.

No standard data ports.

No fake machine screens.

No excessive glow.

---

# 31. VFX OVERHAUL

Bütün VFX hierarchy yeniden standardize edilecek.

## Normal activity

Çok subtle.

## Processing

Local functional feedback.

## Warning

Noticeable.

## Critical/error

Strong attention allowed.

Rule:

> Strong visual intensity must be reserved for strong gameplay importance.

---

# 32. STATUS LED

Yeni Status LED canonical.

Eski 18px glow disc KULLANILMAYACAK.

Yeni:

* physical 6px lamp
* dark well
* thin rim
* small highlight

States:

```text
Waiting      amber dot
Throttling   amber + thin ring
Overheated   red + thin ring
Error        red diamond
```

Normal processing devasa lamp glow üretmemeli.

---

# 33. PORT / NODE GLOW

Eski kaba büyük glow efektleri kaldırılacak.

Veri porta girip çıkarken:

KULLANMA:

* giant bloom
* glowing blob
* large radial pulse

KULLAN:

* tiny contact flash
* small precise ring
* subtle port-edge pulse
* short signal shimmer

Mesaj:

> “signal made contact”

olmalı.

> “something exploded”

değil.

---

# 34. COMPONENT-SPECIFIC PROCESSING VFX

Generic whole-machine glow kullanılmayacak.

Örneğin:

### Add

progress ring.

### Splitter

incoming lane + selected branches.

### Merger

converging lane response.

### Gate

open/closed path.

### Buffer

occupancy visualization.

### Register

latch pulse.

### Mux/Demux

active path.

### Encoder

semantic input disappears, bits emerge.

### USB

tiny write/activity indicator.

---

# 35. CONTRACT DESIGN OVERHAUL

Factory growth'un ana sebebi contract sayısı OLMAYACAK.

Multiple simultaneous contracts ancak ileri oyunda yardımcı mechanic olabilir.

Ana progression:

> Tek veya az sayıda workload giderek mevcut fabrikanın kapasitesini zorlar.

---

# 36. CONTRACT'LAR MEVCUT HATTI EVRİMLEŞTİRMELİ

Örneğin:

### Stage A

```text
x + 2
1 value/s
```

```text
USB → Add → Output
```

### Stage B

```text
x + 2
4 values/s
```

Mevcut Add artık yetmez.

Lane upgrade / parallelism gerekir.

### Stage C

```text
x + 2
10 values/s
```

Data bus bottleneck olabilir.

### Stage D

```text
x + 2
10/s
Power ≤ available infrastructure
```

Power expansion gerekir.

### Stage E

```text
x + 2
10/s
Temperature safe
```

Cooling infrastructure gerekir.

Aynı logical operation tüm fabrikanın büyümesini sağlamış olur.

---

# 37. LOGIC COMPLEXITY DE KADEMELİ BÜYÜYECEK

Sürekli yalnız throughput görevi de istemiyoruz.

Örneğin:

```text
x + 2
```

sonra:

```text
(x + 2) mod 26
```

Eski Add kalır.

Modulo eklenir.

Sonra:

```text
if x > 10:
    (x + 2) mod 26
```

Mevcut Add + Modulo kalır.

Compare/Gate eklenir.

Sonra Text USB:

```text
Encoder
 ↓
Compare
 ↓
Add
 ↓
Modulo
 ↓
Decoder
```

Önceki hat giderek uzar.

---

# 38. PROGRESSION TASARIM KURALI

Yeni progression adımlarının çoğu:

> **existing factory + modification**

olmalı.

Sürekli:

> delete everything, build a new line

olmamalı.

Hedef:

yaklaşık `%60–80` progression step mevcut infrastructure'ı reuse/expand etsin.

Yeni architecture gerçekten gerektiğinde eski infrastructure mümkün olduğunca subsystem olarak yaşamaya devam etsin.

---

# 39. 8-BIT BYTE MILESTONE

Global default 8-bit YAPMA.

Early game:

```text
1-bit
3-bit
5-bit
```

kalacak.

Sonra 8-bit BYTE unlock önemli milestone olacak.

8-bit'e geçmek yeni problemler getirir:

* wider wires
* more bandwidth demand
* upgraded components
* width conversion
* larger buffers
* more compute
* more power
* more heat

Dolayısıyla BYTE unlock bütün fabrikayı etkilemeli.

---

# 40. WIDTH CONVERSION

Eski narrow systems hemen çöpe gitmemeli.

Örneğin:

```text
5-bit subsystem
      ↓
Width Converter
      ↓
8-bit backbone
```

Bu legacy infrastructure'ın yaşamaya devam etmesini sağlar.

Components:

* Zero Extend
* Sign Extend
* Truncate
* Generic Width Converter
* Bus Splitter
* Bus Combiner

---

# 41. THROUGHPUT / BANDWIDTH CONTRACTS

Contract yalnız:

```text
deliver 30 packets
```

dememeli.

Daha iyi:

```text
Deliver valid output
Minimum throughput: 8/s
```

veya:

```text
Process burst of 32 values
No packet loss
```

veya:

```text
Sustain 12/s for 20 seconds
```

Bu Buffer, lanes, bus bandwidth gibi sistemleri önemli yapar.

---

# 42. COMPUTE POWER KAVRAMI

“Compute power” tek global sayı olmak zorunda değil.

Asıl değerler:

```text
operation capacity
lanes
clock
processing time
```

olmalı.

Fakat UI gerektiğinde aggregate:

```text
Arithmetic Capacity
Logic Capacity
Memory Bandwidth
```

gösterebilir.

---

# 43. COMPONENT FAMILY — CORE COMPUTE

Implement/keep:

### Arithmetic

* Add
* Subtract
* Increment
* Decrement
* Multiply
* Modulo

### Logic

* AND
* OR
* XOR
* NOT
* Shift Left
* Shift Right

### Comparison/control

* Compare
* Gate
* Counter
* Delay

### Routing

* Splitter
* Merger
* Mux
* Demux
* Conditional Router

### Buffering

* Buffer
* Queue

---

# 44. REPRESENTATION / DATA COMPONENTS

* Number Encoder
* Number Decoder
* Character Encoder
* Character Decoder
* Binary Viewer
* Decimal Viewer
* Signed Decimal Viewer
* Hex Viewer
* Character Viewer

Viewer does NOT change underlying data.

---

# 45. WIDTH / BUS COMPONENTS

* Width Converter
* Zero Extend
* Sign Extend
* Truncate
* Bus Splitter
* Bus Combiner
* later bandwidth adapters/repeaters if needed

Do not add arbitrary adapters just to create busywork.

---

# 46. MEMORY COMPONENTS

Later progression:

* Register
* Register Bank
* ROM
* RAM

Memory introduces:

* capacity
* access latency
* memory bandwidth
* possibly power/heat

---

# 47. ADVANCED COMPUTE

Later:

* ALU
* Program Counter
* Instruction Decoder
* Control Unit
* CPU-like composite architecture

These must emerge naturally from previously learned primitives.

Do not jump to CPU early.

---

# 48. COMPONENT COMPRESSION / MODULES

Once factories become physically large, introduce:

```text
Custom Module / Blueprint
```

Player can select:

```text
Encoder
→ Add
→ Modulo
→ Decoder
```

and save as:

```text
CAESAR UNIT
```

Then instantiate:

```text
[CAESAR UNIT]
```

Possibly double-click to inspect internals.

This prevents late-game factory from becoming unreadable while preserving player-created architecture.

---

# 49. POWER COMPONENT FAMILY

Add:

* Lab Power Input
* Starter Adapter
* Improved Adapter
* High Capacity PSU
* Distribution Board
* Power Rail
* Heavy Power Rail
* Main Power Backbone

Later only if needed:

* regulator
* transformer

---

# 50. THERMAL COMPONENT FAMILY

Early:

* Thermal Connector
* Copper Heat Pipe
* Thermal Manifold/Header
* Heatsink
* Blower
* Radiator

Mid/Late:

* Pump
* Cold Plate / Water Block
* Coolant Pipe
* Reservoir
* Large Radiator

Cooling should become its own infrastructure district.

---

# 51. REMOVED / SUPERSEDED SYSTEMS

The following ideas are now explicitly removed or demoted:

### REMOVE

Permanent power pip rows on machines.

### REMOVE

Permanent processing/tick pips.

### REMOVE

Large normal activity glow.

### REMOVE

Big port/node glow blobs.

### REMOVE

Generic full-chassis processing highlight.

### REMOVE

Mandatory thermal plate under every machine.

### REMOVE

Hard duplicate/component-count restrictions.

### REMOVE

“Factory grows mainly because many unrelated missions are simultaneously running.”

### REMOVE

“Every new mission deserves a completely separate line.”

### REMOVE

Unlimited placeable USB Input machines.

### REMOVE

Global 8-bit assumption.

### DEMOTE

Concurrent contracts to an optional later mechanic.

### KEEP

Persistent Lab.

### KEEP

BitVector core.

### KEEP

Deterministic simulation.

### KEEP

Smooth visual interpolation.

### KEEP

Live routed wire preview.

### KEEP

Atomic rewiring.

---

# 52. INFORMATION UX

Canonical information hierarchy:

## Normal gameplay

Minimal, clean.

## Hover

Quick exact information.

Show:

```text
Component
Width
Lanes
Rate
Power
Heat
Temperature
State
```

## Click / Inspector

Detailed configuration.

## Overlay

Whole-factory analysis.

---

# 53. OVERLAYS

Create separate overlays:

### Data Overlay

* width
* bandwidth
* utilization
* bottlenecks

### Power Overlay

* supply
* distribution capacity
* load
* overloaded segments

### Thermal Overlay

* temperatures
* heat flow
* radiator capacity
* thermal bottlenecks

Potential later:

### Compute Overlay

* utilization
* operations/tick
* idle/busy lanes

Normal board must remain calm.

---

# 54. HOVER UX

Hover ~150–200 ms.

Compact card appears slightly above/right of pointer.

It follows mouse without covering target.

Disappears during:

* drag
* wire placement
* destructive action

Click gives persistent Inspector.

---

# 55. QUICK ACTIONS

Selected component gets compact local menu:

```text
Move
Duplicate
Rotate
Copy Settings
Upgrade
Delete
```

Dedicated Delete mode should no longer be required for ordinary deletion.

---

# 56. FAST BUILD QoL

Implement:

* direct port drag starts wire
* nearest compatible port assist
* component-body smart target
* atomic rewire
* connected-component live reroute
* Alt+drag duplicate
* Ctrl+D duplicate
* copy settings
* undo/redo
* multi-select later
* build search
* favorites
* recent components

---

# 57. CONNECTED COMPONENT MOVE

When moving:

```text
machine + attached wires
```

move together.

Wires reroute live.

If all valid:

commit atomically.

If invalid:

restore original state.

Do not force manual disconnect/reconnect.

---

# 58. CAMERA

* middle mouse pan
* Space+drag optional
* zoom toward cursor
* smooth zoom
* mild inertia
* optional edge-pan

Interactions take priority over camera movement.

---

# 59. PLAYBACK CONTROLS

```text
1 → 1×
2 → 2×
3 → 5×
4 → 10×
```

Separate completely from machine clock.

---

# 60. NEW MACRO PROGRESSION

Recommended structure:

### ERA 1 — Tiny Logic

```text
USB → simple operation → Output
```

Learn:

* bits
* widths
* Add
* simple wires

---

### ERA 2 — Throughput

Same logical line must handle more load.

Unlock:

* lanes
* Splitter/Merger
* Buffer
* basic bandwidth

---

### ERA 3 — Representation

Unlock:

* Text USB
* Encoders/Decoders
* 5-bit alphabet
* Modulo

---

### ERA 4 — Routing

Unlock:

* Compare
* Gate
* Mux/Demux
* Conditional Router

Main line branches but shares infrastructure.

---

### ERA 5 — Power

Compute capacity increases enough that Starter Adapter fails.

Unlock:

* PSU
* Distribution Board
* Power Rail

Now factory gains a Power District.

---

### ERA 6 — Thermal

Upgraded/parallel compute generates serious heat.

Unlock:

* Copper Heat Pipe
* Heatsink
* Blower
* Radiator
* Thermal Overlay

Cooling District appears.

---

### ERA 7 — Multi-input

Second USB socket unlocks.

Use:

```text
Data USB
Key USB
```

for synchronized processing.

Not primarily for making two unrelated factories.

---

### ERA 8 — BYTE

8-bit milestone.

Unlock:

* 8-bit buses
* width conversion
* larger buffers
* upgraded machines

Infrastructure must evolve.

---

### ERA 9 — Infrastructure Scale

Unlock:

* heavier data buses
* heavy power backbone
* better PSU
* larger cooling systems
* advanced component lanes

---

### ERA 10 — Liquid Cooling

High-density compute makes copper/passive systems inefficient.

Unlock cooling loop.

---

### ERA 11 — Memory

Registers/RAM/ROM.

Introduce:

* storage
* latency
* memory bandwidth

---

### ERA 12 — ALU

Primitive arithmetic/logic concepts combine into structural compute.

---

### ERA 13 — CPU / Programmable Computer

Lab finally resembles a real programmable computer.

---

### ERA 14 — Cluster

Multiple high-level compute units and advanced workloads.

Only here should true multi-computer scale become central.

---

# 61. WHAT SHOULD PHYSICALLY GROW?

At the beginning:

```text
[USB] → [ADD] → [OUT]
```

Later screenshot should naturally contain:

```text
POWER DISTRICT
PSU
Distribution
Power backbone

INPUT DISTRICT
USB peripherals
Encoders

DATA BACKBONE
wide high-bandwidth buses

COMPUTE DISTRICT
upgraded multi-lane arithmetic
logic
routing
buffers

MEMORY DISTRICT
registers
RAM

COOLING DISTRICT
thermal manifolds
copper heat pipes
pump
radiators

OUTPUT SYSTEM
decoding
contract drive
```

The board must visibly tell the history of the player's machine.

---

# 62. PENPOT OVERHAUL FIRST

Claude owns this stage.

Do NOT ask DS to invent visuals.

Update Penpot for:

* evolving wire width
* bandwidth-class bus visuals
* compute lane upgrades
* upgraded component chassis
* Lab Power Input
* adapters/PSUs
* Distribution Board
* power rails/backbone
* power connection language
* thermal connectors
* copper heat network
* thermal manifold
* heatsink
* blower
* radiator
* liquid cooling family
* overlays
* hover/Inspector
* upgrade UI
* bottleneck visualization
* new USB C-style integrated design
* restrained VFX
* factory-scale scenes

---

# 63. REQUIRED PENPOT TEST SCENES

Design at real gameplay scale:

### Scene A

Early 3-bit factory.

### Scene B

Parallel upgraded Add system.

### Scene C

8-bit data backbone.

### Scene D

Power District feeding Compute District.

### Scene E

Copper Cooling District.

### Scene F

Liquid cooling late-game cluster.

### Scene G

Full dense Lab:
Data + Power + Cooling + Compute simultaneously.

The board must remain readable.

---

# 64. DESIGN LOCK

After Penpot:

update docs:

```text
ARCHITECTURE.md
IMPLEMENTATION.md
STYLE_GUIDE.md
VISUAL_SYSTEM.md
MOTION_SYSTEM.md
COMPONENT_ROADMAP.md
PROGRESSION.md
```

Add new document if useful:

```text
FACTORY_SYSTEMS.md
```

Then commit:

```text
Factory growth overhaul design locked
```

Only after this begin implementation.

---

# 65. IMPLEMENTATION STRATEGY — DS

Claude is orchestrator/reviewer.

DS writes routine implementation.

Do not send a giant “implement overhaul” request.

Break it into isolated jobs.

### DS Phase 1

Capacity model foundation:
width, bandwidth, lanes, compute rate.

### DS Phase 2

Upgradeable component model.

### DS Phase 3

Data bus capacity / bottleneck system.

### DS Phase 4

External USB + Encoder/Decoder model.

### DS Phase 5

Power supply simulation.

### DS Phase 6

Physical power distribution network.

### DS Phase 7

Thermal generation/diffusion core.

### DS Phase 8

Thermal transport network.

### DS Phase 9

Cooling components.

### DS Phase 10

Upgrade UI and component visuals.

### DS Phase 11

Data/Power/Thermal overlays.

### DS Phase 12

QoL overhaul.

### DS Phase 13

Progression rewrite.

### DS Phase 14

Remaining compute components.

### DS Phase 15

Memory/advanced systems foundation.

### DS Phase 16

VFX / animation polish.

---

# 66. DS RULES

Every DS task must specify:

* exact goal
* exact files or subsystem
* architectural constraints
* tests
* acceptance criteria
* non-goals

Claude must review output before next stage.

Use cheaper DS route for repetitive implementation.

Use strongest route only for difficult architecture:

* thermal simulation
* power network
* upgrade migration
* complex routing
* save migration

---

# 67. SAVE SYSTEM

Existing Lab saves must be versioned.

Persist:

* board expansion
* placed components
* connections
* component upgrades
* lane count
* widths
* clock configuration
* data infrastructure
* PSU
* power distribution
* cooling infrastructure
* USB devices
* progression
* unlocked technologies

Provide migrations.

---

# 68. TESTS

Add tests for:

### Data

* width compatibility
* bus throughput
* bandwidth saturation
* width conversion

### Compute

* lanes
* processing rate
* upgrade behavior
* overclock

### Power

* PSU capacity
* distributor capacity
* rail bottleneck
* overload
* upgrade path

### Thermal

* heat generation
* transport
* dissipation
* heat pipe limits
* fan/radiator
* throttling
* liquid loop later

### Gameplay

* contract throughput
* reuse of previous infrastructure
* USB transitions
* save/load
* upgrades

### Interaction

* wire assist
* reroute
* undo
* duplicate
* copy settings

---

# 69. BALANCE PRINCIPLE

Do not make every new contract introduce a new component.

A healthy rhythm is closer to:

```text
Learn something
↓
Use it
↓
Hit capacity limit
↓
Optimize it
↓
Combine it with previous mechanic
↓
Only then unlock something new
```

The player needs time to actually own the architecture.

---

# 70. THE FINAL PLAYER EXPERIENCE

The game should begin as:

```text
USB → Add → Output
```

and several hours later the player should look at the **same Lab** and see:

```text
      POWER BACKBONE
            │
USB → ENCODING → DATA BUS → ROUTING
                         ↓
                 COMPUTE CLUSTER
                  ↓     ↓
               MEMORY   ALU
                  ↓     ↓
                   OUTPUT
                     │

         COPPER / LIQUID
          COOLING PLANT
```

And be able to say:

> **“This is still the little machine I started with. I had to turn it into this monster because the workloads kept getting harder.”**

That is the factory-growth fantasy we are targeting.

---

## Definition of Done

Bu overhaul ancak şu durumda tamamlanmış sayılacak:

* yeni görevler sürekli bağımsız hat kurmaya zorlamıyor;
* eski fabrikanın önemli bölümü progression boyunca reuse ediliyor;
* compute component'ları width/lane/clock açısından gelişebiliyor;
* data hatlarının gerçek width ve bandwidth kapasitesi var;
* 8-bit ve ilerisi fiziksel olarak daha ağır infrastructure gerektiriyor;
* power yalnız global sayı değil, fiziksel distribution system;
* yeni PSU eski dağıtımın kapasitesiyle sınırlanabiliyor;
* cooling her makinenin altına plaka koymak değil, gerçek ayrı infrastructure;
* copper heat network çalışıyor;
* ileride liquid cooling progression mevcut;
* power/cooling/data bölgeleri fabrikanın fiziksel olarak büyümesini sağlıyor;
* hard component-count limits yok;
* permanent chassis resource pips kaldırılmış;
* normal VFX sakin;
* critical durumlar gerçekten dikkat çekiyor;
* USB visual system canonical C direction'a taşınmış;
* contract progression throughput/capacity/architecture üzerine kurulu;
* aynı Lab başlangıçtan ileri oyuna kadar görünür biçimde evrimleşiyor;
* QoL nedeniyle oyuncu UI ile değil **mimari problemle** uğraşıyor.

**Bence bundan sonra tasarımın ana omurgası bu olmalı.** Özellikle artık yeni component düşünürken ilk soru “bu eğlenceli mi?”den hemen sonra **“bu mevcut fabrikayı büyütüyor mu, yoksa yanına bir mini puzzle daha mı ekliyor?”** olmalı. İkinciyse çoğu durumda o sistemi yeniden tasarlamak gerekir.

