import 'package:flutter/material.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/theme/typography.dart';

/// The app's only theme. Spec §5: no glass panels and zero transparency on
/// stat text — every colour is an opaque Palette token, so overlays cannot
/// wash out the counters.
class AppTheme {
  const AppTheme._();

  // `useMaterial3` is intentionally not passed here: Flutter 3.47.5 flags it as
  // a deprecated_member_use *info*, the analyze gate treats info as an issue,
  // and ThemeData.dark() already defaults it to true (theme_data.dart:413) — so
  // dropping the flag changes no behaviour.
  static ThemeData get dark => ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Palette.bg,
        colorScheme: const ColorScheme.dark(
          surface: Palette.surface,
          primary: Palette.accent,
          onPrimary: Palette.onAccent,
          // The AppBar action icon resolves its colour from
          // `onSurfaceVariant` (app_bar.dart:946,963-969); `ColorScheme.dark()`
          // seeds that pair with raw `Colors.white`, which the contrast law
          // never certified. Route both through `Palette.text` so the icon
          // pair is the certified text/bg one everywhere.
          onSurface: Palette.text,
          onSurfaceVariant: Palette.text,
          error: Palette.danger,
          errorContainer: Palette.danger,
          onError: Palette.text,
        ),
        textTheme: darkTextTheme(),
      );
}
