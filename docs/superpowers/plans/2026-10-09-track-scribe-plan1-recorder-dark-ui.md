# Track Scribe — Recorder Engine + Dark UI (Plan 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fully-offline Android app that records walk/run/bike routes with honest distance/elevation fidelity and shows them in the approved dark UI (layout B), installable on the test phone through GitHub Actions CI.

**Architecture:** Five isolated layers. `RecorderEngine` is pure Dart and owns every fidelity rule (it receives `RawFix`, decides store/reject/idle, and accumulates distance only from the last **stored** point). Persistence is drift/SQLite with write-ahead inserts and a resume checkpoint. The UI is Riverpod over a `FixSource` abstraction so the recording screen is testable without a phone. The first basemap is a generated dark grid (`GridBasemap`) — no tile server, no third-party tile licence.

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4, flutter_map 8.3.2 (BSD-3), geolocator 14.1.1 (MIT), flutter_background_service 5.1.0 (MIT), drift 2.35.2 (MIT), riverpod 3.4.3, gpx 2.5.0 (Apache-2.0), GitHub Actions (`ubuntu-latest`, arm64-only debug APK), adb install on a Realme/ColorOS phone.

**Spec:** `docs/superpowers/specs/2026-10-09-route-recorder-dark-ui-design.md` — read it before Task 1; every rule ر1–ر13 and every token in §5 comes from there.

## Global Constraints

- Android only. No iOS, no watch, no web.
- **Local only:** no backend, no account, no analytics, no ads, no network calls at runtime. No Supabase/Firebase.
- **No GPL/AGPL/LGPL code in the APK.** No `ffmpeg-kit`, no OsmAnd code, no `map-matching-2`, no `background_locator`.
- **No Google Maps and no Mapbox tiles anywhere** (ToS forbids bundling/derivative video).
- **No local APK builds.** The 2-core / 4 GB / HDD machine runs only `flutter create|pub get|analyze|test`. Gradle happens in CI.
- No package that compiles C++ through the NDK.
- `RecorderEngine` must not import `flutter/*`, `dart:io`, or any plugin. It is testable with `flutter test` alone.
- Wall-clock time is for display only; all durations come from a monotonic clock.
- Arabic-first, RTL. Decimal separator is a token (`ar: ','`, `en: '.'`), never a hard-coded character.
- Fidelity claims are forbidden until the Task 11 evidence table exists.

**Deviations from the spec, agreed in-plan (stated, not silent):**
1. **ر1:** `geolocator`'s `Position` does not expose `elapsedRealtimeNanos`, `verticalAccuracyMeters` or `speedAccuracyMetersPerSecond`. v1 timestamps fixes with a Dart `Stopwatch` (monotonic) at receipt. Raw `Location` fields need a hand-written Kotlin channel → deferred to Plan 2 hardening.
2. **ر2:** haversine on the mean Earth radius, not Andoyer. On our ≤ 25 m segments the difference is centimetres — orders of magnitude below GPS noise.
3. **ر11 (DEM altitude), GPX/FIT export, history screens, light theme:** out of Plan 1; each gets its own plan.

---

## File Structure

```
track_scribe/                                  # Flutter app (repo root = workspace root)
  lib/core/geo.dart                            # distance, bearing
  lib/core/monotonic.dart                      # MonotonicTicker
  lib/core/format.dart                         # pace/duration/decimal-separator tokens
  lib/theme/palette.dart                       # colour tokens + WCAG contrast maths
  lib/theme/typography.dart                    # bundled font faces
  lib/theme/theme.dart                         # ThemeData (dark first)
  lib/engine/raw_fix.dart                      # RawFix, WaypointType, StoredPoint
  lib/engine/sport_config.dart                 # ر3–ر6 constants per sport
  lib/engine/recorder_engine.dart              # the whole fidelity layer
  lib/engine/splits.dart                       # per-km splits from stored points
  lib/data/database.dart                       # drift tables
  lib/data/activity_repository.dart            # WAL inserts + resume checkpoint
  lib/source/fix_source.dart                   # abstract Stream<RawFix>
  lib/source/geolocator_fix_source.dart        # production source
  lib/source/synthetic_fix_source.dart         # deterministic test/dev source
  lib/state/recording_controller.dart          # Riverpod glue UI ⇄ engine
  lib/ui/recording/recording_screen.dart       # layout B
  lib/ui/recording/widgets/stat_panel.dart
  lib/ui/recording/widgets/sport_chips.dart
  lib/ui/recording/widgets/stop_button.dart
  lib/ui/recording/widgets/gps_status_banner.dart
  lib/ui/basemap/basemap.dart                  # Basemap interface
  lib/ui/basemap/grid_basemap.dart             # v1 implementation
  lib/ui/basemap/route_painter.dart            # CustomPainter for the polyline
  test/…                                       # mirrors lib/
  assets/fonts/IBMPlexSansArabic-{Regular,Medium,Bold}.ttf
.github/workflows/android-apk.yml
docs/superpowers/{specs,plans}/
```

---

### Task 1: Project scaffold with a green baseline

**Files:**
- Create: `track_scribe/pubspec.yaml`, `track_scribe/lib/main.dart`, `track_scribe/analysis_options.yaml`, `track_scribe/.gitignore`, `track_scribe/test/smoke_test.dart`
- Modify: workspace-root `.gitignore` (create if absent)

**Interfaces:**
- Consumes: nothing.
- Produces: package name `track_scribe`; `lib/main.dart` exposing `void main() => runApp(const TrackScribeApp());` and `TrackScribeApp` from `lib/ui/app.dart`.

- [ ] **Step 1: Create the app**

```bash
cd "C:/Users/Administrator/Documents/Qoder/2026-10-09/240e4a1d"
"/c/src/flutter/bin/flutter" create track_scribe --platforms=android --org=dev.toufik --project-name=track_scribe
```
Expected: `Created project track_scribe` and **no Gradle task runs** (`flutter create` does not invoke Gradle).

- [ ] **Step 2: Pin the dependency set — nothing more**

Replace the `dependencies:` block of `track_scribe/pubspec.yaml` with exactly:

```yaml
dependencies:
  flutter: { sdk: flutter }
  flutter_riverpod: ^3.4.3
  flutter_map: ^8.3.2
  geolocator: ^14.1.1
  flutter_background_service: ^5.1.0
  drift: ^2.35.2
  path_provider: ^2.1.5
dev_dependencies:
  flutter_test: { sdk: flutter }
  flutter_lints: ^6.0.0
  drift_dev: ^2.35.2
  build_runner: ^2.4.15
  gpx: ^2.5.0
flutter:
  uses-material-design: true
  assets:
    - assets/fonts/
```

Run: `flutter pub get` — Expected: exit 0, `Got dependencies!`. If any version is unresolvable, run `flutter pub outdated` and use the newest *same-major* version; do not add any other package.

- [ ] **Step 3: Write the failing smoke test**

`track_scribe/test/smoke_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/ui/app.dart';

void main() {
  testWidgets('app boots into the recording screen', (tester) async {
    await tester.pumpWidget(const TrackScribeApp());
    await tester.pumpAndSettle();
    expect(find.text('تسجيل'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run it to see it fail**

Run: `flutter test test/smoke_test.dart` — Expected: FAIL, `Target of URI doesn't exist: 'package:track_scribe/ui/app.dart'`.

- [ ] **Step 5: Create `lib/ui/app.dart` (placeholder theme, replaced in Task 6)**

```dart
import 'package:flutter/material.dart';

class TrackScribeApp extends StatelessWidget {
  const TrackScribeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Track Scribe',
        home: Scaffold(
          body: Center(child: Text('تسجيل', style: Theme.of(context).textTheme.headlineMedium)),
        ),
      );
}
```
Also replace `lib/main.dart` with:
```dart
import 'package:flutter/material.dart';
import 'package:track_scribe/ui/app.dart';
void main() => runApp(const TrackScribeApp());
```
and delete the generated `lib/main.dart` test widget (`test/widget_test.dart`) that references the counter template.

- [ ] **Step 6: Verify green, then commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → `+1: All tests passed!`

```bash
printf '/.superpowers/\n/build/\n.dart_tool/\n*.apk\n' > ../.gitignore
git add . && git commit -m "chore: scaffold track_scribe Flutter app with pinned dependency set"
```

---

### Task 2: Private GitHub repo + CI that produces an installable APK

**Files:**
- Create: `.github/workflows/android-apk.yml`
- Modify: `track_scribe/android/app/build.gradle.kts` (abi filters, applicationId)

**Interfaces:**
- Consumes: Task 1 project.
- Produces: artifact name `track-scribe-debug-apk` at `track_scribe/build/app/outputs/flutter-apk/app-debug.apk`; the contract every later task must keep green: `flutter analyze` + `flutter test` inside CI.

- [ ] **Step 1: Restrict the build to arm64 so CI stays short**

In `track_scribe/android/app/build.gradle.kts`, inside `defaultConfig { }` add:

```kotlin
ndk { abiFilters.add("arm64-v8a") }
```
and set `applicationId = "dev.toufik.track_scribe"`.

- [ ] **Step 2: Write the workflow**

`.github/workflows/android-apk.yml` (repo root is the workspace, so all flutter commands need the app dir):

