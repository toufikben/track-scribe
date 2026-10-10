import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/theme/theme.dart';
import 'package:track_scribe/theme/typography.dart';

/// Spec §5 law, applied to the *theme*: every slot of `AppTheme.dark`'s text
/// theme must be a certified Palette text token at >= 4.5:1 on `bg`, with no
/// glass/translucent stat text. A slot the app does not author explicitly is
/// still primary text the moment Task 7 sets `theme: AppTheme.dark`, so it has
/// to obey the law by construction.
void main() {
  List<TextStyle?> allSlots(TextTheme t) => [
    t.displayLarge,
    t.displayMedium,
    t.displaySmall,
    t.headlineLarge,
    t.headlineMedium,
    t.headlineSmall,
    t.titleLarge,
    t.titleMedium,
    t.titleSmall,
    t.bodyLarge,
    t.bodyMedium,
    t.bodySmall,
    t.labelLarge,
    t.labelMedium,
    t.labelSmall,
  ];

  test('every text theme slot is an opaque Palette text token', () {
    final allowed = [Palette.text, Palette.textSecondary, Palette.accent];
    for (final style in allSlots(AppTheme.dark.textTheme)) {
      expect(style, isNotNull, reason: 'a null slot cannot satisfy the law');
      expect(
        allowed,
        contains(style!.color),
        reason: '${style.fontFamily} slot colour is not a Palette text token',
      );
      expect(style.color!.a, 1.0, reason: 'spec §5 bans translucent stat text');
      expect(
        contrastRatio(style.color!, Palette.bg),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('unwritten slots resolve to Palette.text, not black (C-1)', () {
    // `Typography.material2021().black` stamps pure black on every slot the
    // theme does not author. headlineMedium is already used by lib/ui/app.dart,
    // and Material seeds DefaultTextStyle from bodyMedium (material.dart:477),
    // which Scaffold wraps around the whole body — black on #101315 is 1.13:1.
    expect(AppTheme.dark.textTheme.headlineMedium!.color, Palette.text);
    expect(AppTheme.dark.textTheme.bodyMedium!.color, Palette.text);
  });

  test('every slot carries the bundled Arabic family (R55)', () {
    // fontFamily is stamped via TextTheme.apply, so it holds on ALL 15 slots,
    // not just the five authored overrides; digit-advance uniformity is
    // unverified until the on-device counter check (Task 11).
    for (final style in allSlots(AppTheme.dark.textTheme)) {
      expect(
        style!.fontFamily,
        kFontFamily,
        reason: 'slot missing kFontFamily',
      );
    }
  });

  test('the five authored overrides still win', () {
    final t = AppTheme.dark.textTheme;
    expect(t.displaySmall!.color, Palette.accent);
    expect(t.titleLarge!.color, Palette.text);
    expect(t.bodyLarge!.color, Palette.text);
    expect(t.labelLarge!.color, Palette.text);
    expect(t.labelMedium!.color, Palette.textSecondary);
  });

  testWidgets('a bare Text() under AppTheme.dark inherits light text', (
    tester,
  ) async {
    late TextStyle inherited;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              inherited = DefaultTextStyle.of(context).style;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(inherited.color, Palette.text);
    expect(
      contrastRatio(inherited.color!, Palette.bg),
      greaterThanOrEqualTo(4.5),
    );
  });
}
