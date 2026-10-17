import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'embedder.dart';
import 'frame_data.dart';
import 'geometry.dart';
import 'quality.dart';
import 'sampler.dart';
import 'tflite_models.dart';

/// Where the app looks for models. See README → "Models".
abstract final class ModelAssets {
  static const detector = 'assets/models/face_detector.tflite';
  static const embedder = 'assets/models/face_embedder.tflite';
}

/// What was loaded, reported once by the worker at start-up.
class ModelInfo {
  final int detectorInput;
  final String detectorHead;
  final String embedderId;
  final int embedderDim;
  final bool placeholderEmbedder;
  const ModelInfo(this.detectorInput, this.detectorHead, this.embedderId,
      this.embedderDim, this.placeholderEmbedder);
}

/// Output of one processed frame. Boxes are in upright image pixels.
class FrameResult {
  final int session;
  final int uprightW, uprightH;
  final List<Box> faces; // largest first
  final Float32List? embedding; // of faces.first, when requested
  final FaceQuality? quality; // of faces.first, when requested
  final Uint8List? crop; // 112×112 grayscale of faces.first (Dev Lab only)
  final double detMs, embMs, totalMs;

  const FrameResult({
    required this.session,
    required this.uprightW,
    required this.uprightH,
    required this.faces,
    this.embedding,
    this.quality,
    this.crop,
    required this.detMs,
    required this.embMs,
    required this.totalMs,
  });

  Box? get primary => faces.isEmpty ? null : faces.first;
}

class _FrameJob {
  final int session;
  final FrameData frame;
  final bool embed, crop;
  const _FrameJob(this.session, this.frame, this.embed, this.crop);
}

class _WorkerError {
  final String message;
  const _WorkerError(this.message);
}

class _Shutdown {
  const _Shutdown();
}

/// A long-lived isolate that owns both TFLite interpreters. Frames offered
/// while it is busy are dropped rather than queued, so the UI never stutters,
/// and interpreters are only closed between frames.
class MlWorker {
  MlWorker._(this._toWorker, this.info, this._fromWorker);

  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  final ModelInfo info;
  final _results = StreamController<FrameResult>.broadcast();
  bool _busy = false;
  DateTime _busySince = DateTime.now();
  int _nextSession = 1;

  Stream<FrameResult> get results => _results.stream;

  /// Each camera screen takes a session id so it ignores results meant for another.
  int newSession() => _nextSession++;

  static Future<MlWorker> start() async {
    final det = await _load(ModelAssets.detector);
    if (det == null) {
      throw StateError('Face detector model missing: ${ModelAssets.detector}');
    }
    final emb = await _load(ModelAssets.embedder);

    final fromWorker = ReceivePort();
    final errors = ReceivePort();
    await Isolate.spawn(_workerMain, (fromWorker.sendPort, det, emb),
        onError: errors.sendPort, debugName: 'ml-worker');

    final handshake = Completer<(SendPort, ModelInfo)>();
    SendPort? port;
    MlWorker? worker;
    errors.listen((e) {
      if (!handshake.isCompleted) handshake.completeError(StateError('$e'));
    });
    fromWorker.listen((msg) {
      if (msg is SendPort) {
        port = msg;
      } else if (msg is ModelInfo) {
        handshake.complete((port!, msg));
      } else if (msg is _WorkerError && !handshake.isCompleted) {
        handshake.completeError(StateError(msg.message));
      } else {
        worker?._onMessage(msg);
      }
    });
    final (sendPort, info) = await handshake.future;
    errors.close();
    return worker = MlWorker._(sendPort, info, fromWorker);
  }

  static Future<Uint8List?> _load(String asset) async {
    try {
      return (await rootBundle.load(asset)).buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  void _onMessage(Object? msg) {
    _busy = false;
    if (msg is FrameResult) {
      _results.add(msg);
    } else if (msg is _WorkerError) {
      debugPrint('ML worker: ${msg.message}');
    }
  }

  /// Returns false (and drops the frame) while the previous frame is still running.
  bool offer(int session, FrameData frame, {bool embed = false, bool crop = false}) {
    if (isBusy) return false;
    _busy = true;
    _busySince = DateTime.now();
    _toWorker.send(_FrameJob(session, frame, embed, crop));
    return true;
  }

  /// A lost reply must not block the pipeline forever, hence the time limit.
  bool get isBusy => _busy && DateTime.now().difference(_busySince).inSeconds < 3;

  void dispose() {
    _toWorker.send(const _Shutdown());
    _fromWorker.close();
    _results.close();
  }
}

void _workerMain((SendPort, Uint8List, Uint8List?) args) {
  final (toMain, detBytes, embBytes) = args;
  final inbox = ReceivePort();
  toMain.send(inbox.sendPort);

  final FaceDetector detector;
  final FaceEmbedder embedder;
  try {
    detector = FaceDetector.fromBuffer(detBytes);
    embedder = embBytes == null
        ? LbpEmbedder()
        : TfliteEmbedder.fromBuffer(embBytes);
  } catch (e) {
    toMain.send(_WorkerError('Could not load models: $e'));
    inbox.close();
    return;
  }
  toMain.send(ModelInfo(detector.inputSize, detector.head.toString(),
      embedder.modelId, embedder.dim, embedder.isPlaceholder));

  final gray = Uint8List(112 * 112);
  inbox.listen((msg) {
    switch (msg) {
      case _FrameJob():
        try {
          toMain.send(_process(msg, detector, embedder, gray));
        } catch (e) {
          toMain.send(_WorkerError('$e'));
        }
      case _Shutdown():
        detector.close();
        embedder.close();
        inbox.close();
    }
  });
}

FrameResult _process(
    _FrameJob job, FaceDetector detector, FaceEmbedder embedder, Uint8List gray) {
  final f = job.frame;
  final total = Stopwatch()..start();
  final faces = detector.detect(f)..sort((a, b) => b.area.compareTo(a.area));
  final detMs = total.elapsedMicroseconds / 1000;

  Float32List? embedding;
  FaceQuality? quality;
  Uint8List? crop;
  var embMs = 0.0;
  if ((job.embed || job.crop) && faces.isNotEmpty) {
    final face = faces.first;
    final t = Stopwatch()..start();
    sampleGray(f, Region.around(face, 1.0), 112, gray);
    quality = measureQuality(gray, 112);
    if (job.crop) crop = Uint8List.fromList(gray);
    if (job.embed) embedding = embedder.embed(f, face);
    embMs = t.elapsedMicroseconds / 1000;
  }
  return FrameResult(
    session: job.session,
    uprightW: f.uprightW,
    uprightH: f.uprightH,
    faces: faces,
    embedding: embedding,
    quality: quality,
    crop: crop,
    detMs: detMs,
    embMs: embMs,
    totalMs: total.elapsedMicroseconds / 1000,
  );
}
