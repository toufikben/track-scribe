import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/data/tile_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // rootBundle

  late AppDatabase db;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory()); // the in-memory pattern from test/data/resume_test.dart
    tmp = await Directory.systemTemp.createTemp('tile-store');
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('first run copies both packs at exact sizes and sets the flag', () async {
    expect(TileStore.flagKey, 'tiles-v2'); // renamed packs require a re-copy
    final store = TileStore(ActivityRepository(db), baseDir: () async => tmp);
    final dir = await store.ensureBundledTiles();
    expect(
      File(p.join(dir, 'dz-khemis-miliana-z14.pmtiles')).lengthSync(),
      1792009,
    );
    expect(File(p.join(dir, 'dz-country-z12.pmtiles')).lengthSync(), 53718750);
    expect(await ActivityRepository(db).flag(TileStore.flagKey), isTrue);
  });

  test('a missing pack is re-copied even when the flag is set', () async {
    final store = TileStore(ActivityRepository(db), baseDir: () async => tmp);
    final dir = await store.ensureBundledTiles();
    File(p.join(dir, 'dz-country-z12.pmtiles')).deleteSync();
    await store.ensureBundledTiles();
    expect(File(p.join(dir, 'dz-country-z12.pmtiles')).lengthSync(), 53718750);
  });

  // ر107 upgrade path: a pack that left the bundle must not stay forever on
  // an installed phone — the copy pass prunes unregistered *.pmtiles.
  test('a stale unregistered pack is pruned even when the flag is set', () async {
    final store = TileStore(ActivityRepository(db), baseDir: () async => tmp);
    final dir = await store.ensureBundledTiles();
    final orphan = File(p.join(dir, 'dz-wilaya-alger-z14.pmtiles'))
      ..createSync()
      ..writeAsStringSync('stale');
    await store.ensureBundledTiles();
    expect(orphan.existsSync(), isFalse);
    // and the registered packs survive the prune
    expect(
      File(p.join(dir, 'dz-khemis-miliana-z14.pmtiles')).lengthSync(),
      1792009,
    );
  });
}
