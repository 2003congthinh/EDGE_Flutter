import 'package:flutter_test/flutter_test.dart';
import 'package:operator_pass/core/auth/face_vote.dart';
import 'package:operator_pass/core/auth/owner_check.dart';
import 'package:operator_pass/core/ml/matcher.dart';
import 'package:operator_pass/core/ml/quality.dart';
import 'package:operator_pass/core/ml/thresholds.dart';
import 'package:operator_pass/core/ml/vectors.dart';

import 'test_helpers.dart';

void main() {
  const t = Thresholds(unlock: .6, label: .5, outlier: .45);

  test('bestMatch finds the right person and rejects strangers', () {
    final a = randomUnit(128), b = randomUnit(128);
    final gallery = [
      Person('a', [near(a), near(a)]),
      Person('b', [near(b)]),
    ];
    final m = bestMatch(near(a), gallery, threshold: t.unlock);
    expect(m.id, 'a');
    expect(m.score, greaterThan(.9));
    final stranger = bestMatch(randomUnit(128), gallery, threshold: t.unlock);
    expect(stranger.id, isNull);
    expect(stranger.bestId, isNotNull);
  });

  test('dropOutliers removes the sample that disagrees', () {
    final a = randomUnit(128);
    final samples = [for (var i = 0; i < 8; i++) near(a), randomUnit(128)];
    final kept = dropOutliers(samples, minMean: .45);
    expect(kept, hasLength(8));
    expect(kept.contains(samples.last), isFalse);
  });

  test('blob round trip keeps the vector', () {
    final v = randomUnit(192);
    expect(fromBlob(toBlob(v)), v);
  });

  test('FaceVote needs 4 of the last 6', () {
    final v = FaceVote();
    for (final ok in [true, false, true, false, true]) {
      expect(v.add(ok), isFalse);
    }
    expect(v.add(true), isTrue);
    v.reset();
    // Old hits slide out of the window.
    for (final ok in [true, true, true, false, false, false, false]) {
      v.add(ok);
    }
    expect(v.passed, isFalse);
  });

  group('checkOwnerFrame', () {
    final owner = randomUnit(128), other = randomUnit(128);
    final gallery = [
      Person('owner', [near(owner)]),
      Person('op', [near(other)]),
    ];

    test('accepts the owner', () {
      expect(checkOwnerFrame(goodFrame(near(owner)), gallery, 'owner', t).ok, isTrue);
    });
    test('rejects another registered person', () {
      expect(checkOwnerFrame(goodFrame(near(other)), gallery, 'owner', t).ok, isFalse);
    });
    test('rejects two faces in view', () {
      final v = checkOwnerFrame(goodFrame(near(owner), faces: 2), gallery, 'owner', t);
      expect(v.ok, isFalse);
      expect(v.hint, contains('Only one'));
    });
  });

  test('faceHint asks the user to fix framing', () {
    expect(faceHint(goodFrame(null).faces, 480, 640, const FaceQuality(120, 200)), isNull);
    expect(faceHint(const [], 480, 640, null), contains('circle'));
    expect(faceHint(goodFrame(null).faces, 480, 640, const FaceQuality(20, 200)),
        contains('dark'));
  });
}
