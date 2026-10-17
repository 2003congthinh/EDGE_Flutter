import 'dart:math';
import 'dart:typed_data';

import '../ml/matcher.dart';
import '../ml/ml_worker.dart';
import '../ml/quality.dart';
import '../ml/thresholds.dart';
import '../ml/vectors.dart';
import 'face_vote.dart';

enum EnrollPhase { capturing, verifying, done, failed }

/// The registration flow, frame by frame, with no UI:
/// 5 guided prompts × 2 good samples → drop outliers → duplicate check →
/// one more look to verify → done.
class EnrollmentSession {
  static const prompts = [
    'Look straight at the camera',
    'Turn your head slightly left',
    'Turn your head slightly right',
    'Tilt your chin up a little',
    'Tilt your chin down a little',
  ];

  final Thresholds thresholds;

  /// Everyone already registered except the person being (re-)scanned.
  final List<Enrolled> others;
  final int perPrompt, minKept;
  final Duration minGap, promptPause, verifyTimeout;

  EnrollmentSession({
    required this.thresholds,
    required this.others,
    this.perPrompt = 2,
    this.minKept = 6,
    this.minGap = const Duration(milliseconds: 400),
    this.promptPause = const Duration(milliseconds: 1200),
    this.verifyTimeout = const Duration(seconds: 10),
  });

  EnrollPhase phase = EnrollPhase.capturing;
  final samples = <Float32List>[];
  List<Float32List> result = const [];
  String? hint;
  String? failure;
  bool canRetry = true;
  String? duplicateId; // set when the face already belongs to someone else
  double? verifyScore;

  DateTime? _lastSample, _holdUntil, _verifyStart;
  final _vote = FaceVote(window: 5, need: 3);

  int get total => prompts.length * perPrompt;
  int get promptIndex => min(samples.length ~/ perPrompt, prompts.length - 1);
  bool get pausedBetweenPrompts => _holdUntil != null;

  String get instruction => switch (phase) {
        EnrollPhase.capturing => prompts[promptIndex],
        EnrollPhase.verifying => 'One more look to confirm',
        EnrollPhase.done => 'Face registered',
        EnrollPhase.failed => 'Registration stopped',
      };

  /// Feeds one processed frame. Returns true when a sample was captured.
  bool onFrame(FrameResult r, DateTime now) {
    switch (phase) {
      case EnrollPhase.capturing:
        return _capture(r, now);
      case EnrollPhase.verifying:
        _verify(r, now);
        return false;
      case EnrollPhase.done || EnrollPhase.failed:
        return false;
    }
  }

  bool _capture(FrameResult r, DateTime now) {
    final hold = _holdUntil;
    if (hold != null) {
      if (now.isBefore(hold)) {
        hint = null;
        return false;
      }
      _holdUntil = null;
    }
    hint = faceHint(r.faces, r.uprightW, r.uprightH, r.quality,
        limits: QualityLimits.enroll);
    final e = r.embedding;
    if (hint != null || e == null) return false;
    final last = _lastSample;
    if (last != null && now.difference(last) < minGap) return false;

    samples.add(e);
    _lastSample = now;
    if (samples.length >= total) {
      _finishCapture(now);
    } else if (samples.length % perPrompt == 0) {
      _holdUntil = now.add(promptPause); // time to turn for the next prompt
    }
    return true;
  }

  void _finishCapture(DateTime now) {
    final kept = dropOutliers(samples, minMean: thresholds.outlier);
    if (kept.length < minKept) {
      _fail("The light or your position changed too much between shots. "
          "Let's try again.");
      return;
    }
    for (final p in others) {
      if (setSimilarity(kept, p) >= thresholds.unlock) {
        duplicateId = p.id;
        _fail('This face is already registered.', retry: false);
        return;
      }
    }
    result = kept;
    phase = EnrollPhase.verifying;
    _verifyStart = now;
    hint = null;
  }

  void _verify(FrameResult r, DateTime now) {
    if (now.difference(_verifyStart!) > verifyTimeout) {
      _fail("We couldn't confirm the new scan. Let's try again.");
      return;
    }
    hint = faceHint(r.faces, r.uprightW, r.uprightH, r.quality,
        limits: QualityLimits.unlock);
    final e = r.embedding;
    if (hint != null || e == null) return;
    var best = -1.0;
    for (final s in result) {
      best = max(best, dot(e, s));
    }
    verifyScore = best;
    if (_vote.add(best >= thresholds.unlock)) phase = EnrollPhase.done;
  }

  void _fail(String reason, {bool retry = true}) {
    phase = EnrollPhase.failed;
    failure = reason;
    canRetry = retry;
    hint = null;
  }

  void restart() {
    phase = EnrollPhase.capturing;
    samples.clear();
    result = const [];
    hint = failure = duplicateId = null;
    verifyScore = null;
    canRetry = true;
    _lastSample = _holdUntil = _verifyStart = null;
    _vote.reset();
  }
}
