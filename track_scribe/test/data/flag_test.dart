import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/database.dart';

// Step 1 (spec §7 / R86): the persisted "has been onboarded" flag that decides
// whether the first screen is the permission instructions screen or the
// recording screen.
void main() {
  test('the onboarded flag round-trips through the in-memory database', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = ActivityRepository(db);

    expect(
      await repo.flag(kOnboardedFlag),
      false,
      reason: 'a fresh install has never been onboarded',
    );

    await repo.setFlag(kOnboardedFlag, true);
    expect(await repo.flag(kOnboardedFlag), true);

    await repo.setFlag(kOnboardedFlag, false);
    expect(await repo.flag(kOnboardedFlag), false);

    await db.close();
  });

  test('an unknown flag key reads its own default', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = ActivityRepository(db);
    expect(await repo.flag('never-written', defaultValue: true), true);
    expect(await repo.flag('never-written'), false);
    await db.close();
  });

  test(
    'a flag set on a file-backed database survives close/reopen (R86: this '
    'really survived, same proof bar as the ر13 durability test)',
    () async {
      // NativeDatabase.memory() proves nothing about durability — a read on the
      // same in-process connection would return the value even if it never
      // reached storage. Reopening the same FILE is the only honest proof, so
      // this mirrors test/data/resume_test.dart:79-113.
      final dir = Directory.systemTemp.createTempSync('track_scribe_flag');
      final file = File(p.join(dir.path, 'flags.sqlite'));
      try {
        final db = AppDatabase(NativeDatabase(file));
        await ActivityRepository(db).setFlag(kOnboardedFlag, true);
        await db.close();

        final reopened = AppDatabase(NativeDatabase(file));
        try {
          expect(
            await ActivityRepository(reopened).flag(kOnboardedFlag),
            true,
            reason: 'the reopened connection can only see what was flushed',
          );
        } finally {
          await reopened.close();
        }
      } finally {
        dir.deleteSync(recursive: true);
      }
    },
  );
}
