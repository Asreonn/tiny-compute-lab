# Tiny Compute Lab — MVP Game Design Plan

## 1. High Concept

Tiny Compute Lab, oyuncunun küçük bir bilgisayar/laboratuvar alanında veri işleyen makineler kurduğu 2D factory/logic oyunudur.

Oyuncu klasik factory oyunlarındaki gibi maden çıkarmaz. Ana kaynak:

**data + compute + space + throughput**

Oyuncuya görev gelir:

> Input verisini istenen output'a dönüştür.

Bunu yapmak için grid üzerine component'lar yerleştirir, kablo çeker ve çalışan bir compute pipeline kurar.

Örnek:

```text
Input
  ↓
Multiply ×2
  ↓
Add +5
  ↓
Output
```

Görev:

```text
Input: 10
Expected output: 25
```

Oyuncu sistemini çalıştırır.

Doğru sonuç üretmesi yetmez.

Sonraki görevlerde:

```text
Accuracy
Throughput
Latency
Power
Space
```

gibi değerler önem kazanmaya başlar.

---

# 2. MVP'nin amacı

MVP'nin amacı “tam bilgisayar simülatörü” yapmak değildir.

MVP şu soruya cevap vermelidir:

> Component yerleştirmek, kablo çekmek ve veri paketlerinin sistemin içinde akmasını izlemek eğlenceli mi?

MVP sonunda oyuncu şu akışı yaşayabilmeli:

```text
Görev al
↓
Input'u incele
↓
Component yerleştir
↓
Portları bağla
↓
Simülasyonu çalıştır
↓
Data packet'ları izle
↓
Hata bul
↓
Sistemi değiştir
↓
Görevi tamamla
↓
Yeni component aç
```

Bu loop eğlenceliyse oyun büyütülür.

---

# 3. MVP Scope

MVP'de olmayacak şeyler:

```text
CPU assembly
RAM architecture
GPU
Image processing
Machine learning
Neural networks
Component crafting
Resource mining
Multiplayer
Procedural world
Story campaign
Electrical voltage simulation
Transistor-level simulation
```

Ama architecture bunların sonradan eklenmesini engellememeli.

MVP sadece:

```text
Scalar numbers
Boolean signals
Basic operations
Routing
Buffers
Throughput
Simple optimization
```

üzerinden ilerleyecek.

---

# 4. Game World

## View

```text
2D Top Down
Orthographic
Square grid
```

Önerilen başlangıç grid'i:

```text
32 × 20 tiles
```

Bir component genelde:

```text
1×1
2×1
2×2
```

alan kaplar.

MVP'de kamera:

```text
Pan
Zoom
Reset view
```

destekler.

---

# 5. Visual Identity

Tema:

```text
Motherboard
+
Miniature factory
+
Laboratory
```

Arka plan düz bir grid değil, hafif PCB hissi vermeli.

Component'lar okunabilir ve mekanik görünmeli.

Örnek:

```text
╔════════════╗
║    ADD     ║
║ A ●    ● Y ║
║ B ●        ║
╚════════════╝
```

Portlar belirgin olmalı.

Input port:

```text
○
```

Output:

```text
●
```

Data paketleri kablolarda fiziksel olarak hareket etmeli.

Örneğin:

```text
●──────•──────•──────●
```

Bu oyunun ana görsel feedback mekanizmasıdır.

---

# 6. Core Data Model

Her veri bir:

```text
DataPacket
```

olarak temsil edilir.

MVP packet:

```text
DataPacket

type:
NUMBER
BOOLEAN

value:
Variant

packet_id

created_tick
```

Sonradan:

```text
VECTOR
TEXT
IMAGE
MATRIX
INSTRUCTION
```

eklenebilir.

---

# 7. Simulation Model

Simülasyon render FPS'den bağımsız olmalıdır.

Önerilen tick:

```text
10 ticks / second
```

Normal:

```text
1×
```

Fast forward:

```text
2×
4×
```

Pause:

```text
0×
```

Her tick:

```text
Connections move packets
↓
Components receive packets
↓
Ready components process
↓
Outputs generate packets
↓
Mission statistics update
```

Simülasyon deterministic olmalıdır.

Aynı input + aynı layout:

```text
aynı output
aynı latency
aynı throughput
```

üretmeli.

---

# 8. Component Architecture

Her component aynı temel interface'i kullanır.

```text
Component
```

Base properties:

```text
component_id

grid_position

input_ports[]
output_ports[]

processing_ticks

buffer_capacity

power_cost

enabled
```

Core function:

```text
can_process()

process()

receive_packet()

emit_packet()
```

Component behavior görsel Node'dan ayrılmalıdır.

Önerilen yapı:

```text
ComponentData
ComponentLogic
ComponentView
```

Bu çok önemli.

Game logic'i Godot node hierarchy'sine fazla bağlarsak oyun büyüyünce problem çıkar.

---

# 9. MVP Components

MVP için yaklaşık 12 component yeterli.

| Component | Görev                                     |
| --------- | ----------------------------------------- |
| Input     | Görev datasını sisteme verir              |
| Output    | Final sonucu toplar                       |
| Wire      | Data taşır                                |
| Splitter  | Bir input'u iki yola gönderir             |
| Merger    | İki hattı tek output hattında birleştirir |
| Add       | X + sabit veya A+B                        |
| Multiply  | X × sabit veya A×B                        |
| Compare   | `>`, `<`, `==`                            |
| Gate      | Boolean değerine göre data geçirir        |
| Buffer    | Packet depolar                            |
| Delay     | Belirli tick kadar bekletir               |
| Counter   | Gelen packet sayısını sayar               |

İlk MVP build'de hepsinin olması şart değildir.

Minimum playable:

```text
Input
Output
Wire
Add
Multiply
Compare
Splitter
Buffer
```

ile başlayabilir.

---

# 10. Ports

Her component açıkça tanımlanmış portlara sahip olur.

Örneğin Add:

```text
┌────────────┐
A ○          │
             ● Result
B ○          │
└────────────┘
```

Ama MVP'de bazı component'larda constant değer kullanılabilir.

Örneğin:

```text
ADD
constant = 5
```

Pipeline:

```text
Input
 ↓
ADD +5
 ↓
Output
```

Daha sonra:

```text
Input A ─┐
         ADD → Output
Input B ─┘
```

modeline geçebiliriz.

---

# 11. Connection System

Kablo placement oyunun en önemli UX noktalarından biri.

Flow:

```text
Output port'a tıkla
↓
Mouse sürükle
↓
Input port'a bırak
↓
Connection oluşur
```

Cable otomatik grid route kullanabilir.

MVP'de tam Factorio belt routing gerekmez.

Connection:

```text
source_component
source_port

target_component
target_port

travel_ticks
bandwidth
```

MVP bandwidth:

```text
1 packet / tick
```

olarak sabit olabilir.

Sonradan:

```text
Fast Bus
32-bit Bus
Fiber
Parallel Link
```

gibi upgrade'ler eklenebilir.

---

# 12. Data Packet Visualization

Packet'ların görünmesi şart.

Örneğin sayı:

```text
[42]
```

olarak kablo üzerinde ilerleyebilir.

Zoom uzak olduğunda sadece küçük ışık noktası.

Zoom yakın:

```text
42
```

görülür.

Packet renklerini veri tipine göre ayırabiliriz.

Ama MVP için iki type yeterli:

```text
NUMBER
BOOLEAN
```

---

# 13. Build Mode

Oyuncunun ana toolbar'ı:

```text
Select
Wire
Delete

Input
Output

Math
Logic
Routing
Storage
```

Component seçildiğinde ghost preview çıkar.

```text
valid tile
invalid tile
```

feedback'i olmalı.

Placement:

```text
Left click → place
R → rotate
Right click → cancel
Delete → remove
```

---

# 14. Inspect Mode

Component seçildiğinde sağ panel açılır.

Örneğin:

```text
MULTIPLIER

Value
× 4

Processing Time
2 ticks

Power
2

Packets Processed
148

Current State
BUSY
```

Component parametreleri buradan değiştirilebilir.

MVP'de:

```text
Add constant
Multiply constant
Compare threshold
Delay ticks
```

değiştirilebilir.

---

# 15. Mission System

Her level bir:

```text
MissionDefinition
```

resource'u olur.

Örneğin:

```text
Mission 01

Input:
5

Expected:
10

Allowed components:
Multiply

Goal:
Correct output
```

Sonraki görev:

```text
Input stream:
2
15
7
21
3

Goal:
Only output numbers > 10
```

Mission validation:

```text
correct output
incorrect output
missing output
extra output
```

hesaplayabilmeli.

---

# 16. MVP Mission Campaign

| Mission             | Öğrettiği şey               |
| ------------------- | --------------------------- |
| Boot Sequence       | Input → Output              |
| Double It           | Multiply                    |
| Offset              | Add                         |
| Decision            | Compare                     |
| Filter              | Compare + Gate              |
| Fork                | Splitter                    |
| Traffic             | Buffer                      |
| Production Line     | Continuous input            |
| Parallel Processing | Split + multiple processors |
| Optimization        | Throughput requirement      |