```yaml
name: android-apk
on:
  push: { branches: [main] }
  workflow_dispatch:
concurrency: { group: apk-${{ github.ref }}, cancel-in-progress: true }
jobs:
  apk:
    runs-on: ubuntu-latest
    timeout-minutes: 25
    defaults: { run: { working-directory: track_scribe } }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '17' }
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.47.5', cache: true }
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
      - run: flutter build apk --debug --target-platform=android-arm64
      - uses: actions/upload-artifact@v4
        with:
          name: track-scribe-debug-apk
          path: track_scribe/build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 3: Create the private repo and push**

```bash
gh repo create track-scribe --private --source=. --remote=origin --push
```
Expected: `✓ Created repository toufikben/track-scribe on GitHub` + `✓ Pushed commits to main`. This is the only step that touches a shared system; it is authorised by the user for a **private** repo.

- [ ] **Step 4: Watch CI until it is green**

```bash
gh run list --limit 3
gh run watch <run-id> --exit-status
```
Expected: `✓ android-apk` with a run id you record. Report the run id in the commit/progress notes.

- [ ] **Step 5: Install on the phone and confirm it launches**

```bash
gh run download <run-id> -n track-scribe-debug-apk
adb install -r app-debug.apk
adb shell monkey -p dev.toufik.track_scribe -c android.intent.category.LAUNCHER 1
adb exec-out screencap -p > ../desktop-check-1.png
```
Expected: the word `تسجيل` on screen in the screenshot. **Look at the screenshot** — an installed app is not a verified app.

- [ ] **Step 6: Commit**

```bash
git add .github . && git commit -m "ci: GitHub Actions debug APK pipeline, verified installed on test device"
```

---

### Task 3: Monotonic clock + spherical distance (the two primitives)

**Files:**
- Create: `track_scribe/lib/core/geo.dart`, `track_scribe/lib/core/monotonic.dart`
- Test: `track_scribe/test/core/geo_test.dart`, `track_scribe/test/core/monotonic_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `double haversineMeters(double lat1, double lon1, double lat2, double lon2)`; `double bearingDeg(...)`; `class MonotonicTicker { bool accept(int nanos); int get lastNanos; double secondsSince(int fromNanos); }`.

- [ ] **Step 1: Write the failing tests**

`test/core/geo_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/core/geo.dart';

void main() {
  test('one metre of latitude is ~111.19 km per degree', () {
    expect(haversineMeters(36.7538, 3.1856, 36.7539, 3.1856), closeTo(11.12, 0.5));
  });
  test('a known Algiers corridor is within 0.3% of geodesic length', () {
    // 1 km walked due east at 36.75N: longitude delta for 1000 m
    const dLon = 1000 / (111412.0 * 0.8013); // approx m per degree at 36.75N
    final d = haversineMeters(36.7538, 3.1856, 36.7538, 3.1856 + dLon);
    expect((d - 1000).abs() / 1000, lessThan(0.003));
  });
  test('identical points are zero', () => expect(haversineMeters(1, 2, 1, 2), 0));
  test('bearing east is ~90°', () {
    expect(bearingDeg(36.75, 3.18, 36.75, 3.19), closeTo(90, 0.5));
  });
}
```

`test/core/monotonic_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/core/monotonic.dart';

void main() {
  test('rejects a non-monotonic timestamp instead of corrupting duration', () {
    final t = MonotonicTicker();
    expect(t.accept(1000), isTrue);
    expect(t.accept(900), isFalse);   // clock went backwards → drop
    expect(t.accept(1000), isFalse);  // duplicate → drop
    expect(t.accept(3_000_000_000), isTrue);
    expect(t.secondsSince(1000), closeTo(2.999999, 1e-9));
  });
}
```

- [ ] **Step 2: Run to see them fail** — Run: `flutter test test/core` → Expected: FAIL, `undefined_function 'haversineMeters'`.

- [ ] **Step 3: Implement**

`lib/core/geo.dart`:

```dart
import 'dart:math' as math;

const double _earthRadiusM = 6371008.8; // WGS84 mean radius (IUGG)
double _rad(double deg) => deg * math.pi / 180.0;

/// Spherical distance in metres. On segments ≤ 25 m the difference from a
/// full ellipsoidal geodesic is centimetres — far below GPS noise.
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = _rad(lat1), phi2 = _rad(lat2);
  final dPhi = phi2 - phi1, dLon = _rad(lon2 - lon1);
  final a = math.pow(math.sin(dPhi / 2), 2) +
      math.cos(phi1) * math.cos(phi2) * math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1.0, math.sqrt(a)));
}

double bearingDeg(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = _rad(lat1), phi2 = _rad(lat2), dLon = _rad(lon2 - lon1);
  final y = math.sin(dLon) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}
```

`lib/core/monotonic.dart`:

```dart
/// Single source of truth for elapsed time. Never DateTime.now().
class MonotonicTicker {
  int _last = -1;
  int get lastNanos => _last;

  /// false → this sample cannot be trusted for durations (reorder or replay).
  bool accept(int nanos) {
    if (nanos <= _last) return false;
    _last = nanos;
    return true;
  }

  double secondsSince(int fromNanos) => (_last - fromNanos) / 1e9;
}
```

- [ ] **Step 4: Run to see them pass** — Run: `flutter test test/core` → Expected: `+5: All tests passed!`
- [ ] **Step 5: Commit** — `git add track_scribe/lib/core track_scribe/test/core && git commit -m "feat(core): monotonic ticker and spherical distance primitives"`

---

### Task 4: Sport config + `RecorderEngine` store-gate and drift rejection

**Files:**
- Create: `lib/engine/raw_fix.dart`, `lib/engine/sport_config.dart`, `lib/engine/recorder_engine.dart`
- Test: `test/engine/recorder_engine_test.dart`

```dart
enum WaypointType { normal, idle, rejected, skipped }
```

(`skipped` — the fix passed every gate but the polyline has no room for it yet —
is an **engine verdict**, not a persisted kind: spec §4 line 50 closes
`waypoint_type` to NORMAL/IDLE/REJECTED/SEGPOINT, so persistence maps `skipped`
to `NORMAL` plus a flags bit. Ledger ruling R43, consumed by Task 8.)

**Interfaces:**
- Consumes: `haversineMeters`, `MonotonicTicker` (Task 3).
- Produces: `RawFix`, `WaypointType`, `StoredPoint`, `Sport`, `SportConfig`, the
  `RawFixSink` typedef, and

```dart
typedef RawFixSink = void Function(RawFix fix, WaypointType verdict);

class RecorderEngine {
  RecorderEngine(SportConfig config, {required int startNanos, RawFixSink? rawSink});
  SportConfig get config;
  double get distanceMeters;
  int get elapsedNanos;
  List<StoredPoint> get storedPoints;
  EngineStats get stats;
  bool get isIdle;
  void onFix(RawFix fix);
}
```

Every fix the ticker accepts is reported to `rawSink` exactly once,
synchronously, before `onFix` returns, with the verdict the engine reached for
it (R41 — this is how ر9's "never delete a raw point" coexists with ر13's "no
in-memory accumulation": the engine keeps no raw buffer, the controller pipes
the verdict stream to the database).

- [ ] **Step 1: Models**

`lib/engine/raw_fix.dart`:

```dart
import 'package:track_scribe/core/geo.dart';

enum WaypointType { normal, idle, rejected, skipped }

class RawFix {
  const RawFix({
    required this.lat, required this.lon, required this.timeNanos,
    required this.accuracyM, this.altitudeM, this.speedMps,
    this.bearingDeg, this.isMocked = false, this.wallMillis = 0,
  });
  final double lat, lon;
  final int timeNanos;      // monotonic (see Global Constraints deviation 1)
  final double accuracyM;   // Android 1σ radius
  final double? altitudeM, speedMps, bearingDeg;
  final bool isMocked;
  final int wallMillis;     // display only, never used for durations
}

class StoredPoint {
  const StoredPoint({
    required this.lat, required this.lon, required this.timeNanos,
    required this.accuracyM, required this.type,
    this.altitudeM, this.speedMps, this.bearingDeg,
  });
  final double lat, lon, accuracyM;
  final int timeNanos;
  final WaypointType type;
  final double? altitudeM, speedMps, bearingDeg;
  double distanceTo(StoredPoint o) => haversineMeters(lat, lon, o.lat, o.lon);
}
```

`lib/engine/sport_config.dart` — spec rules ر3–ر6, verbatim values:

```dart
enum Sport { walk, run, bike }

class SportConfig {
  const SportConfig({
    required this.sport, required this.maxSpeedMps,
    this.minStoreDistanceM = 3.0, this.accuracyFactor = 2.0,
    this.maxStoreDistanceM = 25.0, this.forceStoreAfterS = 15.0,
    this.maxJumpM = 200.0, this.idleSpeedMps = 0.4, this.idleAfterS = 12.0,
  });
  final Sport sport;
  final double maxSpeedMps;      // ر5
  final double minStoreDistanceM, maxStoreDistanceM, accuracyFactor; // ر3
  final double forceStoreAfterS; // ر3 heartbeat
  final double maxJumpM;         // ر4
  final double idleSpeedMps, idleAfterS; // ر6

  /// Store gate: max(3 m, 2 × accuracy), capped at 25 m (spec ر3 verbatim).
  /// The first draft of this plan wrote `minStoreDistanceM + accuracyFactor *
  /// accuracyM` (3 + 2a), which contradicts both the spec and this task's own
  /// `gateFor(0.5) == 3.0` test — ledger ruling R6, spec won. `clamp` returns
  /// `num`, so the `.toDouble()` is load-bearing.
  double gateFor(double accuracyM) =>
      (accuracyFactor * accuracyM).clamp(minStoreDistanceM, maxStoreDistanceM).toDouble();

  factory SportConfig.forSport(Sport s) => switch (s) {
        Sport.walk => const SportConfig(sport: Sport.walk, maxSpeedMps: 2.5),
        Sport.run => const SportConfig(sport: Sport.run, maxSpeedMps: 6.0),
        Sport.bike => const SportConfig(sport: Sport.bike, maxSpeedMps: 20.0),
      };
}
```

- [ ] **Step 2: Write the failing tests** — `test/engine/recorder_engine_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/recorder_engine.dart';
import 'package:track_scribe/engine/sport_config.dart';

RawFix walk({required double dLat, required int sec, double acc = 4}) => RawFix(
      lat: 36.7538 + dLat / 111111.0, lon: 3.1856,
      timeNanos: sec * 1000000000, accuracyM: acc);

