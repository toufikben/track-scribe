import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:track_scribe/data/activity_repository.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/state/permission_providers.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/theme/theme.dart';
import 'package:track_scribe/ui/onboarding/permission_screen.dart';

// R85 row titles, verbatim.
const _t1 = 'إذن الموقع أثناء الاستخدام';
const _t2 = 'خدمة تحديد الموقع مفعّلة';
const _t3 = 'البطارية: بلا قيود';
const _t4 = 'التشغيل التلقائي في realme';
const _granted = 'تم';
const _off = 'غير مُفعّل';
const _unverifiable = 'لا يمكن التحقق';
const _continue = 'الدخول إلى التسجيل';
const _reason = 'أكمِل الصفّين الأوّلين للمتابعة';
const _realmePath =
    'الإعدادات → إدارة التطبيقات → track_scribe → السماح بالتشغيل التلقائي';

/// A [PermissionActions] the test counts calls on, exactly the way
/// `controlled_fix_source.dart` counts `startCalls`.
class _FakeActions {
  int requestCalls = 0;
  int appSettingsCalls = 0;
  int locationSettingsCalls = 0;
  LocationPermission nextRequest = LocationPermission.whileInUse;

  PermissionActions build() => PermissionActions(
    request: () async {
      requestCalls++;
      return nextRequest;
    },
    openAppSettings: () async {
      appSettingsCalls++;
    },
    openLocationSettings: () async {
      locationSettingsCalls++;
    },
  );
}

