import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/source/gps_quality.dart';
import 'package:track_scribe/state/recording_controller.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/app.dart';
import 'package:track_scribe/ui/recording/widgets/gps_status_banner.dart';
import '../support/controlled_fix_source.dart';

/// R86: home is AppGate, so the DB must be seeded with the onboarded flag or
/// the app lands on PermissionScreen instead of the recording screen.
Future<AppDatabase> _seededDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await ActivityRepository(db).setFlag(kOnboardedFlag, true);
  return db;
}

/// The banner was built in Task 7 to wait for this: it renders the ر7/ر8 state
/// machine, and ر8's `lost` must be reachable on the desktop — the clock is
/// injected and the controller's re-read is a timer that `pump` can drive, so
/// no test here sleeps for 20 seconds.
void main() {
  test('every state has its Arabic label, and no label is danger-as-foreground', () {
    expect(gpsStatusLabel(GpsQuality.none), 'جارٍ البحث عن الإشارة…');
    expect(gpsStatusLabel(GpsQuality.searching), 'جارٍ البحث عن الإشارة…');
    // M4: the none/searching collapse is intentional — both mean "no usable
    // signal yet" to the user — so pin the equality, not just the literals.
    expect(gpsStatusLabel(GpsQuality.none), gpsStatusLabel(GpsQuality.searching));
    expect(gpsStatusLabel(GpsQuality.ok), 'تسجيل نشِط');
    expect(gpsStatusLabel(GpsQuality.degraded), 'إشارة ضعيفة');
    expect(gpsStatusLabel(GpsQuality.lost), 'فقدت الإشارة');

    for (final q in GpsQuality.values) {
      final fg = gpsStatusLabelColor(q);
      expect(
        fg,
        isNot(Palette.danger),
        reason: 'danger as text is 2.64:1 on surface — illegal under the law',
      );
      expect(
        contrastRatio(fg, Palette.surface),
        greaterThan(4.5),
        reason: '$q label must be readable on the chip background',
      );
    }
  });

  testWidgets('the chip follows the state machine: searching → active → weak → lost', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final src = ControlledFixSource();
    var nowNanos = 0;
    final db = await _seededDb();
    addTearDown(db.close);
    await tester.pumpWidget(
      TrackScribeApp(
        overrides: [
          fixSourceProvider.overrideWithValue(src),
          gateClockProvider.overrideWithValue(() => nowNanos),
          // R80: recording sessions now write to sqlite; memory DB only.
          appDatabaseProvider.overrideWithValue(db),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('جارٍ البحث عن الإشارة…'),
      findsOneWidget,
      reason: 'before a session starts there is no signal to describe',
    );

    await tester.tap(find.text('ابدأ التسجيل'));
    await _flush(tester);

    src.emit(accuracyM: 3.0); // one good fix: ر7 is not satisfied yet
    await _flush(tester);
    expect(
      find.text('جارٍ البحث عن الإشارة…'),
      findsOneWidget,
      reason: 'a single fix must not advertise an active recording',
    );

    src.emit(accuracyM: 3.0); // ر7 opens
    await _flush(tester);
    expect(find.text('تسجيل نشِط'), findsOneWidget);
    expect(bannerLabelColor(tester), Palette.accent);
    expect(find.text('إيقاف'), findsOneWidget);

    src.emit(accuracyM: 25.0); // 20–35 m: weak signal after the gate opened
    await _flush(tester);
    expect(find.text('إشارة ضعيفة'), findsOneWidget);

    src.emit(accuracyM: 90.0); // > 35 m: the CURRENT fix is too coarse to
    // record against — searching, per ر7's tier table (D3), even though the
    // session is already recording and the button still says إيقاف.
    await _flush(tester);
    expect(find.text('جارٍ البحث عن الإشارة…'), findsOneWidget);
    expect(find.text('إيقاف'), findsOneWidget);

    // ر8: 20 s of silence, measured on the injected clock. Nothing arrives, so
    // only a clock-driven re-read can surface it — which is what the tick is.
    nowNanos = 21 * 1000000000;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('فقدت الإشارة'), findsOneWidget);
    expect(
      bannerLabelColor(tester),
      Palette.text,
      reason: 'lost is never red (contrast law)',
    );

    // A fix that arrives again ends the loss.
    nowNanos = 22 * 1000000000;
    src.emit(accuracyM: 4.0);
    await _flush(tester);
    expect(find.text('تسجيل نشِط'), findsOneWidget);

    await tester.tap(find.text('إيقاف'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('جارٍ البحث عن الإشارة…'),
      findsOneWidget,
      reason: 'a stopped session has no signal state to show',
    );
    await src.dispose();
  });
}

/// A fix travels over a stream: the event is delivered on a microtask, which can
/// land after the frame a single `pump` draws. Two pumps always show the newest
/// fix — the observed lag was one frame, and the second pump is the fix.
Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

/// The banner's own [Chip] — `find.byType(Chip)` alone would also match the
/// three ChoiceChips of the sport row, which build a Chip internally.
Color? bannerLabelColor(WidgetTester tester) => tester
    .widget<Chip>(
      find.descendant(
        of: find.byType(GpsStatusBanner),
        matching: find.byType(Chip),
      ),
    )
    .labelStyle!
    .color;
