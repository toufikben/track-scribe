import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/state/recording_controller.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/basemap/vector_map_band.dart';
import 'package:track_scribe/ui/detail/activity_detail_screen.dart';
import 'package:track_scribe/ui/history/history_screen.dart';
import 'package:track_scribe/ui/recording/widgets/gps_status_banner.dart';
import 'package:track_scribe/ui/recording/widgets/sport_chips.dart';
import 'package:track_scribe/ui/recording/widgets/stat_panel.dart';
import 'package:track_scribe/ui/recording/widgets/storage_error_banner.dart';
import 'package:track_scribe/ui/recording/widgets/stop_button.dart';

/// Layout B2 (spec §5, amended by ر124 — owner order 2026-10-16 «الخريطة
/// تحتل الجزء الأكبر من الواجهة والآخرين في أسفل الواجهة»): map on 60 % of the
/// body height (flex 6), stat panel on the remaining 40 % (flex 4), sport chips
/// and the GPS banner floating over the map, one wide ≥ 56 dp start/stop control
/// at the bottom.
///
/// R23: RTL is set by this explicit `Directionality` — no
/// flutter_localizations dependency anywhere in the app.
class RecordingScreen extends ConsumerWidget {
  const RecordingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(recordingProvider);
    final controller = ref.read(recordingProvider.notifier);
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        elevation: 0,
        title: Text('تسجيل', style: Theme.of(context).textTheme.titleLarge),
        // ر119: the entry point is an AppBar action, never a bottom bar — the
        // AppBar lives outside the 60/40 split that layout B2's tests measure.
        actions: [
          IconButton(
            key: const Key('history-button'),
            tooltip: 'سجل الأنشطة',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              Expanded(
                flex: 6,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: VectorMapBand(
                        points: s.engine?.storedPoints ?? const <StoredPoint>[],
                        current: (s.engine?.storedPoints.isNotEmpty ?? false)
                            ? s.engine!.storedPoints.last
                            : null,
                      ),
                    ),
                    const Positioned(top: 12, right: 12, child: SportChips()),
                    // Anchored bottom-left, not top-left as the mockup sketch:
                    // at a real phone width (~393 dp) the chips row and the
                    // banner together need ~620 dp, so two top corners collide.
                    // Guarded by test/ui/overlay_bounds_test.dart.
                    const Positioned(
                      bottom: 12,
                      left: 12,
                      child: GpsStatusBanner(),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // R78: self-hides while storage is healthy, so a failing
                      // write is the only time it takes space from the panel.
                      const StorageErrorBanner(),
                      StatPanel(
                        distanceM: s.distanceM,
                        elapsedNanos: s.elapsedNanos,
                        sport: s.sport,
                        fixCount: s.fixCount,
                      ),
                      const Spacer(),
                      StopButton(
                        phase: s.phase,
                        onStart: controller.start,
                        onStop: controller.stop,
                      ),
                      // Task 5 left `lastActivityId` as the only handle on the
                      // row the session just closed; this is the affordance that
                      // makes it mean something. It shows ONLY in `stopped` with
                      // a row behind it — a session ر7 never opened made no row,
                      // so there is nothing to open and nothing appears.
                      if (s.lastActivityId != null &&
                          s.phase == RecordingPhase.stopped)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton.icon(
                            key: const Key('detail-button'),
                            onPressed: () {
                              final id = s.lastActivityId!;
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ActivityDetailScreen(activityId: id),
                                ),
                              );
                            },
                            icon: const Icon(Icons.route_outlined, size: 18),
                            label: const Text('تفاصيل النشاط'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
