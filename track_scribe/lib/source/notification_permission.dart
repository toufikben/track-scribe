import 'package:flutter/services.dart';

/// The one platform call the recorder needs outside `geolocator`.
///
/// Android 13 made `POST_NOTIFICATIONS` a runtime permission. The app declares
/// it in the manifest, but declaring is not asking: on the device round the
/// recording notification was enqueued and never posted (`granted=false`,
/// `numPostedByApp=0`), so the user had no outside-app sign that a recording
/// was live. `MainActivity` answers `check`/`request` over this channel and
/// the permission screen asks through it.
///
/// A missing channel (a unit test, a desktop host) reports `false` rather than
/// throwing: the row is advisory, and the worst case is an honest `غير مُفعّل`.
class NotificationPermissionChannel {
  const NotificationPermissionChannel._();

  static const MethodChannel _channel = MethodChannel(
    'dev.toufik.track_scribe/notifications',
  );

  static Future<bool> isGranted() => _ask('check');

  static Future<bool> request() => _ask('request');

  static Future<bool> _ask(String method) async {
    try {
      return await _channel.invokeMethod<int>(method) == 1;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
