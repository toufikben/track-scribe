import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/ui/app.dart';
import 'package:track_scribe/ui/basemap/map_style_provider.dart';
import 'package:track_scribe/ui/basemap/vector_map_band.dart';
import 'package:track_scribe/ui/recording/widgets/gps_status_banner.dart';
import 'package:track_scribe/ui/recording/widgets/sport_chips.dart';

import '../support/stub_vector_style.dart';

/// R86: home is AppGate, so a widget test must seed the onboarded flag or the
/// app lands on PermissionScreen (platform-channel probes) instead of the map.
Future<AppDatabase> _seededDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await ActivityRepository(db).setFlag(kOnboardedFlag, true);
  return db;
}

/// The map carries two floating overlays, and both of their Arabic labels are
/// fixed strings. Measured at a real phone width they are far too wide to share
/// the top band, so the layout contract is "never intersect", tested here at
/// three device widths rather than one mockup width.
///
/// The band renders through the stub style: an unmocked platform channel
/// pends forever under `testWidgets`, so the map branch — not the fallback —
/// is what these rects must measure (R104).
void main() {
  late Style style;

  setUpAll(() async {
    style = await loadStubVectorStyle();
  });

  tearDownAll(() => style.dispose());

  for (final widthDp in <double>[360.0, 392.7, 411.0]) {
    testWidgets('overlays never collide at ${widthDp}dp', (tester) async {
      tester.view.physicalSize = Size(widthDp * 2.75, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final db = await _seededDb();
      addTearDown(db.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            mapStyleProvider.overrideWith((ref) => Future.value(style)),
          ],
          child: const TrackScribeApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull, reason: 'renders at ${widthDp}dp');

      final chips = tester.getRect(find.byType(SportChips));
      final banner = tester.getRect(find.byType(GpsStatusBanner));
      expect(
        chips.overlaps(banner),
        isFalse,
        reason: 'chips=$chips banner=$banner at ${widthDp}dp',
      );

      // Both overlays belong to the map band, not the stat panel below it.
      // The band fills the map Stack, so its rect is the band itself.
      final map = tester.getRect(find.byType(VectorMapBand));
      bool inside(Rect r) =>
          r.left >= map.left - 0.5 &&
          r.top >= map.top - 0.5 &&
          r.right <= map.right + 0.5 &&
          r.bottom <= map.bottom + 0.5;
      expect(inside(chips), isTrue, reason: 'chips $chips outside map $map');
      expect(inside(banner), isTrue, reason: 'banner $banner outside map $map');
    });
  }
}
