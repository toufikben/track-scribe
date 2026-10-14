import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:track_scribe/theme/palette.dart';

/// The honest 1-2-5 scale bar (spec: never print a fabricated figure).
/// `metresPerPixel <= 0` hides it — the same contract the grid basemap had.
class ScaleBar extends StatelessWidget {
  const ScaleBar({super.key, required this.metresPerPixel});

  final double metresPerPixel;

  @override
  Widget build(BuildContext context) {
    if (metresPerPixel <= 0) return const SizedBox.shrink();
    final labelMetres = scaleLabelMetres(metresPerPixel);
    if (labelMetres < 1) return const SizedBox.shrink();
    final barPx = labelMetres / metresPerPixel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${labelMetres.toStringAsFixed(0)} م',
          style: const TextStyle(fontSize: 10, color: Palette.textSecondary),
        ),
        const SizedBox(height: 2),
        Container(width: barPx, height: 2, color: Palette.textSecondary),
      ],
    );
  }
}

/// The smallest 1-2-5 value worth at least 40 px, so the label stays exact
/// and the bar lands in [40, 80) px by construction.
double scaleLabelMetres(double metresPerPixel) {
  final target = metresPerPixel * 40;
  final base = math.pow(10.0, (math.log(target) / math.ln10).floor()).toDouble();
  for (final m in const [1.0, 2.0, 5.0, 10.0]) {
    if (base * m >= target) return base * m;
  }
  return base * 10;
}
