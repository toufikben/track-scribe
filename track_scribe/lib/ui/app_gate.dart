import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/data/app_database_provider.dart';
import 'package:track_scribe/state/recording_controller.dart';
import 'package:track_scribe/theme/palette.dart';
import 'package:track_scribe/ui/onboarding/permission_screen.dart';
import 'package:track_scribe/ui/recording/recording_screen.dart';

/// R86 routing gate: the first screen on a fresh install is the permission
/// instructions screen (spec §7), and it returns whenever a start was refused
/// for a denied permission — never a silently disabled button. An onboarded
/// install goes straight to the recorder.
class AppGate extends ConsumerWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.watch(onboardedProvider).value;
    final permissionDenied = ref.watch(recordingProvider).permissionDenied;
    if (permissionDenied || onboarded == false) {
      return PermissionScreen(
        onCompleted: () =>
            ref.read(recordingProvider.notifier).acknowledgePermission(),
      );
    }
    if (onboarded == null) {
      // The flag is still loading on the first frame: hold the background
      // instead of flashing a screen the flag would replace.
      return const Scaffold(backgroundColor: Palette.bg);
    }
    return const RecordingScreen();
  }
}
