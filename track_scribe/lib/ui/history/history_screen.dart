import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/core/format.dart';
import 'package:track_scribe/data/activity_list_item.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/engine/sport_config.dart';
import 'package:track_scribe/state/locale_providers.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/detail/activity_detail_screen.dart';

/// The history list read (خطة 3).
///
/// `autoDispose` for the reason ر116 ruled on for the detail screen: the
/// screen is this provider's only listener, and re-entering the list must show
/// a recording that ended while the user was elsewhere. The value here is small
/// (totals only, ر117), so the cost of re-reading is two local SELECTs.
///
/// `retry: null` for the reason documented on `mapStyleProvider` (R104):
/// Riverpod 3's default retry would re-run a failed read for ~38 s with the
/// state stuck in AsyncLoading, so the error branch would be unreachable —
/// least of all inside `testWidgets`, whose fake clock owns every timer.
final historyProvider = FutureProvider.autoDispose<List<ActivityListItem>>(
  (ref) => ref.watch(activityRepositoryProvider).listActivities(),
  retry: (retryCount, error) => null,
);

/// Every activity this install recorded, newest first (spec §1 «ويعرض المسار
/// تاريخيًا»). No map, no tiles, no platform channel on this screen — which is
/// why its tests need no style stub.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(historyProvider);
    final sep = ref.watch(localeSepProvider);
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(
        backgroundColor: Palette.bg,
        elevation: 0,
        title: Text('سجل الأنشطة', style: Theme.of(context).textTheme.titleLarge),
      ),
      // R23: RTL is set here explicitly — the app has no locale package.
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: items.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Palette.accent),
          ),
          error: (_, _) => const Center(
            child: Text(
              'تعذّر تحميل السجل',
              style: TextStyle(color: Palette.textSecondary),
            ),
          ),
          data: (list) => list.isEmpty
              ? const _NoActivities()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    thickness: 1,
                    color: Palette.surface,
                  ),
                  itemBuilder: (_, i) =>
                      _ActivityRow(item: list[i], sep: sep),
                ),
        ),
      ),
    );
  }
}

/// The empty install. Worded as a fact plus the way out — the spec §7 rule for
/// every "nothing to show" state: never a silent blank.
class _NoActivities extends StatelessWidget {
  const _NoActivities();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('لا أنشطة بعد', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'سجّل أول مسار من شاشة التسجيل ليظهر هنا',
          textAlign: TextAlign.center,
          style: TextStyle(color: Palette.textSecondary),
        ),
      ],
    ),
  );
}

/// Sport → (word, icon). The words are `SportChips`' exactly — one product, one
/// vocabulary (مشي / جري / دراجة).
(String, IconData) _sport(Sport s) => switch (s) {
  Sport.walk => ('مشي', Icons.directions_walk),
  Sport.bike => ('دراجة', Icons.two_wheeler),
  Sport.run => ('جري', Icons.directions_run),
};

/// One activity. Every cell is read from the row's own columns; nothing is
/// recomputed from the wall clock (ر1), and where a column states an ABSENCE
/// the cell prints a word instead of a number (ر99, R125).
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item, required this.sep});

  final ActivityListItem item;
  final String sep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final (label, icon) = _sport(Sport.values.byName(item.sport));
    // The same R19 rule the live panel applies: pace is meaningless below 50 m
    // and prints `--:--` rather than a number invented from a short track.
    // R125 needs no second gate here: an unstated elapsed IS 0 ns, and
    // `Format.pace` already answers `<= 0` with `--:--` — the test pins that
    // visible outcome rather than this expression.
    final paceSecPerKm = item.distanceM < 50
        ? null
        : (item.elapsedNanos / 1e9) / (item.distanceM / 1000);

    return InkWell(
      key: Key('history-row-${item.id}'),
      // ر121: an open recording has no route to replay yet — its points are in
      // the checkpoint's activity, and its totals are not final. Tapping it
      // would open a screen whose every number lags the recorder.
      onTap: item.isOpen
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ActivityDetailScreen(activityId: item.id),
              ),
            ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Palette.textSecondary),
                const SizedBox(width: 6),
                Expanded(child: Text(label, style: theme.titleMedium)),
                Text(Format.activityDate(item.startWallMillis),
                    style: theme.labelMedium),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _stat('كم', Format.distance(item.distanceM, sep: sep), theme),
                // ر99: «00:00» is a duration somebody measured. An imported row
                // whose file stated no clock stores 0 as an ABSENCE, so the cell
                // says so in words instead of printing the absence as a number.
                _stat(
                  'الوقت',
                  item.elapsedUnstated
                      ? 'غير معروف'
                      : Format.duration(item.elapsedNanos),
                  theme,
                ),
                _stat(
                  'الإيقاع',
                  paceSecPerKm == null
                      ? '--:--'
                      : Format.pace(paceSecPerKm, sep: sep),
                  theme,
                ),
                if (item.isOpen) _stat('الحالة', 'قيد التسجيل', theme),
                // R125: a file from another app is labelled as one, in the same
                // conditional-cell slot the open row uses. It went there rather
                // than beside the sport word because the header row measured a
                // 36 px overflow at the target's 361 dp (measured, not guessed:
                // the test that runs the imported row is what found it), while
                // these cells are `Expanded` and share the width.
                if (item.isImported) _stat('المصدر', 'مستورد', theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, TextTheme theme) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.labelMedium),
        const SizedBox(height: 2),
        Text(value, style: theme.bodyMedium),
      ],
    ),
  );
}
