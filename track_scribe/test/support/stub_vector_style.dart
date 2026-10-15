import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:track_scribe/ui/basemap/map_style_provider.dart';

/// Never decodes a real tile: keeps widget tests deterministic and free
/// of isolate/pending-timer coupling. The [BundledStyle] it backs owns and
/// disposes these providers, so callers only dispose the BundledStyle.
class StubTileProvider implements VectorTileProvider {
  StubTileProvider({this.cacheKey = 'stub'});

  @override
  final String cacheKey;
  @override
  int get minimumZoom => 0;
  @override
  int get maximumZoom => 14;
  @override
  bool get cacheBytesToDisk => false;
  @override
  Future<TileResponse> load(
    TileKey tile, {
    CancellationToken? cancellation,
  }) async => const TileResponseNotFound();
  @override
  void dispose() {}
}

/// The bundled dark style as the production shape — the same asset pipeline
/// (`asset://assets/styles/dark.json`, zero network), two stub layers exactly
/// as many as the registered packs stack in ر107, minus the tile decode. An
/// unmocked platform channel pends forever under `testWidgets`' fake-async,
/// so tests that render the vector band must override `mapStyleProvider`
/// with this instead of relying on a fallback.
Future<BundledStyle> loadStubVectorStyle() async {
  // The Style must resolve its source: StyleReader throws for a style whose
  // every source was dropped, so the deep stub is bound like production.
  final deep = StubTileProvider(cacheKey: 'stub-deep');
  final style = await StyleReader(
    uri: 'asset://assets/styles/dark.json',
    cache: false,
    resolveProvider: (id) async =>
        id == kBundledStyleSourceId ? deep : null,
  ).read();
  final shallow = StubTileProvider(cacheKey: 'stub-shallow');
  return BundledStyle(
    theme: style.theme,
    sprites: style.sprites,
    layers: [
      TileProviders({kBundledStyleSourceId: shallow}),
      TileProviders({kBundledStyleSourceId: deep}),
    ],
  );
}
