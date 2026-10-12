# Fidelity baseline — what the harness has actually measured

Date: 2026-10-09 (harness) · last re-measured **2026-10-12** on the R99–R102
engine. Branch `plan1-recorder-dark-ui`.

Every number in this file is printed by `flutter test test/evidence` in a CI
run. Nothing here is a device accuracy claim: the engine under test is fed
fixtures, not a phone carried over a measured course. The device row of this
table stays empty until Task 11 step 4 (three repeats of a measured course
against Strava) is run on a real install, and that install only comes from CI.

## 1. Synthetic calibration (no phone, ground truth exact by construction)

Fixture: 1000 m straight line, 1.4 m/s, 1 Hz, **independent** uniform scatter of
±10 m (ruling R98), seed 42 — the spec §8 (a) injection. Reproduced by the test
`1000 m walk with ±10 m noise: engine error stays under 1 %`.

| declared accuracy | walk | run | what it proves |
|---|---|---|---|
| 5 m | **1080.9 m (+8.09 %)** | **1450.9 m (+45.09 %)** | a receiver that over-claims its own 1σ inflates the track |
| 10 m | 1004.6 m (+0.46 %) | 1004.6 m (+0.46 %) | the spec §8 gate: under 1 % at an honest 1σ |
| 20 m | 984.3 m (−1.57 %) | 984.3 m (−1.57 %) | a conservative 1σ under-counts instead of inventing |

Printed by `declared accuracy is the lever: over-claiming precision inflates the
track`. The monotonicity (acc 5 > acc 20 for both sports) is asserted, not just
printed: if the gate ever stopped reading the accuracy the test fails.

**This is the product's whole lever.** The engine has no metre of its own — it
spends the 1σ the receiver declares. A phone that optimistically reports 5 m for
a 15 m error bills ~8 % phantom on a walk and ~45 % on a run at the same true
noise, which is why every `.truth` sidecar records the accuracy in force at
capture (R95) and why the stationary fixtures below are graded absolutely.

## 2. Noise envelope (the 1 % bar is seed-dependent, not a guarantee)

50 seeds of the same fixture (±10 m, accuracy 10), printed by
`±10 m noise: the 1 % bar is seed-dependent, measured not claimed`:

| measure | pre-R99 engine | R99–R102 engine |
|---|---|---|
| worst seed | 3.66 % | **2.84 %** |
| median | 0.93 % | **0.70 %** |
| seeds above the 1 % bar | 23 / 50 | **15 / 50** |

Honest reading: the single-seed spec gate passes and the sweep is tighter than
before, but **more than a quarter of noise realisations still exceed 1 %** at
±10 m. No marketing sentence may present 1 % as a promise. The sweep asserts one
thing per seed — that the engine beats a gate-free odometer on the same feed —
so it cannot pass for a rule that was deleted.

## 3. Real device fixtures (the phantom, and its death)

Four sessions recorded 2026-10-11 on the Realme C33 lying on a desk with the
recorder running: ground truth **0 m** known by observation. Replaying the
exported GPX through the production engine:

| fixture | accuracy in force | before R99–R102 | after |
|---|---|---|---|
| `run-0m-desk-1` | 53.488 m | 123.3 m | **0.0 m** |
| `run-0m-desk-2` | 25.687 m | 121.4 m | **0.0 m** |
| `run-0m-desk-3` | 24.857 m | 25.2 m (= the `distance_m` the phone persisted) | **0.0 m** |
| `run-0m-desk-4` | 32.497 m | 375.1 m (= the `distance_m` the phone persisted) | **0.0 m** |

Two doors produced the phantom, and the same two rulings closed them:

- **ر3's 25 m ceiling sat below the receiver's own error.** At accuracy 32.5 m
  the gate demanded 25 m of movement from a fix uncertain by 32 m, so the engine
  billed the difference as distance. R99 removed the ceiling: the gate is
  `max(3 m, 2 × accuracy)` with no cap, and with R74's unmeasured-accuracy
  sentinel it is infinite, so nothing is ever billed against a 1σ nobody
  measured.
- **The ر3 heartbeat billed whatever sub-gate displacement the noise had reached**
  and moved the yardstick to it — 12.5 m of nothing every ~11 s became 375.1 m.
  R101 keeps the heartbeat's promise (a point exists every 15 s) as a marker:
  appended, never billed, and the anchor does not move.
- **A reported speed could end idle and bill the resume.** The Realme's provider
  claimed 1.1–4.7 m/s for a phone on a table. R100 keeps that claim for ر6's
  label, exactly as the spec words it, and cuts its reach into the odometer: a
  resume bills only when the position itself clears the gate.

## 4. Rejected attempt (kept because it is the interesting part)

A fourth rule was implemented, measured, and reverted in the same session:
entering idle by **position consensus** (yardstick unmoved for longer than the
idle window *and* the fix inside half the noise gate). Measured on the 1 km
fixture it was catastrophic — **873.3 m (−12.7 %)**, worst seed 18.15 %, and
50 / 50 seeds above the 1 % bar — while desk-4 still billed 13.7 m.

The reason is physical, not a coding bug: ±10 m of independent scatter produces
a larger net displacement over a 12 s window than a 1 m/s crawl does, so standing
still and crawling are not separable from positions alone at that noise level.
A consensus rule therefore flags real tracks idle, and an idle marker discards
the metres up to it. The engine resolves that ambiguity in the one safe
direction: **under-count, never invent.**

## 5. What is still unmeasured

- Any real course length: no `.gpx` in `real/` yet, so `golden_replay_test.dart`
  skips itself with a printed reason (1 skipped test in every run) rather than
  faking a verdict.
- Elevations (the device delivered a constant 0), battery drain per recording
  hour, and ColorOS kill-resistance (auto-start cannot be verified from adb).
- The ر4-less teleport counterfactual (520.3 m) was measured once by hand and is
  not reproduced by a committed test.
