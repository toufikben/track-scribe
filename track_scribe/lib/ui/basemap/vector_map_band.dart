import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/basemap/follow_policy.dart';
import 'package:track_scribe/ui/basemap/grid_basemap.dart';
import 'package:track_scribe/ui/basemap/map_style_provider.dart';
import 'package:track_scribe/ui/basemap/scale_bar.dart';

/// Degrees of heading change that justify a map redraw. GPS bearing jitters by
/// a degree or two at rest, and a redraw is as expensive as a camera move.
const double _headingEpsilonDeg = 3;

/// The recording map band (spec §12.1): real offline vector map + live route
/// + position marker with 1σ accuracy halo + follow/recenter + north/heading
/// toggle + the mandatory attribution row. Recording never depends on it:
/// while the style loads the band is a flat `bg`, and on style failure it
/// falls back to [GridBasemap] (route still drawn).
class VectorMapBand extends ConsumerStatefulWidget {
  const VectorMapBand({super.key, required this.points, required this.current});

  final List<StoredPoint> points;
  final StoredPoint? current;

  @override
  ConsumerState<VectorMapBand> createState() => _VectorMapBandState();
}

class _VectorMapBandState extends ConsumerState<VectorMapBand> {
  final MapController _map = MapController();
  bool _follow = true;
  bool _heading = false;

  /// `MapController.camera` throws until `FlutterMap` has mounted, and the
  /// band builds its overlays eagerly in the same pass — so both the scale
  /// bar and the follow move read the camera through this gate, and
  /// [MapOptions.onMapReady] is what opens it.
  bool _mapReady = false;

  /// The route draws exactly what [displayablePoints] keeps (ر115) — the one
  /// display filter every surface shares — projected to `LatLng`.
  List<LatLng> get _route =>
      displayablePoints(widget.points).map((p) => LatLng(p.lat, p.lon)).toList();

  /// Follow the fix, but only as far as the band's own tolerance allows
  /// ([shouldRecenter]) — and only turn for a heading change worth a redraw.
  /// Every move and every rotation restarts the vector tile fetch, so chasing
  /// each fix blanked the map on the realme for the whole session.
  void _moveTo(StoredPoint p) {
    if (!_mapReady) return;
    final cam = _map.camera;
    final target = LatLng(p.lat, p.lon);
    if (shouldRecenter(
      center: cam.center,
      target: target,
      metresPerPixel: _metresPerPixel(),
      bandShortSidePx: math.min(cam.size.width, cam.size.height),
    )) {
      _map.move(target, cam.zoom);
    }
    if (_heading && p.bearingDeg != null) {
      final wanted = -p.bearingDeg!;
      if (_signedDeg(wanted - cam.rotation).abs() > _headingEpsilonDeg) {
        _map.rotate(wanted);
      }
    }
  }

  /// Fold a degree delta into (-180, 180] so a heading across the wrap is not
  /// read as a full turn.
  static double _signedDeg(double deg) => (deg + 180) % 360 - 180;

