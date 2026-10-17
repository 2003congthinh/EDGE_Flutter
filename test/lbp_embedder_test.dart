import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_pass/core/ml/embedder.dart';
import 'package:operator_pass/core/ml/vectors.dart';

Uint8List texture(int seed, {double gain = 1, int offset = 0}) {
  final r = Random(seed);
  final base = List.generate(64 * 64, (_) => r.nextInt(200));
  return Uint8List.fromList([for (final v in base) (v * gain + offset).round().clamp(0, 255)]);
}

void main() {
  test('placeholder embedding is unit length and stable', () {
    final a = LbpEmbedder.lbpFeatures(texture(1), 64);
    expect(dot(a, a), closeTo(1, 1e-5));
    expect(a.length, LbpEmbedder().dim);
  });

  test('LBP ignores uniform brightness changes but separates textures', () {
    final a = LbpEmbedder.lbpFeatures(texture(1), 64);
    final brighter = LbpEmbedder.lbpFeatures(texture(1, offset: 40), 64);
    final other = LbpEmbedder.lbpFeatures(texture(2), 64);
    expect(dot(a, brighter), greaterThan(.98));
    expect(dot(a, other), lessThan(dot(a, brighter)));
  });
}
