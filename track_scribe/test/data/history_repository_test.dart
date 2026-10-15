import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/activity_list_item.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/engine/raw_fix.dart';

/// A seed row with given start stamp and totals, written the way the recorder
/// writes them: insert, points, then finishActivity.
Future<int> _seed(
  ActivityRepository repo, {
  required int startWallMillis,
  double distanceM = 6400,
  int elapsedNanos = 2_000_000_000_000,
  String sport = 'run',
}) async {
  final id = await repo.insertActivity(
    uuid: 'uuid-$startWallMillis',
    sport: sport,
    startWallMillis: startWallMillis,
  );
  await repo.appendPoints(id, [
    StoredPoint(
      lat: 36.75,
      lon: 3.04,
      timeNanos: 0,
      accuracyM: 5,
      type: WaypointType.normal,
    ),
  ]);
  await repo.finishActivity(
    activityId: id,
    elapsedNanos: elapsedNanos,
    distanceM: distanceM,
    fixCount: 1,
    rejectedCount: 0,
    mockDetected: false,
  );
  return id;
}

void main() {
  late AppDatabase db;
  late ActivityRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ActivityRepository(db);
  });
  tearDown(() => db.close());

  test('a fresh install lists nothing', () async {
    expect(await repo.listActivities(), isEmpty);
  });

  test('lists newest start first, with the row totals', () async {
    await _seed(repo, startWallMillis: 1_700_000_000_000, distanceM: 1000);
    await _seed(repo, startWallMillis: 1_800_000_000_000, distanceM: 6400);
    await _seed(repo, startWallMillis: 1_750_000_000_000, distanceM: 300, sport: 'walk');

    final items = await repo.listActivities();
    expect(items.map((i) => i.startWallMillis), [
      1_800_000_000_000,
      1_750_000_000_000,
      1_700_000_000_000,
    ]);
    expect(items.map((i) => i.sport), ['run', 'walk', 'run']);
    expect(items.map((i) => i.distanceM), [6400, 300, 1000]);
    expect(items.first.elapsedNanos, 2_000_000_000_000);
    // Every field the row renders must be present; nothing else is invented.
    expect(items.first.isOpen, isFalse);
  });

  test('a soft-deleted activity is not listed', () async {
    final keep = await _seed(repo, startWallMillis: 1_700_000_000_000);
    final gone = await _seed(repo, startWallMillis: 1_800_000_000_000);
    await (db.update(db.activities)
          ..where((t) => t.id.equals(gone)))
        .write(const ActivitiesCompanion(isDeleted: Value(true)));

    final items = await repo.listActivities();
    expect(items.map((i) => i.id), [keep]);
  });

  // ر121: the checkpoint is what makes a row "still open" — a ColorOS kill
  // leaves the activity in the table, and hiding it would read as data loss.
  test('the activity a resume checkpoint still names is marked open', () async {
    final closed = await _seed(repo, startWallMillis: 1_700_000_000_000);
    final live = await repo.insertActivity(
      uuid: 'uuid-live',
      sport: 'bike',
      startWallMillis: 1_800_000_000_000,
    );
    await repo.saveResume(
      activityId: live,
      lastStored: StoredPoint(
        lat: 36.75,
        lon: 3.04,
        timeNanos: 0,
        accuracyM: 5,
        type: WaypointType.normal,
      ),
      distanceM: 120,
      elapsedNanos: 60_000_000_000,
    );

    final items = await repo.listActivities();
    expect(items.map((i) => (i.id, i.isOpen)), [(live, true), (closed, false)]);

    // And closing it removes the marker — the same checkpoint row the recorder
    // clears at stop.
    await repo.clearResume(live);
    final after = await repo.listActivities();
    expect(after.firstWhere((ActivityListItem i) => i.id == live).isOpen, isFalse);
  });
}
