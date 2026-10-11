import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/ui/app.dart';

/// R86: home is AppGate — an unseeded DB would boot into PermissionScreen.
Future<AppDatabase> _seededDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await ActivityRepository(db).setFlag(kOnboardedFlag, true);
  return db;
}

void main() {
  testWidgets('app boots into the recording screen', (tester) async {
    final db = await _seededDb();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const TrackScribeApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('تسجيل'), findsOneWidget);
  });
}
