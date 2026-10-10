import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/state/recording_controller.dart';
import 'package:track_scribe/theme/palette.dart';

/// GPS status chip floating over the map. Dumb on purpose (ruling R22): with
/// the synthetic source every fix is good, so the banner flips to "active" on
/// the first fix. The real GNSS state machine (searching / accuracy tiers /
/// ر7 start gating) lands in Task 9.
class GpsStatusBanner extends ConsumerWidget {
  const GpsStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(recordingProvider);
    final active = s.fixCount > 0;
    return Chip(
      backgroundColor: Palette.surface,
      labelStyle: TextStyle(
        color: active ? Palette.accent : Palette.textSecondary,
      ),
      label: Text(active ? 'تسجيل نشِط' : 'جارٍ البحث عن الإشارة…'),
    );
  }
}
