import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/engine/sport_config.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/theme/theme.dart';
import 'package:track_scribe/ui/recording/widgets/stat_panel.dart';

class _Harness extends StatelessWidget {
  const _Harness({
    required this.distanceM,
    required this.elapsedNanos,
    this.elapsedUnstated = false,
  });
  final double distanceM;
  final int elapsedNanos;
  final bool elapsedUnstated;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      // R23: RTL comes from an explicit Directionality, not from
      // flutter_localizations.
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: StatPanel(
          distanceM: distanceM,
          elapsedNanos: elapsedNanos,
          elapsedUnstated: elapsedUnstated,
          sport: Sport.run,
          fixCount: 0,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('R19 known value: 1000 m in 400 s renders pace 6:40', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: _Harness(distanceM: 1000, elapsedNanos: 400000000000),
      ),
    );
    expect(find.text('6:40'), findsOneWidget);
    // The big number repeats in the panel row, hence two widgets.
    expect(find.text('1,00'), findsNWidgets(2));
  });

  testWidgets('pace shows --:-- below 50 m (R19 guard)', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: _Harness(distanceM: 49.9, elapsedNanos: 60000000000),
      ),
    );
    expect(find.text('--:--'), findsOneWidget);
  });

  testWidgets('stat text uses opaque Palette tokens (spec §5)', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: _Harness(distanceM: 1000, elapsedNanos: 400000000000),
      ),
    );
    for (final element in find.byType(Text).evaluate()) {
      final style = element.widget as Text;
      final color =
          style.style?.color ?? DefaultTextStyle.of(element).style.color;
      expect(color!.a, 1.0, reason: 'no translucency on stat text');
      expect(
        [Palette.text, Palette.textSecondary, Palette.accent],
        contains(color),
        reason: 'stat text must be an opaque Palette token',
      );
    }
  });

  // R125 + ر99: the panel renders a stored ABSENCE as words. Both cases below
  // carry `elapsedNanos: 0`, and only the flag separates them — which is the
  // whole point of the pair: the gate must key on provenance, never on the
  // number, or a recording that measured zero seconds would be relabelled
  // unknown.
  testWidgets(
    'an unstated elapsed prints «غير معروف» and no pace, never 00:00',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: _Harness(
            distanceM: 1000,
            elapsedNanos: 0,
            elapsedUnstated: true,
          ),
        ),
      );
      expect(find.text('غير معروف'), findsOneWidget);
      expect(
        find.text('00:00'),
        findsNothing,
        reason: '0 ns that was never measured is not a zero-length activity',
      );
      expect(
        find.text('--:--'),
        findsOneWidget,
        reason: 'a pace divided from an absence of a clock is not a pace',
      );
      // The distance WAS computed (the file's own positions), so it keeps
      // printing as a number.
      expect(find.text('1,00'), findsNWidgets(2));
    },
  );

  testWidgets(
    'a measured zero elapsed still prints 00:00 — the flag, not the number, '
    'decides',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: _Harness(distanceM: 1000, elapsedNanos: 0),
        ),
      );
      expect(find.text('00:00'), findsOneWidget);
      expect(
        find.text('غير معروف'),
        findsNothing,
        reason: 'a stopwatch that measured zero seconds said so',
      );
    },
  );
}
