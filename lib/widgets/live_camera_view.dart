import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../core/ml/frame_data.dart';
import '../core/ml/geometry.dart';
import '../core/ml/ml_worker.dart';

/// How the preview is laid out, so painters can put boxes in the right place.
class CameraGeometry {
  final Size preview; // upright preview size
  final bool mirror; // front camera previews are mirrored; detection input is not
  const CameraGeometry(this.preview, this.mirror);

  /// Maps a box in upright frame pixels onto a canvas showing the preview with
  /// BoxFit.cover. Works at all four edges, whatever the preview resolution.
  Rect toScreen(Box b, int frameW, int frameH, Size canvas) {
    final s = max(canvas.width / preview.width, canvas.height / preview.height);
    final w = preview.width * s, h = preview.height * s;
    final dx = (canvas.width - w) / 2, dy = (canvas.height - h) / 2;
    var l = dx + b.l / frameW * w, r = dx + b.r / frameW * w;
    if (mirror) (l, r) = (canvas.width - r, canvas.width - l);
    return Rect.fromLTRB(l, dy + b.t / frameH * h, r, dy + b.b / frameH * h);
  }
}

/// Front-camera preview (cover-fit) that streams frames to the ML worker and
/// reports results for its own session only.
class LiveCameraView extends ConsumerStatefulWidget {
  const LiveCameraView({
    super.key,
    required this.onResult,
    this.embed = true,
    this.crop = false,
    this.paused = false,
    this.overlayBuilder,
  });

  final void Function(FrameResult r) onResult;
  final bool embed, crop;

  /// Stops sending frames (the preview keeps running).
  final bool paused;
  final Widget Function(BuildContext context, CameraGeometry geometry)? overlayBuilder;

  @override
  ConsumerState<LiveCameraView> createState() => _LiveCameraViewState();
}

class _LiveCameraViewState extends ConsumerState<LiveCameraView>
    with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  StreamSubscription<FrameResult>? _sub;
  late final MlWorker _worker;
  late final int _session;
  String? _error;
  bool _permissionDenied = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _worker = ref.read(servicesProvider).worker;
    _session = _worker.newSession();
    _sub = _worker.results
        .where((r) => r.session == _session)
        .listen((r) {
      if (mounted && !widget.paused) widget.onResult(r);
    });
    _start();
  }

  Future<void> _start() async {
    if (_starting || _controller != null) return;
    _starting = true;
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) setState(() => _permissionDenied = true);
        return;
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'No camera found on this device.');
        return;
      }
      _camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first);
      // Medium is plenty for a 320–640 px model and halves conversion cost.
      final c = CameraController(_camera!, ResolutionPreset.medium,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.startImageStream(_onImage);
      setState(() {
        _controller = c;
        _permissionDenied = false;
        _error = null;
      });
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = 'Camera error: ${e.description ?? e.code}');
    } finally {
      _starting = false;
    }
  }

  void _onImage(CameraImage img) {
    if (!mounted || widget.paused || _worker.isBusy || img.planes.length < 3) return;
    _worker.offer(_session, FrameData.fromCamera(img, _camera!.sensorOrientation),
        embed: widget.embed, crop: widget.crop);
  }

  Future<void> _stop() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (_controller != null) {
        _stop();
        if (mounted) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionDenied) {
      return _Message(
        icon: Icons.no_photography_outlined,
        text: 'Camera access is needed to recognize faces. Frames are processed '
            'on this device and never saved.',
        action: TextButton(
          onPressed: () async {
            await openAppSettings();
          },
          child: const Text('Open settings'),
        ),
        retry: _start,
      );
    }
    if (_error != null) {
      return _Message(icon: Icons.error_outline, text: _error!, retry: _start);
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.previewSize == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final p = c.value.previewSize!; // landscape sensor size
    final upright = Size(min(p.width, p.height), max(p.width, p.height));
    final geometry = CameraGeometry(
        upright, _camera!.lensDirection == CameraLensDirection.front);

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: upright.width,
                height: upright.height,
                child: CameraPreview(c),
              ),
            ),
          ),
          if (widget.overlayBuilder != null) widget.overlayBuilder!(context, geometry),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action, this.retry});
  final IconData icon;
  final String text;
  final Widget? action;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.muted, size: 32),
              const SizedBox(height: 10),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ?action,
              if (retry != null)
                TextButton(onPressed: retry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}
