import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/state/recording_controller.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/app.dart';
import '../support/controlled_fix_source.dart';

/// R86: home is AppGate, so the DB must be seeded with the onboarded flag or
/// the app lands on PermissionScreen instead of the recording screen.
Future<AppDatabase> _seededDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await ActivityRepository(db).setFlag(kOnboardedFlag, true);
  return db;
}

/// Task 7 left `starting` as a transient with a disabled button, which was safe
/// only because the synthetic source always has a good fix. With real GNSS a
/// signal that never reaches ر7 (indoors, cold start, dead antenna) is reachable
/// in seconds — so `starting` must offer a way out.
void main() {
  testWidgets('starting offers an enabled cancel, never a dead button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final src = ControlledFixSource();
    final db = await _seededDb();
    addTearDown(db.close);
    await tester.pumpWidget(
      TrackScribeApp(
        overrides: [
          fixSourceProvider.overrideWithValue(src),
          // R80: starting a session reads the resume checkpoint — memory DB.
          appDatabaseProvider.overrideWithValue(db),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('ابدأ التسجيل'));
    await _flush(tester);
    src.emitMany(3, accuracyM: 90); // none of them satisfies ر7
    await _flush(tester);

    expect(find.text('ابدأ التسجيل'), findsNothing);
    final cancel = find.widgetWithText(ElevatedButton, 'إلغاء');
    expect(cancel, findsOneWidget);
    final button = tester.widget<ElevatedButton>(cancel);
    expect(
      button.enabled,
      isTrue,
      reason: 'a user who cannot get a fix must still be able to get out',
    );

    // Contrast law: cancel is Palette.text on Palette.surface (the certified
    // pair), never danger as a foreground, and it keeps the 56 dp target.
    final style = button.style!;
    final states = const <WidgetState>{};
    expect(style.backgroundColor!.resolve(states), Palette.surface);
    expect(style.foregroundColor!.resolve(states), Palette.text);
    expect(style.minimumSize!.resolve(states)!.height, 56);

    await tester.tap(cancel);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ابدأ التسجيل'), findsOneWidget);
    expect(src.stopCalls, 1, reason: 'cancel releases the sensors');

    await src.dispose();
  });

  testWidgets('cancel from starting stops the source and does not restart it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final src = ControlledFixSource();
    final db = await _seededDb();
    addTearDown(db.close);
    await tester.pumpWidget(
      TrackScribeApp(
        overrides: [
          fixSourceProvider.overrideWithValue(src),
          // R80: starting a session reads the resume checkpoint — memory DB.
          appDatabaseProvider.overrideWithValue(db),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('ابدأ التسجيل'));
    await _flush(tester);
    src.emit(accuracyM: 90.0);
    await _flush(tester);

    await tester.tap(find.text('إلغاء'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(src.startCalls, 1, reason: 'cancelling must not re-open the sensors');
    expect(src.stopCalls, 1);

    // And the way back in still works: cancel then start again.
    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pump();
    expect(src.startCalls, 2);
    await tester.tap(find.text('إلغاء'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(src.stopCalls, 2);
    await src.dispose();
  });
}

/// A stream listener added during a tap callback rebuilds only on the pump
/// after the one that runs the callback — one pump is not enough.
Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}
