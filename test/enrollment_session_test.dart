import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_pass/core/auth/enrollment_session.dart';
import 'package:operator_pass/core/ml/thresholds.dart';

import 'test_helpers.dart';

const t = Thresholds(unlock: .6, label: .5, outlier: .45);

/// Feeds frames 500 ms apart (pauses between prompts included) until the
/// capture phase ends or [maxFrames] is reached.
DateTime capture(EnrollmentSession s, Float32List Function() sample,
    {DateTime? start, int maxFrames = 200}) {
  var now = start ?? DateTime(2026);
  for (var i = 0; i < maxFrames && s.phase == EnrollPhase.capturing; i++) {
    now = now.add(const Duration(milliseconds: 500));
    s.onFrame(goodFrame(sample()), now);
  }
  return now;
}

void main() {
  test('happy path: 10 samples → verify → done', () {
    final me = randomUnit(128);
    final s = EnrollmentSession(thresholds: t, others: const []);
    var now = capture(s, () => near(me));
    expect(s.samples, hasLength(10));
    expect(s.phase, EnrollPhase.verifying);
    for (var i = 0; i < 3; i++) {
      now = now.add(const Duration(milliseconds: 100));
      s.onFrame(goodFrame(near(me)), now);
    }
    expect(s.phase, EnrollPhase.done);
    expect(s.result.length, greaterThanOrEqualTo(6));
  });

  test('pauses between prompts so the user can turn', () {
    final me = randomUnit(128);
    final s = EnrollmentSession(thresholds: t, others: const []);
    var now = DateTime(2026);
    s.onFrame(goodFrame(near(me)), now);
    now = now.add(const Duration(milliseconds: 500));
    s.onFrame(goodFrame(near(me)), now); // 2nd sample → prompt 2
    expect(s.promptIndex, 1);
    expect(s.pausedBetweenPrompts, isTrue);
    now = now.add(const Duration(milliseconds: 500));
    expect(s.onFrame(goodFrame(near(me)), now), isFalse); // still pausing
  });

  test('frames closer than 400 ms are not both captured', () {
    final me = randomUnit(128);
    final s = EnrollmentSession(thresholds: t, others: const []);
    final now = DateTime(2026);
    expect(s.onFrame(goodFrame(near(me)), now), isTrue);
    expect(s.onFrame(goodFrame(near(me)), now.add(const Duration(milliseconds: 100))), isFalse);
  });

  test('bad frames give a hint and are not captured', () {
    final s = EnrollmentSession(thresholds: t, others: const []);
    expect(s.onFrame(goodFrame(randomUnit(128), faces: 2), DateTime(2026)), isFalse);
    expect(s.hint, contains('Only one'));
    expect(s.samples, isEmpty);
  });

  test('blocks a face that is already registered', () {
    final me = randomUnit(128);
    final s = EnrollmentSession(
      thresholds: t,
      others: [Person('existing', [near(me), near(me)])],
    );
    capture(s, () => near(me));
    expect(s.phase, EnrollPhase.failed);
    expect(s.duplicateId, 'existing');
    expect(s.canRetry, isFalse);
  });

  test('inconsistent samples fail with a retry', () {
    final s = EnrollmentSession(thresholds: t, others: const []);
    capture(s, () => randomUnit(128));
    expect(s.phase, EnrollPhase.failed);
    expect(s.canRetry, isTrue);
    s.restart();
    expect(s.phase, EnrollPhase.capturing);
    expect(s.samples, isEmpty);
  });

  test('verification times out when someone else looks', () {
    final me = randomUnit(128);
    final s = EnrollmentSession(thresholds: t, others: const []);
    var now = capture(s, () => near(me));
    for (var i = 0; i < 30; i++) {
      now = now.add(const Duration(milliseconds: 500));
      s.onFrame(goodFrame(randomUnit(128)), now);
    }
    expect(s.phase, EnrollPhase.failed);
    expect(s.canRetry, isTrue);
  });
}
