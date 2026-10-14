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
final mapStyleProvider = FutureProvider<Style>(
  (ref) async {
    if (kBundledTileNames.isEmpty) throw StateError('no tile packs registered');
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
  },
  // Zero network ⇒ no transient failure to retry. Riverpod 3's defaultRetry
  // would retry an Exception (a failed read is one) for ~38s while the state
  // stays AsyncLoading — the GridBasemap fallback law needs a fast error.
  retry: (retryCount, error) => null,
);
