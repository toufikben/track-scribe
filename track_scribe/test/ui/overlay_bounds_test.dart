import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/ui/app.dart';
import 'package:track_scribe/ui/basemap/grid_basemap.dart';
import 'package:track_scribe/ui/recording/widgets/gps_status_banner.dart';
import 'package:track_scribe/ui/recording/widgets/sport_chips.dart';

/// The map carries two floating overlays, and both of their Arabic labels are
/// fixed strings. Measured at a real phone width they are far too wide to share
/// the top band, so the layout contract is "never intersect", tested here at
/// three device widths rather than one mockup width.
void main() {
  for (final widthDp in <double>[360.0, 392.7, 411.0]) {
    testWidgets('overlays never collide at ${widthDp}dp', (tester) async {
      tester.view.physicalSize = Size(widthDp * 2.75, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ProviderScope(child: TrackScribeApp()));
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
      // GridBasemap fills the map Stack, so its rect is the band itself.
      final map = tester.getRect(find.byType(GridBasemap));
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
