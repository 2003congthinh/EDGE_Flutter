import 'dart:math';
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'embedder.dart';
import 'frame_data.dart';
import 'geometry.dart';
import 'sampler.dart';
import 'vectors.dart';
import 'yolo.dart';

/// Writes float values into a tensor, quantizing when the model wants int8/uint8.
void _writeInput(Tensor t, Float32List x) {
  switch (t.type) {
    case TensorType.float32:
      t.data = x.buffer.asUint8List(x.offsetInBytes, x.lengthInBytes);
    case TensorType.uint8 || TensorType.int8:
      final q = t.params;
      final scale = q.scale == 0 ? 1.0 : q.scale;
      final signed = t.type == TensorType.int8;
      final out = Uint8List(x.length);
      final lo = signed ? -128 : 0, hi = signed ? 127 : 255;
      for (var i = 0; i < x.length; i++) {
        final v = (x[i] / scale + q.zeroPoint).round().clamp(lo, hi);
        out[i] = v & 0xff;
      }
      t.data = out;
    default:
      throw UnsupportedError('Unsupported input tensor type ${t.type}');
  }
}

/// Reads a tensor into [dst] as floats, dequantizing int8/uint8 outputs.
void _readOutput(Tensor t, Float32List dst) {
  final bytes = t.data;
  switch (t.type) {
    case TensorType.float32:
      dst.buffer.asUint8List(dst.offsetInBytes, dst.lengthInBytes).setAll(0, bytes);
    case TensorType.uint8 || TensorType.int8:
      final q = t.params;
      final signed = t.type == TensorType.int8;
      for (var i = 0; i < dst.length; i++) {
        final raw = signed ? bytes[i].toSigned(8) : bytes[i];
        dst[i] = (raw - q.zeroPoint) * q.scale;
      }
    default:
      throw UnsupportedError('Unsupported output tensor type ${t.type}');
  }
}

int _numel(List<int> shape) => shape.fold(1, (a, b) => a * b);

/// YOLO face detector. Input size and output layout are read from the model,
/// so a 320 or 640, YOLO11 or YOLO26 export all work.
class FaceDetector {
  final Interpreter _it;
  late final int inputSize;
  late final YoloHead head;
  late final Float32List _input;
  late final Float32List _output;

  FaceDetector.fromBuffer(Uint8List model, {int threads = 4})
      : _it = Interpreter.fromBuffer(model,
            options: InterpreterOptions()..threads = threads) {
    final inShape = _it.getInputTensor(0).shape; // [1, S, S, 3]
    inputSize = inShape[1];
    _input = Float32List(_numel(inShape));
    final outShape = _it.getOutputTensor(0).shape;
    head = YoloHead.fromShape(outShape);
    _output = Float32List(_numel(outShape));
  }

  /// Returns faces in upright image pixels, best first.
  List<Box> detect(FrameData f, {double conf = .45}) {
    final region = letterbox(f);
    sampleRgb(f, region, inputSize, _input); // RGB 0..1, grey padding
    _writeInput(_it.getInputTensor(0), _input);
    _it.invoke();
    _readOutput(_it.getOutputTensor(0), _output);
    final k = region.size / inputSize; // tensor px → upright px
    return [
      for (final b in decodeYolo(_output, head, conf: conf, inputSize: inputSize))
        b.mapped(k, region.left, region.top)
    ];
  }

  void close() => _it.close();
}

/// A TFLite face embedder such as MobileFaceNet: S×S RGB input normalized as
/// (x − 127.5) / 128, D-dimensional output. Models with a batch of 2 get the
/// crop and its mirror image, and their embeddings are summed.
class TfliteEmbedder implements FaceEmbedder {
  /// Square crop around the detector box. Calibrate against your model's training crops.
  static const cropMargin = 1.2;

  final Interpreter _it;
  late final int _batch, _size;
  late final Float32List _input, _output;
  @override
  late final int dim;
  @override
  final String modelId;

  TfliteEmbedder.fromBuffer(Uint8List model, {int threads = 2})
      : _it = Interpreter.fromBuffer(model,
            options: InterpreterOptions()..threads = threads),
        modelId = 'tflite-${fnv1a32(model).toRadixString(16)}' {
    final inShape = _it.getInputTensor(0).shape; // [B, S, S, 3]
    _batch = inShape[0];
    _size = inShape[1];
    _input = Float32List(_numel(inShape));
    final outShape = _it.getOutputTensor(0).shape; // [B, D]
    dim = outShape.last;
    _output = Float32List(_numel(outShape));
  }

  @override
  bool get isPlaceholder => false;

  @override
  Float32List embed(FrameData f, Box face) {
    final region = Region.around(face, cropMargin);
    final one = _size * _size * 3;
    for (var b = 0; b < _batch; b++) {
      final view = Float32List.view(_input.buffer, b * one * 4, one);
      sampleRgb(f, region, _size, view,
          mean: 127.5, std: 128, fill: 127.5, flipX: b.isOdd);
    }
    _writeInput(_it.getInputTensor(0), _input);
    _it.invoke();
    _readOutput(_it.getOutputTensor(0), _output);
    final sum = Float32List(dim);
    for (var b = 0; b < max(1, _output.length ~/ dim); b++) {
      for (var i = 0; i < dim; i++) {
        sum[i] += _output[b * dim + i];
      }
    }
    return l2Normalize(sum);
  }

  @override
  void close() => _it.close();
}
