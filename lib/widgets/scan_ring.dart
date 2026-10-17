import 'dart:math';

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// A ring around the circular camera.
/// - [segments] set: N segments, [filled] of them lit (enrollment samples).
/// - otherwise: continuous [progress] 0..1 (unlock vote), with a rotating
///   sweep while [scanning] so the user sees the app is working.
class ScanRing extends StatefulWidget {
  const ScanRing({
    super.key,
    required this.child,
    this.segments,
    this.filled = 0,
    this.progress = 0,
    this.color = AppColors.amber,
    this.scanning = true,
  });

  final Widget child;
  final int? segments;
  final int filled;
  final double progress;
  final Color color;
  final bool scanning;

  @override
  State<ScanRing> createState() => _ScanRingState();
}

class _ScanRingState extends State<ScanRing> with SingleTickerProviderStateMixin {
  late final _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.scanning) _spin.repeat();
  }

  @override
  void didUpdateWidget(ScanRing old) {
    super.didUpdateWidget(old);
    if (widget.scanning && !_spin.isAnimating) _spin.repeat();
    if (!widget.scanning && _spin.isAnimating) _spin.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, child) => CustomPaint(
          foregroundPainter: _RingPainter(
            segments: widget.segments,
            filled: widget.filled,
            progress: widget.progress,
            color: widget.color,
            spin: widget.scanning ? _spin.value : null,
          ),
          child: child,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: ClipOval(child: widget.child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.segments,
    required this.filled,
    required this.progress,
    required this.color,
    required this.spin,
  });

  final int? segments;
  final int filled;
  final double progress;
  final Color color;
  final double? spin;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final rect = Rect.fromCircle(
        center: size.center(Offset.zero), radius: size.shortestSide / 2 - stroke);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.outline;
    final lit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    const top = -pi / 2;

    final n = segments;
    if (n != null && n > 0) {
      const gap = .08;
      final sweep = 2 * pi / n;
      for (var i = 0; i < n; i++) {
        canvas.drawArc(rect, top + i * sweep + gap / 2, sweep - gap, false,
            i < filled ? lit : track);
      }
    } else {
      canvas.drawArc(rect, 0, 2 * pi, false, track);
      if (progress > 0) canvas.drawArc(rect, top, 2 * pi * progress, false, lit);
    }

    final s = spin;
    if (s != null) {
      final sweepPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: .55);
      canvas.drawArc(rect.inflate(7), top + s * 2 * pi, pi / 5, false, sweepPaint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.filled != filled ||
      old.progress != progress ||
      old.color != color ||
      old.spin != spin ||
      old.segments != segments;
}