void main() {
  const cfg = SportConfig(sport: Sport.run, maxSpeedMps: 6.0);

  test('gate: accuracy 4 m → 11 m, and points inside the gate are not stored', () {
    final e = RecorderEngine(cfg, startNanos: 0);
    expect(cfg.gateFor(4), closeTo(11.0, 1e-9));
    e.onFix(walk(dLat: 0, sec: 0));            // first fix is always stored
    e.onFix(walk(dLat: 30, sec: 1));           // 0.27 m — inside gate, skipped
    expect(e.storedPoints.length, 1);
    expect(e.distanceMeters, 0.0);
  });

  test('distance accumulates from the LAST STORED point, not the last fix', () {
    final e = RecorderEngine(cfg, startNanos: 0);
    e.onFix(walk(dLat: 0, sec: 0));
    e.onFix(walk(dLat: 600, sec: 10));  // ~6.03 m, inside gate → skipped
    e.onFix(walk(dLat: 2500, sec: 20)); // ~25 m from stored point → stored
    expect(e.distanceMeters, closeTo(22.52, 0.3)); // 2500-30-0 m ≈ 22.5 m
    expect(e.storedPoints.length, 2);
  });

  test('re3: gate is capped at 25 m even for terrible accuracy', () {
    expect(cfg.gateFor(99), 25.0);
    expect(cfg.gateFor(0.5), 3.0);
  });

  test('re4: a 300 m teleport adds zero distance and is flagged rejected', () {
    final e = RecorderEngine(cfg, startNanos: 0);
    e.onFix(walk(dLat: 0, sec: 0));
    e.onFix(walk(dLat: 200, sec: 1));   // ~2.2 m → inside gate, no store
    e.onFix(walk(dLat: 300000, sec: 2)); // ~2700 m jump
    expect(e.distanceMeters, 0.0);
    expect(e.stats.rejectedCount, 1);
    expect(e.storedPoints.last.type, WaypointType.rejected);
    expect(e.storedPoints.last.distanceTo(e.storedPoints[e.storedPoints.length - 3]),
        greaterThan(1000)); // the raw point is kept, never deleted
  });

  test('re3 heartbeat: 15 s with no movement still stores a point', () {
    final e = RecorderEngine(cfg, startNanos: 0);
    e.onFix(walk(dLat: 10, sec: 0));
    e.onFix(walk(dLat: 12, sec: 16));
    expect(e.storedPoints.length, 2);
  });

  test('non-monotonic timestamps are dropped, not averaged', () {
    final e = RecorderEngine(cfg, startNanos: 0);
    e.onFix(walk(dLat: 0, sec: 5));
    e.onFix(walk(dLat: 100, sec: 3)); // goes backwards
    expect(e.stats.droppedOutOfOrder, 1);
    expect(e.elapsedNanos, 5_000_000_000);
  });
}
```

- [ ] **Step 3: Run to see them fail** — Run: `flutter test test/engine` → Expected: FAIL, `Target of URI doesn't exist: '.../recorder_engine.dart'`.

- [ ] **Step 4: Implement `lib/engine/recorder_engine.dart`**

This is the file as shipped (`8c4e340`), after three review rounds. The draft
that was in this plan before execution had seven defects; they are listed
immediately after the code, with the measurement that proved each one, so a
future reader does not reintroduce them.

```dart
import 'package:track_scribe/core/geo.dart';
import 'package:track_scribe/core/monotonic.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/sport_config.dart';

/// Sink for EVERY accepted raw fix (ر9/R41): invoked synchronously, once per
/// fix, before `RecorderEngine.onFix` returns.
typedef RawFixSink = void Function(RawFix fix, WaypointType verdict);

/// Counters exposed to the UI/persistence layers (ر10 mock detection feeds the
/// activity-level flag; ر4/ر1 diagnostics).
class EngineStats {
  const EngineStats({
    this.fixCount = 0, this.rejectedCount = 0, this.droppedOutOfOrder = 0,
    this.mockFixCount = 0,
  });
  final int fixCount, rejectedCount, droppedOutOfOrder, mockFixCount;
}

class RecorderEngine {
  /// Deliberately does NOT pre-accept [startNanos] into the ticker: a first
  /// fix stamped exactly `startNanos` is legitimate (elapsed 0), and the
  /// ticker's strict `>` gate would silently drop it.
  RecorderEngine(this.config, {required int startNanos, this.rawSink})
      : _sessionStartNanos = startNanos, _ticker = MonotonicTicker();

  /// R40: rejected fixes must be mutually consistent across this many
  /// consecutive pairs (each d/dt <= v_max) before the anchor may move.
  /// GPS noise cannot fabricate three such pairs, so the transport rescue
  /// never bills the teleport gap itself.
  static const int _reanchorAfterPairs = 3;

  final SportConfig config;
  final RawFixSink? rawSink;
  final MonotonicTicker _ticker;
  final int _sessionStartNanos;
  final List<StoredPoint> _points = [];

  /// R39: the yardstick for distance accumulation and for the next
  /// gate/jump/heartbeat comparison (ر2). It moves only with points that
  /// PASSED the jump test — a rejected point never moves it, otherwise the
  /// first noise spike becomes the reference and freezes accumulation.
  StoredPoint? _anchor;

  /// R40 re-acquisition state: while fixes disagree with the anchor, track
  /// the chain of consecutive fixes that are mutually consistent, its length
  /// in completed pairs and its internal movement.
  StoredPoint? _chainPrev;
  int _consistentPairs = 0;
  double _chainDistanceM = 0;

  int? _idleSinceNanos;
  bool _idle = false;
  bool _hasAcceptedFix = false;

  /// ر3: monotonic time of the LAST append to `_points` — any type, including
  /// idle markers and rejected keeps. The heartbeat means "15 s without a
  /// point", so it is measured against the point stream, never against the
  /// anchor: during idle the anchor only moves via idle appends, and an
  /// anchor-based comparison made the idle heartbeat permanently unreachable.
  /// -1 until the first append.
  int _lastAppendNanos = -1;
  int _fixCount = 0, _rejected = 0, _dropped = 0, _mocks = 0;
  double _distanceM = 0;

  List<StoredPoint> get storedPoints => List.unmodifiable(_points);
  double get distanceMeters => _distanceM;

  /// Display/accumulation-safe elapsed: 0 until the first fix is accepted,
  /// then ticker-last minus start, never negative.
  int get elapsedNanos {
    if (!_hasAcceptedFix) return 0;
    final e = _ticker.lastNanos - _sessionStartNanos;
    return e < 0 ? 0 : e;
  }

  bool get isIdle => _idle;
  EngineStats get stats => EngineStats(
      fixCount: _fixCount, rejectedCount: _rejected,
      droppedOutOfOrder: _dropped, mockFixCount: _mocks);

  void onFix(RawFix fix) {
    // ر1 — the ticker is the enforcement point for monotonicity; equal or
    // earlier timestamps are dropped, never averaged. A dropped fix was
    // never accepted, so it must not reach the sink (R41).
    if (!_ticker.accept(fix.timeNanos)) { _dropped++; return; }
    _hasAcceptedFix = true;
    _fixCount++;
    if (fix.isMocked) _mocks++;                       // ر10
    final verdict = _process(fix);
    rawSink?.call(fix, verdict); // R41 — synchronous, before onFix returns
  }

  WaypointType _process(RawFix fix) {
    final anchor = _anchor;
    if (anchor == null) {
      _store(fix, WaypointType.normal, addDistance: false);
      return WaypointType.normal;
    }

    final dt = _ticker.secondsSince(anchor.timeNanos);
    final d = haversineMeters(anchor.lat, anchor.lon, fix.lat, fix.lon);
    final impliedSpeed = dt > 0 ? d / dt : null;
    final speed = fix.speedMps ?? impliedSpeed;        // Doppler wins over differencing

    // ر4 — impossible jump: keep the raw point, add nothing to distance.
    // Spec threshold is v_max itself (the draft's 2× v_max was a silent
    // relaxation the spec does not authorise). R39: _store() keeps _anchor
    // where it is; R40 then watches for a locally consistent chain.
    if (d > config.maxJumpM ||
        (impliedSpeed != null && impliedSpeed > config.maxSpeedMps)) {
      _rejected++;
      _trackReacquisition(_store(fix, WaypointType.rejected, addDistance: false));
      return WaypointType.rejected;
    }
    _resetChain(); // a fix agreeing with the anchor invalidates the chain

    final idleEvent = _updateIdle(fix, speed ?? 0.0);

    // ر3 heartbeat — "15 s without a point", measured from the last APPEND.
    final heartbeatDue = _lastAppendNanos >= 0 &&
        _ticker.secondsSince(_lastAppendNanos) >= config.forceStoreAfterS;

    // Every path below performs AT MOST one _store for this fix: `_updateIdle`
    // no longer stores, it only reports the transition, so a double append is
    // structurally impossible and the returned verdict always matches the
    // append it made.
    if (idleEvent == _IdleTransition.resumed) {
      // Idle→resume: append exactly once and bill the pending `d` measured
      // from the pre-idle anchor — real movement that ended the idle, which
      // ر6's zero-distance rule does not cover (see R45 below).
      _store(fix, WaypointType.normal, addDistance: true);
      return WaypointType.normal;
    }

    if (_idle) {
      // ر6 — time flows, distance does not. Entering idle and the heartbeat
      // share this single store: at most one append per fix.
      if (heartbeatDue || idleEvent == _IdleTransition.entered) {
        _store(fix, WaypointType.idle, addDistance: false);
      }
      return WaypointType.idle;
    }
    if (d >= config.gateFor(fix.accuracyM) || heartbeatDue) {
      _store(fix, WaypointType.normal, addDistance: true); // ر2 — from the anchor
      return WaypointType.normal;
    }
    return WaypointType.skipped;
  }

  /// Idle state machine (ر6) with NO store side effects — `_process` owns
  /// every append.
  _IdleTransition _updateIdle(RawFix fix, double speed) {
    if (speed < config.idleSpeedMps) {
      _idleSinceNanos ??= fix.timeNanos;
      if (!_idle && _ticker.secondsSince(_idleSinceNanos!) >= config.idleAfterS) {
        _idle = true;
        return _IdleTransition.entered;
      }
    } else {
      _idleSinceNanos = null;
      if (_idle) { _idle = false; return _IdleTransition.resumed; }
    }
    return _IdleTransition.none;
  }

  /// R40: genuine transport (walk → car → walk) keeps every post-transport
  /// fix disagreeing with the stale anchor, so the anchor must be allowed to
  /// move again — but only after 3 consecutive pairs among the rejected
  /// fixes are mutually consistent at <= v_max, and only the chain's
  /// INTERNAL movement is billed; the teleport gap is never added.
  void _trackReacquisition(StoredPoint p) {
    final prev = _chainPrev;
    if (prev != null) {
      final dt = _ticker.secondsSince(prev.timeNanos);
      final d = haversineMeters(prev.lat, prev.lon, p.lat, p.lon);
      if (dt > 0 && d / dt <= config.maxSpeedMps) {
        _consistentPairs++;
        _chainDistanceM += d;
        if (_consistentPairs >= _reanchorAfterPairs) {
          _anchor = p;
          _distanceM += _chainDistanceM;
          _resetChain();
          return;
        }
        _chainPrev = p;
        return;
      }
    }
    _chainPrev = p;      // chain start, or this fix breaks the chain
    _consistentPairs = 0;
    _chainDistanceM = 0;
  }

  void _resetChain() {
    _chainPrev = null;
    _consistentPairs = 0;
    _chainDistanceM = 0;
  }

  /// Appends to the polyline (`storedPoints`: map, distance, resume
  /// checkpoint), stamps the ر3 heartbeat clock, and moves the anchor only
  /// when the point passed the jump test — rejected points are kept (ر9) but
  /// must never become the yardstick (R39).
  StoredPoint _store(RawFix fix, WaypointType type, {required bool addDistance}) {
    final anchor = _anchor;
    if (addDistance && anchor != null) {
      _distanceM += haversineMeters(anchor.lat, anchor.lon, fix.lat, fix.lon);
    }
    final p = StoredPoint(
      lat: fix.lat, lon: fix.lon, timeNanos: fix.timeNanos, accuracyM: fix.accuracyM,
      type: type, altitudeM: fix.altitudeM, speedMps: fix.speedMps, bearingDeg: fix.bearingDeg,
    );
    _points.add(p);
    _lastAppendNanos = fix.timeNanos;
    if (type != WaypointType.rejected) _anchor = p;
    return p;
  }
}

/// Outcome of the ر6 idle state machine for the fix just processed.
enum _IdleTransition { none, entered, resumed }
```

