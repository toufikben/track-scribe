import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/engine/sport_config.dart';
import 'package:track_scribe/state/recording_controller.dart';
import 'package:track_scribe/theme/palette.dart';

/// مشي / جري / دراجة floating over the map. Selected chip is accent-onAccent;
/// the rest are surface with secondary text. Disabled while a session is
/// live — switching sport mid-recording would silently change the engine
/// constants under the running RecorderEngine.
class SportChips extends ConsumerWidget {
  const SportChips({super.key});

  static const _entries = [
    (Sport.walk, 'مشي'),
    (Sport.run, 'جري'),
    (Sport.bike, 'دراجة'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(recordingProvider);
    final controller = ref.read(recordingProvider.notifier);
    final enabled = s.phase == RecordingPhase.stopped;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (sport, label) in _entries)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: ChoiceChip(
              label: Text(label),
              selected: s.sport == sport,
              onSelected: enabled ? (_) => controller.setSport(sport) : null,
              selectedColor: Palette.accent,
              backgroundColor: Palette.surface,
              disabledColor: Palette.surface,
              labelStyle: TextStyle(
                color: s.sport == sport
                    ? Palette.onAccent
                    : Palette.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}
