import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/app.dart';
import 'package:track_scribe/ui/basemap/grid_basemap.dart';

void main() {
  testWidgets('layout B: half map + big number panel, RTL, dark', (
    tester,
  ) async {
    // R20: the tester.binding.window form is deprecated on Flutter 3.47.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: TrackScribeApp()));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester
          .widget<Directionality>(find.byType(Directionality).last)
          .textDirection,
      TextDirection.rtl,
    );
    expect(find.text('المسافة · كم'), findsOneWidget);
    expect(find.text('جري'), findsOneWidget);
    expect(find.text('مشي'), findsOneWidget);
    expect(find.text('دراجة'), findsOneWidget);
    expect(find.text('ابدأ التسجيل'), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Palette.bg,
    );

    // Layout contract (spec §5): the map takes 40 % of the body Column and
    // the panel 60 % (Expanded flex 4 / 6).
    final bodyColumn = tester
        .element(find.byType(GridBasemap))
        .findAncestorWidgetOfExactType<Column>();
    expect(bodyColumn, isNotNull);
    final columnHeight = tester.getSize(find.byWidget(bodyColumn!)).height;
    final mapHeight = tester.getSize(find.byType(GridBasemap)).height;
    expect(mapHeight, closeTo(columnHeight * 0.4, 1.0));

    // Before start the counters render real formatted values, not
    // placeholders. The distance appears twice (big number + panel row).
    expect(find.text('0,00'), findsNWidgets(2));
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('--:--'), findsOneWidget);

    // R53: start is NOT danger — Palette.text on Palette.surface.
    final startButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'ابدأ التسجيل'),
    );
    final startStyle = startButton.style!;
    expect(
      startStyle.backgroundColor!.resolve(const <WidgetState>{}),
      Palette.surface,
    );
    expect(
      startStyle.foregroundColor!.resolve(const <WidgetState>{}),
      Palette.text,
    );
    expect(startStyle.minimumSize!.resolve(const <WidgetState>{})!.height, 56);

    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pump(const Duration(seconds: 2));
    // R21: Stopwatch is NOT faked by pump (only Timer.periodic is), so after
    // a fake 2 s we assert ONLY the phase change — never a specific non-zero
    // distance.
    expect(find.text('إيقاف'), findsOneWidget);

    // R53: while recording, the stop button is danger-as-background carrying
    // Palette.text (the certified 6.08:1 pair), never danger as a foreground.
    final stopButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'إيقاف'),
    );
    final stopStyle = stopButton.style!;
    expect(
      stopStyle.backgroundColor!.resolve(const <WidgetState>{}),
      Palette.danger,
    );
    expect(
      stopStyle.foregroundColor!.resolve(const <WidgetState>{}),
      Palette.text,
    );
    expect(stopStyle.minimumSize!.resolve(const <WidgetState>{})!.height, 56);

    // Stop the session so the synthetic source's periodic timer is cancelled
    // before the fake-async zone teardown (pending timers fail the test).
    await tester.tap(find.text('إيقاف'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ابدأ التسجيل'), findsOneWidget);
  });

  testWidgets(
    'start is enabled with the synthetic source (ر7 deferred to Task 9)',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: TrackScribeApp()));
      await tester.pump(const Duration(milliseconds: 400));
      final f = find.widgetWithText(ElevatedButton, 'ابدأ التسجيل');
      expect(
        tester.widget<ElevatedButton>(f).enabled,
        isTrue,
        reason: 'the synthetic source always has a fix; the disabled state is covered in Task 9',
      );
    },
  );

  testWidgets('screen rebuilds from the recording state machine', (
    tester,
  ) async {
    // Sanity: the widgets under test are the screen's own, so a full
    // start→stop cycle returns to the start label.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: TrackScribeApp()));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('إيقاف'), findsOneWidget);
    await tester.tap(find.text('إيقاف'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ابدأ التسجيل'), findsOneWidget);
  });
}