**What the draft got wrong, and the evidence that settled it:**

1. **Gate formula** — draft: `3 + 2 × accuracy`; spec ر3: `max(3 م, 2 × accuracy)` capped 25 م. The draft contradicted its own `gateFor(0.5) == 3.0` test. Ruling R6; spec won. (`clamp` returns `num`, so `.toDouble()` is load-bearing.)
2. **Jump threshold** — draft rejected at `2 × v_max`; spec line 36 says `d/dt > v_max`. The implementer caught this one, not the controller.
3. **Constructor pre-accepted `startNanos`** into the ticker, so a first fix stamped exactly `startNanos` failed the strict `>` gate and was silently dropped. Now the ticker starts empty and `elapsedNanos` reports 0 until the first accepted fix.
4. **Anchor freeze (R39, Critical).** The draft stored every point through one `_lastStored` reference, so a rejected noise spike became the yardstick: the next honest fix then looked like a jump, was rejected too, and the anchor chased the noise forever. Simulated on this task's own fixture (1000 m walk, 1 Hz, accuracy 10 m): ±10 m alternating jitter → **0.0 m recorded, 715/715 fixes rejected, 100 % loss**; ±10 m random jitter → 317.0 m, 68 % loss. Fix: two references — `_anchor` (only points that passed the jump test) and `_points` (every appended point, flagged, per ر9).
5. **Transport rescue (R40).** Anchor-stays alone fixes noise but steals a real workout: walk 500 m → car 500 m → walk 500 m recorded 493.2 m of 999.8 m (**50.7 % loss**). Adding the 3-pair re-acquisition chain: transport clean 990.5 m (0.93 %), transport ±5 m noise 965.5 m (3.43 %), alternating jitter 964.9 m (3.51 %) with **zero** re-acquisitions, random jitter 1002.6 m (0.26 %) with **zero** re-acquisitions. Noise cannot fabricate three mutually consistent pairs, so the rescue is free.
6. **Raw stream lost (R41).** The draft discarded gate-skipped fixes, so ر9's "every raw point persisted" was impossible while ر13 forbids buffering. Fix: the injected verdict sink.
7. **Idle double-store and unreachable heartbeat (round 2).** `_updateIdle` stored a resume point and `_process` stored it again for the same fix, while the returned verdict lied about it; and because the heartbeat was compared against the anchor — which during idle only moves via idle markers, guarded off by `_lastWasIdleMarker` — ر3's heartbeat was permanently unreachable while idle. Fix: `_updateIdle` returns a transition instead of storing, and the heartbeat is clocked from `_lastAppendNanos`.
8. **R45 (kept deliberately):** the resume append bills `d` from the pre-idle anchor even when `d` is below the store gate. ر3's own heartbeat already bills below-gate movement after a long interval, and this is the same kind of long-interval difference; the channel is bounded to once per idle cycle and needs `speed ≥ idleSpeedMps`, which standing-with-jitter does not produce. Task 11's evidence table measures it instead of trusting this argument.

- [ ] **Step 5: Run to see them pass** — Run: `flutter test test/engine && flutter analyze` → Expected: `+11: All tests passed!` and `No issues found!` (11 = the 6 drafted above plus the R39 anchor-freeze, R40 re-acquisition, R41 per-fix sink, resume single-store, and idle-heartbeat tests).
- [ ] **Step 6: Commit** — shipped as three commits: `da1c404` (rules ر2–ر5), `9ec2c8f` (R39/R40/R41 anchor split, re-acquisition, raw sink), `8c4e340` (single store decision per fix, reachable ر3 idle heartbeat). CI runs 38004683146, 38006534016, 38008425618 — all success.

---

### Task 5: Idle accounting, elapsed-time correctness, and splits

**Files:**
- Create: `lib/engine/splits.dart`
- Modify: `lib/engine/recorder_engine.dart` (only if a test exposes a defect)
- Test: `test/engine/idle_and_splits_test.dart`

**Interfaces:**
- Consumes: `RecorderEngine`, `StoredPoint` (Task 4).
- Produces: `List<Split> computeSplits(List<StoredPoint> points)` and `class Split { final int kmIndex; final double distanceM; final int elapsedNanos; final double paceSecPerKm; }`.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/recorder_engine.dart';
import 'package:track_scribe/engine/sport_config.dart';
import 'package:track_scribe/engine/splits.dart';

RawFix at({required double dLat, required int sec, double? speed}) => RawFix(
      lat: 36.7538 + dLat / 111111.0, lon: 3.1856,
      timeNanos: sec * 1000000000, accuracyM: 3, speedMps: speed);

void main() {
  test('re6: 5 minutes standing still costs zero distance but full time', () {
    final e = RecorderEngine(SportConfig.forSport(Sport.walk), startNanos: 0);
    e.onFix(at(dLat: 0, sec: 0, speed: 1.4));
    for (var s = 1; s <= 300; s++) {
      e.onFix(at(dLat: 0, sec: s, speed: 0.0));   // same coordinates, stopped
      expect(e.distanceMeters, 0.0, reason: 'drift inflated at second $s');
    }
    expect(e.isIdle, isTrue);
    expect(e.elapsedNanos, 300_000_000_000);
    expect(e.storedPoints.where((p) => p.type == WaypointType.idle), isNotEmpty);
  });

  test('a 1 km straight-line walk yields one full split at true distance', () {
    final e = RecorderEngine(SportConfig.forSport(Sport.walk), startNanos: 0);
    const mPerStep = 5.0; // gate is 3+2*3=9 m; 5 m steps are skipped until the gate
    for (var i = 0; i * mPerStep <= 1000; i++) {
      e.onFix(at(dLat: i * mPerStep, sec: i * 4, speed: 1.25));
    }
    expect(e.distanceMeters, closeTo(1000, 6));
    final splits = computeSplits(e.storedPoints);
    expect(splits.length, 1);
    expect(splits.first.kmIndex, 1);
    expect(splits.first.paceSecPerKm, greaterThan(0));
  });

  test('computeSplits is empty before the first kilometre', () {
    final e = RecorderEngine(SportConfig.forSport(Sport.walk), startNanos: 0);
    for (var i = 0; i <= 60; i++) { e.onFix(at(dLat: i * 10.0, sec: i * 8, speed: 1.25)); }
    expect(e.distanceMeters, greaterThan(400));
    expect(computeSplits(e.storedPoints), isEmpty);
  });
}
```

- [ ] **Step 2: Run to see them fail** — Run: `flutter test test/engine` → Expected: FAIL, `undefined_function 'computeSplits'`.

- [ ] **Step 3: Implement `lib/engine/splits.dart`**

```dart
import 'package:track_scribe/core/geo.dart';
import 'package:track_scribe/engine/raw_fix.dart';

class Split {
  const Split({required this.kmIndex, required this.distanceM,
               required this.elapsedNanos, required this.paceSecPerKm});
  final int kmIndex;
  final double distanceM, elapsedNanos, paceSecPerKm;
}

