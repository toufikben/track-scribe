import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/sport_config.dart';
import 'package:track_scribe/state/recording_controller.dart';

import '../support/controlled_fix_source.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// Task 9b: the wire between the recorder and the repository. Rules in play:
/// ر13 (each point is written immediately, before the next one arrives),
/// ر12 (a killed session resumes from the checkpoint, distance not zero),
/// R78 (serialized writes with a persisted cursor; storage failure neither
/// kills the session nor goes unreported), R79 (the on-screen الوقت restarts
/// while المسافة carries) and R81 (the PERSISTED elapsed accumulates, so
/// `Activities.elapsedNanos` and `.distanceM` are totals of the same sessions).
void main() {
  test('every stored point reaches sqlite, and stop() finalizes the activity (ر13/ر12)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ActivityRepository(db);
    final src = ControlledFixSource()..stepNanos = 2000000000; // 2 s cadence
    final container = ProviderContainer(
      overrides: [
        fixSourceProvider.overrideWithValue(src),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(recordingProvider.notifier);

    await controller.start();
    src.emitMany(2, accuracyM: 3.0); // ر7 opens on the second fix
    var lat = 36.7538;
    for (var i = 0; i < 6; i++) {
      lat += 0.0001; // ~11.1 m per 2 s ≈ 5.6 m/s: real run distance
      src.emit(lat: lat);
    }
    await _settle(); // the stream delivers asynchronously; without this the
    // engine would still be null at the read below.
    final stored = container
        .read(recordingProvider)
        .engine!
        .storedPoints
        .length;
    expect(stored, greaterThan(1));

    // ر13: the checkpoint must catch up with the engine while the session is
    // still live — no batch-at-stop.
    final resume = await _waitForResumeCheckpoint(repo, (r) => r.distanceM > 0);
    if (resume == null) {
      fail('a resume checkpoint exists while recording (none appeared)');
    }
    expect(resume.distanceM, greaterThan(0));

    var count = 0;
    for (var i = 0; i < 250; i++) {
      count = await repo.pointCount(resume.activityId);
      if (count == stored) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(count, stored, reason: 'every stored point is in TrackPoints');

    await controller.stop();
    final row = await (db.select(
      db.activities,
    )..where((t) => t.id.equals(resume.activityId))).getSingle();
    expect(
      row.distanceM,
      greaterThan(0),
      reason: 'finishActivity wrote the distance',
    );
    expect(row.elapsedNanos, greaterThan(0));
    expect(row.fixCount, greaterThan(0));
    expect(
      await repo.loadResume(),
      isNull,
      reason: 'a clean stop clears the checkpoint',
    );
    await src.dispose();
  });

  test('the write chain never overlaps appendPoints (R78 §3): DB order == engine order', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = _CountingRepo(db);
    final src = ControlledFixSource()..stepNanos = 2000000000;
    final container = ProviderContainer(
      overrides: [
        fixSourceProvider.overrideWithValue(src),
        appDatabaseProvider.overrideWithValue(db),
        activityRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(recordingProvider.notifier);

    await controller.start();
    src.emitMany(2, accuracyM: 3.0);
    // A burst: every emit synchronously enqueues its slice while each
    // appendPoints still sleeps 10 ms — an unserialized fire-and-forget chain
    // would overlap here and drive maxConcurrent above 1.
    var lat = 36.7538;
    for (var i = 0; i < 12; i++) {
      lat += 0.0001;
      src.emit(lat: lat);
    }
    await _settle(); // stream delivery is async — see the first test
    final stored = container
        .read(recordingProvider)
        .engine!
        .storedPoints
        .length;

    var count = 0;
    for (var i = 0; i < 250; i++) {
      final resume = await ActivityRepository(db).loadResume();
      if (resume != null) count = await repo.pointCount(resume.activityId);
      if (count == stored) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(count, stored);
    expect(
      repo.appendCalls,
      greaterThan(1),
      reason: 'the points went through several per-point writes, not one blob',
    );
    expect(
      repo.maxConcurrent,
      1,
      reason:
          'appendPoints never overlaps: DB row order equals engine order (ر13)',
    );

    await controller.stop();
    await src.dispose();
  });

  test('a storage failure keeps the session recording and is reported, not swallowed (R78 §4)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = _FailingRepo(db);
    final src = ControlledFixSource()..stepNanos = 2000000000;
    final container = ProviderContainer(
      overrides: [
        fixSourceProvider.overrideWithValue(src),
        appDatabaseProvider.overrideWithValue(db),
        activityRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    final escaped = <Object>[];
    late RecordingController controller;
    var lat = 36.7538;
    var distanceAtFailure = 0.0;
    var distanceAfter = 0.0;
    var phaseAfter = RecordingPhase.stopped;

    await runZonedGuarded(() async {
      controller = container.read(recordingProvider.notifier);
      await controller.start();
      src.emitMany(2, accuracyM: 3.0);
      for (var i = 0; i < 4; i++) {
        lat += 0.0001;
        src.emit(lat: lat);
      }
      for (var i = 0; i < 250; i++) {
        if (container.read(recordingProvider).storageError != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      distanceAtFailure = container.read(recordingProvider).distanceM;
      // keep walking: the session must still record after the failure
      for (var i = 0; i < 3; i++) {
        lat += 0.0001;
        src.emit(lat: lat);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      distanceAfter = container.read(recordingProvider).distanceM;
      phaseAfter = container.read(recordingProvider).phase;
    }, (e, s) => escaped.add(e));

    final s = container.read(recordingProvider);
    expect(s.phase, RecordingPhase.recording);
    expect(
      s.storageError,
      isNotNull,
      reason: 'the UI must be able to stop claiming durability',
    );
    expect(
      distanceAfter,
      greaterThan(distanceAtFailure),
      reason: 'a write failure must not stop the recorder (a)',
    );
    expect(phaseAfter, RecordingPhase.recording);
    expect(
      escaped,
      isEmpty,
      reason: 'no unhandled async error may escape the write chain (c)',
    );

    await controller.stop();
    expect(container.read(recordingProvider).phase, RecordingPhase.stopped);
    await src.dispose();
  });

  test('only a session where ر7 opened owns an activity row — a failed start leaves none', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ActivityRepository(db);
    final src = ControlledFixSource()..stepNanos = 2000000000;
    final container = ProviderContainer(
      overrides: [
        fixSourceProvider.overrideWithValue(src),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(recordingProvider.notifier);

    // positive control first: a real session DOES create exactly one row
    // (this half is RED before the wiring exists, so the test cannot pass
    // vacuously).
    await controller.start();
    src.emitMany(2, accuracyM: 3.0);
    src.emit(lat: 36.7548);
    for (var i = 0; i < 250; i++) {
      if (await repo.loadResume() != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await controller.stop();
    expect((await db.select(db.activities).get()).length, 1);

    // now a session where ر7 never opens: nothing may be inserted.
    await controller.start();
    src.emitMany(4, accuracyM: 90); // none satisfies ر7
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await controller.stop();
    expect(
      (await db.select(db.activities).get()).length,
      1,
      reason: 'no orphan activity row from a session that never recorded',
    );
    expect(await repo.loadResume(), isNull);
    await src.dispose();
  });

  test('a killed session resumes: distance carries from the checkpoint, elapsed restarts (ر12/R79)', () async {
    // The closest local proof of ر12: a file-backed database in a temp dir,
    // closed mid-session without a clean stop — exactly the Task 8 ر13
    // reopen pattern (test/data/resume_test.dart) one level up.
    final dir = Directory.systemTemp.createTempSync('track_scribe_r12');
    final file = File(p.join(dir.path, 'kill_resume.sqlite'));
    AppDatabase? db2;
    try {
      // ---- session 1, then death ----
      final db1 = AppDatabase(NativeDatabase(file));
      addTearDown(db1.close);
      final repo1 = ActivityRepository(db1);
      final src1 = ControlledFixSource()..stepNanos = 2000000000;
      addTearDown(src1.dispose);
      final c1 = ProviderContainer(
        overrides: [
          fixSourceProvider.overrideWithValue(src1),
          appDatabaseProvider.overrideWithValue(db1),
        ],
      );
      final k1 = c1.read(recordingProvider.notifier);
      var lat = 36.7538;
      await k1.start();
      src1.emitMany(2, accuracyM: 3.0);
      for (var i = 0; i < 8; i++) {
        lat += 0.0001;
        src1.emit(lat: lat);
      }
      ResumeRow? checkpoint;
      var stored1 = 0;
      for (var i = 0; i < 250; i++) {
        final s = c1.read(recordingProvider);
        final engine = s.engine;
        checkpoint = await repo1.loadResume();
        if (engine != null && checkpoint != null) {
          stored1 = engine.storedPoints.length;
          if (checkpoint.distanceM == s.distanceM &&
              await repo1.pointCount(checkpoint.activityId) == stored1) {
            break;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(checkpoint, isNotNull, reason: 'session 1 wrote a checkpoint');
      final cp = checkpoint!;
      expect(cp.distanceM, greaterThan(0));
      final activityId1 = cp.activityId;
      final checkpointDistance = cp.distanceM;
      final checkpointLastTimeNanos = cp.lastStored.timeNanos;

      // the kill: the container goes away mid-recording and the database
      // connection simply dies — no stop(), no finishActivity.
      c1.dispose();
      await db1.close();

      // ---- session 2: fresh process, fresh everything ----
      // (Windows keeps a held sqlite file locked, so db2 is closed in the
      // finally below — addTearDown would run only AFTER the body already
      // tried to delete the directory.)
      db2 = AppDatabase(NativeDatabase(file));
      final repo2 = ActivityRepository(db2);
      final src2 = ControlledFixSource()..stepNanos = 2000000000;
      final c2 = ProviderContainer(
        overrides: [
          fixSourceProvider.overrideWithValue(src2),
          appDatabaseProvider.overrideWithValue(db2),
        ],
      );
      addTearDown(c2.dispose);
      final k2 = c2.read(recordingProvider.notifier);
      await k2.start();
      for (var i = 0; i < 2; i++) {
        src2.emit(
          lat: lat,
          accuracyM: 3.0,
        ); // ر7 re-opens at the checkpoint spot
      }
      for (var i = 0; i < 4; i++) {
        lat += 0.0001;
        src2.emit(lat: lat);
      }
      for (var i = 0; i < 250; i++) {
        if (c2.read(recordingProvider).distanceM > checkpointDistance) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final s2 = c2.read(recordingProvider);
      expect(
        s2.distanceM,
        greaterThan(checkpointDistance),
        reason: 'المسافة continues from the checkpoint, not from zero (ر12)',
      );
      // الر79 asymmetry, pinned on purpose: المسافة carries while the
      // ON-SCREEN الوقت restarts. The checkpoint holds a session-relative
      // lastTimeNanos that is meaningless in a new process, and wall clock is
      // banned for durations (ر1/R21). A future reader must NOT "fix" this with
      // a DateTime.now() subtraction. Session-only here is the counter the user
      // watches; the PERSISTED total accumulates across sessions (R81, pinned by
      // the next test) — that is a sum of measured durations, not a resumed
      // clock. If the on-screen counter were seeded from the checkpoint it would
      // start above the checkpoint's own last session-relative timestamp.
      expect(
        s2.elapsedNanos,
        lessThan(checkpointLastTimeNanos),
        reason: 'elapsed restarts near 0 instead of resuming (R79)',
      );

      final stored2 = s2.engine!.storedPoints.length;
      var total = 0;
      for (var i = 0; i < 250; i++) {
        total = await repo2.pointCount(activityId1);
        if (total == stored1 + stored2) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(
        total,
        stored1 + stored2,
        reason: 'the resumed session appends — it never re-writes or duplicates rows',
      );
      final r2 = await repo2.loadResume();
      expect(
        r2!.activityId,
        activityId1,
        reason: 'same activity, not a new row',
      );

      await k2.stop();
      await src2.dispose();
    } finally {
      await db2?.close();
      dir.deleteSync(recursive: true);
    }
  });

  test(
    'a resumed activity stores one TOTAL: every session\'s distance AND every '
    'session\'s elapsed (I-2/R81)',
    () async {
      // The ر12 defect is narrower than "time does not resume": the checkpoint
      // carried distance but not elapsed, so `finishActivity` wrote THIS
      // session's monotonic duration against ALL sessions' accumulated distance.
      // The row looks perfectly valid and every average-pace/speed number read
      // from it is wrong. Adding measured durations is not a ر1 violation
      // (wall clock is still never a duration source), so the total must be
      // carried through the checkpoint.
      final dir = Directory.systemTemp.createTempSync('track_scribe_r81');
      final file = File(p.join(dir.path, 'resume_elapsed.sqlite'));
      AppDatabase? db2;
      try {
        // ---- session 1, then death ----
        final db1 = AppDatabase(NativeDatabase(file));
        addTearDown(db1.close);
        final repo1 = ActivityRepository(db1);
        final src1 = ControlledFixSource()..stepNanos = 2000000000; // 2 s
        addTearDown(src1.dispose);
        final c1 = ProviderContainer(
          overrides: [
            fixSourceProvider.overrideWithValue(src1),
            appDatabaseProvider.overrideWithValue(db1),
          ],
        );
        final k1 = c1.read(recordingProvider.notifier);
        var lat = 36.7538;
        await k1.start();
        src1.emitMany(2, accuracyM: 3.0); // ر7 opens on the second fix
        for (var i = 0; i < 8; i++) {
          lat += 0.0001; // ~11.1 m / 2 s ≈ 5.6 m/s, under run v_max 6.0
          src1.emit(lat: lat);
        }
        await _settle(); // the burst is delivered asynchronously

        // Wait until the checkpoint equals the engine, so what session 1
        // persisted is exactly its own final totals (nothing later can move
        // them: no further fix arrives, and elapsed is fix-driven).
        ResumeRow? checkpoint;
        var elapsed1 = 0;
        var distance1 = 0.0;
        var stored1 = 0;
        for (var i = 0; i < 250; i++) {
          final s = c1.read(recordingProvider);
          checkpoint = await repo1.loadResume();
          if (checkpoint != null && s.engine != null) {
            final rows = await repo1.pointCount(checkpoint.activityId);
            if (checkpoint.distanceM == s.distanceM &&
                rows == s.engine!.storedPoints.length) {
              elapsed1 = s.elapsedNanos;
              distance1 = s.distanceM;
              stored1 = rows;
              break;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(checkpoint, isNotNull, reason: 'session 1 wrote a checkpoint');
        expect(elapsed1, greaterThan(0), reason: 'session 1 recorded time');
        final cp = checkpoint!;
        final activityId1 = cp.activityId;
        expect(distance1, greaterThan(0));
        // R81, the carrier: the killed session's own measured duration is
        // IN the checkpoint, next to the distance. Without this the resumed
        // total has nothing to add to.
        expect(
          cp.elapsedNanos,
          elapsed1,
          reason: 'the checkpoint persists the elapsed total (R81)',
        );

        // the kill: no stop(), no finishActivity()
        c1.dispose();
        await db1.close();

        // ---- session 2: fresh process, resumes, records a little, stops ----
        db2 = AppDatabase(NativeDatabase(file));
        final repo2 = ActivityRepository(db2);
        final src2 = ControlledFixSource()..stepNanos = 2000000000;
        addTearDown(src2.dispose);
        final c2 = ProviderContainer(
          overrides: [
            fixSourceProvider.overrideWithValue(src2),
            appDatabaseProvider.overrideWithValue(db2),
          ],
        );
        addTearDown(c2.dispose);
        final k2 = c2.read(recordingProvider.notifier);
        await k2.start();
        for (var i = 0; i < 2; i++) {
          src2.emit(lat: lat, accuracyM: 3.0); // ر7 re-opens at the checkpoint
        }
        for (var i = 0; i < 4; i++) {
          lat += 0.0001;
          src2.emit(lat: lat);
        }
        await _settle();
        // Wait until session 2's checkpoint has caught up with its engine, then
        // read both halves from that SAME state: what `stop()` writes must
        // equal these, and the checkpoint itself must already hold the TOTAL —
        // a third kill reads exactly this row back, so a per-session number
        // stored here would silently drop everything before it while a
        // two-session recording still stopped with a correct-looking row.
        var distanceTotal = 0.0;
        var elapsed2 = 0;
        ResumeRow? carried;
        for (var i = 0; i < 250; i++) {
          final s = c2.read(recordingProvider);
          final c = await repo2.loadResume();
          if (c != null &&
              s.engine != null &&
              c.distanceM == s.distanceM &&
              await repo2.pointCount(c.activityId) ==
                  stored1 + s.engine!.storedPoints.length) {
            carried = c;
            distanceTotal = s.distanceM;
            elapsed2 = s.elapsedNanos;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(carried, isNotNull, reason: 'the resumed session checkpointed');
        final cp2 = carried!;
        expect(
          distanceTotal,
          greaterThan(distance1),
          reason: 'session 2 resumed and then moved (ر12)',
        );
        expect(elapsed2, greaterThan(0));
        expect(
          cp2.elapsedNanos,
          elapsed1 + elapsed2,
          reason: 'R81: a resumed session writes the TOTAL into its checkpoint '
              '(distanceM has always been cumulative, so both halves of the '
              'checkpoint describe the same set of sessions)',
        );
        expect(
          cp2.distanceM,
          closeTo(distanceTotal, 1e-9),
          reason: 'the checkpoint pair is the engine state of one frame',
        );

        await k2.stop();

        final row =
            await (db2.select(
              db2.activities,
            )..where((t) => t.id.equals(activityId1))).getSingle();

        // Half 1 of the pair: distance is the accumulated total (this already
        // held at BASE — it is the half that made the row look believable).
        expect(
          row.distanceM,
          closeTo(distanceTotal, 1e-9),
          reason: 'Activities.distanceM is BOTH sessions\' distance',
        );
        // Half 2, the defect: elapsed must be the same total, i.e. session 1's
        // carried duration plus session 2's own. With the old code this is
        // session 2's `elapsedNanos` alone.
        expect(
          row.elapsedNanos,
          elapsed1 + elapsed2,
          reason:
              'Activities.elapsedNanos is the sum of the measured session '
              'durations (R81), not the resumed session\'s alone. Expected '
              'session1=$elapsed1 + session2=$elapsed2.',
        );
        // The PAIR is the claim: one session's time against all sessions'
        // distance yields an average speed this sport can not have produced.
        final impliedMps = row.distanceM / (row.elapsedNanos / 1e9);
        expect(
          impliedMps,
          lessThan(SportConfig.forSport(Sport.run).maxSpeedMps),
          reason:
              'distance and elapsed must describe the same recording: '
              'implied $impliedMps m/s exceeds a run\'s v_max, which is the '
              'signature of a mixed-total row.',
        );
        expect(
          await repo2.loadResume(),
          isNull,
          reason: 'the clean stop still cleared the checkpoint',
        );
      } finally {
        await db2?.close();
        dir.deleteSync(recursive: true);
      }
    },
  );

  test(
    'a saveResume throw after a committed slice leaves the checkpoint stale by '
    'exactly that slice — and writes no duplicate row (M-1/R83)',
    () async {
      // The accepted, bounded failure mode: appendPoints committed, the cursor
      // advanced, then the checkpoint write threw. The rows are durable, the
      // checkpoint is one slice behind, and the session keeps recording behind
      // an already-reported storage error. Re-ordering the two writes is worse
      // (a checkpoint pointing at rows that never landed), so the behaviour
      // stays — this test is the pin that it stays *this* way.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = _ResumeFailingRepo(db);
      final src = ControlledFixSource()..stepNanos = 2000000000;
      final container = ProviderContainer(
        overrides: [
          fixSourceProvider.overrideWithValue(src),
          appDatabaseProvider.overrideWithValue(db),
          activityRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(recordingProvider.notifier);

      await controller.start();
      src.emitMany(2, accuracyM: 3.0);
      var lat = 36.7538;
      // One fix per event-loop turn: the chain cuts its slice when a link RUNS,
      // so a burst folds every fix into a single link and gives `saveResume`
      // one call. Paced, each stored point is its own link — which is exactly
      // the per-point durability ر13 asks for.
      for (var i = 0; i < 6; i++) {
        lat += 0.0001;
        src.emit(lat: lat);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      for (var i = 0; i < 250; i++) {
        if (container.read(recordingProvider).storageError != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // (a) the throw is surfaced to the UI, not swallowed.
      expect(
        container.read(recordingProvider).storageError,
        isNotNull,
        reason: 'a checkpoint write failure must still be reported',
      );
      final checkpoint = await repo.loadResume();
      expect(
        checkpoint,
        isNotNull,
        reason: 'the earlier successful checkpoint is untouched',
      );
      final cp = checkpoint!;

      // (c) the session keeps recording after the throw.
      for (var i = 0; i < 6; i++) {
        lat += 0.0001;
        src.emit(lat: lat);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      final s = container.read(recordingProvider);
      expect(
        s.phase,
        RecordingPhase.recording,
        reason: 'a saveResume throw does not end the session',
      );

      final stored = s.engine!.storedPoints.length;
      var rows = 0;
      for (var i = 0; i < 250; i++) {
        rows = await repo.pointCount(cp.activityId);
        if (rows == stored) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      // (b) no duplicated rows: the cursor had already advanced, so the
      // committed slice is never re-written by the links that follow.
      expect(
        rows,
        stored,
        reason: 'every stored point exactly once — the committed slice is not '
            're-written after the checkpoint write threw',
      );
      final persisted =
          await (db.select(
            db.trackPoints,
          )..where((t) => t.activityId.equals(cp.activityId))).get();
      expect(
        persisted.length,
        persisted.map((r) => r.timeNanos).toSet().length,
        reason: 'no timeNanos appears twice: the write chain never re-emitted a '
            'slice (a rollback of the cursor would have)',
      );

      // The documented bound: the checkpoint is behind the engine by the slices
      // it failed to write, so a kill now loses their contribution to the
      // activity total — and only that, behind the error already reported.
      expect(
        cp.distanceM,
        lessThan(s.distanceM),
        reason: 'R83 bound: the surviving checkpoint is stale by exactly the '
            'slices whose saveResume threw',
      );

      await controller.stop();
      await src.dispose();
    },
  );

  test(
    'a repository throw while stop() drains the chain escapes nowhere and the '
    'resume row survives (M-2/R82)',
    () async {
      // `stop()` releases the session BEFORE awaiting the write chain, so a
      // link failing in that drain cannot set any state — the reset discards
      // it one statement later (ruling R82: log it, do not add a field). This
      // pins the two things that make that silence non-fatal: no unhandled
      // exception, and a checkpoint a later start can resume from.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = _StopDrainFailingRepo(db);
      final src = ControlledFixSource()..stepNanos = 2000000000;
      final container = ProviderContainer(
        overrides: [
          fixSourceProvider.overrideWithValue(src),
          appDatabaseProvider.overrideWithValue(db),
          activityRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final escaped = <Object>[];
      late RecordingController controller;
      var lat = 36.7538;
      var durableRowsBeforeDrain = 0;
      await runZonedGuarded(() async {
        controller = container.read(recordingProvider.notifier);
        await controller.start();
        src.emitMany(2, accuracyM: 3.0);
        for (var i = 0; i < 4; i++) {
          lat += 0.0001;
          src.emit(lat: lat);
        }
        // let the honest writes land, and wait for the checkpoint with them
        for (var i = 0; i < 250; i++) {
          final cp = await repo.loadResume();
          if (cp != null && cp.distanceM > 0) break;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        final cp = await repo.loadResume();
        expect(cp, isNotNull, reason: 'the session reached a checkpoint');
        durableRowsBeforeDrain = await repo.pointCount(cp!.activityId);
        expect(durableRowsBeforeDrain, greaterThan(0));

        // Now the drain is what fails: the next link sleeps, so it is still
        // queued when stop() has already released the session.
        repo.failWrites = true;
        lat += 0.0001;
        src.emit(lat: lat);
        await _settle(); // delivers the fix and starts the sleeping link
        await controller.stop();
      }, (e, s) => escaped.add(e));

      expect(
        escaped,
        isEmpty,
        reason: 'a failure inside the stop drain must not surface as an '
            'unhandled async error',
      );
      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.stopped,
        reason: 'and it must not strand the UI in a live phase',
      );

      // The recovery path the log message points at: the resume row is still
      // there, with the distance the durable links had reached.
      final survivor = await ActivityRepository(db).loadResume();
      expect(
        survivor,
        isNotNull,
        reason: 'the checkpoint survives a failed finalize — the next start '
            'resumes from it (R82)',
      );
      expect(survivor!.distanceM, greaterThan(0));
      expect(
        survivor.elapsedNanos,
        greaterThan(0),
        reason: 'the carried total is part of what survives (R81)',
      );
      expect(
        await repo.pointCount(survivor.activityId),
        durableRowsBeforeDrain,
        reason: 'nothing that was already durable is lost or re-written',
      );
      // The finalize threw, so the activity row keeps its untouched defaults
      // rather than a half-written total a reader would trust.
      final row =
          await (db.select(
            db.activities,
          )..where((t) => t.id.equals(survivor.activityId))).getSingle();
      expect(
        row.distanceM,
        0,
        reason: 'no partial total is persisted when finishActivity throws',
      );
      await src.dispose();
    },
  );
}

/// Polls [ActivityRepository.loadResume] until a checkpoint appears and
/// [test] accepts it; returns null if none ever did.
Future<ResumeRow?> _waitForResumeCheckpoint(
  ActivityRepository repo,
  bool Function(ResumeRow row) test,
) async {
  for (var i = 0; i < 250; i++) {
    final r = await repo.loadResume();
    if (r != null && test(r)) return r;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return null;
}

/// Counts concurrent `appendPoints` invocations: R78 §3 requires this to
/// never exceed 1, and each call is artificially slowed so an overlapping
/// (fire-and-forget) chain would be caught.
class _CountingRepo extends ActivityRepository {
  _CountingRepo(super.db);

  int appendCalls = 0;
  int maxConcurrent = 0;
  int _inFlight = 0;

  @override
  Future<void> appendPoints(int activityId, List<StoredPoint> points) async {
    appendCalls++;
    _inFlight++;
    if (_inFlight > maxConcurrent) maxConcurrent = _inFlight;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    try {
      await super.appendPoints(activityId, points);
    } finally {
      _inFlight--;
    }
  }
}

/// A storage layer that always rejects writes — the simulated disk full.
class _FailingRepo extends ActivityRepository {
  _FailingRepo(super.db);

  @override
  Future<void> appendPoints(int activityId, List<StoredPoint> points) {
    throw StateError('simulated storage failure');
  }
}

/// A storage layer whose `saveResume` lands [succeedFirst] times and throws
/// afterwards: the M-1/R83 case, where the points commit and the checkpoint
/// written right after them does not.
class _ResumeFailingRepo extends ActivityRepository {
  _ResumeFailingRepo(super.db);

  /// The first two checkpoints land (so a real, distance-bearing row exists),
  /// every write after them throws.
  static const int succeedFirst = 2;
  int _calls = 0;

  @override
  Future<void> saveResume({
    required int activityId,
    required StoredPoint lastStored,
    required double distanceM,
    required int elapsedNanos,
  }) async {
    _calls++;
    if (_calls <= succeedFirst) {
      await super.saveResume(
        activityId: activityId,
        lastStored: lastStored,
        distanceM: distanceM,
        elapsedNanos: elapsedNanos,
      );
      return;
    }
    throw StateError('simulated checkpoint write failure');
  }
}

/// A storage layer for the stop drain: once [failWrites] is set, `appendPoints`
/// sleeps before throwing (so the throw lands after `stop()` released the
/// session), and `finishActivity` always throws (so the resume row is never
/// cleared) — the M-2/R82 case.
class _StopDrainFailingRepo extends ActivityRepository {
  _StopDrainFailingRepo(super.db);

  bool failWrites = false;

  @override
  Future<void> appendPoints(int activityId, List<StoredPoint> points) async {
    if (!failWrites) {
      await super.appendPoints(activityId, points);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
    throw StateError('simulated failure inside the stop drain');
  }

  @override
  Future<void> finishActivity({
    required int activityId,
    required int elapsedNanos,
    required double distanceM,
    required int fixCount,
    required int rejectedCount,
    required bool mockDetected,
  }) async {
    throw StateError('simulated finalize failure');
  }
}
