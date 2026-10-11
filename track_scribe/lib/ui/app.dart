import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is the type ProviderScope takes; it is public in riverpod's
// secondary entry point, not in the main one.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:track_scribe/theme/theme.dart';
import 'package:track_scribe/ui/app_gate.dart';

/// The app root.
///
/// It owns its [ProviderScope] on purpose (Task 7): a bare `TrackScribeApp()`
/// boots in tests with no wrapper. That design has a consequence the app must
/// manage — a `ProviderScope` placed OUTSIDE this widget (i.e. in `main()`, as
/// `runApp(ProviderScope(overrides: [...], child: TrackScribeApp()))`) is a
/// different container than the one its widgets resolve providers through, so
/// such overrides can be silently ignored. Production overrides therefore enter
/// through [overrides] and are forwarded to the scope below, which is the only
/// scope the app's widgets can see. Guarded by
/// test/ui/app_overrides_test.dart.
class TrackScribeApp extends StatelessWidget {
  const TrackScribeApp({super.key, this.overrides = const <Override>[]});

  final List<Override> overrides;

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      title: 'Track Scribe',
      theme: AppTheme.dark,
      home: const AppGate(),
    ),
  );
}
