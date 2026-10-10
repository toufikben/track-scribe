import 'package:flutter/material.dart';
import 'package:track_scribe/state/recording_controller.dart';
import 'package:track_scribe/theme/palette.dart';

/// The single wide start/stop control (spec §5: ≥ 56 dp one-handed target).
///
/// R53 contrast ruling: `Palette.danger` may ONLY appear as a background
/// carrying `Palette.text` (the certified 6.08:1 pair) — the recording-state
/// stop button. Start is NOT red: `Palette.text` on `Palette.surface`.
class StopButton extends StatelessWidget {
  const StopButton({
    super.key,
    required this.phase,
    required this.onStart,
    required this.onStop,
    required this.onToggle,
  });

  final RecordingPhase phase;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    switch (phase) {
      case RecordingPhase.recording:
        return FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Palette.danger,
            foregroundColor: Palette.text,
            minimumSize: const Size.fromHeight(56),
          ),
          onPressed: onStop,
          child: const Text('إيقاف'),
        );
      case RecordingPhase.stopped:
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Palette.surface,
            foregroundColor: Palette.text,
            minimumSize: const Size.fromHeight(56),
          ),
          onPressed: onStart,
          child: const Text('ابدأ التسجيل'),
        );
      case RecordingPhase.starting:
        // Transient guard: the button is dead until the first fix promotes
        // the phase to recording (or the user stops).
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Palette.surface,
            foregroundColor: Palette.text,
            minimumSize: const Size.fromHeight(56),
          ),
          onPressed: null,
          child: const Text('ابدأ التسجيل'),
        );
    }
  }
}
