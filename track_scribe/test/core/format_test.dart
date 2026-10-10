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
}
