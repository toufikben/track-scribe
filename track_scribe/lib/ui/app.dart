import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/theme/theme.dart';
import 'package:track_scribe/ui/recording/recording_screen.dart';

class TrackScribeApp extends StatelessWidget {
  const TrackScribeApp({super.key});

  @override
  Widget build(BuildContext context) => ProviderScope(
    // The app owns its ProviderScope so a bare `TrackScribeApp()` (as in
    // test/smoke_test.dart) boots straight into the recording screen.
    child: MaterialApp(
      title: 'Track Scribe',
      theme: AppTheme.dark,
      home: const RecordingScreen(),
    ),
  );
}
