# Tiny Compute Lab — Performance

## Probe

```
timeout 60 godot --path . --fixed-fps 60 --disable-vsync -s tools/perf_probe.gd -- <level> <frames> <speed> [off] [--micro]
```

The probe boots `main.tscn` in the Lab, loads the reference solution of `<level>`
(`Solutions.lab_solution`) and plays it at `<speed>`. It prints:
- the average and p95 frame time;
- Godot's render CPU/GPU time;
- draw calls.

**Options:**

| Option | Effect |
|---|---|
| `off <path>` | hides one view (or `noproc:<path>` stops its `_process`), to find what costs |
| `--micro` | times each part separately, headless: every view's `refresh`, `Simulation.step`, the ticked handlers, the autosave, the undo snapshot, `World._sync_layout` and `sim.changed` |

**Measurement notes:**
- Headless runs need the low-processor sleep off; the probe does that.
- Windowed runs need `--fixed-fps 60 --disable-vsync`.
- An empty scene is about 3.4 ms windowed.
- Compare interleaved runs against a baseline worktree, not against numbers from another session.

## Results of the 2026-09-26 pass (commit `9b4792e`, L13 and L21 at 10×)

| Metric | Before | After |
|---|---|---|
| Windowed frame (avg) | ~13.1 ms | ~8.4 ms |
| Windowed frame (p95) | ~17.6 ms | ~13.6 ms |
| Layout change (place/wire) | ~6.0 ms | ~0.6 ms |
| `Simulation.step` | ~1.1 ms | ~0.5 ms |
| Thermal step | 439 µs | 62 µs |
| Tick handlers | 853 µs | 39 µs |

## What made the difference (keep these patterns)

- **Incremental views.**
  - `World._sync_layout()` diffs views by `MachineView.view_key` and `ConnectionView.key_of`
    instead of rebuilding.
  - `on_layout()` refreshes port sprites.
- **Change-driven redraws.**
  - Machine texts are keyed by tick, view mode and running state.
  - Wires re-apply layers only when their state key changes.
  - Board, desk and contract drive split into a static painter and an animated `*Fx` child
    (`show_behind_parent`).
- **Warm-box thermal grid.** Diffusion and dissipation visit only the bounding box of warm tiles
  (+1). Tiles outside it stay exactly 0, so the result is bit-identical.
- **Deferred autosave.** `sim.changed` queues one coalesced `_autosave` per frame.
- **HUD.** `HudKit.set_color` only overrides on change; `_roll_metric` skips unchanged values.

Every new painter in the factory overhaul (lane slices, rails, liquid parts, overlays) must follow
the same pattern: a view key plus a tick key, and no per-frame `queue_redraw` unless it is animating.
