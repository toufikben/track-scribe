# Fidelity baseline — 2026-10-09 (measured 2026-10-11)

The precondition for any sentence about track fidelity: a table of
`scenario | engine distance | truth | error %`. Nothing in this file may
claim a field distance it did not measure.

## Harness calibration (synthetic — never cited as device evidence)

Fixture: `test/evidence/fixtures/synthetic/walk-1km.gpx` — 716 points at
1 Hz, 1.4 m/s forward drift plus **independent ±10 m scatter** (fixed seed 42;
ruling R98, which superseded R92's smooth random walk because that walk was so
gentle a gate-free odometer scored better on it than the engine — see
`test/evidence/synthetic_injection_test.dart`). Generated with
`dart run tool/replay.dart --gen … --metres 1000 --speed 1.4 --jitter 10`;
ground truth exact by construction. GPX 1.1 carries no accuracy field (ruling
R95), so the replay injects one — and the injected value is part of the
scenario, not a detail.

All rows below are the printed output of
`dart run tool/replay.dart test/evidence/fixtures/synthetic/walk-1km.gpx --truth 1000 --sport X --accuracy Y`.

| scenario | accuracy injected | engine distance | truth | error % |
|---|---|---|---|---|
| walk-1km.gpx replayed as walk | 10 m (matches the fixture's noise) | 1004.6 | 1000.0 | 0.46 |
| walk-1km.gpx replayed as run | 10 m | 999.5 | 1000.0 | 0.05 |
| walk-1km.gpx replayed as walk | 5 m (the tool default — understates this noise) | 1080.9 | 1000.0 | 8.09 |
| walk-1km.gpx replayed as run | 5 m | 1450.9 | 1000.0 | 45.09 |

Two things this table shows, and only these:

1. **The harness agrees with the engine test.** Row 1 (1004.6 m) is the same
   scenario the injection suite runs in-process, and it produces the same
   number to 0.1 m — the GPX path is not measuring a different engine.
2. **The engine's accuracy claim is load-bearing.** The identical track is
   within 0.46 % when the fix reports accuracy equal to its real error, and
   8–45 % inflated when the fix reports half of it, because ر3's store gate is
   `max(3, 2 × reported accuracy)` — reported accuracy is the only yardstick
   the engine has for noise. That is a measured risk for the device phase, not
   a hypothetical: whatever Geolocator reports on the Realme has to be close to
   the truth, and the field protocol below is what tests it.

### Synthetic injection suite (`test/evidence/synthetic_injection_test.dart`, 4 tests)

All pass locally. Each scenario also asserts the engine beats a gate-free
odometer on the same fixture, so a broken engine cannot pass it:

- 1000 m walk, ±10 m noise, accuracy 10 → engine 1004.6 m (0.46 %), odometer
  4906.1 m (390.6 %) — spec §8 item 1's 1 % bar, with discrimination restored.
- The same scenario across 50 noise seeds: worst 3.66 %, median ≈0.9 %,
  **23/50 above the 1 % bar**. So "under 1 %" is a property of the seed the
  spec's scenario pins, not a guarantee the engine holds for every noise
  realization at accuracy 10. The sweep test prints those numbers on every run
  so this sentence stays checked rather than remembered.
- 25 m teleport (500 m truth, run) → engine 492.5 m, odometer 551.0 m, and a
  ر4-less engine bills 520.3 m — hence the window `450 < d < 515`, which the
  old `< 560` bound let both the correct and the broken engine through.
- 10 minutes standing with ±3 m scatter → engine 0.0 m, elapsed the full
  600 s, while the same fixture gives a gate-free odometer more than 50 m
  (the test asserts that floor, so the fixture cannot quietly stop carrying
  the inflation ر6 is asked to reject). The previous fixture used one
  identical coordinate, which scores 0 m for any accumulator and so proved
  nothing about ر6.

**Conclusion the tables support (and only this):** the replay harness and the
engine's rules are calibrated on synthetic input at matched accuracy, and the
engine's error tracks how honestly the platform reports accuracy. Nothing here
is a claim about device GPS accuracy.

## Field protocol (device — NOT RUN)

One measured 1 km walking course on the Realme, three repetitions. Per rep:
`app distance / Strava distance / true distance (OSM routing)`, screenshots
via `adb exec-out screencap`, with the CI build run id that produced the APK.

| rep | app (m) | Strava (m) | true (m) | app err % | CI run id |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

The device fixtures land in `test/evidence/fixtures/real/` per
`test/evidence/fixtures/README.md`; until then
`test/evidence/golden_replay_test.dart` skips itself with a printed reason.
Each real fixture needs a `.truth` sidecar whose second line is the accuracy
that was in force, because the table above shows the verdict moves by an order
of magnitude with that one number.
