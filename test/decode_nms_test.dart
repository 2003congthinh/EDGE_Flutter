import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_pass/core/ml/geometry.dart';
import 'package:operator_pass/core/ml/yolo.dart';

void main() {
  group('YoloHead.fromShape', () {
    test('YOLO11 channel-major [1, 5, 8400]', () {
      final h = YoloHead.fromShape([1, 5, 8400]);
      expect(h.layout, YoloLayout.channelsFirst);
      expect(h.candidates, 8400);
    });
    test('YOLO26 end-to-end [1, 300, 6]', () {
      expect(YoloHead.fromShape([1, 300, 6]).layout, YoloLayout.endToEnd);
    });
    test('transposed [1, 2100, 5]', () {
      expect(YoloHead.fromShape([1, 2100, 5]).layout, YoloLayout.channelsLast);
    });
  });

  test('decodes normalized channel-major output and suppresses overlaps', () {
    const n = 4;
    final o = Float32List(5 * n);
    void put(int i, double cx, double cy, double w, double h, double s) {
      o[i] = cx;
      o[n + i] = cy;
      o[2 * n + i] = w;
      o[3 * n + i] = h;
      o[4 * n + i] = s;
    }

    put(0, .5, .5, .2, .2, .9); // face A
    put(1, .51, .5, .2, .2, .8); // duplicate of A
    put(2, .2, .2, .1, .1, .7); // face B
    put(3, .8, .8, .1, .1, .1); // below threshold
    final boxes = decodeYolo(o, const YoloHead(YoloLayout.channelsFirst, n, 5),
        conf: .5, inputSize: 320);
    expect(boxes, hasLength(2));
    expect(boxes.first.score, closeTo(.9, 1e-6));
    expect(boxes.first.l, closeTo(.4 * 320, 1e-3)); // scaled to tensor pixels
    expect(boxes.first.r, closeTo(.6 * 320, 1e-3));
  });

  test('keeps pixel coordinates as they are', () {
    final o = Float32List.fromList([100, 120, 40, 60, .95]); // [1, 1, 5] row-major
    final boxes = decodeYolo(o, const YoloHead(YoloLayout.channelsLast, 1, 5),
        conf: .5, inputSize: 320);
    expect(boxes.single.l, closeTo(80, 1e-6));
    expect(boxes.single.b, closeTo(150, 1e-6));
  });

  test('end-to-end rows are xyxy and need no NMS', () {
    final o = Float32List.fromList([
      10, 20, 110, 140, .9, 0, //
      12, 22, 112, 142, .8, 0, // overlapping, but already filtered by the model
      0, 0, 0, 0, .01, 0,
    ]);
    final boxes = decodeYolo(o, const YoloHead(YoloLayout.endToEnd, 3, 6),
        conf: .5, inputSize: 320);
    expect(boxes, hasLength(2));
    expect(boxes.first.r, 110);
  });

  test('iou', () {
    const a = Box(0, 0, 10, 10, 1), b = Box(5, 0, 15, 10, 1);
    expect(iou(a, b), closeTo(50 / 150, 1e-6));
    expect(iou(a, const Box(20, 20, 30, 30, 1)), 0);
  });
}
