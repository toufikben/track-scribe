import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:track_scribe/engine/raw_fix.dart';
import 'package:track_scribe/engine/recorder_engine.dart';
import 'package:track_scribe/engine/sport_config.dart';
import 'package:track_scribe/source/fix_source.dart';
import 'package:track_scribe/source/synthetic_fix_source.dart';

class RecordingState {
  const RecordingState({
    required this.sport,
    required this.phase,
    this.engine,
    this.distanceM = 0,
    this.elapsedNanos = 0,
    this.fixCount = 0,
  });

  final Sport sport;
  final RecordingPhase phase;
  final RecorderEngine? engine;
  final double distanceM;
  final int elapsedNanos;
  final int fixCount;

  RecordingState copyWith({
    Sport? sport,
    RecordingPhase? phase,
    RecorderEngine? engine,
  }) => RecordingState(
    sport: sport ?? this.sport,
    phase: phase ?? this.phase,
    engine: engine ?? this.engine,
    distanceM: distanceM,
    elapsedNanos: elapsedNanos,
    fixCount: fixCount,
  );
}

enum RecordingPhase { stopped, starting, recording }

final fixSourceProvider = Provider<FixSource>((_) => SyntheticFixSource());

class RecordingController extends Notifier<RecordingState> {
  @override
  RecordingState build() => RecordingState(
    sport: Sport.run,
    phase: RecordingPhase.stopped,
    engine: null,
  );

  StreamSubscription<RawFix>? _sub;

  void setSport(Sport s) {
    if (state.phase != RecordingPhase.stopped) return;
    state = state.copyWith(sport: s);
  }

  Future<void> start() async {
    if (state.phase != RecordingPhase.stopped) return;
    state = state.copyWith(phase: RecordingPhase.starting);
    final src = ref.read(fixSourceProvider);
    await src.start();
    _sub = src.fixes.listen(_onFix);
  }

  void _onFix(RawFix fix) {
    var e = state.engine;
    if (e == null) {
      e = RecorderEngine(
        SportConfig.forSport(state.sport),
        startNanos: fix.timeNanos,
      );
      state = state.copyWith(phase: RecordingPhase.recording, engine: e);
    }
    e.onFix(fix);
    // mutate through a fresh state object so Riverpod notifies listeners
    state = RecordingState(
      sport: state.sport,
      phase: state.phase,
      engine: e,
      distanceM: e.distanceMeters,
      elapsedNanos: e.elapsedNanos,
      fixCount: e.stats.fixCount,
    );
  }

  Future<void> stop() async {
    _sub?.cancel();
    _sub = null;
    await ref.read(fixSourceProvider).stop();
    state = RecordingState(
      sport: state.sport,
      phase: RecordingPhase.stopped,
      engine: null,
    );
  }
}

final recordingProvider = NotifierProvider<RecordingController, RecordingState>(
  RecordingController.new,
);
