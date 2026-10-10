import 'package:track_scribe/engine/raw_fix.dart';

/// A source of GPS fixes. The recording screen only ever consumes fixes
/// through this interface: Task 7 drives it with [SyntheticFixSource] so the
/// UI is testable with no phone; Task 9 swaps in the real GNSS source behind
/// the same interface (rulings R18/R22).
abstract class FixSource {
  /// Emits fixes once [start] has been called. Implementations must keep
  /// emitting on a later `start()` after a `stop()`: recording twice in one
  /// app session is an ordinary gesture, not an edge case.
  Stream<RawFix> get fixes;
  Future<void> start();
  Future<void> stop();
}
