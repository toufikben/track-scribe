/// Single source of truth for elapsed time. Never DateTime.now().
class MonotonicTicker {
  int _last = -1;
  int get lastNanos => _last;

  /// false → this sample cannot be trusted for durations (reorder or replay).
  bool accept(int nanos) {
    if (nanos <= _last) return false;
    _last = nanos;
    return true;
  }

  double secondsSince(int fromNanos) => (_last - fromNanos) / 1e9;
}