İlk görev:

```text
Input → Output
```

Oyuncuya hiçbir şey öğretmeden önce sistemin nasıl aktığını gösterir.

Mission 2:

```text
x → x × 2
```

Mission 3:

```text
x → x + 10
```

Mission 4:

```text
x > 20
```

Mission 5:

```text
Only pass values > 20
```

Mission 6:

```text
Process two data streams
```

Mission 7:

```text
Handle packets faster than one processor can process.
```

Oyuncu burada splitter öğrenir.

---

# 17. Throughput

Throughput factory hissinin temelidir.

Görev:

```text
Incoming:
10 packets/sec

Current system:
4 packets/sec
```

UI:

```text
INPUT RATE
10/s

OUTPUT RATE
4/s

BOTTLENECK
Multiplier
```

Oyuncu:

```text
               ┌→ Multiply ─┐
Input → Splitter             Merger → Output
               └→ Multiply ─┘
```

yapar.

Throughput:

```text
8/s
```

Sonra üçüncü processor.

Bu mekanik sayesinde oyun sadece puzzle değil:

> factory optimization game

olur.

---

# 18. Latency

Her packet'ın:

```text
created_tick
completed_tick
```

değerleri tutulur.

Latency:

```text
completed_tick - created_tick
```

olarak hesaplanır.

MVP görevlerinde latency zorunlu hedef olmak zorunda değil.

Ama stats'ta gösterilmeli.

Örneğin:

```text
Average latency
12 ticks

Best
8 ticks

Worst
22 ticks
```

---

# 19. Power

Power sistemi MVP'de basit olabilir.

Her component:

```text
Power Cost
```

taşır.

Örneğin:

```text
Wire 0
Add 1
Multiply 2
Buffer 1
```

Mission:

```text
Power limit: 20
```

Sonradan oyuncu:

```text
daha yavaş ama verimli
vs
daha hızlı ama enerji tüketen
```

architecture kurabilir.

---

# 20. Space Constraint

Board sınırsız olmamalı.

İlk level:

```text
16 × 12
```

Sonraki:

```text
20 × 16
```

Alan da bir resource olur.

Bu oyuncuyu spaghetti wiring yerine daha kompakt tasarımlar yapmaya iter.

---

# 21. Scoring

İlk MVP'de yıldız sistemi olabilir.

Mission completion:

```text
PASS
```

Ek objectives:

```text
Power < 15
Latency < 20
Components < 12
```

Sonuç:

```text
★★★
```

Ama oyuncu yıldız alamasa bile mission tamamlayabilir.

Bu önemli.

Optimization zorunlu olmamalı.

---

# 22. Failure Feedback

Hata mesajları çok net olmalı.

Kötü:

```text
MISSION FAILED
```

İyi:

```text
Expected:
24

Received:
22

Packet:
#143
```

ve sistem o packet'ın geçtiği path'i highlight edebilmeli.

Örneğin:

```text
Input
 ↓
Multiply  ← highlight
 ↓
Add
 ↓
Output
```

Bu debugging sistemi oyunun büyük parçası olacak.

---

# 23. Simulation Debugging

Pause sırasında oyuncu packet seçebilmeli.

Packet info:

```text
Packet #238

Value
42

Created
Tick 120

Current location
Buffer #4

Path
Input → Splitter → Multiply → Buffer
```

Sonradan bu sistem CPU debugging için de kullanılabilir.

---

# 24. Save System

MVP save:

```text
current mission
unlocked components
best mission score
```

Layout save:

```text
component type
position
rotation
settings
connections
```

JSON/resource bazlı olabilir.

Simulation state'i save etmek MVP için gerekli değil.

Level yeniden açıldığında simülasyon sıfırdan başlar.

---

# 25. Godot Project Structure

Önerilen:

```text
res://

core/
    simulation/
    data/
    components/
    connections/

game/
    missions/
    progression/

ui/
    build_menu/
    inspector/
    stats/
    mission/

world/
    grid/
    camera/

assets/

resources/
    components/
    missions/
```

---

# 26. Godot Scene Architecture

Main:

```text
Game
├── World
│   ├── Grid
│   ├── ComponentLayer
│   ├── ConnectionLayer
│   └── PacketLayer
│
├── SimulationManager
│
├── BuildManager
│
├── MissionManager
│
├── Camera2D
│
└── UI
```

Component scene:

```text
ComponentView
├── Sprite
├── InputPorts
├──
```