/// Mounts the screen over fake probes. `permission` is read lazily so a test
/// can change it and let the screen's post-request invalidate re-read the new
/// value.
Future<void> _mount(
  WidgetTester tester, {
  required LocationPermission Function() permission,
  required bool service,
  bool Function()? serviceProbe,
  required PermissionActions actions,
  bool pendingProbes = false,
  bool failWrites = false,
  bool notifications = false,
  VoidCallback? onCompleted,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        if (failWrites)
          activityRepositoryProvider.overrideWithValue(_FailingRepository(db)),
        if (pendingProbes)
          // A never-completing future, not a delayed one: no timer is left
          // pending at teardown, and the row is genuinely still unknown.
          locationPermissionProvider.overrideWith(
            (_) => Completer<LocationPermission>().future,
          )
        else
          locationPermissionProvider.overrideWith(
            (_) => Future.value(permission()),
          ),
        locationServiceProvider.overrideWith(
          (_) => Future.value(serviceProbe == null ? service : serviceProbe()),
        ),
        permissionActionsProvider.overrideWithValue(actions),
        // The fifth row is covered by its own file; here it is pinned to one
        // known answer so the four-row state counts stay honest.
        notificationActionsProvider.overrideWithValue(
          NotificationActions(
            isGranted: () async => notifications,
            request: () async => notifications,
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: PermissionScreen(onCompleted: onCompleted),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FailingRepository extends ActivityRepository {
  _FailingRepository(super.db);

  @override
  Future<void> setFlag(String key, bool value) async {
    throw StateError('storage refuses the write');
  }
}

LocationPermission _alwaysGranted() => LocationPermission.whileInUse;

void main() {
  testWidgets('the four R85 rows render, in order, with the granted/service states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1178, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _mount(
      tester,
      permission: _alwaysGranted,
      service: true,
      actions: _FakeActions().build(),
    );

    expect(find.text(_t1), findsOneWidget);
    expect(find.text(_t2), findsOneWidget);
    expect(find.text(_t3), findsOneWidget);
    expect(find.text(_t4), findsOneWidget);

    // Rows 1+2 verified-true; the two advisory rows never claim a verified
    // state (the project forbids pretending to know).
    expect(find.text(_granted), findsNWidgets(2), reason: 'rows 1 and 2');
    expect(find.text(_unverifiable), findsNWidgets(2), reason: 'rows 3 and 4');
    expect(
      find.text(_off),
      findsNWidgets(1),
      reason: 'row 5 only — its probe is the notification grant, pinned off here',
    );
  });

  testWidgets('denied permission reads as off and denied-forever as off too', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1178, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _mount(
      tester,
      permission: () => LocationPermission.denied,
      service: false,
      actions: _FakeActions().build(),
    );

    // Row 1 off, row 2 off, row 5 off; the two advisory rows still `لا يمكن التحقق`.
    expect(find.text(_off), findsNWidgets(3));
    expect(find.text(_granted), findsNothing);
    expect(find.text(_unverifiable), findsNWidgets(2));
  });

  testWidgets('an unknown permission probe reads as لا يمكن التحقق, never as off', (
    tester,
  ) async {
    // "We have not asked yet / the platform cannot tell us" is not a
    // negative. Row 1 must not print `غير مُفعّل` off an unknown, or the app
    // states a fact it never measured.
    tester.view.physicalSize = const Size(1178, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    for (final (label, probe, pending) in [
      ('a probe that has not returned', LocationPermission.whileInUse, true),
      (
        'unableToDetermine',
        LocationPermission.unableToDetermine,
        false,
      ),
    ]) {
      await _mount(
        tester,
        permission: () => probe,
        service: true,
        actions: _FakeActions().build(),
        pendingProbes: pending,
      );
      expect(
        find.text(_off),
        findsNWidgets(1),
        reason:
            'row 5 (the pinned-off notification grant) is the only `off` — '
            '$label is not evidence of off',
      );
      expect(
        find.text(_unverifiable),
        findsNWidgets(3),
        reason: 'rows 1, 3 and 4 at $label',
      );
      expect(
        find.text(_granted),
        findsOneWidget,
        reason: 'row 2 (service on) at $label',
      );
      expect(
        tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, _continue),
        ).enabled,
        isFalse,
        reason: 'an unknown permission cannot unlock the app',
      );
    }
  });

  testWidgets('a refused flag write says so instead of doing nothing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1178, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    var completed = 0;
    await _mount(
      tester,
      permission: _alwaysGranted,
      service: true,
      actions: _FakeActions().build(),
      failWrites: true,
      onCompleted: () => completed++,
    );

    await tester.tap(
      find.widgetWithText(ElevatedButton, _continue),
    );
    await tester.pump();
    expect(
      find.text('تعذّر حفظ الإعدادات — أعد المحاولة.'),
      findsOneWidget,
      reason: 'the write failed out loud',
    );
    expect(completed, 0, reason: 'never route on an unpersisted flag');
    // Let the snack bar's own timer expire so nothing is pending at teardown.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('the continue button is disabled with a visible reason while rows 1+2 '
      'are not satisfied (spec §7: never a silent disable)', (tester) async {
    tester.view.physicalSize = const Size(1178, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    // Service on but permission denied: still not satisfied.
    await _mount(
      tester,
      permission: () => LocationPermission.denied,
      service: true,
      actions: _FakeActions().build(),
    );
    expect(
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, _continue))
          .enabled,
      isFalse,
    );
    expect(find.text(_reason), findsOneWidget);
  });

  testWidgets('the continue button is enabled and the reason line is gone once rows '
      '1+2 are both satisfied', (tester) async {
    tester.view.physicalSize = const Size(1178, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _mount(
      tester,
      permission: _alwaysGranted,
      service: true,
      actions: _FakeActions().build(),
    );
    expect(
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, _continue))
          .enabled,
      isTrue,
    );
    expect(find.text(_reason), findsNothing);
  });

  testWidgets('deniedForever routes row 1 to open app settings, not a request dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1178, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final actions = _FakeActions();
    await _mount(
      tester,
      permission: () => LocationPermission.deniedForever,
      service: true,
      actions: actions.build(),
    );

    await tester.tap(find.byKey(const ValueKey('perm-action-1')));
    await tester.pumpAndSettle();

    expect(
      actions.appSettingsCalls,
      1,
      reason: 'the system will not show the dialog again, so open app settings',
    );
    expect(actions.requestCalls, 0);
  });

  testWidgets('a granted request re-reads the state so the row flips to تم without '
      'a restart', (tester) async {
    tester.view.physicalSize = const Size(1178, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    var permission = LocationPermission.denied;
    final actions = _FakeActions()..nextRequest = LocationPermission.whileInUse;
    await _mount(
      tester,
      permission: () => permission,
      service: true,
      actions: actions.build(),
    );

    expect(find.text(_t1), findsOneWidget);
    // Row 1 starts off and row 5 (notifications) is pinned off; only row 2 is
    // granted (service on).
    expect(find.text(_off), findsNWidgets(2), reason: 'rows 1 and 5');
    expect(find.text(_granted), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('perm-action-1')));
    // The request fake grants; the screen invalidates the probe afterwards.
    permission = LocationPermission.whileInUse;
    await tester.pumpAndSettle();

    expect(actions.requestCalls, 1);
    // Now rows 1 and 2 both read granted; row 5 stays off because row 5 has
    // its own action and is never touched by granting location permission.
    expect(find.text(_granted), findsNWidgets(2));
    expect(find.text(_off), findsOneWidget);
  });

  testWidgets('each row action calls its injected function exactly once', (
    tester,
  ) async {
    // Tall viewport so every row button is on-screen (a tap at an off-screen
    // center is a hit-test miss, not a call).
    tester.view.physicalSize = const Size(1178, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final actions = _FakeActions();
    await _mount(
      tester,
      permission: () => LocationPermission.denied,
      service: false,
      actions: actions.build(),
    );

    await tester.tap(find.byKey(const ValueKey('perm-action-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perm-action-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perm-action-3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('perm-action-4')));
    await tester.pumpAndSettle();

    expect(actions.requestCalls, 1, reason: 'row 1 requests permission');
    expect(actions.locationSettingsCalls, 1, reason: 'row 2 opens location settings');
    expect(actions.appSettingsCalls, 2, reason: 'rows 3 and 4 open app settings');
  });

  testWidgets('the advisory rows carry the verbatim Realme path text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1178, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _mount(
      tester,
      permission: _alwaysGranted,
      service: true,
      actions: _FakeActions().build(),
    );
    expect(find.textContaining(_realmePath, findRichText: true), findsOneWidget);
  });

  testWidgets('every button is a >= 48 dp touch target', (tester) async {
    tester.view.physicalSize = const Size(1178, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _mount(
      tester,
      permission: _alwaysGranted,
      service: true,
      actions: _FakeActions().build(),
    );
    for (final key in ['perm-action-1', 'perm-action-2', 'perm-action-3', 'perm-action-4', 'perm-continue']) {
      final h = tester.getSize(find.byKey(ValueKey(key))).height;
      expect(h, greaterThanOrEqualTo(48), reason: '$key is only ${h}dp tall');
    }
  });

  for (final widthDp in <double>[360.0, 392.7, 411.0]) {
    testWidgets('the screen lays out without overflow at ${widthDp}dp', (
      tester,
    ) async {
      tester.view.physicalSize = Size(widthDp * 2.75, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await _mount(
        tester,
        permission: () => LocationPermission.deniedForever,
        service: false,
        actions: _FakeActions().build(),
      );
      // R58 lesson: long Arabic strings must not overflow or collide.
      expect(tester.takeException(), isNull, reason: 'renders at ${widthDp}dp');
      expect(find.text(_t1), findsOneWidget);
      expect(find.text(_t4), findsOneWidget);
    });
  }

  testWidgets('no state badge uses danger as a foreground colour, and every badge '
      'clears the contrast law on the row surface', (tester) async {
    tester.view.physicalSize = const Size(1178, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await _mount(
      tester,
      permission: () => LocationPermission.denied,
      service: false,
      actions: _FakeActions().build(),
    );
    for (final word in [_granted, _off, _unverifiable]) {
      final matches = find.text(word);
      if (matches.evaluate().isEmpty) continue;
      final color = tester.widget<Text>(matches.first).style!.color!;
      expect(color, isNot(Palette.danger), reason: '$word must not be danger text');
      expect(
        contrastRatio(color, Palette.surface),
        greaterThan(4.5),
        reason: '$word must be readable on the surface card',
      );
    }
  });

  testWidgets('coming back from the system settings re-reads the two GPS probes',
      (tester) async {
    // Device-found on the realme: GPS was switched on from the shade while this
    // screen sat open, and row 2 kept reading «غير مُفعّل» until a full app
    // restart. The gate must re-probe when the app returns to the foreground.
    tester.view.physicalSize = const Size(1178, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    var service = false;
    var permissionCalls = 0;
    await _mount(
      tester,
      permission: () {
        permissionCalls++;
        return LocationPermission.whileInUse;
      },
      service: false,
      serviceProbe: () => service,
      actions: _FakeActions().build(),
    );

    expect(find.text(_off), findsNWidgets(2), reason: 'row 2 (service) + row 5');
    expect(permissionCalls, 1);

    service = true;
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text(_granted), findsNWidgets(2), reason: 'rows 1 and 2');
    expect(find.text(_off), findsOneWidget, reason: 'row 5 only');
    expect(permissionCalls, 2, reason: 'the permission probe re-reads as well');
  });
}
