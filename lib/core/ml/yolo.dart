import 'dart:math';
import 'dart:typed_data';

import 'geometry.dart';

enum YoloLayout {
  /// [1, 4 + classes, n]: cx, cy, w, h, class scores (YOLOv8/11 export). Needs NMS.
  channelsFirst,

  /// [1, n, 4 + classes]: the same, transposed.
  channelsLast,

  /// [1, n, 6]: x1, y1, x2, y2, score, class (YOLO26 end-to-end export). NMS done.
  endToEnd,
}

/// Describes a YOLO detection head from its output tensor shape, so a retrained
/// or re-exported model works without code changes.
class YoloHead {
  final YoloLayout layout;
  final int candidates; // number of anchor rows
  final int channels; // values per candidate

  const YoloHead(this.layout, this.candidates, this.channels);

  factory YoloHead.fromShape(List<int> shape) {
    final dims = shape.length == 3 ? shape.sublist(1) : shape;
    if (dims.length != 2) {
      throw ArgumentError('Unsupported detector output shape $shape');
    }
    final (a, b) = (dims[0], dims[1]);
    if (a < b && a >= 5) return YoloHead(YoloLayout.channelsFirst, b, a);
    if (b == 6 && a <= 1000) return YoloHead(YoloLayout.endToEnd, a, b);
    if (b >= 5) return YoloHead(YoloLayout.channelsLast, a, b);
    throw ArgumentError('Unsupported detector output shape $shape');
  }

  @override
  String toString() => '${layout.name} ${candidates}x$channels';
}

/// Decodes raw YOLO output into boxes in tensor pixels (0..[inputSize]).
/// Handles both normalized (0..1) and pixel outputs. Applies NMS when needed.
List<Box> decodeYolo(Float32List o, YoloHead head,
    {required double conf, required int inputSize, double iouThreshold = .45}) {
  final n = head.candidates, c = head.channels;
  final raw = <Box>[];

  double at(int i, int ch) => switch (head.layout) {
        YoloLayout.channelsFirst => o[ch * n + i],
        _ => o[i * c + ch],
      };

  for (var i = 0; i < n; i++) {
    double score;
    if (head.layout == YoloLayout.endToEnd) {
      score = at(i, 4);
    } else {
      score = at(i, 4);
      for (var ch = 5; ch < c; ch++) {
        score = max(score, at(i, ch));
      }
    }
    if (score < conf) continue;
    final a = at(i, 0), b = at(i, 1), cc = at(i, 2), d = at(i, 3);
    raw.add(head.layout == YoloLayout.endToEnd
        ? Box(a, b, cc, d, score)
        : Box(a - cc / 2, b - d / 2, a + cc / 2, b + d / 2, score));
  }
  if (raw.isEmpty) return raw;

  // Normalized outputs never exceed ~1; pixel outputs for any real face do.
  var maxCoord = 0.0;
  for (final x in raw) {
    maxCoord = max(maxCoord, max(x.r, x.b));
  }
  final k = maxCoord <= 1.5 ? inputSize.toDouble() : 1.0;
  final boxes = k == 1 ? raw : [for (final x in raw) x.mapped(k, 0, 0)];

  return head.layout == YoloLayout.endToEnd
      ? (boxes..sort((a, b) => b.score.compareTo(a.score)))
      : nms(boxes, iouThreshold: iouThreshold);
}
