import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

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
/// battery-optimization, notification-permission or autostart call here: none
/// exists in geolocator 14.1.1, so rows 3 and 4 are advisory and route to the
/// app-info page instead (R85).
final permissionActionsProvider = Provider<PermissionActions>(
  (ref) => PermissionActions(
    request: Geolocator.requestPermission,
    openAppSettings: Geolocator.openAppSettings,
    openLocationSettings: Geolocator.openLocationSettings,
  ),
);
