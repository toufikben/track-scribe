import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/theme/theme.dart';

void main() {
  test('the dark palette obeys the contrast law, not taste', () {
    expect(Palette.bg, const Color(0xFF101315));
    expect(Palette.accent, const Color(0xFFC6FF3D));
    expect(
      Palette.danger,
      const Color(0xFFB42318),
      reason:
          '#E03131 fails 4.5:1 for white text — danger is darkened, verified',
    );
    expect(contrastRatio(Palette.text, Palette.bg), greaterThan(16.0));
    expect(contrastRatio(Palette.accent, Palette.bg), greaterThan(7.0));
    expect(contrastRatio(Palette.textSecondary, Palette.bg), greaterThan(4.5));
    expect(contrastRatio(Palette.text, Palette.danger), greaterThan(4.5));
    expect(contrastRatio(Palette.text, Palette.surface), greaterThan(15.0));
  });

  test('no text token sits on the accent at less than 7:1', () {
    expect(contrastRatio(Palette.onAccent, Palette.accent), greaterThan(7.0));
  });

  test('the surface pairs the recording screen introduced are certified', () {
    // Task 7 put two new token pairs on Palette.surface — the unselected chip
    // label and the active GPS label — that the original law never measured
    // (it only certified each token against bg). Measured here: 6.81:1 and
    // 14.66:1.
    expect(
      contrastRatio(Palette.textSecondary, Palette.surface),
      greaterThan(4.5),
    );
    expect(contrastRatio(Palette.accent, Palette.surface), greaterThan(4.5));
  });

  test('the app bar icon pair is a certified token, not a scheme default', () {
    // AppBar actions resolve their icon colour from `colorScheme
    // .onSurfaceVariant` (app_bar.dart:946,963-969), which falls back to
    // `onSurface`. `ColorScheme.dark()` seeds both with raw `Colors.white` —
    // an uncertified colour the palette law never measured. The theme must
    // route them through `Palette.text` so the icon pair is the certified
    // text/bg one (>16:1, pinned above) everywhere, not a per-widget colour.
    expect(AppTheme.dark.colorScheme.onSurface, Palette.text);
    expect(AppTheme.dark.colorScheme.onSurfaceVariant, Palette.text);
  });
}
