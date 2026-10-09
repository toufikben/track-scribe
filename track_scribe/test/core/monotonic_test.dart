import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/core/monotonic.dart';

void main() {
  test('rejects a non-monotonic timestamp instead of corrupting duration', () {
    final t = MonotonicTicker();
    expect(t.accept(1000), isTrue);
    expect(t.accept(900), isFalse);   // clock went backwards → drop
    expect(t.accept(1000), isFalse);  // duplicate → drop
    expect(t.accept(3_000_000_000), isTrue);
    // _last=3_000_000_000; elapsed since the first valid sample (1000 ns) is
    // (3_000_000_000 - 1000)/1e9 = 2.999999 s exactly (brief said 3.0 - a slip).
    expect(t.secondsSince(1000), closeTo(2.999999, 1e-9));
  });
}
