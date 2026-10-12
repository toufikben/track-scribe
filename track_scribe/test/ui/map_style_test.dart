import 'dart:convert';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:http/http.dart' as http;
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/basemap/local_pmtiles_provider.dart';

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
      resolveProvider: (id) async => id == 'openmaptiles'
          ? LocalPmTilesProvider(archives: const [], cacheKey: 'style-test')
          : null,
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
}
