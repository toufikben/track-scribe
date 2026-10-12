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
