import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/state/permission_providers.dart';
import 'package:track_scribe/theme/theme.dart';
import 'package:track_scribe/ui/onboarding/permission_screen.dart';

/// The fifth row, added from the device round's measurement: `POST_NOTIFICATIONS`
/// is declared in the manifest but was never requested, so the recording
/// notification was enqueued and never posted (`granted=false`,
/// `numPostedByApp=0`). The row is ADVISORY — it never gates المتابعة, because
/// the same device test showed a screen-off recording keeps storing points
/// with notifications denied.
const _t5 = 'إشعار التسجيل';
const _granted = 'تم';
const _off = 'غير مُفعّل';
const _continue = 'الدخول إلى التسجيل';

class _FakeNotifications {
  _FakeNotifications({this.granted = false});

  bool granted;
  int checkCalls = 0;
  int requestCalls = 0;
  bool requestResult = true;

  NotificationActions build() => NotificationActions(
    isGranted: () async {
      checkCalls++;
      return granted;
    },
    request: () async {
      requestCalls++;
      granted = requestResult;
      return granted;
    },
  );
}

Future<void> _mount(
  WidgetTester tester, {
  required NotificationActions notifications,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await ActivityRepository(db).setFlag(kOnboardedFlag, true);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        locationPermissionProvider.overrideWith(
          (ref) => Future.value(LocationPermission.whileInUse),
        ),
        locationServiceProvider.overrideWith((ref) => Future.value(true)),
        permissionActionsProvider.overrideWithValue(
          PermissionActions(
            request: () async => LocationPermission.whileInUse,
            openAppSettings: () async {},
            openLocationSettings: () async {},
          ),
        ),
        notificationActionsProvider.overrideWithValue(notifications),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const PermissionScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('the notification row reports the real grant state', (tester) async {
    final fake = _FakeNotifications(granted: false);
    await _mount(tester, notifications: fake.build());

    expect(find.text(_t5), findsOneWidget);
    expect(find.text(_off), findsOneWidget);
    expect(fake.checkCalls, greaterThan(0));
  });

  testWidgets('its action asks once and the row re-reads to تم', (tester) async {
    final fake = _FakeNotifications(granted: false);
    await _mount(tester, notifications: fake.build());

    final action = find.byKey(const ValueKey('perm-action-5'));
    await tester.ensureVisible(action);
    await tester.pump();
    await tester.tap(action);
    await tester.pump(const Duration(milliseconds: 400));

    expect(fake.requestCalls, 1);
    // Rows 1, 2 and 5 are granted by then — the fifth row is what makes three.
    expect(find.text(_granted), findsNWidgets(3));
  });

  testWidgets('a denied notification never blocks المتابعة', (tester) async {
    final fake = _FakeNotifications(granted: false)..requestResult = false;
    await _mount(tester, notifications: fake.build());

    final action = find.byKey(const ValueKey('perm-action-5'));
    await tester.ensureVisible(action);
    await tester.pump();
    await tester.tap(action);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(_off), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('perm-continue')),
    );
    expect(button.onPressed, isNotNull, reason: 'notifications are not a gate');
    expect(find.text(_continue), findsOneWidget);
  });
}
