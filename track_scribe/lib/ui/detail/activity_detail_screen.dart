import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// `Theme` hidden: flutter_map_vector_tiles exports its own style `Theme`, which
// would shadow Material's and break `Theme.of(context)` in the app bar.
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' hide Theme;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:track_scribe/data/activity_summary.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/sport_config.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/basemap/grid_basemap.dart';
import 'package:track_scribe/ui/basemap/map_style_provider.dart';
import 'package:track_scribe/ui/basemap/vector_map_band.dart' show AttributionStrip;
import 'package:track_scribe/ui/detail/elevation_strip.dart';
import 'package:track_scribe/ui/detail/graded_route_layer.dart';
import 'package:track_scribe/ui/recording/widgets/stat_panel.dart';

/// One finished activity, read by row id — the screen's override target: a
/// family so a test can inject a synthetic [ActivitySummary] without a
/// database, while production resolves through `activityRepositoryProvider`
/// (R80). A missing row throws: the screen's error branch is the honest answer,
/// never an empty map dressed up as a track.
///
/// `retry: null` for the reason documented on `mapStyleProvider` (R104):
/// Riverpod 3's default retry would re-run a failed read for ~38 s with the
/// state stuck in AsyncLoading, so the error branch could not be reached —
/// least of all inside `testWidgets`, whose fake clock owns every timer.
final activityDetailProvider = FutureProvider.family<ActivitySummary, int>(
  (ref, id) => ref
      .watch(activityRepositoryProvider)
      .loadActivityWithPoints(
        id,
      )
      .then((s) => s ?? (throw StateError('activity $id not found'))),
  retry: (retryCount, error) => null,
);

/// The finished-activity screen (spec §12.1): the recorded totals, the route
/// graded by speed with its direction arrow and start/end markers, the line
/// thickness choice, and the elevation profile with grade shading below.
class ActivityDetailScreen extends ConsumerWidget {
  const ActivityDetailScreen({super.key, required this.activityId});

  final int activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(activityDetailProvider(activityId));
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        elevation: 0,
        title: Text('تفاصيل النشاط', style: Theme.of(context).textTheme.titleLarge),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: summary.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Palette.accent),
          ),
          error: (_, _) => const Center(
            child: Text(
              'تعذّر تحميل النشاط',
              style: TextStyle(color: Palette.textSecondary),
            ),
          ),
          data: (s) => _DetailBody(summary: s),
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.summary});

  final ActivitySummary summary;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  double _thickness = 5;

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatPanel(
            distanceM: s.distanceM,
            elapsedNanos: s.elapsedNanos,
            sport: Sport.values.byName(s.sport),
            fixCount: s.fixCount,
          ),
          const SizedBox(height: 8),
          Expanded(flex: 4, child: _DetailMap(summary: s, thickness: _thickness)),
          const SizedBox(height: 8),
          Center(
            child: SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 3, label: Text('رفيع')),
                ButtonSegment(value: 5, label: Text('متوسط')),
                ButtonSegment(value: 8, label: Text('غليظ')),
              ],
              selected: {_thickness},
              onSelectionChanged: (v) => setState(() => _thickness = v.first),
            ),
          ),
          const SizedBox(height: 8),
          ElevationStrip(points: s.points),
        ],
      ),
    );
  }
}

/// The replay map. It moves the camera exactly once — flutter_map applies
/// `initialCameraFit` on the first sized build and never again
/// (`_initialCameraFitApplied`, widget.dart:120) — and calls no
/// `MapController.move`/`rotate` at all, so R105's dead-zone rule has nothing
/// here to gate: there is no repeating source behind this camera. A finger pan
/// is a gesture, not a programmatic move.
class _DetailMap extends ConsumerWidget {
  const _DetailMap({required this.summary, required this.thickness});

  final ActivitySummary summary;
  final double thickness;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(mapStyleProvider);
    final route = [
      for (final p in summary.points)
        if (p.type != WaypointType.rejected) LatLng(p.lat, p.lon),
    ];
    final start = route.isEmpty ? null : route.first;
    final end = route.isEmpty ? null : route.last;
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: style.when(
              loading: () => const ColoredBox(color: Palette.bg),
              error: (_, _) => GridBasemap(points: summary.points),
              data: (s) => FlutterMap(
                options: MapOptions(
                  initialCameraFit: route.length >= 2
                      ? CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(route),
                          padding: const EdgeInsets.all(24),
                        )
                      // A track that spans nothing (one point, or a replay of an
                      // empty route) has no bounds to fit: flutter_map 8.3.2
                      // takes a LIST of coordinates here, capped at zoom 16.
                      : CameraFit.coordinates(
                          coordinates: [start ?? const LatLng(36.7525, 3.0420)],
                          maxZoom: 16,
                        ),
                  minZoom: 2,
                  maxZoom: 18,
                  backgroundColor: Palette.bg,
                ),
                children: [
                  VectorTileLayer(
                    theme: s.theme,
                    tileProviders: s.providers,
                    sprites: s.sprites,
                    diskCacheMaximumSizeInBytes: 0,
                  ),
                  GradedRouteLayer(points: summary.points, strokeWidth: thickness),
                  MarkerLayer(
                    markers: [
                      if (start != null)
                        Marker(
                          point: start,
                          width: 16,
                          height: 16,
                          child: const _StartDot(),
                        ),
                      if (end != null && end != start)
                        Marker(
                          point: end,
                          width: 16,
                          height: 16,
                          child: const _EndDot(),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        // The plan's global constraint: the attribution is on every view that
        // shows the bundled map — the recording band and this screen.
        const AttributionStrip(),
      ],
    );
  }
}

class _StartDot extends StatelessWidget {
  const _StartDot();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Palette.onAccent,
      border: Border.all(color: Palette.accent, width: 2.5),
    ),
  );
}

class _EndDot extends StatelessWidget {
  const _EndDot();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(shape: BoxShape.circle, color: Palette.accent),
  );
}