  /// Metres per screen pixel of Web Mercator at [lat]/[zoom] (256 px tiles,
  /// logical pixels) — the scale bar's one honest input on a real map.
  /// 0 means "no camera yet", which is exactly what hides the bar.
  double _metresPerPixel() {
    if (!_mapReady) return 0;
    final cam = _map.camera;
    final latRad = cam.center.latitude * math.pi / 180;
    return 156543.03392 * math.cos(latRad) / math.pow(2, cam.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final style = ref.watch(mapStyleProvider);
    final current = widget.current;
    if (current != null && _follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _follow) _moveTo(current);
      });
    }
    return Column(
      children: [
        Expanded(
          child: style.when(
            loading: () => const ColoredBox(color: Palette.bg),
            error: (_, _) => GridBasemap(points: widget.points),
            data: (s) => Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: current == null
                          ? const LatLng(36.7525, 3.0420) // Algiers
                          : LatLng(current.lat, current.lon),
                      initialZoom: 16,
                      minZoom: 2,
                      maxZoom: kMapDisplayMaxZoom,
                      backgroundColor: Palette.bg,
                      onPositionChanged: (camera, hasGesture) {
                        if (hasGesture) setState(() => _follow = false);
                      },
                      onMapReady: () {
                        if (mounted) setState(() => _mapReady = true);
                      },
                    ),
                    children: [
                      // One layer per pack, shallowest first (ر107): the deep
                      // pack paints its box, the country pack paints beneath
                      // and around it — never a second decode of the same tile.
                      for (final providers in s.layers)
                        VectorTileLayer(
                          theme: s.theme,
                          tileProviders: providers,
                          sprites: s.sprites,
                          diskCacheMaximumSizeInBytes: 0,
                        ),
                      if (_route.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _route,
                              color: Palette.accent,
                              strokeWidth: 5,
                            ),
                          ],
                        ),
                      if (current != null) ...[
                        if (current.type != WaypointType.idle)
                          CircleLayer(
                            circles: [
                              CircleMarker(
                                point: LatLng(current.lat, current.lon),
                                radius: current.accuracyM,
                                useRadiusInMeter: true,
                                color: Palette.accent.withValues(alpha: 0.12),
                                borderColor: Palette.accent.withValues(
                                  alpha: 0.6,
                                ),
                                borderStrokeWidth: 1,
                              ),
                            ],
                          ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(current.lat, current.lon),
                              width: 22,
                              height: 22,
                              child: current.type == WaypointType.idle
                                  ? const _IdleBadge()
                                  : const _PositionDot(),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const Positioned(
                  top: 8,
                  left: 8,
                  child: Icon(
                    Icons.north,
                    key: Key('basemap-north'),
                    size: 16,
                    color: Palette.textSecondary,
                  ),
                ),
                Positioned(
                  top: 28,
                  left: 8,
                  child: _MapControls(
                    onRecenter: () {
                      setState(() {
                        _follow = true;
                        _heading = false;
                      });
                      if (!_mapReady) return;
                      final c = current ?? widget.points.lastOrNull;
                      if (c != null) _map.move(LatLng(c.lat, c.lon), 16);
                      _map.rotate(0);
                    },
                    onHeading: current?.bearingDeg == null
                        ? null
                        : () {
                            setState(() => _heading = !_heading);
                            if (!_mapReady) return;
                            if (_heading) {
                              _map.rotate(-current!.bearingDeg!);
                            } else {
                              _map.rotate(0);
                            }
                          },
                    headingActive: _heading,
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: ScaleBar(
                    key: const Key('basemap-scale'),
                    metresPerPixel: _metresPerPixel(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const AttributionStrip(),
      ],
    );
  }
}

class _PositionDot extends StatelessWidget {
  const _PositionDot();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Palette.accent,
      border: Border.all(color: Palette.onAccent, width: 3),
    ),
  );
}

/// ر6: standing still draws an IDLE badge, no position dot and no halo —
/// nothing here implies motion.
class _IdleBadge extends StatelessWidget {
  const _IdleBadge();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Palette.surface,
      border: Border.all(color: Palette.textSecondary, width: 2),
    ),
    child: const Center(
      child: Icon(Icons.pause, size: 12, color: Palette.textSecondary),
    ),
  );
}

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.onRecenter,
    required this.onHeading,
    required this.headingActive,
  });

  final VoidCallback onRecenter;
  final VoidCallback? onHeading;
  final bool headingActive;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _ControlButton(
        key: const Key('map-recenter'),
        icon: Icons.my_location,
        onTap: onRecenter,
        active: false,
      ),
      const SizedBox(height: 6),
      _ControlButton(
        key: const Key('map-heading'),
        icon: Icons.explore_outlined,
        onTap: onHeading,
        active: headingActive,
      ),
    ],
  );
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.active,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Material(
    color: active ? Palette.accent : Palette.surface,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 18,
          color: active ? Palette.onAccent : Palette.textSecondary,
        ),
      ),
    ),
  );
}

/// ODbL/CC-BY attribution — legally required and never dismissable.
/// Public because the plan's global constraint puts it on every view that
/// shows the bundled map, the finished-activity detail screen included.
class AttributionStrip extends StatelessWidget {
  const AttributionStrip({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Palette.bg,
    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
    child: const Text(
      '© OpenStreetMap contributors · © OpenMapTiles · Style: OpenFreeMap (MIT)',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 9, color: Palette.textSecondary),
    ),
  );
}
