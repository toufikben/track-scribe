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

  /// R104 M-4: the stub used to dispose nothing, so "the single disposal path
  /// reaches every provider" was true for production and unproven for the stub
  /// every widget test actually renders with. Counting makes it assertible.
  int disposeCalls = 0;

  @override
  Future<TileResponse> load(
    TileKey tile, {
    CancellationToken? cancellation,
  }) async => const TileResponseNotFound();
  @override
  void dispose() => disposeCalls++;
}

/// The bundled dark style as the production shape — the same asset pipeline
/// (`asset://assets/styles/dark.json`, zero network), two stub layers exactly
/// as many as the registered packs stack in ر107, minus the tile decode. An
/// unmocked platform channel pends forever under `testWidgets`' fake-async,
/// so tests that render the vector band must override `mapStyleProvider`
/// with this instead of relying on a fallback.
Future<BundledStyle> loadStubVectorStyle() async =>
    (await loadStubVectorStyleWithProviders()).style;

/// The same construction with the two providers handed back, so a test can
/// count their disposals (R104 M-4). `loadStubVectorStyle` is the only other
/// builder, so no test can drift from what production renders.
Future<({BundledStyle style, List<StubTileProvider> providers})>
  loadStubVectorStyleWithProviders() async {
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
    final bundled = BundledStyle(
      theme: style.theme,
      sprites: style.sprites,
      layers: [
        TileProviders({kBundledStyleSourceId: shallow}),
        TileProviders({kBundledStyleSourceId: deep}),
      ],
    );
    return (style: bundled, providers: [shallow, deep]);
  }
