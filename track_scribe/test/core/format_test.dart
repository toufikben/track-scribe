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

  // ر118: the month names are ours, not `intl`'s — the app rejected the locale
  // package in R23 and this label is the only date it needs.
  group('activityDate', () {
    test('prints day, Arabic month and year with a 24-hour clock', () {
      final stamp = DateTime(2026, 10, 15, 21, 33).millisecondsSinceEpoch;
      expect(
        Format.activityDate(stamp, now: DateTime(2026, 11, 2, 9)),
        '15 أكتوبر 2026 · 21:33',
      );
    });

    test('single-digit day and minute are not zero-padded in the day, padded in the clock', () {
      final stamp = DateTime(2026, 4, 5, 7, 3).millisecondsSinceEpoch;
      expect(
        Format.activityDate(stamp, now: DateTime(2026, 4, 20)),
        '5 أبريل 2026 · 07:03',
      );
    });

    // «اليوم»/«أمس» compare CALENDAR days: 23:50 → 00:10 is one day apart, not
    // 20 minutes, and the row must not claim an old activity happened today.
    test('today and yesterday use words, keyed on the calendar day', () {
      final lateNight = DateTime(2026, 10, 15, 23, 50).millisecondsSinceEpoch;
      expect(Format.activityDate(lateNight, now: DateTime(2026, 10, 15, 23, 55)), 'اليوم · 23:50');
      expect(Format.activityDate(lateNight, now: DateTime(2026, 10, 16, 0, 10)), 'أمس · 23:50');
      expect(
        Format.activityDate(lateNight, now: DateTime(2026, 10, 17)),
        '15 أكتوبر 2026 · 23:50',
      );
    });

    test('a stamp from twelve months back still resolves its month', () {
      final stamp = DateTime(2025, 10, 15, 8, 0).millisecondsSinceEpoch;
      expect(
        Format.activityDate(stamp, now: DateTime(2026, 10, 15)),
        '15 أكتوبر 2025 · 08:00',
      );
    });

    // ر118 buys us "no locale package" at the price of owning twelve strings.
    // This loop is the only thing that notices a transposition — the two
    // months the other tests happen to touch cannot.
    test('all twelve Arabic month names are in calendar order', () {
      const names = [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', //
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
      ];
      for (var m = 1; m <= 12; m++) {
        final stamp = DateTime(2026, m, 15, 12, 0).millisecondsSinceEpoch;
        expect(
          Format.activityDate(stamp, now: DateTime(2031, 1, 1)),
          '15 ${names[m - 1]} 2026 · 12:00',
          reason: 'month $m',
        );
      }
    });

    test('a future stamp is not called today', () {
      final stamp = DateTime(2026, 10, 16, 9).millisecondsSinceEpoch;
      expect(
        Format.activityDate(stamp, now: DateTime(2026, 10, 15)),
        '16 أكتوبر 2026 · 09:00',
      );
    });

    test('now defaults to the device clock', () {
      expect(Format.activityDate(DateTime.now().millisecondsSinceEpoch), startsWith('اليوم'));
    });
  });
}
