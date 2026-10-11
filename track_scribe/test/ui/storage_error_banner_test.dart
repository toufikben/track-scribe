import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/state/recording_controller.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/app.dart';

import '../support/controlled_fix_source.dart';

/// R78 §4: a storage failure must not kill the session, and the UI must stop
/// claiming durability while it lasts. The controller has published
/// `storageError` since Task 9b; these tests pin the other half of the rule —
/// that a user can actually see it. On the device round the failure path was
/// reached with zero visible trace, which is what this file exists to prevent.
const _warning = 'التسجيل مستمر، لكنّ النقاط لا تُحفظ.';

/// The first write refuses, the way a full or unwritable data directory does.
class _FailingRepository extends ActivityRepository {
  _FailingRepository(super.db);

  int insertCalls = 0;

  @override
  Future<int> insertActivity({
    required String uuid,
    required String sport,
    required int startWallMillis,
  }) async {
    insertCalls++;
    throw FileSystemException('No space left on device');
  }
}

Future<void> _mount(
  WidgetTester tester, {
  required AppDatabase db,
  required ActivityRepository repo,
  required ControlledFixSource src,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        activityRepositoryProvider.overrideWithValue(repo),
        fixSourceProvider.overrideWithValue(src),
      ],
      child: const TrackScribeApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('a storage failure shows the warning and the session keeps running (R78)', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    await ActivityRepository(db).setFlag(kOnboardedFlag, true);
    final repo = _FailingRepository(db);
    final src = ControlledFixSource();
    addTearDown(db.close);
    await _mount(tester, db: db, repo: repo, src: src);

    expect(find.text(_warning), findsNothing);

    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pump();
    src.emitMany(2, accuracyM: 3.0); // ر7 opens on the second fix
    src.emit(lat: 36.7540);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.insertCalls, greaterThan(0), reason: 'the write was attempted');
    final s = tester.element(find.byType(Scaffold).last);
    expect(
      find.text(_warning),
      findsOneWidget,
      reason: 'the failure is on screen, not only in state (R78)',
    );
    // The same rule's other half: the session is still recording, and the
    // warning is legible on the surface it is drawn over.
    expect(
      ProviderScope.containerOf(s).read(recordingProvider).phase,
      RecordingPhase.recording,
    );
    final banner = tester.widget<Material>(
      find
          .ancestor(
            of: find.text(_warning),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(banner.color, Palette.danger);
    expect(
      contrastRatio(Palette.danger, Palette.text),
      greaterThan(4.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the warning disappears when the session ends', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await ActivityRepository(db).setFlag(kOnboardedFlag, true);
    final repo = _FailingRepository(db);
    final src = ControlledFixSource();
    addTearDown(db.close);
    await _mount(tester, db: db, repo: repo, src: src);

    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pump();
    src.emitMany(2, accuracyM: 3.0);
    src.emit(lat: 36.7540);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(_warning), findsOneWidget);

    await tester.tap(find.text('إيقاف'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(_warning), findsNothing);
    expect(find.text('ابدأ التسجيل'), findsOneWidget);
  });
}
