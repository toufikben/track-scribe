import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/database.dart';

/// R80: the controller depends on these providers, never on a concrete DB.
/// Production overrides `appDatabaseProvider` in `main.dart`; tests MUST
/// override it with `AppDatabase(NativeDatabase.memory())` or a file-backed
/// temp DB — `AppDatabase.open()` needs path_provider, which has no platform
/// in a unit test.
final appDatabaseProvider = Provider<AppDatabase>((_) => AppDatabase.open());

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => ActivityRepository(ref.watch(appDatabaseProvider)),
);
