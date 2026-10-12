import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:pmtiles/pmtiles.dart';

/// Serves bundled PMTiles archives to flutter_map_vector_tiles.
///
/// Overzoom is NOT this class's job: the fmvt pipeline clamps display zooms
/// to [maximumZoom] and renders the overzoomed sub-region itself (verified in
/// tile_store.dart), so a request outside [minimumZoom, maximumZoom] is
/// honestly NotFound and nothing here ever upscales coordinates.
///
/// [cacheBytesToDisk] is false: the bytes already live on disk; mirroring
/// them into the renderer's disk cache would double storage and drop a
/// zero-byte sentinel per absent tile.
class LocalPmTilesProvider implements VectorTileProvider {
  LocalPmTilesProvider({required List<PmTilesArchive> archives, required this.cacheKey})
    // R103: priority is read off each archive's own header, so callers may
    // pass packs in any order (and adding a pack is data, not code).
    : _archives = List.of(archives)
        ..sort((a, b) => b.maxZoom.compareTo(a.maxZoom));

  /// Deepest zoom first: the wilaya pack (z0-14) before the country pack
  /// (z0-12), so a request both can answer gets the more detailed bytes.
  final List<PmTilesArchive> _archives;

  @override
  final String cacheKey;

  bool _disposed = false;

  @override
  int get minimumZoom =>
      _archives.map((a) => a.minZoom).reduce(math.min);

  @override
  int get maximumZoom =>
      _archives.map((a) => a.maxZoom).reduce(math.max);

  @override
  bool get cacheBytesToDisk => false;

  @override
  Future<TileResponse> load(
    TileKey tile, {
    CancellationToken? cancellation,
  }) async {
    if (_disposed || (cancellation?.isCancelled ?? false)) {
      return const TileResponseCancelled();
    }
    if (!tile.isValid || tile.z < minimumZoom || tile.z > maximumZoom) {
      return const TileResponseNotFound();
    }
    for (final archive in _archives) {
      if (tile.z < archive.minZoom || tile.z > archive.maxZoom) continue;
      final id = ZXY(tile.z, tile.x, tile.y).toTileId();
      try {
        // inside the try: tile() awaits lookup + readAt and can itself throw.
        final t = await archive.tile(id);
        final bytes = t.bytes();
        // the renderer's invariant: never produce empty TileResponseData —
        // a zero-length directory entry is treated as absent.
        if (bytes.isEmpty) continue;
        return TileResponseData(Uint8List.fromList(bytes));
      } on TileNotFoundException {
        continue; // this pack doesn't have it — try the next
      } catch (error) {
        // e.g. a read pool closed under a live provider, or a corrupt pack:
        // surface it to dart:developer (the app's logger-free channel, as in
        // the recording controller) — never rethrow to the renderer, never
        // let one unreadable pack hide the healthy shallower one.
        developer.log(
          'z${tile.z}/${tile.x}/${tile.y} unreadable from one pack, trying the next',
          name: 'track_scribe/basemap',
          error: error,
        );
        continue;
      }
    }
    return const TileResponseNotFound();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final archive in _archives) {
      archive.close();
    }
  }
}
