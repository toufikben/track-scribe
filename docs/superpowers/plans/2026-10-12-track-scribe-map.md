# خطة 2: الخريطة الحقيقية الأوفلاين — شاشة التسجيل + شاشة تفاصيل النشاط

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the generated grid basemap with a real offline vector map (bundled PMTiles + OpenFreeMap dark style) on the recording screen, and add the finished-activity detail screen (speed-graded route, markers, direction arrow, elevation strip, thickness choice).

**Architecture:** Two PMTiles packs (Alger wilaya z0-14 + Algeria z0-12) ship as Flutter assets and are copied once to app documents by a versioned `TileStore`; a custom `VectorTileProvider` (pmtiles 2.2.0, file-backed lazy reads) serves `flutter_map_vector_tiles` 2.9.1, whose pipeline clamps overzoom to `provider.maximumZoom` itself (verified in tile_store.dart). The localized OpenFreeMap dark style loads from `asset://` with `cache: false` and `resolveProvider` — zero runtime network. The recording band and the detail screen share one `mapStyleProvider`; `GridBasemap` stays as the honest fallback so recording never depends on the map.

**Tech Stack:** flutter_map 8.3.2 (BSD-3, already pinned), flutter_map_vector_tiles 2.9.1 (BSD-3), pmtiles 2.2.0 (BSD-2-Clause), flutter_riverpod, drift, path_provider.

**Spec:** `docs/superpowers/specs/2026-10-09-route-recorder-dark-ui-design.md` §12 (addendum of 2026-10-12) — the plan argues from the spec; executors read both. Evidence: `docs/superpowers/evidence/2026-10-12-tile-spike.md`.

## Global Constraints

