import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/auth/face_vote.dart';
import '../../core/auth/owner_check.dart';
import '../../core/ml/ml_worker.dart';
import '../../widgets/common.dart';
import '../../widgets/live_camera_view.dart';
import '../../widgets/scan_ring.dart';

/// Scans for the owner's face. Succeeds when 4 of the last 6 usable frames
/// match the owner with exactly one face in view; gives up after [window].
class OwnerFaceScan extends ConsumerStatefulWidget {
  const OwnerFaceScan({
    super.key,
    required this.onMatched,
    required this.onTimeout,
    this.window = const Duration(seconds: 8),
  });

  final Future<void> Function(double score) onMatched;

  /// Called with the best owner score seen, when a scan window ends without a match.
  final Future<void> Function(double? bestScore) onTimeout;
  final Duration window;

  @override
  ConsumerState<OwnerFaceScan> createState() => _OwnerFaceScanState();
}

enum _Phase { scanning, matched, failed }

class _OwnerFaceScanState extends ConsumerState<OwnerFaceScan> {
  final _vote = FaceVote(window: 6, need: 4);
  _Phase _phase = _Phase.scanning;
  String? _hint;
  double? _best, _last;
  Timer? _timer;

  void _armTimer() {
    _timer?.cancel();
    _timer = Timer(widget.window, () async {
      if (!mounted || _phase != _Phase.scanning) return;
      setState(() => _phase = _Phase.failed);
      HapticFeedback.heavyImpact();
      await widget.onTimeout(_best);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onResult(FrameResult r) {
    if (_phase != _Phase.scanning) return;
    if (_timer == null) _armTimer(); // the window starts with the first frame
    final owner = ref.read(ownerProvider);
    if (owner == null) return;
    final v = checkOwnerFrame(
        r, ref.read(galleryProvider), owner.id, ref.read(settingsProvider).thresholds);
    if (v.score != null) {
      _last = v.score;
      _best = max(_best ?? -1, v.score!);
    }
    _hint = v.hint;
    // Frames with no usable face don't vote; the window timer still runs.
    if (v.hint == null && v.score != null && _vote.add(v.ok)) {
      _phase = _Phase.matched;
      _timer?.cancel();
      HapticFeedback.mediumImpact();
      widget.onMatched(_last ?? _best ?? 0);
    }
    setState(() {});
  }

  void _retry() {
    setState(() {
      _vote.reset();
      _phase = _Phase.scanning;
      _hint = null;
      _best = _last = null;
      _timer?.cancel();
      _timer = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(modelInfoProvider);
    final showScore = info.placeholderEmbedder; // helps calibrate the test matcher
    final (title, color) = switch (_phase) {
      _Phase.scanning => (
          _vote.hits > 0 ? 'Matching ${_vote.hits} of ${_vote.need} frames…' : 'Look at the camera',
          AppColors.amber
        ),
      _Phase.matched => ('Welcome back', AppColors.cyan),
      _Phase.failed => ('Not recognized', AppColors.red),
    };

    return LayoutBuilder(builder: (context, c) {
      final ring = min(c.maxWidth, 340.0) * .78;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: ring,
            child: ScanRing(
              progress: _phase == _Phase.matched ? 1 : _vote.progress,
              color: color,
              scanning: _phase == _Phase.scanning,
              child: LiveCameraView(onResult: _onResult, paused: _phase != _Phase.scanning),
            ),
          ),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: Center(
              child: switch (_phase) {
                _Phase.failed => TextButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                _ when _hint != null => StatusPill(_hint!, color: AppColors.amber),
                _ when showScore && _last != null => Text(
                    'score ${_last!.toStringAsFixed(2)} · need '
                    '${ref.read(settingsProvider).thresholds.unlock.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontFamily: monoFont, color: AppColors.muted, fontSize: 12)),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
        ],
      );
    });
  }
}
