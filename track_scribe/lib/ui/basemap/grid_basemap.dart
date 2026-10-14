import 'package:flutter/material.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/basemap/route_painter.dart';
import 'package:track_scribe/ui/basemap/scale_bar.dart';

/// The generated dark basemap (spec §6): a 40 px grid + the route polyline +
/// a north indicator and a scale bar, fully local with zero tile licences.
/// The constructor contract (`points`) is what the recording screen consumes
/// and must not change.
class GridBasemap extends StatelessWidget {
  const GridBasemap({super.key, required this.points});

  final List<StoredPoint> points;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final painter = RoutePainter(points);
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                key: const Key('basemap-canvas'),
                painter: painter,
              ),
            ),
            // The two corners the recording screen's overlays do not own:
            // chips top-right, GPS banner bottom-left (pinned by
            // test/ui/overlay_bounds_test.dart) — north and scale take the
            // remaining two, guarded by the 360 dp test in basemap_test.dart.
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
              bottom: 8,
              right: 8,
              child: ScaleBar(
                key: const Key('basemap-scale'),
                metresPerPixel: painter.metresPerPixel(size),
              ),
            ),
          ],
        );
      },
    );
  }
}
