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

  /// 62 % of text composited over bg, precomputed so the contrast test is honest.
  static const Color textSecondary = Color(0xFF9DA4A1);

  /// Route line + big number ONLY.
  static const Color accent = Color(0xFFC6FF3D);

  static const Color onAccent = Color(0xFF101315);

  /// Stop action ONLY. #E03131 fails 4.5:1 for white text, so danger is darkened.
  static const Color danger = Color(0xFFB42318);
}

double _lin(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double relativeLuminance(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

double contrastRatio(Color a, Color b) {
  final l1 = relativeLuminance(a), l2 = relativeLuminance(b);
  return l1 > l2 ? (l1 + 0.05) / (l2 + 0.05) : (l2 + 0.05) / (l1 + 0.05);
}
