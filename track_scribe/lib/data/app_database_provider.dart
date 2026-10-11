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

/// R86: the durable "has this install ever been onboarded" flag. [AppGate]
/// watches it to choose the first screen; production reads it from the real
/// (file-backed) database, tests from an in-memory one they seed or leave empty.
final onboardedProvider = FutureProvider<bool>(
  (ref) => ref.watch(activityRepositoryProvider).flag(kOnboardedFlag),
);
