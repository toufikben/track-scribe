import 'package:flutter_test/flutter_test.dart';
import 'package:track_scribe/core/format.dart';

void main() {
  test('decimal separator is a token, never a hard-coded character', () {
    expect(Format.distance(4230, sep: ','), '4,23');
    expect(Format.distance(4230, sep: '.'), '4.23');
    expect(Format.distance(430, sep: ','), '0,43');
  });
  test('pace uses m:ss', () {
    expect(Format.pace(321.5, sep: ','), '5:21');
    expect(Format.pace(double.nan, sep: ','), '--:--');
  });
  test('duration hides hours when zero', () {
    expect(Format.duration(22 * 60 * 1000000000), '22:00');
    expect(Format.duration((36 * 60 + 2) * 60 * 1000000000), '36:02:00');
  });

  // I-2: distance and elapsed time are monotonic accumulations, so nothing in
  // the app feeds these a negative. No sign-handling code is added — instead a
  // future delta-style caller must fail loudly rather than get a plausible
  // lie, which is what the old body produced: -500 m printed '-1,50' (floor
  // sends -0.5 km to -1, so the fraction silently gains a kilometre) and
  // -1e9 ns printed '59:59' (Dart's % is non-negative).
  test('negative distance fails loudly instead of lying quietly', () {
    expect(() => Format.distance(-500, sep: ','), throwsAssertionError);
  });
  test('negative duration fails loudly instead of lying quietly', () {
    expect(() => Format.duration(-1000000000), throwsAssertionError);
  });
}
