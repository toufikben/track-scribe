import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/state/recording_controller.dart';
import 'package:track_scribe/theme/palette.dart';

/// R78 §4's user-facing half: while a storage write is failing, the recorder
/// keeps recording — so it must stop claiming that the points are saved.
/// Nothing else in the UI says this; before it existed, a device session that
/// persisted nothing looked exactly like a healthy one.
const kStorageFailureWarning = 'التسجيل مستمر، لكنّ النقاط لا تُحفظ.';

/// Renders nothing while storage is healthy, so the caller can place it
/// unconditionally. `danger` is a background with `text` on it — the one pair
/// the contrast law certifies for red (spec §5), and it is asserted here as
/// well as in test/ui/storage_error_banner_test.dart.
class StorageErrorBanner extends ConsumerWidget {
  const StorageErrorBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(recordingProvider).storageError == null) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Palette.danger,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          kStorageFailureWarning,
          style: const TextStyle(
            color: Palette.text,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
