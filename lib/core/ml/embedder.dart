import 'dart:math';
import 'dart:typed_data';

import 'frame_data.dart';
import 'geometry.dart';
import 'sampler.dart';

/// Turns a face into a unit-length vector. Similar faces → high dot product.
abstract interface class FaceEmbedder {
  /// Stored next to every embedding: vectors from different models aren't comparable.
  String get modelId;
  int get dim;

  /// True for the built-in test matcher that stands in until a real model is added.
  bool get isPlaceholder;

  Float32List embed(FrameData f, Box face);
  void close();
}

/// Placeholder embedder: uniform LBP texture histograms over a 4×4 grid.
///
/// It needs no model file, so the register → unlock flow can be tested end to
/// end. It is NOT secure: lookalikes and photos can pass. The app shows a
/// warning while it is in use and switches to assets/models/face_embedder.tflite
/// as soon as that file exists.
class LbpEmbedder implements FaceEmbedder {
  static const _size = 64, _grid = 4, _bins = 59, _margin = .95;
  static final _lut = _uniformLut();

  final _gray = Uint8List(_size * _size);

  @override
  String get modelId => 'lbp-placeholder-v1';
  @override
  int get dim => _grid * _grid * _bins;
  @override
  bool get isPlaceholder => true;

  @override
  Float32List embed(FrameData f, Box face) {
    sampleGray(f, Region.around(face, _margin), _size, _gray);
    return lbpFeatures(_gray, _size);
  }

  @override
  void close() {}

  /// Exposed for tests. [g] is a [size]×[size] grayscale image.
  static Float32List lbpFeatures(Uint8List g, int size) {
    final cell = (size - 2) ~/ _grid;
    final hist = Float64List(_grid * _grid * _bins);
    for (var y = 1; y < size - 1; y++) {
      final gy = min((y - 1) ~/ cell, _grid - 1);
      for (var x = 1; x < size - 1; x++) {
        final gx = min((x - 1) ~/ cell, _grid - 1);
        final i = y * size + x, c = g[i];
        var code = 0;
        if (g[i - size - 1] >= c) code |= 1;
        if (g[i - size] >= c) code |= 2;
        if (g[i - size + 1] >= c) code |= 4;
        if (g[i + 1] >= c) code |= 8;
        if (g[i + size + 1] >= c) code |= 16;
        if (g[i + size] >= c) code |= 32;
        if (g[i + size - 1] >= c) code |= 64;
        if (g[i - 1] >= c) code |= 128;
        hist[(gy * _grid + gx) * _bins + _lut[code]] += 1;
      }
    }
    // Hellinger kernel (sqrt of the normalized histogram), then centre and
    // L2-normalize so the dot product behaves like a correlation in [-1, 1].
    final perCell = (cell * cell).toDouble();
    final v = Float32List(hist.length);
    var mean = 0.0;
    for (var i = 0; i < v.length; i++) {
      v[i] = sqrt(hist[i] / perCell);
      mean += v[i];
    }
    mean /= v.length;
    var norm = 0.0;
    for (var i = 0; i < v.length; i++) {
      v[i] -= mean;
      norm += v[i] * v[i];
    }
    norm = sqrt(norm) + 1e-10;
    for (var i = 0; i < v.length; i++) {
      v[i] /= norm;
    }
    return v;
  }

  static Uint8List _uniformLut() {
    final lut = Uint8List(256);
    var k = 0;
    for (var c = 0; c < 256; c++) {
      var transitions = 0;
      for (var i = 0; i < 8; i++) {
        if (((c >> i) & 1) != ((c >> ((i + 1) % 8)) & 1)) transitions++;
      }
      lut[c] = transitions <= 2 ? k++ : 58;
    }
    return lut;
  }
}
