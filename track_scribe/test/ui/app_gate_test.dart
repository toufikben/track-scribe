import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/source/geolocator_fix_source.dart';
import 'package:track_scribe/state/permission_providers.dart';
import 'package:track_scribe/state/recording_controller.dart';
import 'package:track_scribe/ui/app_gate.dart';
import 'package:track_scribe/ui/onboarding/permission_screen.dart';
import 'package:track_scribe/ui/recording/recording_screen.dart';
import '../support/controlled_fix_source.dart';

// R86 routing: the first screen is the permission instructions screen until the
// onboarded flag is set, and it returns whenever a start is refused for a denied
// permission — never a silently disabled button (spec §7).

/// A memory database with the onboarded flag already set to [value].
Future<AppDatabase> _dbWithFlag(bool value) async {
  final db = AppDatabase(NativeDatabase.memory());
  await ActivityRepository(db).setFlag(kOnboardedFlag, value);
  return db;
}

/// The probes PermissionScreen reads, faked so no test touches a platform
/// channel. Granted + service-on, so PermissionScreen would offer continue.
List<Override> _probeOverrides() => [
  locationPermissionProvider.overrideWith(
    (_) => Future.value(LocationPermission.whileInUse),
  ),
  locationServiceProvider.overrideWith((_) => Future.value(true)),
  permissionActionsProvider.overrideWithValue(
    PermissionActions(
      request: () async => LocationPermission.whileInUse,
      openAppSettings: () async {},
      openLocationSettings: () async {},
    ),
  ),
];

Widget _gate(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(theme: ThemeData.dark(), home: const AppGate()),
);

void main() {
  testWidgets('a fresh install (flag not seeded) opens on the permission screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1178, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final db = await _dbWithFlag(false);
    addTearDown(db.close);
    await tester.pumpWidget(
      _gate([
        appDatabaseProvider.overrideWithValue(db),
        ..._probeOverrides(),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PermissionScreen), findsOneWidget);
    expect(find.byType(RecordingScreen), findsNothing);
  });

  testWidgets('an onboarded install goes straight to the recording screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1178, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final db = await _dbWithFlag(true);
    addTearDown(db.close);
    await tester.pumpWidget(
      _gate([
        appDatabaseProvider.overrideWithValue(db),
        ..._probeOverrides(),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RecordingScreen), findsOneWidget);
    expect(find.byType(PermissionScreen), findsNothing);
  });

  testWidgets('completing onboarding sets the flag and goes straight through', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1178, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final db = await _dbWithFlag(false);
    addTearDown(db.close);
    await tester.pumpWidget(
      _gate([
        appDatabaseProvider.overrideWithValue(db),
        ..._probeOverrides(),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PermissionScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('perm-continue')));
    await tester.pumpAndSettle();

    expect(find.byType(PermissionScreen), findsNothing);
    expect(find.byType(RecordingScreen), findsOneWidget);
    expect(
      await ActivityRepository(db).flag(kOnboardedFlag),
      isTrue,
      reason: 'the flag really reached the database, so a relaunch skips '
          'onboarding too',
    );
  });

  testWidgets('a revoked permission mid-life routes back to the permission screen '
      'and leaves the phase stopped', (tester) async {
    tester.view.physicalSize = const Size(1178, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final db = await _dbWithFlag(true);
    addTearDown(db.close);
    final src = ControlledFixSource()
      ..startFailure = const LocationPermissionDenied();
    late ProviderContainer container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            fixSourceProvider.overrideWithValue(src),
            ..._probeOverrides(),
          ],
        ),
        child: MaterialApp(theme: ThemeData.dark(), home: const AppGate()),
      ),
    );
    addTearDown(container.dispose);
    await tester.pumpAndSettle();
    expect(find.byType(RecordingScreen), findsOneWidget);

    await tester.tap(find.text('ابدأ التسجيل'));
    await tester.pumpAndSettle();

    expect(
      find.byType(PermissionScreen),
      findsOneWidget,
      reason: 'R86: revoked permission shows the instructions screen, not a dead '
          'button',
    );
    expect(find.byType(RecordingScreen), findsNothing);
    expect(
      container.read(recordingProvider).phase,
      RecordingPhase.stopped,
      reason: 'the recorder is left usable once permission is granted again',
    );

    // The return flow: once the user has fixed the permission, completing
    // onboarding must clear the denial and hand them back to the recorder.
    src.startFailure = null;
    await tester.tap(find.byKey(const ValueKey('perm-continue')));
    await tester.pumpAndSettle();
    expect(find.byType(RecordingScreen), findsOneWidget);
    expect(find.byType(PermissionScreen), findsNothing);
    expect(
      container.read(recordingProvider).permissionDenied,
      isFalse,
      reason: 'acknowledgePermission() clears the stale denial, or the gate '
          'would keep routing to the instructions screen forever',
    );
    await src.dispose();
  });
}
