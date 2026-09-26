# Agent notes — Tiny Compute Lab (Godot 4.7, GDScript)

- Test: `make test` (imports first, then runs `tests/run_tests.gd` headless; exit 0 = pass).
  `make check` = tests + every headless smoke (`make smoke`); run it before handing work back.
  A NEW `class_name` script is only visible after the import step, so always use `make test`.
- ALWAYS wrap ad-hoc Godot runs in `timeout 60 godot ...`. A SceneTree script that `await`s frames
  (especially under `--headless`) can hang forever. Screenshots need a real renderer: use
  `timeout 60 godot --path . -s tools/shot.gd -- <mission> <out.png>` (no `--headless`).
- Read `docs/ARCHITECTURE.md` before changing code. Hard rules:
  - `core/` and `game/` are pure data + deterministic simulation: no `Node`, no `_process`,
    no unseeded RNG, iterate by ascending id.
  - Views (`world/`, `ui/`) only READ simulation state; edits go through `Simulation` methods.
  - All data is a `BitVector`; NUMBER/CHAR/HEX are `ViewMode` interpretations only.
- Visual style is LOCKED (`docs/STYLE_GUIDE.md`). Use the exported assets in `assets/art/` and
  tokens from `core/visual/palette.gd`; never invent new colours, shapes or materials.
- Content is data: machines, sticks, levels and campaign rules are `.tres` assets under `content/`
  (`docs/CONTENT.md`). Add or tune content there, not in code tables.
- The factory systems (bus/compute lanes, power network, thermal caps) are specified in
  `docs/FACTORY_SYSTEMS.md`. Performance: `tools/perf_probe.gd`, `docs/PERFORMANCE.md`. New views must
  be change-driven.
- GDScript style: tabs, typed vars where practical, `##` doc comments, match surrounding code.
- Never commit; the orchestrator reviews and commits.
