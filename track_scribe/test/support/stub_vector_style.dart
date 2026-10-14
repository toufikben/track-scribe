import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';

/// Never decodes a real tile: keeps widget tests deterministic and free
/// of isolate/pending-timer coupling. `Style.dispose()` disposes the
/// providers it owns (verified in style_reader.dart), so callers only
/// dispose the Style.
class StubTileProvider implements VectorTileProvider {
  @override
  String get cacheKey => 'stub';
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

/// The bundled dark style with the stub provider — the same asset pipeline
/// as production (`asset://assets/styles/dark.json`, zero network), minus
/// the tile decode. An unmocked platform channel pends forever under
/// `testWidgets`' fake-async, so tests that render the vector band must
/// override `mapStyleProvider` with this instead of relying on a fallback.
Future<Style> loadStubVectorStyle() => StyleReader(
  uri: 'asset://assets/styles/dark.json',
  cache: false,
  resolveProvider: (id) async => StubTileProvider(),
).read();
