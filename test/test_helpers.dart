import 'dart:math';
import 'dart:typed_data';

import 'package:operator_pass/core/ml/geometry.dart';
import 'package:operator_pass/core/ml/matcher.dart';
import 'package:operator_pass/core/ml/ml_worker.dart';
import 'package:operator_pass/core/ml/quality.dart';
import 'package:operator_pass/core/ml/vectors.dart';

final rng = Random(7);

Float32List randomUnit(int dim) =>
    l2Normalize(Float32List.fromList(List.generate(dim, (_) => rng.nextDouble() * 2 - 1)));

/// [base] plus a little noise: another sample of the same person.
Float32List near(Float32List base, {double noise = .15}) => l2Normalize(
    Float32List.fromList([for (final x in base) x + (rng.nextDouble() * 2 - 1) * noise / sqrt(base.length)]));

class Person implements Enrolled {
  @override
  final String id;
  @override
  final List<Float32List> embeddings;
  Person(this.id, this.embeddings);
}

/// A good, centred, single-face frame in a 480×640 upright image.
FrameResult goodFrame(Float32List? e, {int faces = 1}) => FrameResult(
      session: 1,
      uprightW: 480,
      uprightH: 640,
      faces: [
        for (var i = 0; i < faces; i++) Box(130.0 + i, 140, 350.0 + i, 420, .9),
      ],
      embedding: e,
      quality: const FaceQuality(120, 200),
      detMs: 0,
      embMs: 0,
      totalMs: 0,
    );
