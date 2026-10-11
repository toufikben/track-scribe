import 'package:flutter/material.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/data/database.dart';
import 'package:track_scribe/source/geolocator_fix_source.dart';
import 'package:track_scribe/state/recording_controller.dart';
import 'package:track_scribe/ui/app.dart';

/// The production wiring is the override set on the scope the app's own widgets
/// resolve through — `TrackScribeApp.overrides`. Wrapping the app in a second
/// `ProviderScope` here would build a different container and the app would
/// keep recording SyntheticFixSource's fake walk on a real phone (R72, guarded
/// by test/ui/app_overrides_test.dart).
void main() => runApp(
  TrackScribeApp(
    overrides: [
      fixSourceProvider.overrideWithValue(GeolocatorFixSource()),
      appDatabaseProvider.overrideWithValue(AppDatabase.open()),
    ],
  ),
);
