import 'dart:math';

/// An axis-aligned face box in upright image pixels.
class Box {
  final double l, t, r, b, score;
  const Box(this.l, this.t, this.r, this.b, this.score);

  double get w => r - l;
  double get h => b - t;
  double get cx => (l + r) / 2;
  double get cy => (t + b) / 2;
  double get area => max(0.0, w) * max(0.0, h);

  /// Maps a box from tensor space to image space: `x * k + offset`.
  Box mapped(double k, double dx, double dy) =>
      Box(l * k + dx, t * k + dy, r * k + dx, b * k + dy, score);

  @override
  String toString() =>
      'Box(${l.toStringAsFixed(1)}, ${t.toStringAsFixed(1)}, '
      '${r.toStringAsFixed(1)}, ${b.toStringAsFixed(1)}, ${score.toStringAsFixed(2)})';
}

double iou(Box a, Box b) {
  final iw = max(0.0, min(a.r, b.r) - max(a.l, b.l));
  final ih = max(0.0, min(a.b, b.b) - max(a.t, b.t));
  final inter = iw * ih;
  return inter / (a.area + b.area - inter + 1e-9);
}

/// Greedy non-maximum suppression. Returns boxes sorted by score, best first.
List<Box> nms(List<Box> boxes, {double iouThreshold = .45}) {
  final sorted = [...boxes]..sort((a, b) => b.score.compareTo(a.score));
  final kept = <Box>[];
  for (final b in sorted) {
    if (kept.every((k) => iou(k, b) < iouThreshold)) kept.add(b);
  }
  return kept;
}
