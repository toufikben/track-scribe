import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:track_scribe/data/tile_store.dart' show kBundledTileNames;
import 'package:track_scribe/ui/basemap/local_pmtiles_provider.dart';
import 'package:track_scribe/ui/basemap/map_style_provider.dart'
    show readBundledStyle, stackProviders;

TileKey _tileKeyAt(int z, double lat, double lon) {
  final n = 1 << z;
  final x = ((lon + 180) / 360 * n).floor();
  final rad = lat * math.pi / 180;
  final y =
      ((1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2 * n)
          .floor();
  return TileKey(z, x, y);
}

/// `PlatformAssetBundle.load` does NOT cache ByteData, and `MemoryAt` (what
/// `fromBytes` builds) retains every copy it is handed with a no-op `close()` —
/// so the 53,718,750 B country pack would cross the asset channel once per
/// call site. One buffer per asset name: the archives share it (read-only),
/// which is safe precisely because their close does nothing.
final _packBytes = <String, Future<Uint8List>>{};

/// Loads a bundled pack as an archive, the way the app does at runtime.
/// rootBundle.load never runs inside a fake-async zone here (plain `test`,
/// and the asset completes in real time).
Future<PmTilesArchive> openAsset(String name) async {
  final bytes = _packBytes.putIfAbsent(name, () async {
    final data = await rootBundle.load('assets/tiles/$name');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  });
  return PmTilesArchive.fromBytes(await bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('serves a real pack tile, reports honest zooms, rejects outside', () async {
    final provider = LocalPmTilesProvider(
      archive: await openAsset('dz-khemis-miliana-z14.pmtiles'),
      cacheKey: 'test-khemis',
    );

    expect(provider.minimumZoom, 0);
    expect(provider.maximumZoom, 14);
    expect(provider.cacheKey, 'test-khemis');
    expect(provider.cacheBytesToDisk, isFalse);

    // Khemis Miliana centre — inside the pack's own bbox (2.10..2.37 E, 36.13..36.40 N)
    final inside = await provider.load(_tileKeyAt(14, 36.2537, 2.2328));
    expect(inside, isA<TileResponseData>());
    expect((inside as TileResponseData).bytes.length, greaterThan(100));

    // far outside the pack (30 N, 0 E is beyond its bounds)
    final outside = await provider.load(_tileKeyAt(14, 30.0, 0.0));
    expect(outside, isA<TileResponseNotFound>());

    // a zoom the pack does not cover is not the pack's job — the pipeline
    // clamps, but a direct over-range request must be NotFound, never a throw
    final deep = await provider.load(_tileKeyAt(17, 36.2537, 2.2328));
    expect(deep, isA<TileResponseNotFound>());

    provider.dispose();
  });

  test('serves the country pack at a zoom only it covers', () async {
    final provider = LocalPmTilesProvider(
      archive: await openAsset('dz-country-z12.pmtiles'),
      cacheKey: 'test-country',
    );
    expect(provider.maximumZoom, 12);
    // a z12 tile inside Algeria (Tamanrasset ~22.8 N, 5.5 E)
    final res = await provider.load(_tileKeyAt(12, 22.8, 5.5));
    expect(res, isA<TileResponseData>());
    provider.dispose();
  });

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

    // The header itself is pinned, so a rebuilt pack that moves its box cannot
    // silently change the routing. These are the values decoded from the
    // shipped pack on 2026-10-14.
    expect(
      deep.bounds,
      equals(const (west: 2.1000, south: 36.1300, east: 2.3700, north: 36.4000)),
    );

    deep.dispose();
    shallow.dispose();
    shadowed.dispose();
  });

  // Ruling R103: pack priority is read off each PMTiles header's own maxZoom,
  // never from the order the caller passes. The law moved from
  // LocalPmTilesProvider to stackProviders (map_style_provider.dart) when each
  // layer bound its own archive; it still guards, on the Khemis pack now.
  test('deepest-pack-first ordering comes from the headers, not caller order', () async {
    final country = await openAsset('dz-country-z12.pmtiles');
    final khemis = await openAsset('dz-khemis-miliana-z14.pmtiles');

    // WRONG caller order on purpose: the headers decide (R103).
    final providers = stackProviders([
      (archive: khemis, cacheKey: 'test-order-deep'),
      (archive: country, cacheKey: 'test-order-shallow'),
    ]);
    expect(
      providers.map((p) => p.maximumZoom),
      [12, 14],
      reason: 'shallowest first, from the headers, not the argument order',
    );

    // Measured on the shipped packs: for the TOWN's own z12 tile both packs
    // hold byte-identical data (the country build shares the clipped one
    // there), so a winner assertion on that tile would be vacuous. The bbox-
    // edge tile is held by both and its bytes DIFFER (the deep pack's is
    // clipped at the bbox) — only there can the negative half pin which
    // pack won. Layers paint bottom-up, so the deep provider's bytes are
    // what wins on screen.
    final key = _tileKeyAt(12, 36.42, 2.2328);
    final served = await providers[1].load(key);
    expect(served, isA<TileResponseData>());

    final deeper = await khemis.tile(ZXY(12, key.x, key.y).toTileId());
    expect(
      listEquals((served as TileResponseData).bytes, deeper.bytes()),
      isTrue,
      reason: 'the z14-header pack must win for a tile both packs hold',
    );

    // The negative half: the shallow pack also holds this tile, and its bytes
    // are NOT what wins. Without this the positive assertion could pass
    // under any ordering the day both packs are rebuilt from one source.
    final shallower = await country.tile(ZXY(12, key.x, key.y).toTileId());
    expect(
      listEquals(served.bytes, shallower.bytes()),
      isFalse,
      reason: 'the z12 pack must not be what wins for a contested tile',
    );

    // And the shallow provider is shadowed over the town: stacked above by
    // the deep pack's FULL bbox, it must refuse a fully-covered tile outright.
    final home = _tileKeyAt(12, 36.2537, 2.2328);
    expect(
      await providers[0].load(home),
      isA<TileResponseNotFound>(),
      reason: 'the z12 tile of a shadowed pack must not decode under the deep layer',
    );

    for (final p in providers) {
      p.dispose();
    }
  });

  // The everyday path of the real map: the deep header claims z0-14 but its
  // bounds cover one town, so most z<=12 queries over Algeria are honest
  // absences in the deep pack that the stacked country layer answers instead.
  test('a tile outside the deep pack is its honest NotFound while the country pack answers it', () async {
    final khemis = await openAsset('dz-khemis-miliana-z14.pmtiles');
    final country = await openAsset('dz-country-z12.pmtiles');
    const cacheKey = 'test-fall-through';
    final deepProvider = LocalPmTilesProvider(
      archive: khemis,
      cacheKey: cacheKey,
    );
    final countryProvider = LocalPmTilesProvider(
      archive: country,
      cacheKey: 'test-fall-through-country',
    );

    final key = _tileKeyAt(12, 22.8, 5.5); // Tamanrasset: in country, outside the deep box
    expect(
      await deepProvider.load(key),
      isA<TileResponseNotFound>(),
      reason: 'the bbox test, not the directory, must reject an outside tile',
    );

    final served = await countryProvider.load(key);
    expect(served, isA<TileResponseData>());

    final direct = await country.tile(ZXY(12, key.x, key.y).toTileId());
    expect(
      listEquals((served as TileResponseData).bytes, direct.bytes()),
      isTrue,
      reason: 'the country pack must answer a tile the deeper pack does not cover',
    );

    deepProvider.dispose();
    countryProvider.dispose();
  });

  // tile() awaits lookup + readAt, which can throw — e.g. its FileAt read pool
  // closed while the provider stays live. Such an error must never escape to
  // the renderer: the provider answers NotFound and stays silent.
  test('a closed read pool neither escapes nor throws at the renderer', () async {
    // File-backed exactly like the first-launch runtime (pack copied to docs).
    final khemis = await PmTilesArchive.fromFile(
      File('assets/tiles/dz-khemis-miliana-z14.pmtiles'),
    );
    final provider = LocalPmTilesProvider(
      archive: khemis,
      cacheKey: 'test-closed-pool',
    );
    await khemis.close();

    // A z14 tile over Khemis the pack holds: reading it now fails inside the
    // await itself. The guard must convert that into an honest NotFound.
    final key = _tileKeyAt(14, 36.2537, 2.2328);
    final served = await provider.load(key);
    expect(served, isA<TileResponseNotFound>());

    provider.dispose(); // disposing an archive whose pool is already closed
  });

  // ر107 review I-1: a pack opened on the way to the style has NO owner until
  // the caller registers `ref.onDispose(bundled.dispose)` — which only happens
  // once the read succeeds. So a failed read must close every pack it opened,
  // or the app settles on the GridBasemap fallback with both packs stranded for
  // the session. File-backed over the real assets, exactly like the runtime.
  test('a failed style read closes the packs it opened instead of stranding them',
      () async {
    List<LocalPmTilesProvider>? opened;
    await expectLater(
      readBundledStyle(
        'assets/tiles',
        readStyle: (providers) async {
          opened = providers;
          // The documented offline failure: StyleReader drops every source it
          // cannot resolve and then throws (style_reader.dart:221-223).
          throw const StyleReaderException('style contains no usable sources');
        },
      ),
      throwsA(isA<StyleReaderException>()),
    );

    expect(opened, hasLength(kBundledTileNames.length));
    for (final provider in opened!) {
      // Both tiles below are proven served earlier in this file (the deep
      // pack's own town at z14, the country pack at Tamanrasset z12): a
      // provider nobody closed keeps answering them for the whole session.
      final held = provider.maximumZoom == 14
          ? _tileKeyAt(14, 36.2537, 2.2328)
          : _tileKeyAt(12, 22.8, 5.5);
      expect(
        await provider.load(held),
        isA<TileResponseCancelled>(),
        reason: 'the pack this provider holds open was never closed',
      );
    }
  });
}