/// Interpolates the exact position/time at each 1000 m crossing along the
/// stored polyline. Never extrapolates beyond the last point.
List<Split> computeSplits(List<StoredPoint> points) {
  final out = <Split>[];
  double travelled = 0;
  int km = 1;
  StoredPoint? prev;
  int startNanos = points.isNotEmpty ? points.first.timeNanos : 0;

  for (final p in points) {
    if (p.type == WaypointType.rejected) continue;
    if (prev != null) {
      final seg = haversineMeters(prev.lat, prev.lon, p.lat, p.lon);
      final segTime = p.timeNanos - prev.timeNanos;
      double remaining = seg;
      while (travelled + remaining >= km * 1000.0) {
        final need = km * 1000.0 - travelled;
        final frac = seg == 0 ? 0.0 : need / seg;
        final nanosAt = prev.timeNanos + (segTime * frac).round();
        final elapsed = (nanosAt - startNanos) / 1e9;
        out.add(Split(kmIndex: km, distanceM: km * 1000.0,
            elapsedNanos: nanosAt - startNanos,
            paceSecPerKm: elapsed / km - (out.isEmpty ? 0 : out.last.elapsedNanos / 1e9)));
        travelled += need; remaining -= need; km++;
      }
      travelled += remaining;
    }
    prev = p;
  }
  return out;
}
```
Note: for the split pace we want the **segment** pace, so replace the `paceSecPerKm` line with:
```dart
final prevNanos = out.isEmpty ? startNanos : out.last.elapsedNanos;
paceSecPerKm: (nanosAt - prevNanos) / 1e9,
```
and store `elapsedNanos: nanosAt - startNanos` on the returned `Split` as declared.

- [ ] **Step 4: Run to see them pass** — Run: `flutter test test/engine` → Expected: `+9: All tests passed!`
- [ ] **Step 5: Commit** — `git add track_scribe/lib/engine track_scribe/test/engine && git commit -m "feat(engine): idle accounting verified and per-km splits"`

---

### Task 6: Dark theme tokens with a contrast law, and offline Arabic font

**Files:**
- Create: `lib/theme/palette.dart`, `lib/theme/typography.dart`, `lib/theme/theme.dart`, `lib/core/format.dart`
- Create: `assets/fonts/IBMPlexSansArabic-Regular.ttf`, `-Medium.ttf`, `-Bold.ttf`
- Modify: `track_scribe/pubspec.yaml` (font family declaration)
- Test: `test/theme/palette_contrast_test.dart`, `test/core/format_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class Palette { static const Color bg, surface, text, textSecondary, accent, danger; }`, `double contrastRatio(Color a, Color b)`, `class Format { static String distance(double m, String sep); static String pace(double secPerKm, String sep); static String duration(int nanos); }`, and `AppTheme.dark`.

- [ ] **Step 1: Fetch the fonts once (dev-time network, runtime stays offline)**

```bash
mkdir -p track_scribe/assets/fonts
B=https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexsansarabic
for w in Regular Medium Bold; do curl -sfLO "$B/IBMPlexSansArabic-$w.ttf" -o "track_scribe/assets/fonts/IBMPlexSansArabic-$w.ttf"; done
ls -l track_scribe/assets/fonts
```
Expected: three files, each **> 100 KB**. A 1.4 KB file means GitHub returned an error page — refetch. Licence: SIL OFL 1.1 (keep the downloaded `OFL.txt` alongside and commit it).

- [ ] **Step 2: Declare fonts** in `pubspec.yaml` under `flutter:`:

```yaml
  fonts:
    - family: PlexArabic
      fonts:
        - { asset: assets/fonts/IBMPlexSansArabic-Regular.ttf, weight: 400 }
        - { asset: assets/fonts/IBMPlexSansArabic-Medium.ttf,  weight: 500 }
        - { asset: assets/fonts/IBMPlexSansArabic-Bold.ttf,    weight: 700 }
```

- [ ] **Step 3: Write the failing contrast test** — `test/theme/palette_contrast_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/theme/palette.dart';

void main() {
  test('the dark palette obeys the contrast law, not taste', () {
    expect(Palette.bg, const Color(0xFF101315));
    expect(Palette.accent, const Color(0xFFC6FF3D));
    expect(Palette.danger, const Color(0xFFB42318),
        reason: '#E03131 fails 4.5:1 for white text — danger is darkened, verified');
    expect(contrastRatio(Palette.text, Palette.bg), greaterThan(16.0));
    expect(contrastRatio(Palette.accent, Palette.bg), greaterThan(7.0));
    expect(contrastRatio(Palette.textSecondary, Palette.bg), greaterThan(4.5));
    expect(contrastRatio(Palette.text, Palette.danger), greaterThan(4.5));
    expect(contrastRatio(Palette.text, Palette.surface), greaterThan(15.0));
  });

  test('no text token sits on the accent at less than 7:1', () {
    expect(contrastRatio(Palette.onAccent, Palette.accent), greaterThan(7.0));
  });
}
```

- [ ] **Step 4: Run to see it fail** — Run: `flutter test test/theme` → Expected: FAIL, URI does not exist.

- [ ] **Step 5: Implement `lib/theme/palette.dart`**

```dart
import 'package:flutter/material.dart';

class Palette {
  const Palette._();
  static const Color bg = Color(0xFF101315);
  static const Color surface = Color(0xFF171B1E);
  static const Color text = Color(0xFFF4F7F2);
  /// 62 % of text composited over bg, precomputed so the contrast test is honest.
  static const Color textSecondary = Color(0xFF9DA4A1);
  static const Color accent = Color(0xFFC6FF3D);   // route line + big number ONLY
  static const Color onAccent = Color(0xFF101315);
  static const Color danger = Color(0xFFB42318);   // stop action ONLY
}

double _lin(double c) => c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055);

double relativeLuminance(Color c) => 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

double contrastRatio(Color a, Color b) {
  final l1 = relativeLuminance(a), l2 = relativeLuminance(b);
  return (l1 > l2 ? (l1 + 0.05) / (l2 + 0.05) : (l2 + 0.05) / (l1 + 0.05));
}
```
The `_lin` body above is `pow(c, 2.4)` written without importing `dart:math`; **replace it** with:
```dart
import 'dart:math' as math;
double _lin(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
```

- [ ] **Step 6: Implement `lib/core/format.dart`** and its failing-then-passing test

`test/core/format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/core/format.dart';

void main() {
  test('decimal separator is a token, never a hard-coded character', () {
    expect(Format.distance(4230, sep: ','), '4,23');
    expect(Format.distance(4230, sep: '.'), '4.23');
    expect(Format.distance(430, sep: ','), '0,43');
  });
  test('pace uses m:ss', () {
    expect(Format.pace(321.5, sep: ','), '5:21');
    expect(Format.pace(double.nan), '--:--');
  });
  test('duration hides hours when zero', () {
    expect(Format.duration(22 * 60 * 1000000000), '22:00');
    expect(Format.duration((36 * 60 + 2) * 60 * 1000000000), '36:02:00');
  });
}
```

`lib/core/format.dart`:

```dart
class Format {
  const Format._();
  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String distance(double metres, {required String sep}) {
    final km = metres / 1000.0;
    final whole = km.floor();
    final frac = ((km - whole) * 100).round();
    if (frac == 100) return '${whole + 1}$sep00';
    return '$whole$sep${_pad(frac)}';
  }

  static String pace(double secPerKm, {required String sep}) {
    if (secPerKm.isNaN || secPerKm <= 0 || secPerKm > 3600) return '--:--';
    final s = secPerKm.round();
    return '${(s ~/ 60).toString()}:${_pad(s % 60)}';
  }

  static String duration(int nanos) {
    final s = (nanos / 1e9).floor();
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return h == 0 ? '${_pad(m)}:${_pad(sec)}' : '$_pad2(h):${_pad(m)}:${_pad(sec)}';
  }
  static String _pad2(int n) => n.toString().padLeft(2, '0');
}
```

- [ ] **Step 7: `lib/theme/typography.dart` + `lib/theme/theme.dart`**

```dart
// typography.dart
import 'package:flutter/material.dart';
import 'package:track_scribe/theme/palette.dart';

const String kFontFamily = 'PlexArabic';
/// Tabular figures stop the counter from dancing as digits change width.
const List<FontFeature> kFigureFeatures = [FontFeature.tabularFigures()];

TextTheme darkTextTheme() => Typography.material2021().black.merge(const TextTheme(
  displaySmall: TextStyle(fontFamily: kFontFamily, fontSize: 44, fontWeight: FontWeight.w800,
                          fontFeatures: kFigureFeatures, color: Palette.accent, height: 1.0),
  titleLarge: TextStyle(fontFamily: kFontFamily, fontSize: 22, fontWeight: FontWeight.w700,
                        fontFeatures: kFigureFeatures, color: Palette.text),
  bodyLarge: TextStyle(fontFamily: kFontFamily, fontSize: 17, fontWeight: FontWeight.w600,
                       fontFeatures: kFigureFeatures, color: Palette.text),
  labelLarge: TextStyle(fontFamily: kFontFamily, fontSize: 13, fontWeight: FontWeight.w700,
                        color: Palette.text),
  labelMedium: TextStyle(fontFamily: kFontFamily, fontSize: 11, fontWeight: FontWeight.w500,
                         letterSpacing: 0.4, color: Palette.textSecondary),
))!;
```
`theme.dart`: `ThemeData.dark()` base with `scaffoldBackgroundColor: Palette.bg`, `colorScheme: ColorScheme.dark(surface: Palette.surface, primary: Palette.accent, onPrimary: Palette.onAccent, error: Palette.danger, errorContainer: Palette.danger, onError: Palette.text)`, `textTheme: darkTextTheme()`, and **`useMaterial3: true` with zero transparency on stat text** (spec §5 bans the glass panel).

- [ ] **Step 8: Run everything** — Run: `flutter test && flutter analyze` → Expected: all tests pass (the `textSecondary` and `danger` ratios are computed, so if a value is off, **change the token to satisfy the test**, never the threshold).
- [ ] **Step 9: Commit** — `git add track_scribe/assets track_scribe/lib/theme track_scribe/lib/core track_scribe/test && git commit -m "feat(theme): dark tokens under an enforced contrast law + offline Arabic font"`

---

### Task 7: Recording screen (layout B) against a synthetic fix source

**Files:**
- Create: `lib/source/fix_source.dart`, `lib/source/synthetic_fix_source.dart`, `lib/state/recording_controller.dart`, `lib/ui/recording/recording_screen.dart`, `lib/ui/recording/widgets/{stat_panel,sport_chips,stop_button,gps_status_banner}.dart`
- Modify: `lib/ui/app.dart`
- Test: `test/ui/recording_screen_test.dart`

**Interfaces:**
- Consumes: `RecorderEngine`, `SportConfig.forSport`, `Palette`, `Format`, `AppTheme.dark`.
- Produces:
```dart
abstract class FixSource { Stream<RawFix> get fixes; Future<void> start(); Future<void> stop(); }
class SyntheticFixSource implements FixSource { SyntheticFixSource({int everyMs = 100, double speedMps = 1.4}); }
class RecordingController { RecordingController({required FixSource source, required Sport sport}); … }
```

- [ ] **Step 1: `lib/source/fix_source.dart`** — interface + `SyntheticFixSource` that emits a 1.4 m/s straight-line walk with 3 m accuracy, timestamped from a `Stopwatch`, so the UI is testable with no phone:

```dart
import 'dart:async';
import 'package:track_scribe/engine/raw_fix.dart';

abstract class FixSource {
  Stream<RawFix> get fixes;
  Future<void> start();
  Future<void> stop();
}

class SyntheticFixSource implements FixSource {
  SyntheticFixSource({this.everyMs = 100, this.speedMps = 1.4, this.accuracyM = 3.0});
  final int everyMs; final double speedMps; final double accuracyM;
  final _c = StreamController<RawFix>.broadcast();
  Timer? _t; final _sw = Stopwatch();
  double _dLat = 0;
  @override Stream<RawFix> get fixes => _c.stream;
  @override Future<void> start() async {
    _sw.start();
    _t = Timer.periodic(Duration(milliseconds: everyMs), (_) {
      _dLat += speedMps * (everyMs / 1000.0);
      _c.add(RawFix(lat: 36.7538 + _dLat / 111111.0, lon: 3.1856,
          timeNanos: _sw.elapsedMicroseconds * 1000, accuracyM: accuracyM,
          speedMps: speedMps));
    });
  }
  @override Future<void> stop() async { _t?.cancel(); _sw.stop(); await _c.close(); }
}
```

- [ ] **Step 2: Write the failing widget test** — `test/ui/recording_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/ui/app.dart';

void main() {
  testWidgets('layout B: half map + big number panel, RTL, dark', (tester) async {
    tester.binding.window.physicalSizeTestValue = const Size(1080, 2340);
    tester.binding.window.devicePixelRatioTestValue = 2.75;
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
    await tester.pumpWidget(const ProviderScope(child: TrackScribeApp()));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.widget<Directionality>(find.byType(Directionality).last).textDirection,
        TextDirection.rtl);
    expect(find.text('المسافة · كم'), findsOneWidget);
    expect(find.text('جري'), findsOneWidget);
    expect(find.text('مشي'), findsOneWidget);
    expect(find.text('دراجة'), findsOneWidget);
    expect(find.text('ابدأ التسجيل'), findsOneWidget);

    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('إيقاف'), findsOneWidget);
    // the counter must be rendering a real number, not a placeholder
    expect(find.textContaining('0,'), findsWidgets);
  });

  testWidgets('stop is unreachable until a fix is good enough (rule ر7)', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TrackScribeApp()));
    await tester.pump(const Duration(milliseconds: 400));
    final f = find.text('ابدأ التسجيل');
    expect(tester.widget<ElevatedButton>(f).enabled, isTrue,
        reason: 'the synthetic source always has a fix; the disabled state is covered in Task 9');
  });
}
```

- [ ] **Step 3: Run to see it fail** — Run: `flutter test test/ui` → Expected: FAIL, `The constructor 'TrackScribeApp' has no parameter 'child'`-free but `find.text('المسافة · كم')` not found.

- [ ] **Step 4: `lib/state/recording_controller.dart`**

```dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/recorder_engine.dart';
import 'package:track_scribe/engine/sport_config.dart';
import 'package:track_scribe/source/fix_source.dart';
import 'package:track_scribe/source/synthetic_fix_source.dart';

