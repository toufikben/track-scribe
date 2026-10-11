import 'package:gpx/gpx.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/recorder_engine.dart';
import 'package:track_scribe/engine/sport_config.dart';

/// The replay core, shared by `tool/replay.dart` and the golden test so both
/// read the production engine, never a copy of it.
///
/// Every track point of [xml] is fed through a fresh [RecorderEngine] in
/// timestamp order; wall-clock times become monotonic offsets from the first
/// point. GPX 1.1 carries no accuracy, so [accuracyM] supplies it (ruling
/// R95 — the fixture README documents the per-fixture value). Speed is left
/// to the engine's implied differencing, exactly as production does.
double engineDistanceFromGpx(
  String xml, {
  required Sport sport,
  double accuracyM = 5,
}) {
  final gpx = GpxReader().fromString(xml);
  final fixes = <RawFix>[];
  DateTime? t0;
  for (final trk in gpx.trks) {
    for (final seg in trk.trksegs) {
      for (final p in seg.trkpts) {
        final lat = p.lat;
        final lon = p.lon;
        if (lat == null || lon == null) continue;
        final t = p.time;
        if (t != null) t0 ??= t;
        if (t0 == null || t == null) continue;
        fixes.add(
          RawFix(
            lat: lat,
            lon: lon,
            timeNanos: t.difference(t0).inMicroseconds * 1000,
            accuracyM: accuracyM,
          ),
        );
      }
    }
  }
  if (fixes.isEmpty) {
    throw ArgumentError('the GPX carries no timestamped track points');
  }
  fixes.sort((a, b) => a.timeNanos.compareTo(b.timeNanos));
  final engine = RecorderEngine(
    SportConfig.forSport(sport),
    startNanos: fixes.first.timeNanos,
  );
  for (final f in fixes) {
    engine.onFix(f);
  }
  return engine.distanceMeters;
}

/// A deterministic synthetic line fixture (ruling R92): fixed-seed random
/// walk bounded at ±jitterM with per-step increments of jitterM/40, so the
/// noise keeps its ±10 m amplitude while no fix implies an impossible speed.
/// Ground truth is exact by construction — synthetic fixtures calibrate the
/// harness, they are never cited as device evidence.
List<Wpt> syntheticTrackPoints({
  required double metres,
  required double speedMps,
  required double jitterM,
  int seed = 42,
}) {
  final per = 1.0; // 1 Hz
  final steps = (metres / (speedMps * per)).ceil();
  final rng = _SeededRng(seed);
  var noise = 0.0;
  final base = DateTime.utc(2026, 1, 1);
  final out = <Wpt>[];
  for (var i = 0; i <= steps; i++) {
    noise = (noise + (rng.next() * 2 - 1) * (jitterM / 40))
        .clamp(-jitterM, jitterM)
        .toDouble();
    out.add(
      Wpt(
        lat: 36.7538 + (i * speedMps * per + noise) / 111111.0,
        lon: 3.1856,
        ele: 0,
        time: base.add(Duration(seconds: i)),
      ),
    );
  }
  return out;
}

/// Minimal deterministic LCG — enough for the fixture, no external package.
class _SeededRng {
  _SeededRng(this._state);
  int _state;
  double next() {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state / 0x7fffffff;
  }
}
