import 'package:flutter/material.dart';
import 'package:track_scribe/theme/palette.dart';

const String kFontFamily = 'PlexArabic';

/// Tabular figures stop the counter from dancing as digits change width.
/// Verified against the three bundled Plex files: their GSUB FeatureList carries
/// no `tnum` feature (aalt, calt, ccmp, dlig, dnom, fina, frac, init, liga,
/// locl, medi, numr, ordn, rlig, salt, sinf, ss01–ss06, subs, sups, zero), so on
/// this family the request is inert — PlexArabic's own digit metrics are what
/// keep the counter steady. The feature is kept because it costs nothing and is
/// free insurance if the family ever falls back to a font that does honour it.
const List<FontFeature> kFigureFeatures = [FontFeature.tabularFigures()];

/// Built from `material2021`'s **white** chain with an explicitly dark
/// `ColorScheme`, then stamped with `Palette.text`.
///
/// The starting chain matters: `Typography.material2021()` defaults to
/// `ColorScheme.light()`, so `.black` carries `onSurface` = `Colors.black` and
/// `apply(bodyColor:)` stamps it on *every* slot. `merge` below only replaces
/// the five authored slots, and `ThemeData.dark().copyWith` routes through
/// `ThemeData.raw`, which skips the `isDark ? white : black` re-derivation — so
/// the un-written slots would have stayed black. Since `Material` seeds
/// `DefaultTextStyle` from `textTheme.bodyMedium`, a bare `Text()` would have
/// rendered black on `#101315` (1.13:1), breaking spec §5. Stamping
/// `Palette.text` makes every slot obey the contrast law by construction.
TextTheme darkTextTheme() =>
    Typography.material2021(colorScheme: const ColorScheme.dark()).white
        .apply(
          displayColor: Palette.text,
          bodyColor: Palette.text,
          // R55: the bundled Plex family must hold on every slot, not just the
          // five authored overrides below; decorationColor keeps any future
          // underlined text on the certified text token.
          fontFamily: kFontFamily,
          decorationColor: Palette.text,
        )
        .merge(
          const TextTheme(
            displaySmall: TextStyle(
              fontFamily: kFontFamily,
              fontSize: 44,
              fontWeight: FontWeight.w800,
              fontFeatures: kFigureFeatures,
              color: Palette.accent,
              height: 1.0,
            ),
            titleLarge: TextStyle(
              fontFamily: kFontFamily,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              fontFeatures: kFigureFeatures,
              color: Palette.text,
            ),
            bodyLarge: TextStyle(
              fontFamily: kFontFamily,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              fontFeatures: kFigureFeatures,
              color: Palette.text,
            ),
            labelLarge: TextStyle(
              fontFamily: kFontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Palette.text,
            ),
            labelMedium: TextStyle(
              fontFamily: kFontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4,
              color: Palette.textSecondary,
            ),
          ),
        );