class RecordingState {
  const RecordingState({required this.sport, required this.phase,
      this.engine, this.distanceM = 0, this.elapsedNanos = 0, this.fixCount = 0});
  final Sport sport; final RecordingPhase phase;
  final RecorderEngine? engine;
  final double distanceM; final int elapsedNanos; final int fixCount;
  RecordingState copyWith({Sport? sport, RecordingPhase? phase, RecorderEngine? engine}) =>
      RecordingState(sport: sport ?? this.sport, phase: phase ?? this.phase,
          engine: engine ?? this.engine, distanceM: distanceM,
          elapsedNanos: elapsedNanos, fixCount: fixCount);
}
enum RecordingPhase { stopped, starting, recording }

final fixSourceProvider = Provider<FixSource>((_) => SyntheticFixSource());

class RecordingController extends Notifier<RecordingState> {
  @override
  RecordingState build() => RecordingState(
      sport: Sport.run, phase: RecordingPhase.stopped, engine: null);
  StreamSubscription<RawFix>? _sub;

  void setSport(Sport s) {
    if (state.phase != RecordingPhase.stopped) return;
    state = state.copyWith(sport: s);
  }

  Future<void> start() async {
    if (state.phase != RecordingPhase.stopped) return;
    state = state.copyWith(phase: RecordingPhase.starting);
    final src = ref.read(fixSourceProvider);
    await src.start();
    _sub = src.fixes.listen(_onFix);
  }

  void _onFix(RawFix fix) {
    var e = state.engine;
    if (e == null) {
      e = RecorderEngine(SportConfig.forSport(state.sport), startNanos: fix.timeNanos);
      state = state.copyWith(phase: RecordingPhase.recording, engine: e);
    }
    e.onFix(fix);
    // mutate through a fresh state object so Riverpod notifies listeners
    state = RecordingState(sport: state.sport, phase: state.phase, engine: e,
        distanceM: e.distanceMeters, elapsedNanos: e.elapsedNanos, fixCount: e.stats.fixCount);
  }

  Future<void> stop() async {
    _sub?.cancel(); _sub = null;
    await ref.read(fixSourceProvider).stop();
    state = RecordingState(sport: state.sport, phase: RecordingPhase.stopped, engine: null);
  }
}
final recordingProvider =
    NotifierProvider<RecordingController, RecordingState>(RecordingController.new);
```

- [ ] **Step 5: Implement the five UI files.** Layout contract from the approved mockup — map 40 % of the body height, panel below, wide button, chips over the map, no opacity on numbers:

`lib/ui/recording/recording_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/state/recording_controller.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/basemap/grid_basemap.dart';
import 'package:track_scribe/ui/recording/widgets/gps_status_banner.dart';
import 'package:track_scribe/ui/recording/widgets/sport_chips.dart';
import 'package:track_scribe/ui/recording/widgets/stat_panel.dart';
import 'package:track_scribe/ui/recording/widgets/stop_button.dart';

class RecordingScreen extends ConsumerWidget {
  const RecordingScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(recordingProvider);
    final controller = ref.read(recordingProvider.notifier);
    return Scaffold(
      backgroundColor: Palette.bg,
      body: SafeArea(child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(children: [
          Expanded(flex: 4, child: Stack(children: [
            GridBasemap(points: s.engine?.storedPoints ?? const []),
            const Positioned(top: 12, right: 12, child: SportChips()),
            const Positioned(top: 12, left: 12, child: GpsStatusBanner()),
          ])),
          Expanded(flex: 6, child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              StatPanel(distanceM: s.distanceM, elapsedNanos: s.elapsedNanos,
                        sport: s.sport, fixCount: s.fixCount),
              const Spacer(),
              StopButton(phase: s.phase,
                onStart: () => controller.start(), onStop: () => controller.stop(),
                onToggle: () { s.phase == RecordingPhase.recording
                    ? controller.stop() : controller.start(); }),
            ]),
          )),
        ]),
      )),
    );
  }
}
```

`stat_panel.dart` — one big number in `Palette.accent` with `displaySmall`, then a `Row` of three `labelMedium`/`bodyLarge` pairs (المسافة · كم / الوقت / الإيقاع), pace derived as `elapsedNanos / (distanceM / 1000)` seconds, guarded for `distanceM < 50` → `--:--`, and `sep: ','` from a `localeSepProvider` (add `final localeSepProvider = Provider<String>((_) => ',');`).

`sport_chips.dart` — three chips (`مشي`, `جري`, `دراجة`) bound to `recordingProvider.notifier.setSport`, selected chip painted `Palette.accent` with `Palette.onAccent`, unselected `Palette.surface` + `Palette.textSecondary`, and disabled while `phase != stopped`.

`stop_button.dart` — `stopped/starting` → `ElevatedButton` labelled `ابدأ التسجيل` with `Palette.text` on `Palette.surface` (start is **not** red); `recording` → `FilledButton` labelled `إيقاف`, background `Palette.danger`, foreground `Palette.text`, `minimumSize: Size.fromHeight(56)` — the ≥ 56 dp one-handed target from spec §5.

`gps_status_banner.dart` — reads `fixCount`; `0` → `جارٍ البحث عن الإشارة…` chip in `Palette.surface`, `> 0` → `تسجيل نشِط` chip in accent text. Keep it dumb; the real GNSS state machine lands in Task 9.

- [ ] **Step 6: Run to see it pass** — Run: `flutter test test/ui && flutter analyze` → Expected: `+2: All tests passed!`, no analyzer issues.
- [ ] **Step 7: Commit** — `git add track_scribe/lib track_scribe/test && git commit -m "feat(ui): layout B recording screen driven by synthetic fix source"`

---

### Task 8: Local persistence with write-ahead inserts and a resume checkpoint

**Files:**
- Create: `lib/data/database.dart`, `lib/data/activity_repository.dart`
- Test: `test/data/resume_test.dart`

**Interfaces:**
- Consumes: `StoredPoint`, `WaypointType`.
- Produces:
```dart
class AppDatabase extends _$AppDatabase { AppDatabase(QueryExecutor e); AppDatabase.open(); }
class ActivityRepository {
  Future<int> insertActivity({required String uuid, required String sport, required int startWallMillis});
  Future<void> appendPoints(int activityId, List<StoredPoint> points);
  Future<void> saveResume({required int activityId, required StoredPoint lastStored, required double distanceM});
  Future<ResumeRow?> loadResume();
  Future<void> clearResume(int activityId);
}
```

- [ ] **Step 1: `lib/data/database.dart`** — drift tables exactly as spec §4, minus `alt_dem` (DEM is Plan 2):

```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

