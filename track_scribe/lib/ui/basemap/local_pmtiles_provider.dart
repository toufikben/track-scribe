import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:latlong2/latlong.dart';
import 'package:pmtiles/pmtiles.dart';

/// A pack's bounding box, decoded from its own PMTiles header: the
/// int32×1e7 positions arrive as lat/lon values already corrected by the
/// pmtiles package (`minPosition` = south-west, `maxPosition` = north-east).
typedef TileBounds = ({double west, double south, double east, double north});

TileBounds tileBoundsOf(PmTilesArchive archive) => (
  west: archive.header.minPosition.longitude,
  south: archive.header.minPosition.latitude,
  east: archive.header.maxPosition.longitude,
  north: archive.header.maxPosition.latitude,
);

/// Serves ONE bundled PMTiles archive to flutter_map_vector_tiles.
///
/// ر107: exactly one archive per provider, so `minimumZoom`/`maximumZoom` are
/// that pack's own header ceilings. The merged provider this replaces clamped
/// every display zoom to the MAX over all packs (14) and then refused the
/// shallow country pack — which is what left the recording band an empty
/// rectangle outside the deep pack's box. Overzoom is free: the fmvt pipeline
/// clamps to [maximumZoom] and shifts to the parent tile itself (verified in
/// core/tile_zoom.dart:17-32), so a z12 pack serves any display zoom ≥ 12.
///
/// [cacheBytesToDisk] is false: the bytes already live on disk; mirroring
/// them into the renderer's disk cache would double storage and drop a
/// zero-byte sentinel per absent tile.
///
/// A stacked deep pack [shadowedBy] makes this provider refuse what the
/// deeper layer paints: a tile fully inside a deeper pack's bbox is never
/// decoded here, so stacking costs no coarse duplicate tile under the deep
/// layer (and a partly-covered tile still serves its uncovered margin).
class LocalPmTilesProvider implements VectorTileProvider {
  LocalPmTilesProvider({
    required PmTilesArchive archive,
    required this.cacheKey,
    List<TileBounds> shadowedBy = const [],
  }) : _archive = archive,
       _bounds = tileBoundsOf(archive),
       _shadowedBy = List.of(shadowedBy);

  final PmTilesArchive _archive;
  final TileBounds _bounds;
  final List<TileBounds> _shadowedBy;

  @override
  final String cacheKey;

  bool _disposed = false;

  @override
  int get minimumZoom => _archive.minZoom;

  @override
  int get maximumZoom => _archive.maxZoom;

  /// The header bbox this provider routes on.
  TileBounds get bounds => _bounds;

  @override
  bool get cacheBytesToDisk => false;

  /// The point form of the routing: true only inside this pack's own bbox
  /// and outside every deeper stacked pack's box.
  bool covers(LatLng point) =>
      _within(_bounds, point) &&
      !_shadowedBy.any((b) => _within(b, point));

  static bool _within(TileBounds b, LatLng p) =>
      p.longitude >= b.west &&
      p.longitude <= b.east &&
      p.latitude >= b.south &&
      p.latitude <= b.north;

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
    // Rectangle ∩ pack bbox, not a corner test: a z14 tile spans ~2 km, so
    // probing one corner would leave the pack's last column and row unpainted.
    final rect = _tileRect(tile);
    if (!_intersects(_bounds, rect)) return const TileResponseNotFound();
    if (_shadowedBy.any((b) => _contains(b, rect))) {
      return const TileResponseNotFound();
    }
    final id = ZXY(tile.z, tile.x, tile.y).toTileId();
    try {
      // inside the try: tile() awaits lookup + readAt and can itself throw.
      final t = await _archive.tile(id);
      final bytes = t.bytes();
      // the renderer's invariant: never produce empty TileResponseData —
      // a zero-length directory entry is treated as absent.
      if (bytes.isEmpty) return const TileResponseNotFound();
      return TileResponseData(Uint8List.fromList(bytes));
    } on TileNotFoundException {
      return const TileResponseNotFound();
    } catch (error) {
      // e.g. a read pool closed under a live provider, or a corrupt pack:
      // surface it to dart:developer (the app's logger-free channel, as in
      // the recording controller) — never rethrow to the renderer.
      developer.log(
        'z${tile.z}/${tile.x}/${tile.y} unreadable from $cacheKey',
        name: 'track_scribe/basemap',
        error: error,
      );
      return const TileResponseNotFound();
    }
  }

  /// The tile's lon/lat rectangle. Web-Mercator rows are nonlinear, so the
  /// north/south edges come from the inverse-mercator of each row boundary.
  static TileBounds _tileRect(TileKey tile) {
    final n = math.pow(2, tile.z).toDouble();
    return (
      west: tile.x / n * 360 - 180,
      east: (tile.x + 1) / n * 360 - 180,
      north: _latAt(tile.y / n),
      south: _latAt((tile.y + 1) / n),
    );
  }

  /// Web-Mercator row → latitude (standard inverse mercator). dart:math has
  /// no `sinh`, so it is composed from `exp`.
  static double _latAt(double ty) {
    final x = math.pi * (1 - 2 * ty);
    final sinh = (math.exp(x) - math.exp(-x)) / 2;
    return 180 / math.pi * math.atan(sinh);
  }

  static bool _intersects(TileBounds a, TileBounds b) =>
      !(b.east < a.west ||
        b.west > a.east ||
        b.north < a.south ||
        b.south > a.north);

  static bool _contains(TileBounds outer, TileBounds inner) =>
      outer.west <= inner.west &&
      outer.east >= inner.east &&
      outer.south <= inner.south &&
      outer.north >= inner.north;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _archive.close();
  }
}
