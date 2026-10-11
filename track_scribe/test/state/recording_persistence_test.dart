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
import 'package:track_scribe/state/recording_controller.dart';

import '../support/controlled_fix_source.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// Task 9b: the wire between the recorder and the repository. Rules in play:
/// ر13 (each point is written immediately, before the next one arrives),
/// ر12 (a killed session resumes from the checkpoint, distance not zero),
/// R78 (serialized writes with a persisted cursor; storage failure neither
/// kills the session nor goes unreported), R79 (distance carries, elapsed
/// deliberately does not).
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
      // الر79 asymmetry, pinned on purpose: المسافة carries but الوقت
      // restarts. The checkpoint holds a session-relative lastTimeNanos that
      // is meaningless in a new process, and wall clock is banned for
      // durations (ر1/R21). A future reader must NOT "fix" this with a
      // DateTime.now() subtraction. If elapsed were carried (or re-seeded
      // from the checkpoint clock), it would start above the checkpoint's own
      // last session-relative timestamp.
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
