import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/app_database_provider.dart';

/// Bundled tile packs: `assets/tiles/<name>` → `<documents>/tiles/<name>`.
/// Exact artifact sizes from CI runs 38201305204 / 38201311231 (spec §12.1).
const kBundledTileNames = [
  'dz-wilaya-alger-z14.pmtiles', // 20_548_695 B — Alger wilaya z0-14
  'dz-country-z12.pmtiles', // 53_718_750 B — Algeria z0-12
];

/// Versioned first-launch copy of the bundled packs into app documents —
/// pmtiles opens archives from real file paths (lazy range reads), so the
/// packs cannot be read from inside the APK.
class TileStore {
  TileStore(this._repo, {Future<Directory> Function()? baseDir})
    : _baseDir = baseDir ?? getApplicationDocumentsDirectory;

  final ActivityRepository _repo;
  final Future<Directory> Function() _baseDir;

  static const flagKey = 'tiles-v1';

  /// Copies the packs if the flag is unset OR any pack is missing (a copy
  /// killed mid-write must not leave a permanently broken install). Returns
  /// the tiles directory path.
  Future<String> ensureBundledTiles() async {
    final docs = await _baseDir();
    final dir = Directory(p.join(docs.path, 'tiles'));
    await dir.create(recursive: true);
    var needCopy = !await _repo.flag(flagKey);
    if (!needCopy) {
      for (final name in kBundledTileNames) {
        if (!await File(p.join(dir.path, name)).exists()) {
          needCopy = true;
          break;
        }
      }
    }
    if (needCopy) {
      for (final name in kBundledTileNames) {
        final data = await rootBundle.load('assets/tiles/$name');
        await File(p.join(dir.path, name)).writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      await _repo.setFlag(flagKey, true);
    }
    return dir.path;
  }
}

final tileStoreProvider = Provider<TileStore>(
  (ref) => TileStore(ref.watch(activityRepositoryProvider)),
);
