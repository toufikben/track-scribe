import 'dart:async';

import 'package:geolocator/geolocator.dart' as gl;
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/source/fix_source.dart';

export 'package:track_scribe/source/gps_quality.dart';

/// Thrown by [GeolocatorFixSource.start] when the user has not granted
/// while-in-use location access. Recording cannot begin, so the UI must show
/// the permission path (Task 9b's onboarding) rather than a spinner.
class LocationPermissionDenied implements Exception {
  const LocationPermissionDenied();
}

/// Production [FixSource]: the device's GNSS, mapped onto [RawFix].
///
/// The plugin call path is injected rather than hard-wired, so every rule in
/// this file — the settings we ask Android for, the field mapping, the
/// permission failure path and the restart contract — is verifiable with
/// `flutter test` on a desktop, with no phone and no platform channel. The
/// defaults are the real `Geolocator` statics.
///
/// What the settings are, and why (rulings R67/R69; the brief's plain
/// `LocationSettings(accuracy: high, distanceFilter: 0)` would have shipped
/// three of them wrong):
///
/// * `intervalDuration: 200 ms` — `geolocator_android` documents that a *null*
///   interval means 5000 ms, i.e. 0.2 Hz. The engine's store gate, jump
///   rejection and 15 s heartbeat would all be fed one fix per ~5 s.
/// * `forceLocationManager: true` — the legacy LocationManager/GPS path: no
///   FusedLocationProvider smoothing or batching (the spec forbids cosmetic
///   filtering of stored data) and no runtime dependence on Google Play
///   Services. The plugin itself still falls back to LocationManager when Play
///   Services are absent, so forcing it cannot hard-fail on a device.
/// * `foregroundNotificationConfig` with `enableWakeLock` — without a wake lock
///   the CPU sleeps at screen-off and a screen-off walk records a straight
///   line, which is exactly the spec's own field test.
/// * `useMSLAltitude` stays false: geoid alignment is Plan 2's DEM work.
class GeolocatorFixSource implements FixSource {
  GeolocatorFixSource({
    Future<gl.LocationPermission> Function()? checkPermission,
    Future<gl.LocationPermission> Function()? requestPermission,
    Stream<gl.Position> Function(gl.LocationSettings settings)? positionStream,
  }) : _checkPermission =
           checkPermission ?? gl.Geolocator.checkPermission,
       _requestPermission =
           requestPermission ?? gl.Geolocator.requestPermission,
       _positionStream =
           positionStream ??
           ((settings) => gl.Geolocator.getPositionStream(
             locationSettings: settings,
           ));

  final Future<gl.LocationPermission> Function() _checkPermission;
  final Future<gl.LocationPermission> Function() _requestPermission;
  final Stream<gl.Position> Function(
    gl.LocationSettings settings,
  )
  _positionStream;

  StreamController<RawFix>? _out;
  StreamSubscription<gl.Position>? _sub;
  final Stopwatch _clock = Stopwatch();

  /// The live output controller, created on first use. Deliberately NOT closed
  /// by [stop]: a listener that subscribed before a stop/start cycle must keep
  /// receiving (see the restart contract on [FixSource]).
  StreamController<RawFix> _stream() =>
      _out ??= StreamController<RawFix>.broadcast();

  @override
  Stream<RawFix> get fixes => _stream().stream;

  @override
  Future<void> start() async {
    var permission = await _checkPermission();
    if (permission != gl.LocationPermission.whileInUse &&
        permission != gl.LocationPermission.always) {
      permission = await _requestPermission();
    }
    if (permission == gl.LocationPermission.denied ||
        permission == gl.LocationPermission.deniedForever) {
      throw const LocationPermissionDenied();
    }

    final out = _stream();
    // A previous stop() cancelled _sub, but a start() without a stop() must
    // never leave two sensors feeding one controller.
    await _sub?.cancel();
    _sub = null;

    _clock.start();
    _sub = _positionStream(_androidSettings()).listen(
      (p) => out.add(_toRawFix(p)),
      onError: out.addError,
      cancelOnError: false,
    );
  }

  @override
  Future<void> stop() async {
    // Only the plugin subscription is cancelled: the GNSS stream is the battery
    // and the sensor, the output controller costs nothing and must survive.
    final sub = _sub;
    _sub = null;
    if (sub != null) await sub.cancel();
    _clock.stop();
  }

  static gl.LocationSettings _androidSettings() => gl.AndroidSettings(
    accuracy: gl.LocationAccuracy.high,
    distanceFilter: 0,
    intervalDuration: const Duration(milliseconds: 200),
    forceLocationManager: true,
    foregroundNotificationConfig: const gl.ForegroundNotificationConfig(
      enableWakeLock: true,
      setOngoing: true,
      notificationTitle: 'تسجيل المسار',
      notificationText: 'track_scribe يسجّل مسارك',
      notificationChannelName: 'تسجيل المسار',
    ),
  );

  /// `geolocator_platform_interface`'s `Position` stamps arrival with the
  /// device's wall clock and carries no `elapsedRealtimeNanos`, and both
  /// `isMocked` and `timestamp` are non-nullable there (R70) — so monotonic
  /// time is taken from this source's own [Stopwatch] and the platform instant
  /// is kept only as the display-side `wallMillis` (ر1).
  ///
  /// `hasX` matters more than it looks: Android omits a field the platform
  /// could not measure and the model substitutes `0.0` for it. A `speed` of
  /// 0.0 that was never measured would tell ر6 the user is standing still and
  /// freeze the distance, so unavailable measurements are mapped to null and
  /// the engine falls back to the values it can derive.
  RawFix _toRawFix(gl.Position p) => RawFix(
    lat: p.latitude,
    lon: p.longitude,
    timeNanos: _clock.elapsedMicroseconds * 1000,
    accuracyM: p.accuracy,
    altitudeM: p.hasAltitude ? p.altitude : null,
    speedMps: p.hasSpeed ? p.speed : null,
    bearingDeg: p.hasHeading ? p.heading : null,
    isMocked: p.isMocked,
    wallMillis: p.timestamp.millisecondsSinceEpoch,
  );
}
