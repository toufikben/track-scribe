import 'dart:convert';
import 'dart:io' show Directory;

import 'package:drift/native.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:http/http.dart' as http;
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/data/tile_store.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/basemap/map_style_provider.dart';

import '../support/stub_vector_style.dart';

/// Any network attempt fails the test: the bundled style must load fully
/// offline (spec §12.1 «لا شيء يُجلب من الشبكة»).
class _NoNetworkClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw StateError('network used for ${request.url}');
  }
}

/// The brand water colour, asserted against the parsed style so any
/// representation of it in the JSON (hex, rgb(), hsl()) is pinned.
const _water = Color(0xFF182128);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled dark style loads with zero network and locks its contract',
      () async {
    final style = await StyleReader(
      uri: 'asset://assets/styles/dark.json',
      cache: false,
      httpClient: _NoNetworkClient(),
      resolveProvider: (id) async =>
          id == 'openmaptiles' ? StubTileProvider() : null,
    ).read();

    expect(style.theme.backgroundColor(0), Palette.bg);
    final water = style.theme.layers
        .whereType<FillThemeLayer>()
        .singleWhere((l) => l.id == 'water');
    expect(water.color.eval(const EvalContext(zoom: 12)), _water);
    final waterway = style.theme.layers
        .whereType<LineThemeLayer>()
        .singleWhere((l) => l.id == 'waterway');
    expect(waterway.color.eval(const EvalContext(zoom: 12)), _water);

    expect(style.providers.providers, isNotEmpty);
    expect(style.providers.providers.keys, ['openmaptiles']);
    expect(style.rasterSources, isEmpty);
    expect(style.sprites, isNotNull); // asset sprite sheet resolved
    style.dispose();
  });

  // `glyphs`, source ids and the sprite key are dropped by StyleReader when
  // it compiles the theme, so these locks read the shipped document itself.
  test('bundled style document: no glyphs, no raster source, asset sprite',
      () async {
    final doc =
        jsonDecode(await rootBundle.loadString('assets/styles/dark.json'))
            as Map<String, dynamic>;

    expect(doc.containsKey('glyphs'), isFalse);
    final sources = (doc['sources']! as Map).cast<String, Object?>();
    expect(sources.keys, ['openmaptiles']);
    expect(sources.containsKey('ne2_shaded'), isFalse);
    expect(sources.values
        .whereType<Map>()
        .where((s) => s['type'] == 'raster'), isEmpty);
    expect(doc['sprite'], 'sprites/ofm');
  });

  // ر107: the provider yields one TileProviders entry per registered pack —
  // shallowest first, each binding the source id the style declares — so the
  // bands can stack one VectorTileLayer per pack instead of one merged ceiling.
  test('mapStyleProvider stacks two layers, shallow→deep, each on the style source id',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final tmp = await Directory.systemTemp.createTemp('map-style-r107');
    addTearDown(() => tmp.delete(recursive: true));
    final container = ProviderContainer(
      overrides: [
        tileStoreProvider.overrideWithValue(
          TileStore(ActivityRepository(db), baseDir: () async => tmp),
        ),
      ],
    );
    // container.dispose runs ref.onDispose → BundledStyle.dispose → the one
    // owner of every archive closes each exactly once. Do not dispose twice.
    addTearDown(container.dispose);

    final bundled = await container.read(mapStyleProvider.future);

    expect(bundled.layers.length, 2);
    expect(
      bundled.layers.map((l) => l.providers.values.single.maximumZoom),
      [12, 14],
      reason: 'ordered shallow→deep from the headers (R103)',
    );
    for (final layer in bundled.layers) {
      expect(
        layer.providers.keys,
        [kBundledStyleSourceId],
        reason: 'the only key is the source id the bundled style declares',
      );
    }
    expect(
      bundled.layers.map((l) => l.providers.values.single.cacheKey).toSet().length,
      2,
      reason: 'distinct cacheKey per archive, or the renderer caches across packs',
    );
    expect(bundled.maximumZoom, 14);
    expect(bundled.theme.layers, isNotEmpty);
    expect(bundled.sprites, isNotNull);
  });

  // R114: the theme the bands render with must paint NOTHING for a tile its
  // pack refused, or the stacked deep layer hides the shallow one outside its
  // box. `Theme.backgroundColor` is the public seam: it reports the first
  // background layer, or null when the theme has none.
  test('the stacked theme carries no background layer — the bands supply it',
      () async {
    final raw = await StyleReader(
      uri: 'asset://assets/styles/dark.json',
      cache: false,
      httpClient: _NoNetworkClient(),
      resolveProvider: (id) async =>
          id == 'openmaptiles' ? StubTileProvider() : null,
    ).read();
    addTearDown(raw.dispose);

    expect(raw.theme.backgroundColor(0), Palette.bg,
        reason: 'the shipped style still paints its own background');

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final tmp = await Directory.systemTemp.createTemp('map-style-r114');
    addTearDown(() => tmp.delete(recursive: true));
    final container = ProviderContainer(
      overrides: [
        tileStoreProvider.overrideWithValue(
          TileStore(ActivityRepository(db), baseDir: () async => tmp),
        ),
      ],
    );
    // The one disposal path: container.dispose → ref.onDispose → BundledStyle
    // .dispose → every archive closes exactly once.
    addTearDown(container.dispose);

    final bundled = await container.read(mapStyleProvider.future);

    expect(bundled.theme.backgroundColor(0), isNull,
        reason: 'a stacked layer that fills its tiles hides the layer below');
    expect(bundled.theme.layers.length, raw.theme.layers.length - 1,
        reason: 'exactly the background layer is dropped — nothing else');
  });

  // R104 M-4: the disposal law above was proven for production only. The stub
  // that every widget test renders with disposed nothing at all — an empty
  // `dispose()` — so a `BundledStyle` that forgot one of its two stacked layers
  // would have leaked past every test in the suite. Counting makes the fake
  // assertible: both providers, reached through the one path, exactly once each.
  test('the stub style disposes every provider it stacked, exactly once',
      () async {
    final (:style, :providers) = await loadStubVectorStyleWithProviders();
    expect(providers, hasLength(2));
    expect(providers.map((p) => p.disposeCalls), [0, 0],
        reason: 'nothing is disposed before the caller asks');

    style.dispose();

    expect(providers.map((p) => p.disposeCalls), [1, 1],
        reason: 'BundledStyle.dispose is the single owner of both layers');
  });
}
