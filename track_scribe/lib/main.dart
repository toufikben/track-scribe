import 'package:flutter/material.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/source/synthetic_gate.dart';
import 'package:track_scribe/state/recording_controller.dart';
import 'package:track_scribe/ui/app.dart';

/// The production wiring is the override set on the scope the app's own widgets
/// resolve through — `TrackScribeApp.overrides`. Wrapping the app in a second
/// `ProviderScope` here would build a different container and the app would
/// keep recording SyntheticFixSource's fake walk on a real phone (R72, guarded
/// by test/ui/app_overrides_test.dart).
///
/// The fix source is no longer hard-wired: [resolveFixSource] returns
/// `GeolocatorFixSource` unless this is a debug build holding the
/// `synthetic.mode` marker (borrow 1أ, `docs/BORROW-FROM-TRAILMARK.md`). The
/// marker is read before the first frame, hence `ensureInitialized` —
/// path_provider needs a binding, and `runApp` would only have created its own
/// afterwards.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final source = await resolveFixSource();
  runApp(
    TrackScribeApp(
      overrides: [
        fixSourceProvider.overrideWithValue(source),
        appDatabaseProvider.overrideWithValue(AppDatabase.open()),
      ],
    ),
  );
}
