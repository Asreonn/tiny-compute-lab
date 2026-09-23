# Agent notes — Tiny Compute Lab (Godot 4.7, GDScript)

- Test: `make test` (imports first, then runs `tests/run_tests.gd` headless; exit 0 = pass).
  A NEW `class_name` script is only visible after the import step, so always use `make test`.
- Read `docs/ARCHITECTURE.md` before changing code. Hard rules:
  - `core/` and `game/` are pure data + deterministic simulation: no `Node`, no `_process`,
    no unseeded RNG, iterate by ascending id.
  - Views (`world/`, `ui/`) only READ simulation state; edits go through `Simulation` methods.
  - All data is a `BitVector`; NUMBER/CHAR/HEX are `ViewMode` interpretations only.
- Visual style is LOCKED (`docs/STYLE_GUIDE.md`). Use the exported assets in `assets/art/` and
  tokens from `core/visual/palette.gd`; never invent new colours, shapes or materials.
- GDScript style: tabs, typed vars where practical, `##` doc comments, match surrounding code.
- Never commit; the orchestrator reviews and commits.
