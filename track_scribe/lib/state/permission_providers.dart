import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:track_scribe/source/notification_permission.dart';

/// The two verifiable permission facts the instructions screen reads (R85 rows
/// 1 and 2), exposed as providers so a widget test can supply fakes and
/// `flutter test` never touches a platform channel — the same injectable-source
/// pattern Task 9a used for `GeolocatorFixSource` and `fixSourceProvider`.
/// Production leaves these defaults (the real `Geolocator` statics) untouched;
/// only tests override them.
final locationPermissionProvider =
    FutureProvider<LocationPermission>((ref) => Geolocator.checkPermission());

final locationServiceProvider =
    FutureProvider<bool>((ref) => Geolocator.isLocationServiceEnabled());

/// The settings pages the rows can open, carried as injectable function fields
/// for the same reason. The real calls return `Future<bool>`; the fields widen
/// to `Future<void>` because the screen never branches on that bool.
class PermissionActions {
  const PermissionActions({
    required this.request,
    required this.openAppSettings,
    required this.openLocationSettings,
  });

  final Future<LocationPermission> Function() request;
  final Future<void> Function() openAppSettings;
  final Future<void> Function() openLocationSettings;
}

/// The defaults are the real plugin statics. There is deliberately no
/// battery-optimization or autostart call here: none exists in geolocator
/// 14.1.1, so rows 3 and 4 are advisory and route to the app-info page instead
/// (R85).
final permissionActionsProvider = Provider<PermissionActions>(
  (ref) => PermissionActions(
    request: Geolocator.requestPermission,
    openAppSettings: Geolocator.openAppSettings,
    openLocationSettings: Geolocator.openLocationSettings,
  ),
);

/// The notification grant, as the same injectable pair. `geolocator` creates
/// the channel and posts the ongoing notification but never asks Android for
/// permission to show it, so this is the app's own call.
class NotificationActions {
  const NotificationActions({
    required this.isGranted,
    required this.request,
  });

  final Future<bool> Function() isGranted;
  final Future<bool> Function() request;
}

final notificationActionsProvider = Provider<NotificationActions>(
  (ref) => const NotificationActions(
    isGranted: NotificationPermissionChannel.isGranted,
    request: NotificationPermissionChannel.request,
  ),
);

final notificationPermissionProvider = FutureProvider<bool>(
  (ref) => ref.watch(notificationActionsProvider).isGranted(),
);
