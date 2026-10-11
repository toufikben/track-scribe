import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/source/gps_quality.dart';
import 'package:track_scribe/state/recording_controller.dart';
import 'package:track_scribe/theme/palette.dart';

/// The ر7/ر8 label table, as data (spec §5 wording).
/// `none` and `searching` share one string ON PURPOSE (M4 ruling): both tell
/// the user "no usable signal yet", and pinning that in gps_banner_test.dart
/// keeps the collapse a decision, not an oversight.
String gpsStatusLabel(GpsQuality q) => switch (q) {
  GpsQuality.none || GpsQuality.searching => 'جارٍ البحث عن الإشارة…',
  GpsQuality.ok => 'تسجيل نشِط',
  GpsQuality.degraded => 'إشارة ضعيفة',
  GpsQuality.lost => 'فقدت الإشارة',
};

/// Label colour, under the contrast law: `Palette.danger` is a BACKGROUND only
/// (as a foreground it is 2.64:1 on `surface`, which
/// test/theme/palette_contrast_test.dart forbids), so a lost signal is loud
/// because of its wording and its full-strength text token, not because it is
/// red. Everything here is a token the law already certifies on `surface`.
Color gpsStatusLabelColor(GpsQuality q) => switch (q) {
  GpsQuality.ok => Palette.accent,
  GpsQuality.degraded || GpsQuality.searching || GpsQuality.none =>
    Palette.textSecondary,
  GpsQuality.lost => Palette.text,
};

/// GPS status chip floating over the map. Dumb on purpose (ruling R22): it
/// renders the [GpsQuality] state the controller publishes — Task 9 replaced
/// the Task 7 "any fix counts" placeholder with the real ر7/ر8 machine.
class GpsStatusBanner extends ConsumerWidget {
  const GpsStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(recordingProvider);
    // Until ر7 promotes the session, the user is searching for a recordable
    // signal even if the last fix's own tier was precise: readiness is the
    // phase's truth, the tier is the fix's (D3 — the two are never merged).
    final q = session.phase == RecordingPhase.starting
        ? GpsQuality.searching
        : session.quality;
    return Chip(
      backgroundColor: Palette.surface,
      labelStyle: TextStyle(color: gpsStatusLabelColor(q)),
      label: Text(gpsStatusLabel(q)),
    );
  }
}
