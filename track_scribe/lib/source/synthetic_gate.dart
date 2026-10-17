import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:track_scribe/source/fix_source.dart';
import 'package:track_scribe/source/geolocator_fix_source.dart';
import 'package:track_scribe/source/synthetic_fix_source.dart';

/// Borrow 1أ of `docs/BORROW-FROM-TRAILMARK.md`: the behaviour is trailmark's
/// `app/gps/SyntheticFixSource.kt`, which `MainActivity` turns on with
/// `adb shell am start --ez synthetic true`. This device refuses mock location
/// (`cmd location … add-test-provider` was rejected), so the switch has to live
/// inside the app for ر105/ر106 and the map §2/§3 rows to be measurable on a
/// table instead of waiting for a street walk.
///
/// Only the decision and the probe are public; `main()` calls [resolveFixSource]
/// and nothing else, so the debug rule cannot be re-implemented by accident.

/// The file that turns the synthetic walk on, read from the app's own
/// documents directory:
/// `adb shell run-as dev.toufik.track_scribe sh -c 'touch <docs>/synthetic.mode'`.
const String kSyntheticMarkerName = 'synthetic.mode';

/// The whole rule, with no filesystem and no platform in it.
///
/// A release build ignores the marker: a `synthetic.mode` left behind on a
/// customer's phone must not silently replace their GPS. That half is the
/// reason this is a pure function — it is the line the test suite pins.
FixSource chooseFixSource({
  required bool debugMode,
  required bool markerPresent,
}) => debugMode && markerPresent
    ? SyntheticFixSource()
    : GeolocatorFixSource();

/// Does the marker exist? Any failure — no platform channel, no permission, a
/// documents path that cannot be read — answers `false`.
///
/// This probe runs on the boot path, so a throw here would be a crash before
/// the first frame over a switch the app was never going to use.
Future<bool> syntheticMarkerPresent({
  Future<Directory> Function() documentsDirectory = getApplicationDocumentsDirectory,
}) async {
  try {
    final dir = await documentsDirectory();
    return await File(p.join(dir.path, kSyntheticMarkerName)).exists();
  } on Object catch (_) {
    return false;
  }
}

/// What `main()` awaits: the real GNSS unless this is a debug build that was
/// handed the marker file.
///
/// The probe is only made when [kDebugMode] — a store build never touches the
/// filesystem for a switch it cannot honour, and there is no simulation affordance
/// in its UI, its assets or its code path.
Future<FixSource> resolveFixSource() async => chooseFixSource(
  debugMode: kDebugMode,
  markerPresent: kDebugMode ? await syntheticMarkerPresent() : false,
);
