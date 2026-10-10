import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Dark design tokens. Every value here is a law, not a taste: the contrast
/// test in test/theme/palette_contrast_test.dart enforces WCAG ratios against
/// these exact hexes. If a ratio fails, change the token, never the threshold.
class Palette {
  const Palette._();

  static const Color bg = Color(0xFF101315);
  static const Color surface = Color(0xFF171B1E);
  static const Color text = Color(0xFFF4F7F2);

  /// ≈62 % of text composited over bg, rounded for the palette. Exact 62 %
  /// would be #9DA09E; this token is the pre-verified 7.33:1 value the contrast
  /// test pins, so it is the hex that ships.
  static const Color textSecondary = Color(0xFF9DA4A1);

  /// The brand signal: route line, the big number, selected/active
  /// affordances (chip fill under `onAccent`, active status label). It is not
  /// a general-purpose text colour — and every place it is used must clear the
  /// contrast law, including on `surface` (pinned in the contrast test).
  static const Color accent = Color(0xFFC6FF3D);

  static const Color onAccent = Color(0xFF101315);

  /// Stop action ONLY. #E03131 fails 4.5:1 for white text, so danger is darkened.
  ///
  /// Usage rule (spec §5): `danger` is a **background** colour, and the only
  /// thing ever drawn on it is `Palette.text` — the certified 6.08:1 pair, e.g.
  /// the filled stop control. As a *foreground* on `bg` it is 2.84:1 and on
  /// `surface` 2.64:1, both illegal under the contrast law, so never use it as
  /// text or icon colour.
  static const Color danger = Color(0xFFB42318);
}

double _lin(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double relativeLuminance(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

/// WCAG contrast between two **opaque** colours.
///
/// Alpha is deliberately not modelled: a translucent "glass" token would be
/// certified here at its un-composited ratio, which the spec's contrast law
/// must never allow. Compose over the real background first (`Color.alphaBlend`)
/// and measure that.
double contrastRatio(Color a, Color b) {
  assert(
    a.a == 1 && b.a == 1,
    'contrastRatio takes opaque colours only; blend the alpha first',
  );
  final l1 = relativeLuminance(a), l2 = relativeLuminance(b);
  return l1 > l2 ? (l1 + 0.05) / (l2 + 0.05) : (l2 + 0.05) / (l1 + 0.05);
}
