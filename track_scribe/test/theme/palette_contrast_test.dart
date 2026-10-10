import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/theme/palette.dart';

void main() {
  test('the dark palette obeys the contrast law, not taste', () {
    expect(Palette.bg, const Color(0xFF101315));
    expect(Palette.accent, const Color(0xFFC6FF3D));
    expect(Palette.danger, const Color(0xFFB42318),
        reason: '#E03131 fails 4.5:1 for white text — danger is darkened, verified');
    expect(contrastRatio(Palette.text, Palette.bg), greaterThan(16.0));
    expect(contrastRatio(Palette.accent, Palette.bg), greaterThan(7.0));
    expect(contrastRatio(Palette.textSecondary, Palette.bg), greaterThan(4.5));
    expect(contrastRatio(Palette.text, Palette.danger), greaterThan(4.5));
    expect(contrastRatio(Palette.text, Palette.surface), greaterThan(15.0));
  });

  test('no text token sits on the accent at less than 7:1', () {
    expect(contrastRatio(Palette.onAccent, Palette.accent), greaterThan(7.0));
  });
}