class Activities extends Table {
  IntColumn get id => integer().autoIncrement();
  TextColumn get uuid => text()();
  TextColumn get sport => text()();
  IntColumn get startWallMillis => integer()();
  IntColumn get elapsedNanos => integer().withDefault(const Constant(0))();
  RealColumn get distanceM => real().withDefault(const Constant(0))();
  RealColumn get climbM => real().withDefault(const Constant(0))();
  IntColumn get fixCount => integer().withDefault(const Constant(0))();
  IntColumn get rejectedCount => integer().withDefault(const Constant(0))();
  BoolColumn get mockDetected => boolean().withDefault(const Constant(false))();
  // sync-ready columns, deliberately unused until a backend exists
  TextColumn get serverUuid => text().nullable()();
  IntColumn get updatedAt => integer().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
}

class TrackPoints extends Table {
  IntColumn get id => integer().autoIncrement();
  IntColumn get activityId => integer().references(Activities, #id)();
  IntColumn get timeNanos => integer()();
  RealColumn get lat => real()();  RealColumn get lon => real()();
  RealColumn get accuracyM => real()();  RealColumn get speedMps => real().nullable()();
  RealColumn get bearingDeg => real().nullable()();
  TextColumn get waypointType => text()();
}

class TrackState extends Table {
  TextColumn get key => text()();
  IntColumn get activityId => integer()();
  IntColumn get lastTimeNanos => integer()();
  RealColumn get lastLat => real()(); RealColumn get lastLon => real()();
  RealColumn get lastAccuracyM => real()(); TextColumn get lastType => text()();
  RealColumn get distanceM => real()();
  @override Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Activities, TrackPoints, TrackState])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);
  AppDatabase.open() : super(_openLocal());
  @override int get schemaVersion => 1;
}

LazyDatabase _openLocal() => LazyDatabase(() async {
  final dir = await getApplicationDocumentsDirectory();
  return NativeDatabase(File(p.join(dir.path, 'track_scribe.sqlite')));
});
```
Run `dart run build_runner build --delete-conflicting-outputs` and commit `database.g.dart` — CI does not need to regenerate it.

- [ ] **Step 2: Write the failing resume test** — `test/data/resume_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';

void main() {
  test('a killed session resumes with the same distance, not a reset one (rule ر12)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = ActivityRepository(db);
    final id = await repo.insertActivity(uuid: 'u1', sport: 'run', startWallMillis: 1);
    await repo.appendPoints(id, [
      const StoredPoint(lat: 36.7538, lon: 3.1856, timeNanos: 1000, accuracyM: 4, type: WaypointType.normal),
      const StoredPoint(lat: 36.7558, lon: 3.1856, timeNanos: 9000, accuracyM: 4, type: WaypointType.normal),
    ]);
    await repo.saveResume(activityId: id,
      lastStored: const StoredPoint(lat: 36.7558, lon: 3.1856, timeNanos: 9000, accuracyM: 4, type: WaypointType.normal),
      distanceM: 222.4);

    final r = await repo.loadResume();
    expect(r, isNotNull);
    expect(r!.activityId, id);
    expect(r.distanceM, closeTo(222.4, 0.1));
    expect(r.lastStored.distanceTo(const StoredPoint(lat: 36.7538, lon: 3.1856,
        timeNanos: 1000, accuracyM: 4, type: WaypointType.normal)), closeTo(222.4, 1.0));
    await db.close();
  });

  test('every appended point is durable before the next one arrives (rule ر13)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = ActivityRepository(db);
    final id = await repo.insertActivity(uuid: 'u2', sport: 'walk', startWallMillis: 1);
    for (var i = 0; i < 50; i++) {
      await repo.appendPoints(id, [StoredPoint(lat: 36.7538 + i / 10000, lon: 3.1856,
          timeNanos: i * 1000000000, accuracyM: 5, type: WaypointType.normal)]);
    }
    expect(await repo.pointCount(id), 50);
    await db.close();
  });
}
```

- [ ] **Step 3: Run to see it fail** — `flutter test test/data` → FAIL on `undefined_class 'ActivityRepository'`.
- [ ] **Step 4: Implement `activity_repository.dart`** with the signatures above plus `Future<int> pointCount(int id)`. `appendPoints` must be one `batch()` that inserts each point (`waypointType.name`) and returns only after the transaction completes — that is the write-ahead guarantee; `saveResume` upserts `TrackState` with `key: 'resume'`.
- [ ] **Step 5: Run to see them pass** — `flutter test && flutter analyze` → `+13` (adjust to the real count) all passing.
- [ ] **Step 6: Commit** — `git commit -am "feat(data): drift schema with per-point durability and resume checkpoint"`

---

### Task 9: Real fixes — production `FixSource`, permissions, and surviving ColorOS

**Files:**
- Create: `lib/source/geolocator_fix_source.dart`, `lib/data/app_database_provider.dart`, `android/app/src/main/res/xml/` (nothing new needed), `lib/ui/onboarding/permission_screen.dart`
- Modify: `track_scribe/android/app/src/main/AndroidManifest.xml`, `lib/state/recording_controller.dart` (`fixSourceProvider` → geolocator in `main.dart` via override)
- Test: `test/source/gps_gate_test.dart`

**Interfaces:**
- Consumes: `RecorderEngine`, `ActivityRepository`.
- Produces: `GeolocatorFixSource implements FixSource`, `bool isFixGoodEnough(RawFix fix)` (rule ر7), `class GpsQuality { none, searching, ok, degraded, lost }`.

- [ ] **Step 1: Write the failing GPS-gate test** — pure function, so the "no start without a fix" rule is provable without a device:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/source/geolocator_fix_source.dart';

RawFix f(double acc, {int sec = 0}) => RawFix(lat: 1, lon: 1,
    timeNanos: sec * 1000000000, accuracyM: acc);

void main() {
  test('start is refused until two consecutive fixes are ≤ 35 m (rule ر7)', () {
    final gate = FixQualityGate();
    expect(gate.ready, isFalse);
    expect(gate.add(f(12)), isFalse);        // one good fix is not enough
    expect(gate.add(f(30)), isTrue);         // second consecutive good fix
    expect(gate.add(f(40)), isTrue);         // stays ready, but…
    expect(gate.quality, GpsQuality.degraded); // …flagged degraded, shown in UI
    expect(gate.add(f(90)), isTrue);
    expect(gate.quality, GpsQuality.degraded);
  });
  test('a single fix never lies about quality', () {
    expect(const GpsQualityX.fromAccuracy(200), GpsQuality.searching);
  });
}
```
(Second test defines `GpsQualityX.fromAccuracy` as the rule used in Task 9's banner chip: `> 35 m → searching`, `20–35 → degraded`, `≤ 20 → ok`, plus rule ر8's `lost` when no fix for 20 s.)

- [ ] **Step 2: Manifest — declare exactly what we use, no more**

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
<uses-feature android:name="android.hardware.location.gps" android:required="true" />
```
and inside `<application>`:
```xml
<service android:name=id.flutter.flutter_background_service.BackgroundService
         android:foregroundServiceType="location"
         android:exported="false" />
```
**No `ACCESS_BACKGROUND_LOCATION`** — recording runs only while the service is foregrounded (spec §5 of the research: it shrinks Play review and is unnecessary).

- [ ] **Step 3: `GeolocatorFixSource`** — map `geolocator.Position` → `RawFix`, with a `Stopwatch` timestamp because the plugin hides `elapsedRealtimeNanos`:

```dart
import 'dart:async';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/source/fix_source.dart';

class GeolocatorFixSource implements FixSource {
  StreamSubscription<gl.Position>? _sub;
  final _c = StreamController<RawFix>.broadcast();
  final _sw = Stopwatch()..start();
  @override Stream<RawFix> get fixes => _c.stream;
  @override Future<void> start() async {
    var perm = await gl.Geolocator.checkPermission();
    if (perm != gl.LocationPermission.whileInUse && perm != gl.LocationPermission.always) {
      perm = await gl.Geolocator.requestPermission();
    }
    if (perm == gl.LocationPermission.denied || perm == gl.LocationPermission.deniedForever) {
      throw const LocationPermissionDenied();
    }
    _sub = gl.Geolocator.getPositionStream(locationSettings: gl.LocationSettings(
      accuracy: gl.LocationAccuracy.high, distanceFilter: 0,
    )).listen((p) => _c.add(RawFix(
      lat: p.latitude, lon: p.longitude, timeNanos: _sw.elapsedMicroseconds * 1000,
      accuracyM: p.accuracy, altitudeM: p.altitude, speedMps: p.speed,
      bearingDeg: p.heading, isMocked: p.isMocked ?? false,
      wallMillis: p.timestamp.millisecondsSinceEpoch,
    )));
  }
  @override Future<void> stop() async { await _sub?.cancel(); _sub = null; }
}
class LocationPermissionDenied implements Exception { const LocationPermissionDenied(); }

