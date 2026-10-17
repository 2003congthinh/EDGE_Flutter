import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/ml/matcher.dart';
import '../../core/ml/ml_worker.dart';
import '../../widgets/face_overlay_painter.dart';
import '../../widgets/live_camera_view.dart';

/// Similarity Lab + benchmarks: live boxes, the crop the embedder sees,
/// per-stage timings, quality values and the score against every registered
/// person. Use it to verify orientation and to calibrate thresholds.
class DevLabPage extends ConsumerStatefulWidget {
  const DevLabPage({super.key});

  @override
  ConsumerState<DevLabPage> createState() => _DevLabPageState();
}

class _DevLabPageState extends ConsumerState<DevLabPage> {
  FrameResult? _r;
  ui.Image? _crop;
  final _frameTimes = <DateTime>[];
  Map<String, double> _scores = const {};

  void _onResult(FrameResult r) {
    final now = DateTime.now();
    _frameTimes.add(now);
    _frameTimes.removeWhere((t) => now.difference(t).inMilliseconds > 2000);
    final e = r.embedding;
    final gallery = ref.read(galleryProvider);
    _scores = e == null
        ? const {}
        : {for (final p in gallery) if (!p.needsRescan) p.id: scoreAgainst(e, p)};
    setState(() => _r = r);
    final crop = r.crop;
    if (crop != null) _decodeCrop(crop);
  }

  void _decodeCrop(Uint8List gray) {
    final rgba = Uint8List(gray.length * 4);
    for (var i = 0; i < gray.length; i++) {
      rgba[i * 4] = rgba[i * 4 + 1] = rgba[i * 4 + 2] = gray[i];
      rgba[i * 4 + 3] = 255;
    }
    ui.decodeImageFromPixels(rgba, 112, 112, ui.PixelFormat.rgba8888, (img) {
      if (!mounted) {
        img.dispose();
        return;
      }
      final old = _crop;
      setState(() => _crop = img);
      old?.dispose();
    });
  }

  @override
  void dispose() {
    _crop?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(modelInfoProvider);
    final t = ref.watch(settingsProvider).thresholds;
    final gallery = ref.watch(galleryProvider);
    final r = _r;
    final fps = _frameTimes.length / 2;

    String? labelFor() {
      final e = r?.embedding;
      if (e == null) return null;
      final m = bestMatch(e, gallery.where((p) => !p.needsRescan), threshold: t.label);
      final name = gallery.where((p) => p.id == m.id).firstOrNull?.name;
      return '${name ?? 'Unknown'} · ${m.score.toStringAsFixed(2)}';
    }

    final label = labelFor();
    final primaryKnown = label != null && !label.startsWith('Unknown');

    return Scaffold(
      appBar: AppBar(title: const Text('Dev Lab')),
      body: Column(
        children: [
          Expanded(
            child: LiveCameraView(
              onResult: _onResult,
              embed: true,
              crop: true,
              overlayBuilder: (context, g) => r == null
                  ? const SizedBox.shrink()
                  : CustomPaint(
                      painter: FaceOverlayPainter(
                        geometry: g,
                        frameW: r.uprightW,
                        frameH: r.uprightH,
                        marks: [
                          for (var i = 0; i < r.faces.length; i++)
                            FaceMark(
                              r.faces[i],
                              known: i == 0 && primaryKnown,
                              label: i == 0
                                  ? label ?? (r.faces[i].score * 100).toStringAsFixed(0)
                                  : '${(r.faces[i].score * 100).toStringAsFixed(0)}%',
                            ),
                        ],
                      ),
                    ),
            ),
          ),
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: SafeArea(
              top: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                        border: Border.all(color: AppColors.outline),
                        borderRadius: BorderRadius.circular(8)),
                    clipBehavior: Clip.antiAlias,
                    child: _crop == null
                        ? const Center(
                            child: Text('crop',
                                style: TextStyle(color: AppColors.muted, fontSize: 11)))
                        : RawImage(image: _crop, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DefaultTextStyle(
                      style: const TextStyle(
                          fontFamily: monoFont, fontSize: 11.5, color: AppColors.text, height: 1.45),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${fps.toStringAsFixed(1)} fps · ${r?.faces.length ?? 0} faces'),
                          Text('det ${_ms(r?.detMs)} · emb ${_ms(r?.embMs)} · total ${_ms(r?.totalMs)}'),
                          Text('det ${info.detectorInput}px ${info.detectorHead}'),
                          Text(info.placeholderEmbedder
                              ? 'emb LBP placeholder ${info.embedderDim}-d'
                              : 'emb tflite ${info.embedderDim}-d'),
                          if (r?.quality != null)
                            Text('light ${r!.quality!.brightness.toStringAsFixed(0)} · '
                                'sharp ${r.quality!.sharpness.toStringAsFixed(0)}'),
                          Text('unlock ≥ ${t.unlock.toStringAsFixed(2)} · '
                              'label ≥ ${t.label.toStringAsFixed(2)}',
                              style: const TextStyle(color: AppColors.muted)),
                          for (final p in gallery.where((p) => !p.needsRescan))
                            Text(
                              '${p.name.length > 14 ? '${p.name.substring(0, 14)}…' : p.name}'
                              ' ${_scores[p.id]?.toStringAsFixed(3) ?? '–'}',
                              style: TextStyle(
                                color: (_scores[p.id] ?? -1) >= t.unlock
                                    ? AppColors.cyan
                                    : (_scores[p.id] ?? -1) >= t.label
                                        ? AppColors.amber
                                        : AppColors.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _ms(double? v) => v == null ? '–' : '${v.toStringAsFixed(0)}ms';
}
