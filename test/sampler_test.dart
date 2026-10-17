import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:operator_pass/core/ml/frame_data.dart';
import 'package:operator_pass/core/ml/sampler.dart';

/// A 4×2 sensor image whose Y value is its index, with neutral chroma.
FrameData frame(int rotation) {
  const w = 4, h = 2;
  return FrameData(
    width: w,
    height: h,
    rotation: rotation,
    y: Uint8List.fromList(List.generate(w * h, (i) => i * 10)),
    u: Uint8List.fromList(List.filled(4, 128)),
    v: Uint8List.fromList(List.filled(4, 128)),
    yRowStride: w,
    uvRowStride: 2,
    uvPixelStride: 1,
  );
}

int sensorY(FrameData f, int sx, int sy) => f.y[sy * f.yRowStride + sx];

void main() {
  test('upright size swaps for 90 and 270', () {
    expect((frame(270).uprightW, frame(270).uprightH), (2, 4));
    expect((frame(0).uprightW, frame(0).uprightH), (4, 2));
  });

  test('rotation 270 (front camera): upright top-left is sensor top-right', () {
    final f = frame(270);
    expect(toSensor(0, 0, f), (3, 0));
    expect(toSensor(1, 0, f), (3, 1)); // upright top-right = sensor bottom-right
    expect(toSensor(0, 3, f), (0, 0));
  });

  test('rotation 90 (back camera): upright top-left is sensor bottom-left', () {
    final f = frame(90);
    expect(toSensor(0, 0, f), (0, 1));
    expect(toSensor(1, 0, f), (0, 0));
  });

  test('sampleGray reads the rotated image', () {
    for (final rot in [0, 90, 180, 270]) {
      final f = frame(rot);
      final out = Uint8List(4);
      // 2×2 output covering the upright top-left 2×2 pixels.
      sampleGray(f, const Region(0, 0, 2), 2, out);
      for (var py = 0; py < 2; py++) {
        for (var px = 0; px < 2; px++) {
          final (sx, sy) = toSensor(px, py, f);
          expect(out[py * 2 + px], sensorY(f, sx, sy), reason: 'rot $rot at ($px,$py)');
        }
      }
    }
  });

  test('sampleRgb: neutral chroma gives grey, outside pixels get the fill', () {
    final f = frame(0);
    final out = Float32List(3 * 3 * 3);
    // Region starting one pixel left of the image: first column is padding.
    sampleRgb(f, const Region(-1, 0, 3), 3, out, mean: 0, std: 1, fill: 114);
    expect(out.sublist(0, 3), [114, 114, 114]);
    expect(out.sublist(3, 6), [0, 0, 0]); // sensor (0,0) = 0
    expect(out.sublist(6, 9), [10, 10, 10]); // sensor (1,0) = 10
  });

  test('sampleRgb flipX mirrors horizontally', () {
    final f = frame(0);
    final a = Float32List(2 * 2 * 3), b = Float32List(2 * 2 * 3);
    sampleRgb(f, const Region(0, 0, 2), 2, a, mean: 0, std: 1);
    sampleRgb(f, const Region(0, 0, 2), 2, b, mean: 0, std: 1, flipX: true);
    expect(b.sublist(0, 3), a.sublist(3, 6));
  });
}