class FixQualityGate {
  bool _ready = false; int _goodStreak = 0;
  GpsQuality quality = GpsQuality.none;
  bool get ready => _ready;
  bool add(RawFix fix) {
    quality = GpsQualityX.fromAccuracy(fix.accuracyM);
    if (fix.accuracyM <= 35) { _goodStreak++; if (_goodStreak >= 2) _ready = true; }
    else { _goodStreak = 0; }
    return _ready;
  }
}
```
Add `enum GpsQuality { none, searching, ok, degraded, lost }` and `class GpsQualityX { static GpsQuality fromAccuracy(double a) => a > 35 ? GpsQuality.searching : (a > 20 ? GpsQuality.degraded : GpsQuality.ok); }`.

- [ ] **Step 4: Battery-optimisation onboarding (the ColorOS problem the spec §7 demands)** — `lib/ui/onboarding/permission_screen.dart` with four rows, each opening a real state: (1) allow while-in-use location, (2) `Geolocator.openBatteryOptimizationSettings()`, (3) `Geolocator.openAppSettings()`, (4) static instructions for Realme autostart (`الإعدادات → إدارة التطبيقات → track_scribe → السماح بالتشغيل التلقائي`). Each row shows the verified current state, not just a button — and this screen is the **first** screen on a fresh install, reachable again from settings.
- [ ] **Step 5: Wire production source** — in `lib/main.dart` override the provider:

```dart
runApp(ProviderScope(overrides: [fixSourceProvider.overrideWithValue(GeolocatorFixSource())],
  child: const TrackScribeApp()));
```
and in `RecordingController.start()`, refuse to enter `recording` until `FixQualityGate.ready`, appending every stored point through `ActivityRepository.appendPoints` and calling `saveResume` whenever a point is stored.

- [ ] **Step 6: Push through CI, install, and field-verify on the phone**

```bash
git add -A && git commit -m "feat(source): geolocator stream, GPS gate, battery-optimization onboarding"
git push origin main
gh run watch <new-run-id> --exit-status
gh run download <new-run-id> -n track-scribe-debug-apk && adb install -r app-debug.apk
```
Then **walk 200 m outdoors, screen on then screen off**, take screenshots with `adb exec-out screencap -p > check-<n>.png`, and read them. Expected: distance within ~2 % of a measuring-tape/known-path value; `الوقت` keeps counting when you stand still and `المسافة` does not move.
- [ ] **Step 7: Kill-resistance check (rule ر12)** — during a recording:
```bash
adb shell am kill dev.toufik.track_scribe
```
Expected: notification survives or reappears, and the resumed distance starts from the checkpoint (not 0). Capture a screenshot **before and after** the kill; both numbers go into the report.

---

### Task 10: Dark generated basemap with the route polyline

**Files:**
- Create: `lib/ui/basemap/basemap.dart`, `lib/ui/basemap/grid_basemap.dart`, `lib/ui/basemap/route_painter.dart`, `lib/state/locale_providers.dart`
- Test: `test/ui/basemap_test.dart`

**Interfaces:**
- Consumes: `Palette`, `StoredPoint`.
- Produces: `abstract class Basemap { Widget build(BuildContext c, {required List<StoredPoint> points, required Rect bounds}); }`, `class GridBasemap extends StatelessWidget { GridBasemap({required List<StoredPoint> points}); }`.

- [ ] **Step 1: Failing test** — assert the widget renders and that a two-point route produces a stroked path without throwing on an empty route (the crash case that kills recording screens):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/ui/basemap/grid_basemap.dart';

void main() {
  testWidgets('empty route renders a grid, never throws', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: SizedBox(width: 300, height: 300, child: GridBasemap(points: []))));
    expect(find.byType(CustomPaint), findsWidgets);
  });
  testWidgets('a stored route paints in the accent colour', (tester) async {
    const pts = [
      StoredPoint(lat: 36.7538, lon: 3.1856, timeNanos: 0, accuracyM: 4, type: WaypointType.normal),
      StoredPoint(lat: 36.7558, lon: 3.1876, timeNanos: 1000, accuracyM: 4, type: WaypointType.normal),
    ];
    await tester.pumpWidget(const MaterialApp(
        home: SizedBox(width: 300, height: 300, child: GridBasemap(points: pts))));
    final p = tester.renderObject<CustomPaint>(find.byType(CustomPaint).last).painter!;
    expect(p, isA<RoutePainter>());
  });
}
```
- [ ] **Step 2: Implement** — `GridBasemap` fills `Palette.surface`, draws a 40 px grid in `Color(0x14F4F7F2)` (grid is decoration, not text, so the contrast law does not bind it), then `RoutePainter` maps lat/lon to canvas via equirectangular scaling about the bounds centre (valid for a single route's extent), stroking `Palette.accent` at 5.0 width with round joins, skipping `WaypointType.rejected` points (drawn as 3 px faint dots so the raw trail stays visible honestly), and a 9 px start dot + 9 px end ring. Padding of 24 px so a route is never cut off; if `points.length < 2`, only the start dot renders.
- [ ] **Step 3: Run** — `flutter test test/ui && flutter analyze` → Expected: all pass.
- [ ] **Step 4: Device check** — rebuild through CI, install, record 400 m, and **read the screenshot**: the line must hug the road you actually walked. If it visibly zig-zags, that is a Task 4 gate problem — fix it there, not by smoothing the drawing.
- [ ] **Step 5: Commit** — `git commit -am "feat(ui): generated dark basemap with honest route rendering"`

---

### Task 11: The evidence harness — no fidelity claim without a table

**Files:**
- Create: `test/evidence/fixtures/README.md`, `test/evidence/synthetic_injection_test.dart`, `test/evidence/golden_replay_test.dart`, `tool/replay.dart`, `docs/superpowers/evidence/2026-10-09-fidelity-baseline.md`

**Interfaces:**
- Consumes: `RecorderEngine`, `SportConfig.forSport`, `package:gpx`.
- Produces: a printed table of `| scenario | engine distance | truth | error % |` that the doc file records; this table is the precondition for any marketing sentence.

- [ ] **Step 1: Synthetic injection suite** — deterministic, runs on the 2-core machine, no phone:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/recorder_engine.dart';
import 'package:track_scribe/engine/sport_config.dart';

List<RawFix> line({required double metres, required double speedMps,
                   required double accuracyM, required double jitterM, double? seedShift}) {
  final per = 1.0;                        // 1 Hz
  final steps = (metres / (speedMps * per)).ceil();
  return [for (var i = 0; i <= steps; i++)
    RawFix(lat: 36.7538 + (i * speedMps * per + (i.isEven ? jitterM : -jitterM)) / 111111.0,
           lon: 3.1856, timeNanos: (i * per * 1e9).round(), accuracyM: accuracyM,
           speedMps: speedMps)];
}

void main() {
  test('1000 m walk with ±10 m noise: engine error stays under 1 %', () {
    final e = RecorderEngine(SportConfig.forSport(Sport.walk), startNanos: 0);
    for (final f in line(metres: 1000, speedMps: 1.4, accuracyM: 10, jitterM: 10)) e.onFix(f);
    final err = (e.distanceMeters - 1000).abs() / 1000;
    expect(err, lessThan(0.01), reason: 'got ${e.distanceMeters.toStringAsFixed(1)} m');
  });
  test('25 m teleportation does not create distance (rule ر4)', () {
    final e = RecorderEngine(SportConfig.forSport(Sport.run), startNanos: 0);
    final fixes = line(metres: 500, speedMps: 3.0, accuracyM: 5, jitterM: 3).toList();
    for (var i = 0; i < fixes.length; i++) {
      e.onFix(fixes[i]);
      if (i == 100) e.onFix(RawFix(lat: fixes[i].lat + 0.00025, lon: 3.1856,
          timeNanos: fixes[i].timeNanos + 1000000000, accuracyM: 6));
    }
    expect(e.stats.rejectedCount, greaterThan(0));
    expect(e.distanceMeters, lessThan(560));
  });
  test('10 minutes of standing adds 0 m and full time (rule ر6)', () {
    final e = RecorderEngine(SportConfig.forSport(Sport.walk), startNanos: 0);
    e.onFix(RawFix(lat: 36.7538, lon: 3.1856, timeNanos: 0, accuracyM: 3, speedMps: 1.2));
    for (var s = 1; s <= 600; s++) {
      e.onFix(RawFix(lat: 36.7538, lon: 3.1856, timeNanos: s * 1000000000, accuracyM: 3, speedMps: 0.0));
    }
    expect(e.distanceMeters, 0.0);
    expect(e.elapsedNanos, 600_000_000_000);
  });
}
```
If the first test fails because our gate under-counts, **do not loosen the threshold to pass** — tune `gateFor`/`forceStoreAfterS` in `SportConfig` and re-run until it earns the 1 %.
- [ ] **Step 2: GPX replay tool** — `tool/replay.dart` reads a `.gpx` with `package:gpx`, feeds a `RecorderEngine`, and prints the table. Run:
```bash
dart run tool/replay.dart test/evidence/fixtures/walk-1km.gpx --truth 1000 | tee -a docs/superpowers/evidence/2026-10-09-fidelity-baseline.md
```
- [ ] **Step 3: Capture real fixtures from the phone** — no invented ground truth: record three known courses on the Realme (`adb pull` the activity DB with `adb exec-out run-as dev.toufik.track_scribe cat databases/track_scribe.sqlite > local.sqlite`, or export GPX once Plan 2 adds export), measure each course with a mapped distance from OpenStreetMap routing, and store the fixture + a `--truth` value in `test/evidence/fixtures/README.md`. Until a fixture exists, the golden test file is **skipped with a printed reason**, never faked.
- [ ] **Step 4: Field protocol on the phone** (this is the deliverable he asked for): one measured 1 km walking course, three repetitions, and for each rep record `app distance / Strava distance / true distance` from screenshots taken with `adb exec-out screencap`. Write the numbers into `2026-10-09-fidelity-baseline.md` with the run id of the CI build used, then state the conclusion in one sentence and **only** the sentence the table supports.
- [ ] **Step 5: Commit** — `git commit -am "test(evidence): synthetic injection suite, replay harness, fidelity baseline table"`

---

## Plan 1 → Plan 2 hand-off list (not in scope, tracked so nothing is lost)

DEM altitude + climb/descent (ر11) · GPX/FIT/CSV export and import · history list and activity detail · light/sunlight token layer · offline tile pipeline spike (`tilemaker` + PMTiles licence check) · Kotlin raw-`Location` channel for `elapsedRealtimeNanos`/`verticalAccuracy` · Kalman/RTS filter **only if** Task 11 shows a measurable need · Health Connect write · sharing and paywall (explicitly deferred by the user).
