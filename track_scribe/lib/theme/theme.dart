import 'package:flutter/material.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/theme/typography.dart';

/// The app's only theme. Spec §5: no glass panels and zero transparency on
/// stat text — every colour is an opaque Palette token, so overlays cannot
/// wash out the counters.
class AppTheme {
  const AppTheme._();

  // ThemeData.dark() is Material 3 by default since Flutter 3.16; passing
  // useMaterial3 here is deprecated (R50: keep analyze clean, no infos).
  static ThemeData get dark => ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Palette.bg,
        colorScheme: const ColorScheme.dark(
          surface: Palette.surface,
          primary: Palette.accent,
          onPrimary: Palette.onAccent,
          error: Palette.danger,
          errorContainer: Palette.danger,
          onError: Palette.text,
        ),
        textTheme: darkTextTheme(),
      );
}
