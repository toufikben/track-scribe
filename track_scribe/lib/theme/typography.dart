import 'package:flutter/material.dart';
import 'package:track_scribe/theme/palette.dart';

const String kFontFamily = 'PlexArabic';

/// Tabular figures stop the counter from dancing as digits change width.
const List<FontFeature> kFigureFeatures = [FontFeature.tabularFigures()];

TextTheme darkTextTheme() =>
    Typography.material2021().black.merge(const TextTheme(
      displaySmall: TextStyle(
          fontFamily: kFontFamily, fontSize: 44, fontWeight: FontWeight.w800,
          fontFeatures: kFigureFeatures, color: Palette.accent, height: 1.0),
      titleLarge: TextStyle(
          fontFamily: kFontFamily, fontSize: 22, fontWeight: FontWeight.w700,
          fontFeatures: kFigureFeatures, color: Palette.text),
      bodyLarge: TextStyle(
          fontFamily: kFontFamily, fontSize: 17, fontWeight: FontWeight.w600,
          fontFeatures: kFigureFeatures, color: Palette.text),
      labelLarge: TextStyle(
          fontFamily: kFontFamily, fontSize: 13, fontWeight: FontWeight.w700,
          color: Palette.text),
      labelMedium: TextStyle(
          fontFamily: kFontFamily, fontSize: 11, fontWeight: FontWeight.w500,
          letterSpacing: 0.4, color: Palette.textSecondary),
    ));
