import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/state/recording_controller.dart';
import 'package:track_scribe/ui/app.dart';
import '../support/controlled_fix_source.dart';

/// R72 was written as: "`main()` wrapping the app in its own `ProviderScope`
/// starts a second container, so the production override would be invisible and
/// the app would record synthetic points on a real phone". Measured on
/// flutter_riverpod 3.4.3 the nested scope DOES inherit an outer override (see
/// the last test), so the fatal half of that claim does not hold on this
/// version. The design ruling still stands and is what these tests pin: the
/// application must not depend on container nesting behaviour it does not own —
/// production overrides enter through `TrackScribeApp.overrides`, which is the
/// only scope its widgets are guaranteed to read.
void main() {
  testWidgets('TrackScribeApp.overrides reaches the controller its widgets build', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final src = ControlledFixSource();
    await tester.pumpWidget(
      TrackScribeApp(overrides: [fixSourceProvider.overrideWithValue(src)]),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pump();
    expect(
      src.startCalls,
      1,
      reason: 'the app must run on the source main() handed it, not on the '
          'built-in SyntheticFixSource. Remove the forwarding in lib/ui/app.dart '
          'and this is the test that fails.',
    );

    src.emitMany(2, accuracyM: 3.0);
    await tester.pump();
    await tester.pump(); // see test/ui/gps_banner_test.dart: stream events can
    // land a frame after the pump that draws them
    expect(find.text('إيقاف'), findsOneWidget);

    await tester.tap(find.text('إيقاف'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(src.stopCalls, 1, reason: 'and stop() must reach the same source');

    await src.dispose();
  });

  testWidgets('with no overrides the app is self-contained: the fake is untouched', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final src = ControlledFixSource();
    await tester.pumpWidget(const TrackScribeApp());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pump();

    expect(
      src.startCalls,
      0,
      reason: 'a source only reaches the app through an override it declares',
    );

    // The default source IS the synthetic one, and its periodic timer must be
    // cancelled before fake-async teardown: stop the session it started.
    await tester.pump(const Duration(milliseconds: 400));
    await _endSession(tester);
    await src.dispose();
  });

  testWidgets('measured: an outer scope override is inherited today', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final src = ControlledFixSource();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fixSourceProvider.overrideWithValue(src)],
        child: const TrackScribeApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pump();

    expect(
      src.startCalls,
      1,
      reason: 'riverpod 3.4.3 resolves a provider not overridden in the inner '
          'container through its parent. If this ever becomes 0, nesting '
          'stopped inheriting — that would only break apps that relied on it, '
          'which main() does not: it uses TrackScribeApp.overrides.',
    );

    // Leave no session running: cancel out of starting (ر7 never opens, because
    // this fake emits nothing on its own).
    await _endSession(tester);
    await src.dispose();
  });
}

/// Taps whichever control the phase offers, so no test hands fake-async a live
/// periodic timer at teardown.
Future<void> _endSession(WidgetTester tester) async {
  if (find.text('إيقاف').evaluate().isNotEmpty) {
    await tester.tap(find.text('إيقاف'));
  } else if (find.text('إلغاء').evaluate().isNotEmpty) {
    await tester.tap(find.text('إلغاء'));
  }
  await tester.pump(const Duration(milliseconds: 100));
}