(Every task's requirements implicitly include this section. Exact values verbatim.)

- CI is the only APK builder; the local PC only runs `flutter analyze` / `flutter test` (never `flutter build`). Device verification on the Realme via adb; never accept the device PIN.
- Packs (exact artifact bytes, from CI runs 38201305204 / 38201311231): `assets/tiles/dz-wilaya-alger-z14.pmtiles` = **20,548,695 B**; `assets/tiles/dz-country-z12.pmtiles` = **53,718,750 B**.
- **R103 — packs are data, not code.** A PMTiles header self-describes its `minZoom`/`maxZoom`/bounds (pmtiles 2.2.0, `archive.dart:386-416`), so `LocalPmTilesProvider` orders archives by each header's `maxZoom` (deepest first) and `mapStyleProvider` opens every name in `kBundledTileNames`. Adding a country or world pack = one name in the registry + one asset file. No task may branch on a pack filename.
- **Coverage scope (owner decision 2026-10-12):** Algeria only for this plan. The world pack is *not* promised or added — it is decided only after two measured numbers exist (world z0-6 pack size from the tiles-spike CI job, and the real APK size after Task 1). Until then no code, asset, or test may reference a world pack.
- Dep pins: `flutter_map_vector_tiles: 2.9.1`, `pmtiles: 2.2.0` (both licenses verified: BSD-3 / BSD-2-Clause). Task 4 also had to add `latlong2: ^0.10.1` to `dependencies` — the band imports `package:latlong2/latlong.dart` directly, and a transitive-only import is what `depend_on_referenced_packages` flags.
- Style colors: land background `#101315` (= `Palette.bg`), water `#182128` (spec's «مائلًا» — leaning blue), live route `#C6FF3D` (= `Palette.accent`, 5 px), speed gradient slow `#4D6112` → fast `#C6FF3D`, grade shading same ramp (flat → steep).
- Attribution row, always visible and never dismissable, exactly: `© OpenStreetMap contributors · © OpenMapTiles · Style: OpenFreeMap (MIT)`.
- Zero runtime network: `StyleReader(cache: false)`, `asset://` URI, `resolveProvider`; the custom provider never touches http; `cacheBytesToDisk => false`.
- **R104 — widget tests cannot reach a `FutureProvider` branch by `await`ing real work inside `testWidgets`.** Both `getApplicationDocumentsDirectory()` (unmocked platform channel) and `rootBundle.load()` (`flutter/assets`) are dispatched to the delegate, whose reply needs the real event loop that `AutomatedTestWidgetsFlutterBinding` never runs, so the future pends and the test dies at the 10-minute `TimeoutException` ceiling — not at an assertion. Any test that must render the loaded/data branch loads its `Style` in `setUpAll` (via `test/support/stub_vector_style.dart`) and overrides `mapStyleProvider`. The error branch needs no such trick — an overridden provider that throws completes immediately, in fake time, which is how `vector_map_band_test` pins the fallback. The bundled style deliberately KEEPS the upstream `"url":"https://tiles.openfreemap.org/planet"` (MIT attribution fidelity), and `style_reader.dart:276-277` short-circuits it only when `resolveProvider` returns a provider for that exact source id — so **every** `StyleReader` call site must pass `resolveProvider` with id `openmaptiles`. A map test that wires a wrong id is a bug that would dial out; `test/ui/map_style_test.dart` keeps a no-network client so a mis-wire fails loudly instead.
- **R105 — a live map must not recenter on every fix.** `MapController.move`/`rotate` restart the vector tile fetch, and on a two-core phone decoding the visible tiles takes longer than the gap between fixes (or between timer rebuilds), so a follow-every-fix band paints NOTHING for the whole session — measured on the realme: streets while idle, flat once recording started, back within seconds of a finger pan. The rule lives in `lib/ui/basemap/follow_policy.dart::shouldRecenter` (pure, unit-tested): move only past 60 % of the half band's shorter side, measured in metres with `haversineMeters`; rotations need a >3° change. Task 6's replay band and Task 7's export renderer MUST reuse it — a replay camera that chases every sample has the same failure.
- **R106 — a verified permission row must re-probe on resume.** GPS and the permission are changed outside the app (shade toggle, system Settings), so a cached `FutureProvider` reads as a lie when the user returns: measured with `gps provider: enabled=true` while row 2 still said «غير مُفعّل». Any screen that gates on a platform fact registers a `WidgetsBindingObserver` and invalidates its probes on `AppLifecycleState.resumed`.
- Recording never blocks on the map: while the style loads, or if it fails, the band shows `Palette.bg` / `GridBasemap` respectively — the route polyline stays visible in the fallback.
- Map labels use the system font (renderer ignores `glyphs`); Arabic reaches the map via Android fallback; UI stays Arabic-first RTL (R23 explicit `Directionality`); no flutter_localizations; IBM Plex Sans Arabic assets unchanged.
- Contrast law unchanged: `Palette` tokens and `test/theme/palette_contrast_test.dart` are laws; `danger` stays reserved for stop. Map internals (grid/gradient/water) are decoration — no contrast claims.
- Engine laws ر1–ر13, R40–R102 unchanged; under-count, never invent. `unmeasuredAccuracyM = double.infinity` stays the sentinel (R74).
- Corner ownership on the recording map band (guarded by `test/ui/overlay_bounds_test.dart` + the 360 dp basemap test): chips top-right, GPS banner bottom-left, north icon top-left, scale bar bottom-right. Keys `basemap-north` / `basemap-scale` keep their names.
- Commit style: conventional, terse, per existing history (`spec(12): …`, `feat(map): …`). Push to `plan1-recorder-dark-ui`; CI (`android-apk.yml`, flutter 3.47.5) is the verifier.

---

## File Structure

- Create: `lib/data/tile_store.dart` — versioned first-launch copy of the two packs + `tileStoreProvider`.
- Create: `lib/ui/basemap/local_pmtiles_provider.dart` — the 5-member `VectorTileProvider` over two `PmTilesArchive`s.
- Create: `lib/ui/basemap/map_style_provider.dart` — `mapStyleProvider: FutureProvider<Style>` (style + provider + sprites lifecycle).
- Create: `lib/ui/basemap/scale_bar.dart` — `ScaleBar` extracted from `grid_basemap.dart` (public `scaleLabelMetres`), reused by both basemaps.
- Create: `lib/ui/basemap/vector_map_band.dart` — the recording map band: FlutterMap + VectorTileLayer + route + halo + marker + follow/recenter/heading + attribution strip.
- Create: `lib/data/activity_summary.dart` — `ActivitySummary` model.
- Create: `lib/ui/detail/activity_detail_screen.dart` — detail screen + `activityDetailProvider`.
- Create: `lib/ui/detail/graded_route_layer.dart` — speed-graded polyline layer + direction arrow + pure helpers (`segmentSpeedMps`, `speedColor`).
- Create: `lib/ui/detail/elevation_strip.dart` — elevation strip painter with grade shading + pure helper `gradeColor`.
- Modify: `track_scribe/pubspec.yaml` — deps + assets (`assets/tiles/`, `assets/styles/`).
- Modify: `lib/ui/basemap/grid_basemap.dart` — use the extracted `ScaleBar` (behavior/keys unchanged).
- Modify: `lib/ui/recording/recording_screen.dart` — `GridBasemap` → `VectorMapBand`; post-stop «تفاصيل النشاط» button.
- Modify: `lib/state/recording_controller.dart` — `RecordingState.lastActivityId` (set at stop, cleared at start).
- Modify: `lib/data/activity_repository.dart` — `loadActivityWithPoints(int) → Future<ActivitySummary?>`.
- Delete: `lib/ui/basemap/basemap.dart` — the abstract interface's only implementer was GridBasemap; the new band has a different contract (no `bounds`), so the interface is dead code.
- Assets (committed binaries, downloaded from CI artifacts in Task 1): `assets/tiles/dz-wilaya-alger-z14.pmtiles`, `assets/tiles/dz-country-z12.pmtiles`; `assets/styles/dark.json`, `assets/styles/sprites/ofm.json`, `assets/styles/sprites/ofm.png`, `assets/styles/sprites/ofm@2x.png`.
- Tests: `test/data/tile_store_test.dart`, `test/ui/local_pmtiles_provider_test.dart`, `test/ui/map_style_test.dart`, `test/ui/vector_map_band_test.dart`, `test/ui/detail_screen_test.dart`, `test/ui/graded_route_layer_test.dart`, `test/ui/elevation_strip_test.dart`, `test/data/activity_detail_repository_test.dart`, plus edits to `test/state/recording_controller_test.dart`, `test/ui/recording_screen_test.dart`, `test/ui/basemap_test.dart` (imports only if needed).

---

## Task 1: الحزم كأصول + TileStore النسخة الأولى

**Files:**
- Modify: `track_scribe/pubspec.yaml` (deps `flutter_map_vector_tiles: 2.9.1`, `pmtiles: 2.2.0`; assets `assets/tiles/`, `assets/styles/`)
- Create: `track_scribe/assets/tiles/dz-wilaya-alger-z14.pmtiles`, `track_scribe/assets/tiles/dz-country-z12.pmtiles` (downloaded, not generated)
- Create: `lib/data/tile_store.dart`
- Test: `test/data/tile_store_test.dart`

**Interfaces:**
- Consumes: `activityRepositoryProvider` (from `lib/data/app_database_provider.dart`), `ActivityRepository.flag/setFlag` (existing).
- Produces: `TileStore.ensureBundledTiles() → Future<String>` (tiles dir path), `TileStore.flagKey = 'tiles-v1'`, `kBundledTileNames`, `tileStoreProvider`. Tasks 2/4/6 consume these.

- [ ] **Step 1: Download the two measured packs from CI**

```bash
cd track_scribe/assets && mkdir -p tiles
gh api repos/toufikben/track-scribe/actions/runs/38201305204/artifacts --jq '.artifacts[] | .name'
# find the wilaya z0-14 artifact name, then:
gh run download 38201305204 -n <wilaya-z14-artifact-name> -D /tmp/packs
gh run download 38201311231 -n <country-z12-artifact-name> -D /tmp/packs
```

Verify sizes BEFORE committing (the spec's measured numbers are the contract):

```bash
find /tmp/packs -name '*.pmtiles' -exec ls -l {} \;
# expect exactly: 20548695  and  53718750
```

Copy into place with these exact names: `assets/tiles/dz-wilaya-alger-z14.pmtiles` (20,548,695 B) and `assets/tiles/dz-country-z12.pmtiles` (53,718,750 B). If an artifact expired (90-day retention), re-run `.github/workflows/tiles-spike.yml` with `max_zoom=14`, take the new run ids, and record them in the commit message — the byte sizes must still match (same OSM data window may differ; then the spec's numbers get a one-line correction commit).

- [ ] **Step 2: Add dependencies and asset declarations to pubspec.yaml**

Under `dependencies:` add (exact pins):

```yaml
  flutter_map_vector_tiles: 2.9.1
  pmtiles: 2.2.0
```

Under `flutter:` add:

```yaml
  assets:
    - assets/tiles/
    - assets/styles/
    - assets/fonts/
```

(Keep the existing font entry; `assets/fonts/` is already declared — do not duplicate it.)

- [ ] **Step 3: Run pub get and confirm resolution**

```bash
cd track_scribe && flutter pub get
```

Expected: resolves with no version conflicts (app SDK `^3.13.4` satisfies pmtiles 2.2.0's `^3.11.3`). If resolution fails, report BLOCKED with the exact conflict instead of downgrading.

- [ ] **Step 4: Write the failing TileStore test**

`test/data/tile_store_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/data/tile_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // rootBundle

  late AppDatabase db;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase.forTesting(); // the in-memory pattern from test/data/resume_test.dart
    tmp = await Directory.systemTemp.createTemp('tile-store');
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('first run copies both packs at exact sizes and sets the flag', () async {
    final store = TileStore(ActivityRepository(db), baseDir: () async => tmp);
    final dir = await store.ensureBundledTiles();
    expect(
      File(p.join(dir, 'dz-wilaya-alger-z14.pmtiles')).lengthSync(),
      20548695,
    );
    expect(File(p.join(dir, 'dz-country-z12.pmtiles')).lengthSync(), 53718750);
    expect(await ActivityRepository(db).flag(TileStore.flagKey), isTrue);
  });

  test('a missing pack is re-copied even when the flag is set', () async {
    final store = TileStore(ActivityRepository(db), baseDir: () async => tmp);
    final dir = await store.ensureBundledTiles();
    File(p.join(dir, 'dz-country-z12.pmtiles')).deleteSync();
    await store.ensureBundledTiles();
    expect(File(p.join(dir, 'dz-country-z12.pmtiles')).lengthSync(), 53718750);
  });
}
```

(If `AppDatabase.forTesting()` does not exist, use the exact in-memory constructor the data tests already use — read `test/data/resume_test.dart` and mirror it.)

- [ ] **Step 5: Run it — expect compile failure (no tile_store.dart)**

```bash
cd track_scribe && flutter test test/data/tile_store_test.dart
```

Expected: FAIL — `Error: Couldn't resolve the package 'track_scribe' in ... tile_store.dart` (file missing).

- [ ] **Step 6: Implement TileStore**

`lib/data/tile_store.dart`:

```dart
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/app_database_provider.dart';

/// Bundled tile packs: `assets/tiles/<name>` → `<documents>/tiles/<name>`.
/// Exact artifact sizes from CI runs 38201305204 / 38201311231 (spec §12.1).
const kBundledTileNames = [
  'dz-wilaya-alger-z14.pmtiles', // 20_548_695 B — Alger wilaya z0-14
  'dz-country-z12.pmtiles', // 53_718_750 B — Algeria z0-12
];

/// Versioned first-launch copy of the bundled packs into app documents —
/// pmtiles opens archives from real file paths (lazy range reads), so the
/// packs cannot be read from inside the APK.
class TileStore {
  TileStore(this._repo, {Future<Directory> Function()? baseDir})
    : _baseDir = baseDir ?? getApplicationDocumentsDirectory;

  final ActivityRepository _repo;
  final Future<Directory> Function() _baseDir;

  static const flagKey = 'tiles-v1';

  /// Copies the packs if the flag is unset OR any pack is missing (a copy
  /// killed mid-write must not leave a permanently broken install). Returns
  /// the tiles directory path.
  Future<String> ensureBundledTiles() async {
    final docs = await _baseDir();
    final dir = Directory(p.join(docs.path, 'tiles'));
    await dir.create(recursive: true);
    var needCopy = !await _repo.flag(flagKey);
    if (!needCopy) {
      for (final name in kBundledTileNames) {
        if (!await File(p.join(dir.path, name)).exists()) {
          needCopy = true;
          break;
        }
      }
    }
    if (needCopy) {
      for (final name in kBundledTileNames) {
        final data = await rootBundle.load('assets/tiles/$name');
        await File(p.join(dir.path, name)).writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      await _repo.setFlag(flagKey, true);
    }
    return dir.path;
  }
}

final tileStoreProvider = Provider<TileStore>(
  (ref) => TileStore(ref.watch(activityRepositoryProvider)),
);
```

- [ ] **Step 7: Run the test — pass**

```bash
cd track_scribe && flutter test test/data/tile_store_test.dart
```

Expected: PASS (2 tests).

- [ ] **Step 8: Commit**

```bash
git add track_scribe/pubspec.yaml track_scribe/pubspec.lock track_scribe/assets/tiles/ lib/data/tile_store.dart test/data/tile_store_test.dart
git commit -m "feat(map): bundle the two measured PMTiles packs and copy them on first launch"
```

Note in the commit body: pack byte sizes + the two CI run ids + licenses (OSM data ODbL via the attribution row; pack generation Apache-2.0 tooling).

---

## Task 2: LocalPmTilesProvider — المزوّد المحلي للبلاطات

**Files:**
- Create: `lib/ui/basemap/local_pmtiles_provider.dart`
- Test: `test/ui/local_pmtiles_provider_test.dart`

**Interfaces:**
- Consumes: `PmTilesArchive.fromBytes` / `from` / `tile(int) → Future<Tile>` / `Tile.bytes()` / `TileNotFoundException` / `ZXY(z,x,y).toTileId()` / `minZoom` / `maxZoom` (pmtiles 2.2.0 — all verified); `VectorTileProvider`, `TileKey`, `TileResponseData/NotFound/Cancelled`, `CancellationToken.isCancelled` (flutter_map_vector_tiles 2.9.1 — verified).
- Produces: `LocalPmTilesProvider({required List<PmTilesArchive> archives, required String cacheKey})` with `minimumZoom`, `maximumZoom`, `cacheKey`, `cacheBytesToDisk => false`, `load`, `dispose`. Tasks 3/4/6 consume it. The constructor **sorts `_archives` by each archive's own `maxZoom`, deepest first** — pack priority comes from the PMTiles header, never from caller order, so adding a pack is one name in `kBundledTileNames` + one asset file (Ruling R103).

**Facts the implementer must trust (all verified from the 2.9.1 / 2.2.0 sources, do not re-verify):** the fmvt pipeline clamps overzoom to `provider.maximumZoom` itself (`tile_store.dart` clamps request zooms), so the provider serves EXACT tiles only and reports honest zoom bounds; `tile()` returns a `Tile` that throws `TileNotFoundException` from `bytes()` when absent (no exception from `tile()` itself); `TileKey` is normalized (`x` wrapped, `y` in range); `dispose()` is called by `Style.dispose()`.

- [ ] **Step 1: Write the failing test**

`test/ui/local_pmtiles_provider_test.dart`:

```dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:track_scribe/ui/basemap/local_pmtiles_provider.dart';

TileKey _tileKeyAt(int z, double lat, double lon) {
  final n = 1 << z;
  final x = ((lon + 180) / 360 * n).floor();
  final rad = lat * math.pi / 180;
  final y =
      ((1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2 * n)
          .floor();
  return TileKey(z, x, y);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('serves a real wilaya tile, reports honest zooms, rejects outside', () async {
    final data = await rootBundle.load('assets/tiles/dz-wilaya-alger-z14.pmtiles');
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final archive = await PmTilesArchive.fromBytes(bytes);
    final provider = LocalPmTilesProvider(
      archives: [archive],
      cacheKey: 'test-wilaya',
    );

    expect(provider.minimumZoom, 0);
    expect(provider.maximumZoom, 14);
    expect(provider.cacheKey, 'test-wilaya');
    expect(provider.cacheBytesToDisk, isFalse);

    // Algiers centre — inside the wilaya bounds (2.85..3.68 E, 36.42..37.10 N)
    final inside = await provider.load(_tileKeyAt(14, 36.7525, 3.0420));
    expect(inside, isA<TileResponseData>());
    expect((inside as TileResponseData).bytes.length, greaterThan(100));

    // far outside the pack (30 N, 0 E is beyond its bounds)
    final outside = await provider.load(_tileKeyAt(14, 30.0, 0.0));
    expect(outside, isA<TileResponseNotFound>());

    // a zoom the pack does not cover is not the pack's job — the pipeline
    // clamps, but a direct over-range request must be NotFound, never a throw
    final deep = await provider.load(_tileKeyAt(17, 36.7525, 3.0420));
    expect(deep, isA<TileResponseNotFound>());

    provider.dispose();
  });

  test('serves the country pack at a zoom only it covers', () async {
    final data = await rootBundle.load('assets/tiles/dz-country-z12.pmtiles');
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final country = await PmTilesArchive.fromBytes(bytes);
    final provider = LocalPmTilesProvider(
      archives: [country],
      cacheKey: 'test-country',
    );
    expect(provider.maximumZoom, 12);
    // a z12 tile inside Algeria (Tamanrasset ~22.8 N, 5.5 E)
    final res = await provider.load(_tileKeyAt(12, 22.8, 5.5));
    expect(res, isA<TileResponseData>());
    provider.dispose();
  });

  // Ruling R103: pack priority comes from each PMTiles header's own maxZoom,
  // never from the order the caller passed. Adding a pack must be data.
  test('deepest-pack-first ordering comes from the headers, not caller order', () async {
    Future<Uint8List> assetBytes(String name) async {
      final data = await rootBundle.load('assets/tiles/$name');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }

    final wilaya = await PmTilesArchive.fromBytes(
      await assetBytes('dz-wilaya-alger-z14.pmtiles'),
    );
    final country = await PmTilesArchive.fromBytes(
      await assetBytes('dz-country-z12.pmtiles'),
    );

    // Both packs answer a z12 tile over Algiers. Pass them in the WRONG order.
    final provider = LocalPmTilesProvider(
      archives: [country, wilaya],
      cacheKey: 'test-both',
    );
    expect(provider.maximumZoom, 14);

    final key = _tileKeyAt(12, 36.7525, 3.0420);
    final served = await provider.load(key);
    expect(served, isA<TileResponseData>());

    final deeper = await wilaya.tile(ZXY(12, key.x, key.y).toTileId());
    expect(
      listEquals((served as TileResponseData).bytes, await deeper.bytes()),
      isTrue,
      reason: 'the z14-header pack must win for a tile both packs hold',
    );

    provider.dispose();
  });
}
```

`dart:typed_data` is already imported; `listEquals` comes from `package:flutter/foundation.dart` — add that import to the test file.

- [ ] **Step 2: Run it — expect compile failure**

```bash
cd track_scribe && flutter test test/ui/local_pmtiles_provider_test.dart
```

Expected: FAIL — `local_pmtiles_provider.dart` missing.

- [ ] **Step 3: Implement the provider**

`lib/ui/basemap/local_pmtiles_provider.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:pmtiles/pmtiles.dart';

/// Serves bundled PMTiles archives to flutter_map_vector_tiles.
///
/// Overzoom is NOT this class's job: the fmvt pipeline clamps display zooms
/// to [maximumZoom] and renders the overzoomed sub-region itself (verified in
/// tile_store.dart), so a request outside [minimumZoom, maximumZoom] is
/// honestly NotFound and nothing here ever upscales coordinates.
///
/// [cacheBytesToDisk] is false: the bytes already live on disk; mirroring
/// them into the renderer's disk cache would double storage and drop a
/// zero-byte sentinel per absent tile.
class LocalPmTilesProvider implements VectorTileProvider {
  LocalPmTilesProvider({required List<PmTilesArchive> archives, required this.cacheKey})
    // R103: priority is read off each archive's own header, so callers may
    // pass packs in any order (and adding a pack is data, not code).
    : _archives = List.of(archives)
        ..sort((a, b) => b.maxZoom.compareTo(a.maxZoom));

  /// Deepest zoom first: the wilaya pack (z0-14) before the country pack
  /// (z0-12), so a request both can answer gets the more detailed bytes.
  final List<PmTilesArchive> _archives;

  @override
  final String cacheKey;

  bool _disposed = false;

  @override
  int get minimumZoom =>
      _archives.map((a) => a.minZoom).reduce(math.min);

  @override
  int get maximumZoom =>
      _archives.map((a) => a.maxZoom).reduce(math.max);

  @override
  bool get cacheBytesToDisk => false;

  @override
  Future<TileResponse> load(
    TileKey tile, {
    CancellationToken? cancellation,
  }) async {
    if (_disposed || (cancellation?.isCancelled ?? false)) {
      return const TileResponseCancelled();
    }
    if (!tile.isValid || tile.z < minimumZoom || tile.z > maximumZoom) {
      return const TileResponseNotFound();
    }
    for (final archive in _archives) {
      if (tile.z < archive.minZoom || tile.z > archive.maxZoom) continue;
      final id = ZXY(tile.z, tile.x, tile.y).toTileId();
      final t = await archive.tile(id);
      try {
        return TileResponseData(await t.bytes());
      } on TileNotFoundException {
        continue; // this pack doesn't have it — try the next
      } catch (_) {
        return const TileResponseNotFound();
      }
    }
    return const TileResponseNotFound();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final archive in _archives) {
      archive.close();
    }
  }
}
```

- [ ] **Step 4: Run the test — pass**

```bash
cd track_scribe && flutter test test/ui/local_pmtiles_provider_test.dart
```

Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/basemap/local_pmtiles_provider.dart test/ui/local_pmtiles_provider_test.dart
git commit -m "feat(map): local VectorTileProvider over bundled PMTiles (exact tiles, pipeline overzooms)"
```

---

## Task 3: أسلوب OpenFreeMap الداكن مُوطَّنًا كأصل — بلا شبكة

**Files:**
- Create: `assets/styles/dark.json` (localized), `assets/styles/sprites/ofm.json`, `assets/styles/sprites/ofm.png`, `assets/styles/sprites/ofm@2x.png`
- Test: `test/ui/map_style_test.dart`

**Interfaces:**
- Consumes: `StyleReader({required String uri, bool cache, http.Client? httpClient, Future<VectorTileProvider?> Function(String)? resolveProvider}).read() → Future<Style>`; `Style.theme`, `Style.tileProviders`, `Style.sprites`, `Style.dispose()` (verified).
- Produces: the bundled style contract — source id `openmaptiles`, sprite key `sprites/ofm`, no `glyphs` key, no raster sources, background `#101315`, water `#182128`. Tasks 4/6 consume it.

**Verified upstream facts (do not re-verify):** the style at `https://tiles.openfreemap.org/styles/dark` (MIT) has sources `openmaptiles` (vector, url `https://tiles.openfreemap.org/planet`) and `ne2_shaded` (raster, Natural Earth hillshade); sprite `https://tiles.openfreemap.org/sprites/ofm_f384/ofm` (ofm.json / ofm.png / ofm@2x.png all HTTP 200); glyphs `https://tiles.openfreemap.org/fonts/…` (the renderer has zero glyph handling — remove the key so no reader can mistake it for data); background `rgb(12,12,12)`; water fill `rgb(27,27,29)`; exactly 1 raster layer (it references `ne2_shaded`).

**Corrections established while executing Task 3 (measured, binding for Tasks 4/6):**
- The asset style URI is `asset://assets/styles/dark.json` — `rootBundle` keys carry the `assets/` prefix, so `asset://styles/dark.json` cannot resolve.
- There is no `Style.tileProviders`; the resolved map is `style.providers.providers`.
- Upstream drift: the current `dark` style has **0** layers referencing `ne2_shaded` (the source itself is stripped regardless); the water literal is `rgb(27 ,27 ,29)` with spaces — rewrite by intent, scoped to water/waterway.
- flutter_map_vector_tiles 2.9.1 never requests `ofm@2x.json` (which does not exist upstream) and falls back to the 1x sprite; `ofm@2x.png` is bundled but unused by the renderer — harmless, and a future @2x support fix would need it.
- `pubspec.yaml` needs an explicit `- assets/styles/sprites/` entry: Flutter's asset directory declarations are NOT recursive.

- [ ] **Step 1: Download the style + sprite**

```bash
cd /tmp && curl -s -o dark.json https://tiles.openfreemap.org/styles/dark
mkdir -p ofm_sprites && cd ofm_sprites
curl -s -O https://tiles.openfreemap.org/sprites/ofm_f384/ofm.json
curl -s -O https://tiles.openfreemap.org/sprites/ofm_f384/ofm.png
curl -s -O https://tiles.openfreemap.org/sprites/ofm_f384/ofm@2x.png
```

- [ ] **Step 2: Localize the JSON**

Copy `dark.json` → `track_scribe/assets/styles/dark.json` and apply EXACTLY these edits (a one-off script is fine, but commit the RESULT, not the script):

1. `"sprite":"https://tiles.openfreemap.org/sprites/ofm_f384/ofm"` → `"sprite":"sprites/ofm"` (resolved relative to the asset style URI; note the style URI itself must be `asset://assets/styles/dark.json` because rootBundle keys include the `assets/` prefix — corrected as executed, Tasks 4/6 use that URI).
2. Delete the `"glyphs"` key entirely.
3. Delete the `ne2_shaded` source entry from `sources`, and delete EVERY layer whose `"source"` is `"ne2_shaded"` (1 layer; grep for it).
4. `"background-color":"rgb(12,12,12)"` (the `background` layer) → `"background-color":"#101315"`.
5. Water: every `"fill-color":"rgb(27,27,29)"` on the `water` and `waterway` layers → `"fill-color":"#182128"` / `"line-color":"#182128"` respectively (spec: water `#171B1E` «مائلًا» — the lean-blue reading; the land/water pair must remain distinguishable at 4:1+ luminance distance).
6. Keep the `openmaptiles` source exactly as upstream ships it (url included — `resolveProvider` bypasses it and no TileJSON fetch happens; verified in style_reader.dart line ~276).
7. Leave all other layers/paints untouched (roads/buildings/labels keep OFM's verified dark palette).

Copy the sprite files to `track_scribe/assets/styles/sprites/ofm.json`, `ofm.png`, `ofm@2x.png` (the sprite JSON's image references stay relative to the sprite URL, so no edit inside ofm.json).

- [ ] **Step 3: Write the failing test**

`test/ui/map_style_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:http/http.dart' as http;
import 'package:track_scribe/ui/basemap/local_pmtiles_provider.dart';

/// Any network attempt fails the test: the bundled style must load fully
/// offline (spec §12.1 «لا شيء يُجلب من الشبكة»).
class _NoNetworkClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw StateError('network used for ${request.url}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled dark style loads with zero network and resolves sprites', () async {
    final style = await StyleReader(
      uri: 'asset://assets/styles/dark.json',
      cache: false,
      httpClient: _NoNetworkClient(),
      resolveProvider: (id) async => id == 'openmaptiles'
          ? LocalPmTilesProvider(archives: const [], cacheKey: 'style-test')
          : null,
    ).read();

    expect(style.theme, isNotNull);
    expect(style.providers.providers, isNotEmpty);
    expect(style.sprites, isNotNull); // asset sprite sheet resolved
    style.dispose();
  });
}
```

(If `LocalPmTilesProvider` with an empty archive list makes `reduce` throw, pass one real archive loaded via `rootBundle` inside this test instead — but keep `httpClient: _NoNetworkClient()`.)

- [ ] **Step 4: Run it — expect failure while assets are missing/uncommitted**

```bash
cd track_scribe && flutter test test/ui/map_style_test.dart
```

Expected: FAIL (asset `assets/styles/dark.json` not yet declared — declare it in pubspec first, then the test's real failure is any network use or parse error). Iterate on the localized JSON until the test passes: a parse error means the edit broke the JSON; a `network used` failure means a URL still points at a host.

- [ ] **Step 5: Run it — pass**

Expected: PASS (1 test, no `network used` failure).

- [ ] **Step 6: Commit**

```bash
git add assets/styles/ test/ui/map_style_test.dart track_scribe/pubspec.yaml
git commit -m "feat(map): bundle the OpenFreeMap dark style (MIT) localized to brand colors, asset sprites"
```

---

## Task 4: شريط الخريطة الحي — VectorMapBand على شاشة التسجيل

**Files:**
- Create: `lib/ui/basemap/scale_bar.dart`
- Create: `lib/ui/basemap/map_style_provider.dart`
- Create: `lib/ui/basemap/vector_map_band.dart`
- Modify: `lib/ui/basemap/grid_basemap.dart` (use extracted `ScaleBar`; keys/behavior unchanged)
- Modify: `lib/ui/recording/recording_screen.dart` (`GridBasemap` → `VectorMapBand`)
- Delete: `lib/ui/basemap/basemap.dart` (dead interface — update any imports)
- Test: `test/ui/vector_map_band_test.dart`; run `test/ui/basemap_test.dart`, `test/ui/overlay_bounds_test.dart`, `test/ui/recording_screen_test.dart` — R104: those three are NOT unchanged; each must override `mapStyleProvider` with a stub style and find `VectorMapBand` where it found `GridBasemap`. The plan's original premise ("the band falls back because `mapStyleProvider` errors without path_provider") is false under `testWidgets`: see the R104 note after Step 6.

**Interfaces:**
- Consumes: `TileStore`/`tileStoreProvider` (Task 1), `LocalPmTilesProvider` (Task 2), style contract (Task 3), `StoredPoint`/`WaypointType` (engine), `Palette` tokens.
- Produces: `mapStyleProvider` (FutureProvider<Style>, override target for tests), `VectorMapBand({required List<StoredPoint> points, required StoredPoint? current})`. Task 6 consumes both.

- [ ] **Step 1: Extract the scale bar (no behavior change)**

`lib/ui/basemap/scale_bar.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:track_scribe/theme/palette.dart';

/// The honest 1-2-5 scale bar (spec: never print a fabricated figure).
/// `metresPerPixel <= 0` hides it — the same contract the grid basemap had.
class ScaleBar extends StatelessWidget {
  const ScaleBar({super.key, required this.metresPerPixel});

  final double metresPerPixel;

  @override
  Widget build(BuildContext context) {
    if (metresPerPixel <= 0) return const SizedBox.shrink();
    final labelMetres = scaleLabelMetres(metresPerPixel);
    if (labelMetres < 1) return const SizedBox.shrink();
    final barPx = labelMetres / metresPerPixel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${labelMetres.toStringAsFixed(0)} م',
          style: const TextStyle(fontSize: 10, color: Palette.textSecondary),
        ),
        const SizedBox(height: 2),
        Container(width: barPx, height: 2, color: Palette.textSecondary),
      ],
    );
  }
}

/// The smallest 1-2-5 value worth at least 40 px, so the label stays exact
/// and the bar lands in [40, 80) px by construction.
double scaleLabelMetres(double metresPerPixel) {
  final target = metresPerPixel * 40;
  final base = math.pow(10.0, (math.log(target) / math.ln10).floor()).toDouble();
  for (final m in const [1.0, 2.0, 5.0, 10.0]) {
    if (base * m >= target) return base * m;
  }
  return base * 10;
}
```

Edit `grid_basemap.dart`: remove `_ScaleBar` and `_scaleLabelMetres`, import `scale_bar.dart`, replace the `Positioned(bottom: 8, right: 8, child: _ScaleBar(...))` with `ScaleBar(metresPerPixel: painter.metresPerPixel(size))` — same `Key('basemap-scale')`. Run `flutter test test/ui/basemap_test.dart` — must stay green before proceeding.

- [ ] **Step 2: mapStyleProvider**

`lib/ui/basemap/map_style_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:path/path.dart' as p;
import 'package:pmtiles/pmtiles.dart';
import 'package:track_scribe/data/tile_store.dart';
import 'package:track_scribe/ui/basemap/local_pmtiles_provider.dart';

/// One app-wide compiled style: bundled packs + bundled localized style,
/// zero network (cache: false, resolveProvider, no http anywhere).
///
/// Packs come from [kBundledTileNames] (R103): this code opens *every* name in
/// the registry and never hardcodes a pack list, so adding a country or world
/// pack is one name in `tile_store.dart` + one asset file. Priority is decided
/// inside LocalPmTilesProvider from each PMTiles header, not here.
///
/// `Style.dispose()` disposes the providers it owns (verified in
/// style_reader.dart), which closes the archives via
/// LocalPmTilesProvider.dispose — do not dispose them separately.
final mapStyleProvider = FutureProvider<Style>((ref) async {
  final tilesDir = await ref.watch(tileStoreProvider).ensureBundledTiles();
  final archives = <PmTilesArchive>[];
  for (final name in kBundledTileNames) {
    archives.add(await PmTilesArchive.from(p.join(tilesDir, name)));
  }
  final provider = LocalPmTilesProvider(
    archives: archives,
    cacheKey: 'pmtiles:dz-bundled',
  );
  final style = await StyleReader(
    uri: 'asset://assets/styles/dark.json',
    cache: false,
    resolveProvider: (id) async => id == 'openmaptiles' ? provider : null,
  ).read();
  ref.onDispose(style.dispose);
  return style;
});
```

If `kBundledTileNames` is empty the provider must still be constructed with an
empty list (fmvt then reports `minimumZoom`/`maximumZoom` via `reduce` on an
empty iterable and throws — so guard: when the registry is empty, throw
`StateError('no tile packs registered')` before building the provider, and the
band's existing error branch falls back to `GridBasemap`. This keeps the
recording path safe if a build ever ships with assets removed.)

- [ ] **Step 3: VectorMapBand**

`lib/ui/basemap/vector_map_band.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/basemap/grid_basemap.dart';
import 'package:track_scribe/ui/basemap/map_style_provider.dart';
import 'package:track_scribe/ui/basemap/scale_bar.dart';

/// The recording map band (spec §12.1): real offline vector map + live route
/// + position marker with 1σ accuracy halo + follow/recenter + north/heading
/// toggle + the mandatory attribution row. Recording never depends on it:
/// while the style loads the band is a flat `bg`, and on style failure it
/// falls back to [GridBasemap] (route still drawn).
class VectorMapBand extends ConsumerStatefulWidget {
  const VectorMapBand({super.key, required this.points, required this.current});

  final List<StoredPoint> points;
  final StoredPoint? current;

  @override
  ConsumerState<VectorMapBand> createState() => _VectorMapBandState();
}

class _VectorMapBandState extends ConsumerState<VectorMapBand> {
  final MapController _map = MapController();
  bool _follow = true;
  bool _heading = false;

  List<LatLng> get _route => [
    for (final p in widget.points)
      if (p.type != WaypointType.rejected) LatLng(p.lat, p.lon),
  ];

  /// R105 (device-found): never move for a fix that still lands inside the
  /// band. Each programmatic move restarts the vector tile fetch, and on a
  /// two-core phone the decode is slower than the gap between fixes, so
  /// chasing every fix paints nothing for the whole session.
  void _moveTo(StoredPoint p) {
    if (!_mapReady) return;
    final cam = _map.camera;
    final target = LatLng(p.lat, p.lon);
    if (shouldRecenter(
      center: cam.center,
      target: target,
      metresPerPixel: _metresPerPixel(),
      bandShortSidePx: math.min(cam.size.width, cam.size.height),
    )) {
      _map.move(target, cam.zoom);
    }
    if (_heading && p.bearingDeg != null) {
      final wanted = -p.bearingDeg!;
      if (_signedDeg(wanted - cam.rotation).abs() > _headingEpsilonDeg) {
        _map.rotate(wanted);
      }
    }
  }

  /// Metres per screen pixel of Web Mercator at [lat]/[zoom] (256 px tiles,
  /// logical pixels) — the scale bar's one honest input on a real map.
  double _metresPerPixel() {
    final cam = _map.camera;
    final latRad = cam.center.latitude * math.pi / 180;
    return 156543.03392 * math.cos(latRad) / math.pow(2, cam.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final style = ref.watch(mapStyleProvider);
    final current = widget.current;
    if (current != null && _follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _follow) _moveTo(current);
      });
    }
    return Column(
      children: [
        Expanded(
          child: style.when(
            loading: () => const ColoredBox(color: Palette.bg),
            error: (_, __) => GridBasemap(points: widget.points),
            data: (s) => Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: current == null
                          ? const LatLng(36.7525, 3.0420) // Algiers
                          : LatLng(current.lat, current.lon),
                      initialZoom: 16,
                      minZoom: 2,
                      maxZoom: 18,
                      backgroundColor: Palette.bg,
                      onPositionChanged: (camera, hasGesture) {
                        if (hasGesture) _follow = false;
                      },
                    ),
                    children: [
                      VectorTileLayer(
                        theme: s.theme,
                        tileProviders: s.providers.providers,
                        sprites: s.sprites,
                        diskCacheMaximumSizeInBytes: 0,
                      ),
                      if (_route.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _route,
                              color: Palette.accent,
                              strokeWidth: 5,
                            ),
                          ],
                        ),
                      if (current != null) ...[
                        if (current.type != WaypointType.idle)
                          CircleLayer(
                            circles: [
                              CircleMarker(
                                point: LatLng(current.lat, current.lon),
                                radius: current.accuracyM,
                                useRadiusInMeter: true,
                                color: Palette.accent.withValues(alpha: 0.12),
                                borderColor: Palette.accent.withValues(
                                  alpha: 0.6,
                                ),
                                borderStrokeWidth: 1,
                              ),
                            ],
                          ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(current.lat, current.lon),
                              width: 22,
                              height: 22,
                              child: current.type == WaypointType.idle
                                  ? const _IdleBadge()
                                  : const _PositionDot(),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const Positioned(
                  top: 8,
                  left: 8,
                  child: Icon(
                    Icons.north,
                    key: Key('basemap-north'),
                    size: 16,
                    color: Palette.textSecondary,
                  ),
                ),
                Positioned(
                  top: 28,
                  left: 8,
                  child: _MapControls(
                    onRecenter: () {
                      setState(() {
                        _follow = true;
                        _heading = false;
                      });
                      final c = current ?? widget.points.lastOrNull;
                      if (c != null) _map.move(LatLng(c.lat, c.lon), 16);
                      _map.rotate(0);
                    },
                    onHeading: current?.bearingDeg == null
                        ? null
                        : () {
                            setState(() => _heading = !_heading);
                            if (_heading) {
                              _map.rotate(-current!.bearingDeg!);
                            } else {
                              _map.rotate(0);
                            }
                          },
                    headingActive: _heading,
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: ScaleBar(
                    key: const Key('basemap-scale'),
                    metresPerPixel: _metresPerPixel(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const _AttributionStrip(),
      ],
    );
  }
}

class _PositionDot extends StatelessWidget {
  const _PositionDot();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Palette.accent,
      border: Border.all(color: Palette.onAccent, width: 3),
    ),
  );
}

/// ر6: standing still draws an IDLE badge, no position dot and no halo —
/// nothing here implies motion.
class _IdleBadge extends StatelessWidget {
  const _IdleBadge();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Palette.surface,
      border: Border.all(color: Palette.textSecondary, width: 2),
    ),
    child: const Center(
      child: Icon(Icons.pause, size: 12, color: Palette.textSecondary),
    ),
  );
}

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.onRecenter,
    required this.onHeading,
    required this.headingActive,
  });

  final VoidCallback onRecenter;
  final VoidCallback? onHeading;
  final bool headingActive;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _ControlButton(
        key: const Key('map-recenter'),
        icon: Icons.my_location,
        onTap: onRecenter,
        active: false,
      ),
      const SizedBox(height: 6),
      _ControlButton(
        key: const Key('map-heading'),
        icon: Icons.explore_outlined,
        onTap: onHeading,
        active: headingActive,
      ),
    ],
  );
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({super.key, required this.icon, required this.onTap, required this.active});

  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Material(
    color: active ? Palette.accent : Palette.surface,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 18,
          color: active ? Palette.onAccent : Palette.textSecondary,
        ),
      ),
    ),
  );
}

/// ODbL/CC-BY attribution — legally required and never dismissable.
class _AttributionStrip extends StatelessWidget {
  const _AttributionStrip();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Palette.bg,
    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
    child: const Text(
      '© OpenStreetMap contributors · © OpenMapTiles · Style: OpenFreeMap (MIT)',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 9, color: Palette.textSecondary),
    ),
  );
}
```

(If `lastOrNull` is unavailable, use `widget.points.isNotEmpty ? widget.points.last : null` — and if `flutter_map` 8.3.2 has no `MapController.camera` getter, use `_map.camera`'s actual name or track last camera via `onPositionChanged`; check the 8.3.2 source in the pub cache. Also verify the `rotate` sign convention on the device in Task 8 — heading-up must turn WITH the bearing, not against it.)

- [ ] **Step 4: Wire the recording screen**

In `lib/ui/recording/recording_screen.dart`:
- Replace the `Positioned.fill(child: GridBasemap(points: s.engine?.storedPoints ?? const <StoredPoint>[]))` with:

```dart
Positioned.fill(
  child: VectorMapBand(
    points: s.engine?.storedPoints ?? const <StoredPoint>[],
    current: (s.engine?.storedPoints.isNotEmpty ?? false)
        ? s.engine!.storedPoints.last
        : null,
  ),
),
```

- Keep the import of `grid_basemap.dart` ONLY if still referenced; add `import 'package:track_scribe/ui/basemap/vector_map_band.dart';`.
- Delete `lib/ui/basemap/basemap.dart` and fix any imports of it (grep `basemap.dart`).

- [ ] **Step 5: Write the band tests**

`test/ui/vector_map_band_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/ui/basemap/map_style_provider.dart';
import 'package:track_scribe/ui/basemap/vector_map_band.dart';

/// Never decodes a real tile: keeps the widget test deterministic and free
/// of isolate/pending-timer coupling.
class _StubProvider implements VectorTileProvider {
  @override
  String get cacheKey => 'stub';
  @override
  int get minimumZoom => 0;
  @override
  int get maximumZoom => 14;
  @override
  bool get cacheBytesToDisk => false;
  @override
  Future<TileResponse> load(TileKey tile, {CancellationToken? cancellation}) async =>
      const TileResponseNotFound();
}

StoredPoint _p(double lat, double lon, {WaypointType type = WaypointType.normal}) =>
    StoredPoint(lat: lat, lon: lon, timeNanos: 0, accuracyM: 5, type: type, bearingDeg: 90);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Style style;

  setUpAll(() async {
    style = await StyleReader(
      uri: 'asset://assets/styles/dark.json',
      cache: false,
      resolveProvider: (id) async => _StubProvider(),
    ).read();
  });

  tearDownAll(() => style.dispose());

  Widget wrap(Widget child) => ProviderScope(
    overrides: [mapStyleProvider.overrideWith((ref) => Future.value(style))],
    child: MaterialApp(home: Scaffold(body: child)),
  );

  testWidgets('renders map, route, halo, marker and the attribution row', (tester) async {
    final points = [_p(36.7500, 3.0400), _p(36.7520, 3.0420)];
    await tester.pumpWidget(wrap(VectorMapBand(points: points, current: points.last)));
    await tester.pumpAndSettle();

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(PolylineLayer), findsOneWidget);
    expect(find.byType(CircleLayer), findsOneWidget);
    expect(find.byType(MarkerLayer), findsOneWidget);
    expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
    expect(find.byKey(const Key('map-recenter')), findsOneWidget);
    expect(find.byKey(const Key('basemap-scale')), findsOneWidget);
  });

  testWidgets('IDLE point draws the idle badge and no halo', (tester) async {
    final idle = _p(36.7520, 3.0420, type: WaypointType.idle);
    await tester.pumpWidget(wrap(VectorMapBand(points: [idle], current: idle)));
    await tester.pumpAndSettle();
    expect(find.byType(CircleLayer), findsNothing);
    expect(find.byIcon(Icons.pause), findsOneWidget);
  });

  testWidgets('style failure falls back to the grid basemap with the route', (tester) async {
    final points = [_p(36.7500, 3.0400), _p(36.7520, 3.0420)];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapStyleProvider.overrideWith((ref) => Future<Style>.error(StateError('no tiles'))),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: VectorMapBand(points: points, current: points.last),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('basemap-canvas')), findsOneWidget);
    expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
  });

  testWidgets('recenter button returns without throwing on an empty route', (tester) async {
    await tester.pumpWidget(wrap(const VectorMapBand(points: [], current: null)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('map-recenter')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 6: Run the suite**

```bash
cd track_scribe && flutter analyze && flutter test
```

Expected: ALL green. R104 (measured, 2026-10-14): the three "untouched" pinned tests do NOT run through the `GridBasemap` fallback, and the reason the plan gave for that is wrong. `mapStyleProvider` does not *error* without path_provider inside `testWidgets` — `TestDefaultBinaryMessenger.send` (`flutter_test/lib/src/test_default_binary_messenger.dart:141-152`) forwards the unmocked `plugins.flutter.io/path_provider` channel to the delegate, whose engine reply needs the REAL event loop that `AutomatedTestWidgetsFlutterBinding` never runs, so the future simply pends and the state stays `AsyncLoading`. The band then renders neither the map nor the fallback, and the pinned corner assertions find zero basemap widgets. (In a plain `test()` the same call throws `MissingPluginException` instantly — that is where the plan's premise came from.) Two consequences baked into the code: `mapStyleProvider` declares `retry: (retryCount, error) => null` because this provider touches no network and Riverpod 3's `defaultRetry` (`riverpod/lib/src/provider_container.dart:983-995`) would otherwise retry an `Exception` for ~38 s while the state stays loading, which violates the fast-error half of the fallback law; and the pinned tests override `mapStyleProvider` with the bundled style + a stub `VectorTileProvider` (`test/support/stub_vector_style.dart`, loaded in `setUpAll` — a `rootBundle.load` awaited inside a fake-async zone pends the same way and eats a 10-minute test timeout), so the corner geometry is now measured on the real vector band instead of the fallback. If a pinned test breaks, fix the band, not the assertion.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/basemap/ lib/ui/recording/recording_screen.dart test/ pubspec.yaml pubspec.lock
git commit -m "feat(map): live vector band on the recording screen — halo, IDLE badge, follow/heading, attribution"
```

- [ ] **Step 8: Push and let CI verify**

```bash
git push
gh run watch
```

Expected: `android-apk` green (analyze + full test suite + APK). Record the run id in the report.

---

## Task 5: طبقة بيانات النشاط المنتهي + lastActivityId

**Files:**
- Create: `lib/data/activity_summary.dart`
- Modify: `lib/data/activity_repository.dart` (`loadActivityWithPoints`)
- Modify: `lib/state/recording_controller.dart` (`lastActivityId`)
- Test: `test/data/activity_detail_repository_test.dart`; extend `test/state/recording_controller_test.dart`

**Interfaces:**
- Consumes: drift tables `Activities`/`TrackPoints` (schema in `lib/data/database.dart`), `unmeasuredAccuracyM` (R76 sentinel), `WaypointType.values.byName`.
- Produces: `ActivitySummary` (fields below) and `ActivityRepository.loadActivityWithPoints(int) → Future<ActivitySummary?>`; `RecordingState.lastActivityId` (int?, set at stop, cleared at start). Task 6 consumes both.

- [ ] **Step 1: ActivitySummary model**

`lib/data/activity_summary.dart`:

```dart
import 'package:track_scribe/engine/raw_fix.dart';

/// One finished activity as the detail screen reads it: the row's totals
/// plus every stored point in engine order (rowid order = write order, R78).
class ActivitySummary {
  const ActivitySummary({
    required this.id,
    required this.sport,
    required this.startWallMillis,
    required this.distanceM,
    required this.elapsedNanos,
    required this.fixCount,
    required this.rejectedCount,
    required this.mockDetected,
    required this.points,
  });

  final int id;
  final String sport;
  final int startWallMillis;
  final double distanceM;
  final int elapsedNanos;
  final int fixCount;
  final int rejectedCount;
  final bool mockDetected;
  final List<StoredPoint> points;
}
```

- [ ] **Step 2: Write the failing repository test**

`test/data/activity_detail_repository_test.dart` (mirror the DB setup of `test/data/resume_test.dart`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/activity_summary.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/source/gps_quality.dart';

void main() {
  late AppDatabase db;
  late ActivityRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(); // or the in-memory pattern resume_test uses
    repo = ActivityRepository(db);
  });

  tearDown(() => db.close());

  test('loadActivityWithPoints returns totals and points in write order', () async {
    final id = await repo.insertActivity(
      uuid: 'act-test', sport: 'run', startWallMillis: 1234,
    );
    final pts = [
      StoredPoint(lat: 36.75, lon: 3.04, timeNanos: 10, accuracyM: 5, type: WaypointType.normal),
      StoredPoint(lat: 36.751, lon: 3.041, timeNanos: 20, accuracyM: unmeasuredAccuracyM, type: WaypointType.idle),
    ];
    await repo.appendPoints(id, pts);
    await repo.finishActivity(
      activityId: id,
      elapsedNanos: 100,
      distanceM: 42.5,
      fixCount: 2,
      rejectedCount: 0,
      mockDetected: false,
    );

    final s = await repo.loadActivityWithPoints(id);
    expect(s, isNotNull);
    expect(s!.sport, 'run');
    expect(s.distanceM, 42.5);
    expect(s.elapsedNanos, 100);
    expect(s.points.length, 2);
    expect(s.points.first.type, WaypointType.normal);
    expect(s.points.last.accuracyM, unmeasuredAccuracyM); // R76 round-trip
    expect(s.points.last.type, WaypointType.idle);
  });

  test('returns null for an unknown id', () async {
    expect(await repo.loadActivityWithPoints(999), isNull);
  });
}
```

- [ ] **Step 3: Run — expect compile failure**

```bash
cd track_scribe && flutter test test/data/activity_detail_repository_test.dart
```

- [ ] **Step 4: Implement loadActivityWithPoints**

In `lib/data/activity_repository.dart`, add (field names/types per `lib/data/database.dart` — read the generated table classes first; use `?? 0` / `?? false` for totals the schema defaults):

```dart
/// The detail screen's read: one activity's row plus every point in
/// engine/write order (rowid order — R78 guarantees append order = id order).
/// NULL accuracy reads back as the R76 sentinel, exactly like [loadResume].
Future<ActivitySummary?> loadActivityWithPoints(int activityId) async {
  final row = await (_db.select(_db.activities)
        ..where((t) => t.id.equals(activityId))
        ..limit(1))
      .getSingleOrNull();
  if (row == null) return null;
  final pts = await (_db.select(_db.trackPoints)
        ..where((t) => t.activityId.equals(activityId))
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .get();
  return ActivitySummary(
    id: row.id,
    sport: row.sport,
    startWallMillis: row.startWallMillis,
    distanceM: row.distanceM ?? 0,
    elapsedNanos: row.elapsedNanos ?? 0,
    fixCount: row.fixCount ?? 0,
    rejectedCount: row.rejectedCount ?? 0,
    mockDetected: row.mockDetected ?? false,
    points: [
      for (final p in pts)
        StoredPoint(
          lat: p.lat,
          lon: p.lon,
          timeNanos: p.timeNanos,
          accuracyM: p.accuracyM ?? unmeasuredAccuracyM,
          type: WaypointType.values.byName(p.waypointType),
          altitudeM: p.altGnss,
          speedMps: p.speedMps,
          bearingDeg: p.bearingDeg,
        ),
    ],
  );
}
```

- [ ] **Step 5: Run — pass**

Expected: PASS (2 tests).

- [ ] **Step 6: lastActivityId in the controller**

In `lib/state/recording_controller.dart`:

1. Add to `RecordingState`: `final int? lastActivityId;` (constructor param default `this.lastActivityId`) and in `copyWith` carry it unchanged (`lastActivityId: lastActivityId` — no new parameter; every copyWith preserves it).
2. In `start()`: the two failure-reset branches and the success path construct via `state.copyWith(...)` — those preserve the old value, which is WRONG for a new session. Change the success path (`phase: starting`) to construct directly:

```dart
state = RecordingState(
  sport: state.sport,
  phase: RecordingPhase.starting,
  engine: null,
  lastActivityId: null, // a new session has no finished activity yet
  quality: GpsQuality.none,
  permissionDenied: false,
);
```

3. In `stop()`: the final reset already constructs directly — add `lastActivityId: activityId` (the id of the activity just finished, or null when nothing was recorded):

```dart
state = RecordingState(
  sport: state.sport,
  phase: RecordingPhase.stopped,
  engine: null,
  lastActivityId: activityId,
);
```

4. Both `LocationPermissionDenied`/generic-failure resets in `start()` already construct directly with `engine: null` — add `lastActivityId: null` there too.

- [ ] **Step 7: Extend the controller test**

In `test/state/recording_controller_test.dart` add:

```dart
test('stop sets lastActivityId for the detail affordance; a new start clears it', () async {
  // reuse the existing harness: start with the controlled source, feed fixes,
  // stop, expect state.lastActivityId != null
  // then start again and expect state.lastActivityId == null while starting
});
```

(Mirror the existing harness exactly — the same controlled source, gate clock override, and repository overrides those tests already use.)

- [ ] **Step 8: Run the full suite + analyze**

```bash
cd track_scribe && flutter analyze && flutter test
```

Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add lib/data/ lib/state/recording_controller.dart test/data/activity_detail_repository_test.dart test/state/recording_controller_test.dart
git commit -m "feat(map): repository read for a finished activity + lastActivityId on the recording state"
```

---

## Task 6: شاشة تفاصيل النشاط — الخط المتدرج، الأسهم، شريط الارتفاع

**Files:**
- Create: `lib/ui/detail/graded_route_layer.dart`
- Create: `lib/ui/detail/elevation_strip.dart`
- Create: `lib/ui/detail/activity_detail_screen.dart`
- Modify: `lib/ui/recording/recording_screen.dart` (post-stop «تفاصيل النشاط» button)
- Test: `test/ui/graded_route_layer_test.dart`, `test/ui/elevation_strip_test.dart`, `test/ui/detail_screen_test.dart`

**Interfaces:**
- Consumes: `ActivitySummary` + `loadActivityWithPoints` (Task 5), `mapStyleProvider` (Task 4), `StatPanel` (existing: `StatPanel(distanceM:, elapsedNanos:, sport:, fixCount:)`), `Sport` enum, `Palette`, `MapCamera.of(context)` + `latLngToScreenOffset` (flutter_map 8.3.2), `StoredPoint.distanceTo` (haversine).
- Produces: `ActivityDetailScreen({required int activityId})`, `activityDetailProvider` (FutureProvider.family, override target), `GradedRouteLayer({required points, required strokeWidth})`, `ElevationStrip({required points})`, pure helpers `segmentSpeedMps`, `speedColor`, `gradeColor`.

- [ ] **Step 1: Pure helpers + tests first (RED)**

`test/ui/graded_route_layer_test.dart`:

```dart
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/detail/graded_route_layer.dart';

StoredPoint _p({required double lat, required double lon, required int t, double? speed}) =>
    StoredPoint(lat: lat, lon: lon, timeNanos: t, accuracyM: 5, type: WaypointType.normal, speedMps: speed);

void main() {
  test('segmentSpeedMps prefers the measured speed, falls back to dist/dt', () {
    final a = _p(lat: 36.75, lon: 3.00, t: 0, speed: 4);
    final b = _p(lat: 36.75, lon: 3.00, t: 1_000_000_000); // 1 s
    expect(segmentSpeedMps(a, b), 4); // measured wins
    final c = _p(lat: 36.75, lon: 3.001, t: 1_000_000_000);
    final fallback = segmentSpeedMps(a, c);
    expect(fallback, greaterThan(0));
    expect(fallback, lessThan(200));
  });

  test('segmentSpeedMps is 0 when dt is zero (never divide)', () {
    final a = _p(lat: 36.75, lon: 3.00, t: 5);
    expect(segmentSpeedMps(a, a), 0);
  });

  test('speedColor maps the ramp endpoints exactly and is monotonic', () {
    expect(speedColor(0), GradedRouteLayer.slowColor);
    expect(speedColor(1), GradedRouteLayer.fastColor);
    expect(GradedRouteLayer.fastColor, Palette.accent); // #C6FF3D
    final mid = speedColor(0.5);
    expect(mid.r, inInclusiveRange(GradedRouteLayer.slowColor.r, Palette.accent.r));
    expect(mid.g, inInclusiveRange(GradedRouteLayer.slowColor.g, Palette.accent.g));
  });
}
```

`test/ui/elevation_strip_test.dart`:

```dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/detail/elevation_strip.dart';

StoredPoint _p(double lat, double lon, double? alt) => StoredPoint(
    lat: lat, lon: lon, timeNanos: 0, accuracyM: 5, type: WaypointType.normal, altitudeM: alt);

void main() {
  test('gradeColor: flat is the dim end, steep saturates to the bright end', () {
    expect(gradeColor(0), ElevationStrip.flatColor);
    expect(gradeColor(0.5), ElevationStrip.steepColor);
    expect(ElevationStrip.steepColor, Palette.accent);
  });

  test('painter draws segments for measured altitudes and skips null gaps', () {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    ElevationStripPainter(
      [_p(0, 0, 10), _p(0, 0, null), _p(0, 0, 30)],
    ).paint(canvas, const Size(200, 96));
    final pic = rec.endRecording();
    expect(pic, isNotNull); // no throw, real draw calls recorded
  });

  test('fewer than two measured altitudes paints the empty message', () {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    ElevationStripPainter([_p(0, 0, null)]).paint(canvas, const Size(200, 96));
    rec.endRecording();
  });
}
```

- [ ] **Step 2: Run — expect compile failure (files missing)**

```bash
cd track_scribe && flutter test test/ui/graded_route_layer_test.dart test/ui/elevation_strip_test.dart
```

- [ ] **Step 3: Implement the graded route layer**

`lib/ui/detail/graded_route_layer.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:track_scribe/core/geo.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/theme/palette.dart';

/// Per-segment speed of the route in m/s: the point's measured speed when
/// present, otherwise distance over the monotonic delta (0 when dt is 0 —
/// never divide, never invent).
double segmentSpeedMps(StoredPoint a, StoredPoint b) {
  final measured = b.speedMps;
  if (measured != null) return measured;
  final dtS = (b.timeNanos - a.timeNanos) / 1e9;
  if (dtS <= 0) return 0;
  return a.distanceTo(b) / dtS;
}

/// Slowest → dim olive, fastest → the brand accent (spec §12.1).
Color speedColor(double t) =>
    Color.lerp(GradedRouteLayer.slowColor, GradedRouteLayer.fastColor, t.clamp(0.0, 1.0))!;

/// The finished-activity route: one coloured segment per pair, coloured by
/// each segment's speed percentile over the whole route, plus a direction
/// arrow at the midpoint. A flutter_map child — it re-projects via
/// [MapCamera.of] on every camera change.
class GradedRouteLayer extends StatelessWidget {
  const GradedRouteLayer({super.key, required this.points, required this.strokeWidth});

  final List<StoredPoint> points;
  final double strokeWidth;

  static const Color slowColor = Color(0xFF4D6112);
  static const Color fastColor = Palette.accent;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return CustomPaint(
      painter: _GradedRoutePainter(points, camera, strokeWidth),
      size: Size.infinite,
    );
  }
}

class _GradedRoutePainter extends CustomPainter {
  _GradedRoutePainter(this.points, this.camera, this.strokeWidth);

  final List<StoredPoint> points;
  final MapCamera camera;
  final double strokeWidth;

  List<StoredPoint> get _route =>
      [for (final p in points) if (p.type != WaypointType.rejected) p];

  @override
  void paint(Canvas canvas, Size size) {
    final route = _route;
    if (route.length < 2) return;
    final speeds = [
      for (var i = 1; i < route.length; i++)
        segmentSpeedMps(route[i - 1], route[i]),
    ];
    final sorted = [...speeds]..sort();
    double percentile(double v) {
      if (sorted.isEmpty) return 0;
      var lo = 0, hi = sorted.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (sorted[mid] < v) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return sorted.isEmpty ? 0 : lo / sorted.length;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 1; i < route.length; i++) {
      final a = camera.latLngToScreenOffset(LatLng(route[i - 1].lat, route[i - 1].lon));
      final b = camera.latLngToScreenOffset(LatLng(route[i].lat, route[i].lon));
      paint.color = speedColor(percentile(speeds[i - 1]));
      canvas.drawLine(a, b, paint);
    }
    _arrow(canvas, route);
  }

  void _arrow(Canvas canvas, List<StoredPoint> route) {
    final mid = route.length ~/ 2;
    if (mid < 1 || mid >= route.length - 1) return;
    final from = route[mid - 1];
    final to = route[mid + 1];
    final o = camera.latLngToScreenOffset(LatLng(route[mid].lat, route[mid].lon));
    final deg = bearingDeg(from.lat, from.lon, to.lat, to.lon);
    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.rotate(deg * math.pi / 180);
    final p = Path()
      ..moveTo(10, 0)
      ..lineTo(-6, -7)
      ..lineTo(-6, 7)
      ..close();
    canvas.drawPath(
      p,
      Paint()
        ..color = Palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GradedRoutePainter old) =>
      old.points != points || old.camera != camera || old.strokeWidth != strokeWidth;
}
```

(If `core/geo.dart` has no `bearingDeg`, add it there with a unit test in `test/core/geo_test.dart`:

```dart
double bearingDeg(double lat1, double lon1, double lat2, double lon2) {
  final φ1 = lat1 * math.pi / 180, φ2 = lat2 * math.pi / 180;
  final Δλ = (lon2 - lon1) * math.pi / 180;
  final y = math.sin(Δλ) * math.cos(φ2);
  final x = math.cos(φ1) * math.sin(φ2) - math.sin(φ1) * math.cos(φ2) * math.cos(Δλ);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}
```

— verify against the existing geo.dart helpers first.)

- [ ] **Step 4: Implement the elevation strip**

`lib/ui/detail/elevation_strip.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/theme/palette.dart';

/// Grade colour: flat → dim olive, ±8 % slope → the accent (spec §12.1
/// «شريط مقطع الارتفاع مع تظليل الدرجة» — GNSS altitude, ر11 data).
Color gradeColor(double t) =>
    Color.lerp(ElevationStrip.flatColor, ElevationStrip.steepColor, t.clamp(0.0, 1.0))!;

class ElevationStrip extends StatelessWidget {
  const ElevationStrip({super.key, required this.points});

  final List<StoredPoint> points;

  static const Color flatColor = Color(0xFF4D6112);
  static const Color steepColor = Palette.accent;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 96,
    width: double.infinity,
    child: CustomPaint(painter: ElevationStripPainter(points)),
  );
}

class ElevationStripPainter extends CustomPainter {
  ElevationStripPainter(this.points);

  final List<StoredPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final measured = [
      for (final p in points)
        if (p.altitudeM != null) p.altitudeM!,
    ];
    if (measured.length < 2) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'لا توجد بيانات ارتفاع',
          style: TextStyle(fontSize: 11, color: Palette.textSecondary),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      tp.paint(
        canvas,
        Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
      );
      return;
    }
    final minA = measured.reduce(math.min);
    final maxA = measured.reduce(math.max);
    final pad = maxA == minA ? 1.0 : (maxA - minA) * 0.1;
    final lo = minA - pad, hi = maxA + pad;
    double yOf(double a) => size.height - (a - lo) / (hi - lo) * size.height;
    double xOf(int i) => points.length <= 1 ? 0 : i / (points.length - 1) * size.width;

    // grade-shaded segments, gaps where altitude is missing
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      if (a.altitudeM == null || b.altitudeM == null) continue;
      final dist = a.distanceTo(b);
      final grade = dist <= 0 ? 0.0 : (b.altitudeM! - a.altitudeM!) / dist;
      line.color = gradeColor((grade.abs() / 0.08).clamp(0.0, 1.0));
      canvas.drawLine(
        Offset(xOf(i - 1), yOf(a.altitudeM!)),
        Offset(xOf(i), yOf(b.altitudeM!)),
        line,
      );
    }

    final labelStyle = const TextStyle(fontSize: 9, color: Palette.textSecondary);
    TextPainter(text: TextSpan(text: '${maxA.round()} م', style: labelStyle), textDirection: TextDirection.rtl)
      ..layout()
      ..paint(canvas, Offset(4, 2));
    TextPainter(text: TextSpan(text: '${minA.round()} م', style: labelStyle), textDirection: TextDirection.rtl)
      ..layout()
      ..paint(canvas, Offset(4, size.height - 13));
  }

  @override
  bool shouldRepaint(covariant ElevationStripPainter old) => old.points != points;
}
```

- [ ] **Step 5: Run both test files — pass**

```bash
cd track_scribe && flutter test test/ui/graded_route_layer_test.dart test/ui/elevation_strip_test.dart
```

Expected: PASS (5 tests total; adjust the `inInclusiveRange` assertions to the actual lerp values if the color space check fails — the endpoints are the contract).

- [ ] **Step 6: The detail screen**

`lib/ui/detail/activity_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/activity_summary.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/sport_config.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/basemap/map_style_provider.dart';
import 'package:track_scribe/ui/detail/elevation_strip.dart';
import 'package:track_scribe/ui/detail/graded_route_layer.dart';
import 'package:track_scribe/ui/recording/widgets/stat_panel.dart';

final activityDetailProvider = FutureProvider.family<ActivitySummary, int>(
  (ref, id) => ref.watch(activityRepositoryProvider).loadActivityWithPoints(id)
      .then((s) => s ?? (throw StateError('activity $id not found'))),
);

class ActivityDetailScreen extends ConsumerWidget {
  const ActivityDetailScreen({super.key, required this.activityId});

  final int activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(activityDetailProvider(activityId));
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        elevation: 0,
        title: Text('تفاصيل النشاط', style: Theme.of(context).textTheme.titleLarge),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: summary.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Palette.accent),
          ),
          error: (_, __) => const Center(
            child: Text(
              'تعذّر تحميل النشاط',
              style: TextStyle(color: Palette.textSecondary),
            ),
          ),
          data: (s) => _DetailBody(summary: s),
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.summary});

  final ActivitySummary summary;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  double _thickness = 5;

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatPanel(
            distanceM: s.distanceM,
            elapsedNanos: s.elapsedNanos,
            sport: Sport.values.byName(s.sport),
            fixCount: s.fixCount,
          ),
          const SizedBox(height: 8),
          Expanded(flex: 4, child: _DetailMap(summary: s, thickness: _thickness)),
          const SizedBox(height: 8),
          Center(
            child: SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 3, label: Text('رفيع')),
                ButtonSegment(value: 5, label: Text('متوسط')),
                ButtonSegment(value: 8, label: Text('غليظ')),
              ],
              selected: {_thickness},
              onSelectionChanged: (v) => setState(() => _thickness = v.first),
            ),
          ),
          const SizedBox(height: 8),
          ElevationStrip(points: s.points),
        ],
      ),
    );
  }
}

class _DetailMap extends ConsumerWidget {
  const _DetailMap({required this.summary, required this.thickness});

  final ActivitySummary summary;
  final double thickness;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(mapStyleProvider);
    final route = [
      for (final p in summary.points)
        if (p.type != WaypointType.rejected) LatLng(p.lat, p.lon),
    ];
    final start = route.isEmpty ? null : route.first;
    final end = route.isEmpty ? null : route.last;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: style.when(
        loading: () => const ColoredBox(color: Palette.bg),
        error: (_, __) => GridBasemap(points: summary.points),
        data: (s) => FlutterMap(
          options: MapOptions(
            initialCameraFit: route.length >= 2
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(route),
                    padding: const EdgeInsets.all(24),
                  )
                : CameraFit.coordinates(
                    coordinates: start ?? const LatLng(36.7525, 3.0420),
                    zoom: 16,
                  ),
            minZoom: 2,
            maxZoom: 18,
            backgroundColor: Palette.bg,
          ),
          children: [
            VectorTileLayer(
              theme: s.theme,
              tileProviders: s.providers.providers,
              sprites: s.sprites,
              diskCacheMaximumSizeInBytes: 0,
            ),
            GradedRouteLayer(points: summary.points, strokeWidth: thickness),
            MarkerLayer(
              markers: [
                if (start != null)
                  Marker(
                    point: start,
                    width: 16,
                    height: 16,
                    child: const _StartDot(),
                  ),
                if (end != null && end != start)
                  Marker(
                    point: end,
                    width: 16,
                    height: 16,
                    child: const _EndDot(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StartDot extends StatelessWidget {
  const _StartDot();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Palette.onAccent,
      border: Border.all(color: Palette.accent, width: 2.5),
    ),
  );
}

class _EndDot extends StatelessWidget {
  const _EndDot();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(shape: BoxShape.circle, color: Palette.accent),
  );
}
```

(Add the missing `GridBasemap` import if the fallback branch references it. If `CameraFit.coordinates` does not exist in flutter_map 8.3.2, check the 8.3.2 API for the single-point fit name and use it.)

- [ ] **Step 7: Post-stop affordance on the recording screen**

In `lib/ui/recording/recording_screen.dart`, after `StopButton(...)` inside the stat Column add:

```dart
if (s.lastActivityId != null && s.phase == RecordingPhase.stopped)
  Padding(
    padding: const EdgeInsets.only(top: 8),
    child: OutlinedButton.icon(
      key: const Key('detail-button'),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ActivityDetailScreen(activityId: s.lastActivityId!),
        ),
      ),
      icon: const Icon(Icons.route_outlined, size: 18),
      label: const Text('تفاصيل النشاط'),
    ),
  ),
```

- [ ] **Step 8: Detail screen tests**

`test/ui/detail_screen_test.dart` (DB seeded via the same in-memory pattern as Task 5; `mapStyleProvider` overridden with the stub style exactly as `vector_map_band_test.dart` does):

```dart
testWidgets('renders stats, graded route, thickness chooser, elevation strip', (tester) async {
  // seed: insert activity + 3 points (altitudes 10, 20, 30), finishActivity
  // override activityRepositoryProvider with the seeded repo
  await tester.pumpWidget(ProviderScope(
    overrides: [mapStyleProvider.overrideWith((ref) => Future.value(style))],
    child: MaterialApp(home: ActivityDetailScreen(activityId: id)),
  ));
  await tester.pumpAndSettle();

  expect(find.text('تفاصيل النشاط'), findsOneWidget);
  expect(find.byType(GradedRouteLayer), findsOneWidget);
  expect(find.byType(ElevationStrip), findsOneWidget);
  expect(find.text('رفيع'), findsOneWidget);
  expect(find.text('غليظ'), findsOneWidget);

  // thickness choice changes the layer's strokeWidth without error
  await tester.tap(find.text('رفيع'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
});

testWidgets('shows the load error state for a missing activity', (tester) async {
  // activityDetailProvider with a repo that has no row id 999
  await tester.pumpWidget(...);
  await tester.pumpAndSettle();
  expect(find.text('تعذّر تحميل النشاط'), findsOneWidget);
});
```

Also extend `test/ui/recording_screen_test.dart` with one case: after stop with recorded points, the «تفاصيل النشاط» button appears; before any recording it does not.

- [ ] **Step 9: Full suite + analyze**

```bash
cd track_scribe && flutter analyze && flutter test
```

Expected: all green.

- [ ] **Step 10: Commit + push + CI**

```bash
git add lib/ui/detail/ lib/ui/recording/recording_screen.dart test/ui/
git commit -m "feat(map): finished-activity detail — speed-graded route, direction arrow, elevation strip"
git push
gh run watch
```

Expected: `android-apk` green. Record the run id.

---

## Task 7: قياس APK الحجم الفعلي بالحزم + إثبات أخضر

**Files:**
- Create: `docs/superpowers/evidence/2026-10-12-map-implementation.md`

**Interfaces:** none new — reads CI outputs.

- [ ] **Step 1: From the green run of Task 6 (or a fresh push), read the artifact**

```bash
gh api repos/toufikben/track-scribe/actions/runs/<RUN_ID>/artifacts --jq '.artifacts[] | {name, size_in_bytes}'
```

- [ ] **Step 2: Write the evidence doc**

`docs/superpowers/evidence/2026-10-12-map-implementation.md` — sections: (1) the APK size WITH the two packs (exact bytes from Step 1, run id) vs the last pre-map APK size if one was recorded; (2) the test counts from the CI log (exact numbers, `flutter test` summary); (3) what remains unmeasured until the device round (Task 8): Arabic-connected labels on the map, live halo, ms-to-first-tile — each marked «سيُقاس على الجهاز», NOT claimed; (4) the localization decisions (water `#182128` reading of «مائلًا», raster/glyphs stripped, why). No PASS claim for anything the CI did not print.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/evidence/2026-10-12-map-implementation.md
git commit -m "evidence(map): APK size with the bundled packs, measured on CI"
git push
```

---

## Task 8: جهاز — اللقطة التي تثبت «الخريطة ممتازة»

**Files:** screenshots under the SDD workspace (not the repo); evidence doc updated with device findings.

**Gate:** this task needs the phone free AND unlocked by the owner. If `com.toufikben.ledger` still holds focus or the device is locked, DO NOT proceed — record the deferral in the ledger and finish the plan with tasks 1-7 verified; the device round joins task #42's round when the phone frees up. Never ask for or accept the PIN.

- [ ] **Step 1: Install the CI APK from Task 6's run on the Realme (adb)**
- [ ] **Step 2: Recording screen**: launch, grant flow as before; walk/drive 100-300 m; capture: map tiles visible (Algiers streets from the wilaya pack), live `#C6FF3D` route over them, accuracy halo around the dot, attribution row visible, Arabic street labels rendered CONNECTED (no disconnected letters) — the screenshot is the proof 12.3 demands.
- [ ] **Step 3: Overzoom**: zoom to 17-18 — tiles stay rendered (pipeline overzoom), no blank flash.
- [ ] **Step 4: Stop → «تفاصيل النشاط»**: graded line (visible light→dark variation), start/end dots, direction arrow, elevation strip with a real altitude profile, thickness switch works (screenshots before/after).
- [ ] **Step 5: Off-pack area** (outside the wilaya, e.g. a drive toward Blida or Boumerdès): country pack takes over seamlessly at z≤12; recording never pauses.
- [ ] **Step 6: Update the evidence doc** with the screenshots' findings (pass/fail per item, NOT RUN where the phone was unavailable) and commit.

---

## Task 9: لا مستطيل فارغ — سقف لكل حزمة بدل سقفٍ واحد للجميع (ر107)

**Why this task exists (measured, not theorised):** Task 8 Step 5 claimed "outside
the wilaya the country pack takes over seamlessly at z≤12". The device disproved
it. The tester's phone sits at 36.2537 N, 2.2328 E (Khemis Miliana), which is
inside `dz-country-z12.pmtiles` (bbox -8.7049,18.9287 → 12.0360,38.0183) and
outside `dz-wilaya-alger-z14.pmtiles` (2.8500,36.4200 → 3.6800,37.1000). During a
live recording the band there is an empty rectangle (screenshot
`21-band-live.png`: overlays, scale bar and attribution alive; zero tiles).

The cause is one getter. `LocalPmTilesProvider.maximumZoom` returns the MAX over
all archives (14), and flutter_map_vector_tiles resolves every display zoom to a
data zoom with `dataZoom.clamp(minimumZoom, maximumZoom)`
(`lib/src/core/tile_zoom.dart:27`). So at z16 the renderer asks this provider for
**z14** tiles; `load()` then skips the country archive because `tile.z > archive.maxZoom`
(`local_pmtiles_provider.dart:57`) and answers NotFound. The z12 archive is never
consulted, even though it holds the ground under the user's feet.

**Corrections from reading the vendor source (verify these, do not re-derive):**

1. `VectorTileLayer.tileProviders` is **`TileProviders`**, a class wrapping
   `Map<String, VectorTileProvider>` keyed by the style's *source id*
   (`flutter_map_vector_tiles-2.9.1/lib/src/vector_tile_layer.dart:61`,
   `lib/src/tile_providers.dart:4-9`). It is not a bare Map. Each stacked layer
   gets `TileProviders({'openmaptiles': providerForThisArchive})`.
2. The overzoom fallback needs **no new code**: `dataKeyForDisplay` clamps the
   data zoom into `[minimumZoom, maximumZoom]` and shifts the tile down to the
   parent (`lib/src/core/tile_zoom.dart:17-32`). A provider whose
   `maximumZoom` is 12 therefore serves *any* display zoom ≥ 12 by fetching the
   z12 parent and scaling its sub-region — precisely the behaviour the merged
   ceiling destroyed.
3. Stacking is visually safe because `assets/styles/dark.json`'s first layer is
   `{"id":"background","type":"background","paint":{"background-color":"#101315"}}`
   — opaque. A deeper layer painted above covers the shallow one wherever it has
   bytes; where it answers `TileResponseNotFound` it paints nothing and the
   shallow layer below stays visible. Order the layers **shallow first**.
4. `cacheKey` must be **distinct per archive**: the interface doc
   (`lib/src/provider/vector_tile_provider.dart:44-53`) states two providers
   sharing a key are assumed to serve identical bytes for identical
   coordinates, including across layers.
5. **Ruling — ship two layers, not three.** Bundling country + Algiers-wilaya +
   Khemis-Miliana would decode one tile *per layer* on every screen: 3× the
   decode on a 2-core phone, which is the exact R105 failure mode this plan is
   trying to disprove. `kBundledTileNames` becomes the country pack + the
   Khemis-Miliana pack, and `dz-wilaya-alger-z14.pmtiles` leaves the bundle (it
   stays a CI artifact; R103's registry makes re-adding it one name). This also
   cuts ~19.6 MB from the 93.3 MB release APK. The cost if wrong: a tester
   standing in Algiers sees the coarse country map above z12 — visible, honest,
   and one asset away from fixed.

**Files:**
- Modify: `track_scribe/lib/ui/basemap/local_pmtiles_provider.dart`
- Modify: `track_scribe/lib/ui/basemap/map_style_provider.dart`
- Modify: `track_scribe/lib/ui/basemap/vector_map_band.dart`
- Modify: `track_scribe/lib/ui/detail/activity_detail_screen.dart`
- Modify: `track_scribe/lib/data/tile_store.dart` (register the new pack name)
- Add: `track_scribe/assets/tiles/dz-khemis-miliana-z14.pmtiles` (the raw
  1,792,009-byte pack already downloaded from tiles-spike run 38637771170 — it is
  on the controller's disk at `Desktop/ts-round/packs/`, hand it to the
  implementer rather than re-downloading)
- Remove: `track_scribe/assets/tiles/dz-wilaya-alger-z14.pmtiles` (per ruling 5
  above: it leaves the bundle, so the APK carries exactly two layers and ~19.6 MB
  less; it also stops being a test fixture, see Step 1)
- Test: `track_scribe/test/ui/local_pmtiles_provider_test.dart`, `track_scribe/test/ui/map_style_test.dart`, `track_scribe/test/ui/vector_map_band_test.dart`

**Interfaces:**
- Consumes: `archive.header` — `Header.minZoom` (u8 @100), `maxZoom` (u8 @101),
  `minPosition` (int32 e7 **longitude** @102 then **latitude** @106 = the
  south-west corner) and `maxPosition` (@110/@114 = north-east), verified in
  `pmtiles-2.2.0/lib/src/header.dart:77-81` + `convert.dart:64-72`. Note the
  on-disk order is lon-then-lat while `LatLng`'s constructor is lat-then-lon:
  transposing them is the one editing mistake that would make routing look
  plausible and fail everywhere (both shipped packs decode to the exact bounds
  CI printed for them — 2.10,36.13→2.37,36.40 and -8.7049,18.9287→12.0360,38.0183).
- Produces: `class BundledStyle { final Theme theme; final SpriteAtlas? sprites; final List<TileProviders> layers; }` —
  one entry per archive, shallowest first. Each entry is
  `TileProviders({'<sourceId>': provider})` built from the source id the bundled
  style actually declares (`dark.json` has exactly one source, `openmaptiles`),
  never a hardcoded string in two places. `mapStyleProvider` becomes
  `FutureProvider<BundledStyle>`.
- Produces: `LocalPmTilesProvider({required PmTilesArchive archive, required String cacheKey, List<TileBounds> shadowedBy = const []})`
  — one archive per provider; `minimumZoom`/`maximumZoom` are that archive's own
  header values; `TileBounds get bounds` exposes the header bbox;
  `covers(LatLng)` is true only inside its own bbox and outside every `shadowedBy`
  box. `TileBounds` is the app's own record — `typedef TileBounds = ({double
  west, double south, double east, double north})` — built from
  `archive.header` (`minPosition`/`maxPosition` already expose the four numbers;
  the header stores them as int32 × 1e7).
- Routing is a **tile-rectangle ∩ pack-bbox** test, not a corner test: `TileKey`
  carries only `z/x/y` (`core/tile_key.dart:9-13`) and a z14 tile spans ~2 km, so
  testing one corner would leave the last column/row of a pack's box unpainted.
  The exact math to use:

```dart
  bool _intersectsPack(final TileKey tile) {
    final n = math.pow(2, tile.z).toDouble();
    final west = tile.x / n * 360 - 180;
    final east = (tile.x + 1) / n * 360 - 180;
    final north = _latAt(tile.y / n);
    final south = _latAt((tile.y + 1) / n);
    return !(east < _west || west > _east || north < _south || south > _north);
  }

  /// Web-Mercator row → latitude (standard inverse mercator).
  static double _latAt(final double ty) =>
      180 / math.pi * math.atan(math.sinh(math.pi * (1 - 2 * ty)));
```

- [ ] **Step 1: RED — the merged provider's single ceiling is the bug**

In `test/ui/local_pmtiles_provider_test.dart`, load both real assets and assert
the new per-archive shape. `openAsset(name)` is the helper this file already
needs (it currently repeats the `rootBundle.load` + `asUint8List` dance three
times — extract it as part of this step):

```dart
test('each pack answers with its OWN ceiling, so a z14 view outside the deep '
     'pack still gets the shallow one (ر107)', () async {
  final deep = LocalPmTilesProvider(
    archive: await openAsset('dz-khemis-miliana-z14.pmtiles'),
    cacheKey: 'test-deep',
  );
  final shallow = LocalPmTilesProvider(
    archive: await openAsset('dz-country-z12.pmtiles'),
    cacheKey: 'test-shallow',
  );
  expect(deep.maximumZoom, 14);
  expect(shallow.maximumZoom, 12,
      reason: 'a merged ceiling of 14 is what made the band an empty rectangle');

  // Khemis Miliana: inside the country bbox AND inside the deep pack's box.
  final home = const LatLng(36.2537, 2.2328);
  expect(shallow.covers(home), isTrue);
  expect(deep.covers(home), isTrue);

  // ~120 km west, still inside Algeria: the deep pack must refuse it and the
  // country pack must take it. This is the exact void the device photographed.
  final elsewhere = const LatLng(36.18, 1.22); // Mascara side
  expect(deep.covers(elsewhere), isFalse);
  expect(shallow.covers(elsewhere), isTrue);

  // A shallow provider shadowed by the deep box does not paint under it: the
  // cost of stacking is one coarse tile per deep tile, and this removes it.
  // `deep.bounds` is the record read off that archive's OWN header — the test
  // must route with the same numbers the provider uses, never a literal box.
  final shadowed = LocalPmTilesProvider(
    archive: await openAsset('dz-country-z12.pmtiles'),
    cacheKey: 'test-shallow-shadowed',
    shadowedBy: [deep.bounds],
  );
  expect(shadowed.covers(home), isFalse);
  expect(shadowed.covers(elsewhere), isTrue);
});
```

Also assert the header itself, so a rebuilt pack that moves its box cannot silently
change the routing: `expect(deep.bounds, equals(const (2.1000, 36.1300, 2.3700,
36.4000)))` — those are the values decoded from the shipped pack on 2026-10-14.

The existing R103 ordering test (`deepest-pack-first ordering comes from the
headers, not caller order`) loads `dz-wilaya-alger-z14.pmtiles`, which this task
removes from the bundle. Migrate it to the Khemis pack rather than deleting it —
the law it pins (priority comes from the header, not caller order) still needs a
guard, and both packs still hold a z12 tile over Khemis, so its positive and
negative halves survive the swap verbatim with only the asset name changed.

Run: `flutter test test/ui/local_pmtiles_provider_test.dart` — must fail to
compile (`archive:`/`covers`/`shadowedBy` do not exist yet). Capture the failure
before touching lib.

- [ ] **Step 2: Implement the one-archive provider**

`LocalPmTilesProvider` keeps its body (the try/continue/logging around
`archive.tile`) and loses the archive loop: `_archives` → one `archive`;
`minimumZoom`/`maximumZoom`/`bounds` read that archive's header. Two predicates,
one purpose: `covers(LatLng)` is the point form the tests and the recenter logic
use, while `load()` short-circuits on the **rectangle** form before touching the
directory — a z14 tile spans ~2 km, so testing one corner would leave the pack's
last column and row unpainted (use the exact `_intersectsPack`/`_latAt` math from
the Interfaces block, not `tile.latLng`, which does not exist on `TileKey`). The
`List<PmTilesArchive>` constructor and the R103 sort are deleted, not kept "for
compatibility" — the ordering law moves to `mapStyleProvider`, which now builds
one provider per archive, shallowest first, each shadowed by **the full bbox of
every deeper pack** (not its centre point).

- [ ] **Step 3: GREEN the provider test, then RED the style test**

`map_style_test.dart`: `mapStyleProvider` must yield `layers.length == 2` for the
two registered packs, ordered shallow→deep, each map's only key equal to the
source id the bundled style declares. Then `vector_map_band_test.dart` (which
stubs the style per R104) asserts the band renders one `VectorTileLayer` per
entry — the widget test is where a single-layer regression would otherwise hide.

- [ ] **Step 4: Stack the layers in both bands**

```dart
children: [
  for (final providers in s.layers)
    VectorTileLayer(
      theme: s.theme,
      tileProviders: providers,
      sprites: s.sprites,
      diskCacheMaximumSizeInBytes: 0,
    ),
  ...
]
```
`activity_detail_screen.dart` gets the same loop. No style JSON edit: the same
source id is bound to a different provider per layer, so each layer paints the
whole style from one pack, and the bbox rules in Step 2 make exactly one of them
paint any given tile.

- [ ] **Step 5: Swap the shipped pack for the one around the tester's town**

Put `dz-khemis-miliana-z0-14.pmtiles` (raw 1,792,009 B, measured in
`Desktop/ts-round/packs/`) at `assets/tiles/dz-khemis-miliana-z14.pmtiles`,
`git rm assets/tiles/dz-wilaya-alger-z14.pmtiles`, and make `kBundledTileNames`
= country + Khemis.

Then handle the upgrade path, which is where a pack *rename* bites: an installed
phone has `tiles-v1` set and a 20.5 MB `dz-wilaya-alger-z14.pmtiles` sitting in
its documents dir. `ensureBundledTiles` already re-copies when a registered name
is missing, but it never deletes anything, so the orphan would stay forever. Bump
`flagKey` to `tiles-v2` **and** delete any `*.pmtiles` in the tiles dir that is
not in `kBundledTileNames` (both in the same pass). Add the two cases to
`test/data/tile_store_test.dart`: a stale unregistered pack is removed, and a
missing registered pack is re-copied even when the version flag is already set.
Record the measured bytes and the z14 density they imply against the 20.5 MB /
836 km² Alger figure (ر108: 24.5 vs 2.5 MB per 1000 km²) in the evidence doc.

- [ ] **Step 6: Full suite + analyze, commit, push, watch CI**

`flutter analyze` and `flutter test` locally (allowed; no local APK build).
Commit `fix(map): one zoom ceiling per pack so the band is never an empty rectangle (R107)`.

- [ ] **Step 7: Device re-proof — this is also R105's real test**

Install the CI APK. At the phone's actual position the band must now show tiles
while a session records: (a) with the Khemis Miliana pack → z14 detail; (b) after
panning ~50 km out of any box → the country pack overzoomed, i.e. coarse map, not
a void. Both screenshots are the R105 proof, which Task 4 left open because every
earlier attempt was taken where no pack had data at all.

(c) One more case this task changes on purpose: the band's pre-fix centre is
Algiers (36.7525, 3.0420), whose z14 pack no longer ships. Before the first GPS
fix that spot must now render the coarse country map rather than the old detail —
screenshot it and write the zoom level the tiles actually come from, because
"the app opens on a town we no longer ship at z14" is a product decision the
owner should see as a picture, not read as a paragraph.
