import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:path/path.dart' as p;
import 'package:pmtiles/pmtiles.dart';
import 'package:track_scribe/data/tile_store.dart';
import 'package:track_scribe/ui/basemap/local_pmtiles_provider.dart';

/// The single source id the bundled style declares (`dark.json` has exactly
/// one vector source). One place, never a duplicated literal.
const kBundledStyleSourceId = 'openmaptiles';

/// The render input of the map bands: one style theme + sprites, and ONE
/// [TileProviders] entry per bundled pack, shallowest first (ر107). Each
/// entry binds the style's source id to its own archive's provider, so every
/// stacked `VectorTileLayer` paints the whole style from one pack while the
/// pack-bbox rules in [LocalPmTilesProvider] make exactly one of them answer
/// any given tile.
class BundledStyle {
  const BundledStyle({
    required this.theme,
    required this.sprites,
    required this.layers,
  });

  final Theme theme;
  final SpriteAtlas? sprites;
  final List<TileProviders> layers;

  /// Deepest header zoom across the stacked packs — the map's honest ceiling.
  int get maximumZoom => layers
      .expand((l) => l.providers.values)
      .map((provider) => provider.maximumZoom)
      .reduce(math.max);

  /// The one disposal path. The [StyleReader]-produced `Style` owns the
  /// provider that `resolveProvider` bound (style_reader.dart:138-140), so
  /// production disposes through here INSTEAD of `Style.dispose()` — each
  /// provider, and the sprite atlas's `ui.Image`, is released exactly once.
  void dispose() {
    for (final layer in layers) {
      layer.dispose();
    }
    sprites?.dispose();
  }
}

/// R103's law in its new home: layer priority comes from each archive's own
/// header `maxZoom`, never from caller order — shallowest first, so the deep
/// pack paints on top. Each entry is shadowed by the FULL bbox of every
/// deeper pack, which is what stops the coarse layer decoding a duplicate
/// tile underneath the deep one.
List<LocalPmTilesProvider> stackProviders(
  Iterable<({PmTilesArchive archive, String cacheKey})> packs,
) {
  final sorted = packs.toList()
    ..sort((a, b) => a.archive.maxZoom.compareTo(b.archive.maxZoom));
  return [
    for (var i = 0; i < sorted.length; i++)
      LocalPmTilesProvider(
        archive: sorted[i].archive,
        cacheKey: sorted[i].cacheKey,
        shadowedBy: [
          for (var j = i + 1; j < sorted.length; j++) tileBoundsOf(sorted[j].archive),
        ],
      ),
  ];
}

/// One app-wide compiled style: bundled packs + bundled localized style,
/// zero network (cache: false, resolveProvider, no http anywhere).
///
/// Packs come from [kBundledTileNames] (R103): this code opens *every* name in
/// the registry and never hardcodes a pack list, so adding a country or world
/// pack is one name in `tile_store.dart` + one asset file. [stackProviders]
/// orders the layers from the headers.
///
/// `resolveProvider` MUST answer the style's source id: [StyleReader] falls
/// through to the document's hosted TileJSON URL when it returns null — a
/// network attempt offline, and its failure drops the source entirely
/// (style_reader.dart:221-223 throws `style contains no usable sources` for a
/// style whose every source was dropped). It receives null back for any other
/// id. Ownership: the returned provider is owned by the `Style`, but
/// [BundledStyle.dispose] is the single disposal path wired to `onDispose`.
final mapStyleProvider = FutureProvider<BundledStyle>(
  (ref) async {
    if (kBundledTileNames.isEmpty) throw StateError('no tile packs registered');
    final tilesDir = await ref.watch(tileStoreProvider).ensureBundledTiles();
    final providers = stackProviders([
      for (final name in kBundledTileNames)
        (
          archive: await PmTilesArchive.from(p.join(tilesDir, name)),
          // Distinct per pack: two providers sharing a cacheKey are assumed
          // to serve identical bytes, including across layers.
          cacheKey: 'pmtiles:$name',
        ),
    ]);
    final style = await StyleReader(
      uri: 'asset://assets/styles/dark.json',
      cache: false,
      resolveProvider: (id) async =>
          id == kBundledStyleSourceId ? providers.last : null,
    ).read();
    final bundled = BundledStyle(
      theme: style.theme,
      sprites: style.sprites,
      layers: [
        for (final provider in providers)
          TileProviders({kBundledStyleSourceId: provider}),
      ],
    );
    // NOT `style.dispose`: it would dispose the bound provider and the
    // sprites a second time past BundledStyle's single ownership.
    ref.onDispose(bundled.dispose);
    return bundled;
  },
  // Zero network ⇒ no transient failure to retry. Riverpod 3's defaultRetry
  // would retry an Exception (a failed read is one) for ~38s while the state
  // stays AsyncLoading — the GridBasemap fallback law needs a fast error.
  retry: (retryCount, error) => null,
);
