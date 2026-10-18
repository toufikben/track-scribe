import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/core/format.dart';
import 'package:track_scribe/engine/sport_config.dart';
import 'package:track_scribe/state/locale_providers.dart';

/// The big number and the three-stat row. Everything is an opaque theme/Palette
/// token — spec §5 bans translucency on stat text.
class StatPanel extends ConsumerWidget {
  const StatPanel({
    super.key,
    required this.distanceM,
    required this.elapsedNanos,
    required this.elapsedUnstated,
    required this.sport,
    required this.fixCount,
  });

  final double distanceM;
  final int elapsedNanos;

  /// R125 + ر99: the caller says whether [elapsedNanos] is a measured duration
  /// or a stored ABSENCE (an imported file that stated no clock). The panel
  /// cannot tell the two apart itself — both are 0 — so the flag is part of its
  /// contract rather than a default: every caller states which it means. The
  /// live recorder always passes false (its clock is a monotonic stopwatch);
  /// the detail screen passes the row's own answer.
  final bool elapsedUnstated;

  /// Part of the panel's public contract; the panel itself renders only
  /// distance-derived values, the sport/fixCount live in the chips and banner.
  final Sport sport;
  final int fixCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sep = ref.watch(localeSepProvider);
    final theme = Theme.of(context).textTheme;
    // R19: seconds per km = elapsed s / km covered; hidden until the runner
    // has actually moved (distance < 50 m → --:--). R125 needs no second gate
    // here either: an unstated elapsed IS 0 ns and `Format.pace` already answers
    // `<= 0` with `--:--`, so the panel's tests pin the visible outcome instead
    // of an expression that cannot change it.
    final paceSecPerKm = distanceM < 50
        ? null
        : (elapsedNanos / 1e9) / (distanceM / 1000);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // displaySmall requests tnum, which the bundled Plex files do not
        // implement (no tnum GSUB feature); digit-advance uniformity is
        // unverified until the on-device counter check (Task 11).
        Text(
          Format.distance(distanceM, sep: sep),
          style: theme.displaySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _stat('المسافة · كم', Format.distance(distanceM, sep: sep), theme),
            // The same rule as the history row: «00:00» claims a measured
            // zero-length activity, so an unstated clock is written in words.
            _stat(
              'الوقت',
              elapsedUnstated ? 'غير معروف' : Format.duration(elapsedNanos),
              theme,
            ),
            _stat(
              'الإيقاع',
              paceSecPerKm == null
                  ? '--:--'
                  : Format.pace(paceSecPerKm, sep: sep),
              theme,
            ),
          ],
        ),
      ],
    );
  }

  /// One third of the row, scaled down rather than clipped when the user turns
  /// the system font up (spec §5 dynamic type). At 1.5× the three Arabic labels'
  /// intrinsic widths overflowed a ~361 dp panel by 97 dp; each cell now gets a
  /// bounded box and the text shrinks inside it — never an ellipsis, never a
  /// scroll view, and the ر124 60/40 band split stays untouched.
  Widget _stat(String label, String value, TextTheme theme) => Expanded(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        children: [
          Text(label, style: theme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: theme.bodyLarge),
        ],
      ),
    ),
  );
}
