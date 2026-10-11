import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/state/locale_providers.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/basemap/route_painter.dart';

/// The generated dark basemap (spec §6): a 40 px grid + the route polyline +
/// a north indicator and a scale bar, fully local with zero tile licences.
/// The constructor contract (`points`) is what the recording screen consumes
/// and must not change.
class GridBasemap extends ConsumerWidget {
  const GridBasemap({super.key, required this.points});

  final List<StoredPoint> points;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sep = ref.watch(localeSepProvider);
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
              child: _ScaleBar(
                key: const Key('basemap-scale'),
                metresPerPixel: painter.metresPerPixel(size),
                sep: sep,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ScaleBar extends StatelessWidget {
  const _ScaleBar({super.key, required this.metresPerPixel, required this.sep});

  final double metresPerPixel;
  final String sep;

  @override
  Widget build(BuildContext context) {
    // No route, no projection, no scale — the bar only exists when it can
    // tell the truth.
    if (metresPerPixel <= 0) return const SizedBox.shrink();
    final labelMetres = _scaleLabelMetres(metresPerPixel);
    final barPx = labelMetres / metresPerPixel;
    final text = labelMetres >= 1
        ? labelMetres.toStringAsFixed(0)
        : labelMetres.toStringAsFixed(1).replaceAll('.', sep);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$text م',
          style: const TextStyle(fontSize: 10, color: Palette.textSecondary),
        ),
        const SizedBox(height: 2),
        Container(width: barPx, height: 2, color: Palette.textSecondary),
      ],
    );
  }
}

/// The smallest 1-2-5 value worth at least 40 px of the projection, so the
/// label stays exact and the bar lands in [40, 80) px by construction.
double _scaleLabelMetres(double metresPerPixel) {
  final target = metresPerPixel * 40;
  final base = math.pow(10.0, (math.log(target) / math.ln10).floor()).toDouble();
  for (final m in const [1.0, 2.0, 5.0, 10.0]) {
    if (base * m >= target) return base * m;
  }
  return base * 10;
}
