import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
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
      listEquals((served as TileResponseData).bytes, deeper.bytes()),
      isTrue,
      reason: 'the z14-header pack must win for a tile both packs hold',
    );

    // The negative half: the shallow pack also holds this tile, and its bytes
    // are NOT what was served. Without this the positive assertion could pass
    // under any ordering the day both packs are rebuilt from one source.
    final shallower = await country.tile(ZXY(12, key.x, key.y).toTileId());
    expect(
      listEquals(served.bytes, shallower.bytes()),
      isFalse,
      reason: 'the z12 pack must not be what wins for a contested tile',
    );

    provider.dispose();
  });

  // The everyday path of the real map: the wilaya header claims z0-14 but its
  // bounds cover only Alger province, so most z<=12 queries over Algeria are
  // honest absences in the deep pack that must fall through to the country one.
  test('falls through to the country pack when the deep pack lacks the tile', () async {
    final wdata = await rootBundle.load('assets/tiles/dz-wilaya-alger-z14.pmtiles');
    final wilaya = await PmTilesArchive.fromBytes(
      wdata.buffer.asUint8List(wdata.offsetInBytes, wdata.lengthInBytes),
    );
    final cdata = await rootBundle.load('assets/tiles/dz-country-z12.pmtiles');
    final country = await PmTilesArchive.fromBytes(
      cdata.buffer.asUint8List(cdata.offsetInBytes, cdata.lengthInBytes),
    );
    // WRONG caller order on purpose: the headers decide (R103), so the wilaya
    // pack is queried first for this tile — and does not hold it.
    final provider = LocalPmTilesProvider(
      archives: [country, wilaya],
      cacheKey: 'test-fall-through',
    );

    final key = _tileKeyAt(12, 22.8, 5.5); // Tamanrasset: in country, outside wilaya
    final served = await provider.load(key);
    expect(served, isA<TileResponseData>());

    final direct = await country.tile(ZXY(12, key.x, key.y).toTileId());
    expect(
      listEquals((served as TileResponseData).bytes, direct.bytes()),
      isTrue,
      reason: 'the country pack must answer a tile the deeper pack does not hold',
    );

    provider.dispose();
  });

  // tile() awaits lookup + readAt, which can throw — e.g. its FileAt read pool
  // closed while the provider stays live. Such an error must never escape to
  // the renderer, and must not hide the healthy shallow pack either.
  test('a closed read pool in the deep pack neither escapes nor hides the shallow pack', () async {
    // File-backed exactly like the first-launch runtime (pack copied to docs).
    final wilaya = await PmTilesArchive.fromFile(
      File('assets/tiles/dz-wilaya-alger-z14.pmtiles'),
    );
    final cdata = await rootBundle.load('assets/tiles/dz-country-z12.pmtiles');
    final country = await PmTilesArchive.fromBytes(
      cdata.buffer.asUint8List(cdata.offsetInBytes, cdata.lengthInBytes),
    );
    final provider = LocalPmTilesProvider(
      archives: [country, wilaya],
      cacheKey: 'test-closed-pool',
    );
    await wilaya.close();

    // A z12 tile over Algiers the deep pack holds: reading it now fails inside
    // the await itself, so only a guarded fall-through reaches the country pack.
    final key = _tileKeyAt(12, 36.7525, 3.0420);
    final served = await provider.load(key);
    expect(served, isA<TileResponseData>());

    final direct = await country.tile(ZXY(12, key.x, key.y).toTileId());
    expect(
      listEquals((served as TileResponseData).bytes, direct.bytes()),
      isTrue,
      reason: 'one unreadable pack must not hide the good shallow pack',
    );

    provider.dispose();
  });
}
