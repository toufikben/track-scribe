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
    required this.sport,
    required this.fixCount,
  });

  final double distanceM;
  final int elapsedNanos;

  /// Part of the panel's public contract; the panel itself renders only
  /// distance-derived values, the sport/fixCount live in the chips and banner.
  final Sport sport;
  final int fixCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sep = ref.watch(localeSepProvider);
    final theme = Theme.of(context).textTheme;
    // R19: seconds per km = elapsed s / km covered; hidden until the runner
    // has actually moved (distance < 50 m → --:--).
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
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _stat('المسافة · كم', Format.distance(distanceM, sep: sep), theme),
            _stat('الوقت', Format.duration(elapsedNanos), theme),
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

  Widget _stat(String label, String value, TextTheme theme) => Column(
    children: [
      Text(label, style: theme.labelMedium),
      const SizedBox(height: 4),
      Text(value, style: theme.bodyLarge),
    ],
  );
}
