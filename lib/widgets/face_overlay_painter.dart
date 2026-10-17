import 'dart:math';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/ml/geometry.dart';
import 'live_camera_view.dart';

/// One face to draw: [known] faces get solid cyan brackets, unknown ones red dashes.
class FaceMark {
  final Box box;
  final String? label;
  final bool known;
  const FaceMark(this.box, {this.label, this.known = false});
}

/// Corner brackets plus an optional name chip for each face.
class FaceOverlayPainter extends CustomPainter {
  FaceOverlayPainter({
    required this.marks,
    required this.frameW,
    required this.frameH,
    required this.geometry,
  });

  final List<FaceMark> marks;
  final int frameW, frameH;
  final CameraGeometry geometry;

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in marks) {
      final r = geometry.toScreen(m.box, frameW, frameH, size);
      final color = m.known ? AppColors.cyan : AppColors.red;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final len = min(r.width, r.height) * .22;
      if (m.known) {
        _brackets(canvas, r, len, paint);
      } else {
        _dashed(canvas, r, paint);
      }
      final label = m.label;
      if (label != null) _chip(canvas, r, label, color);
    }
  }

  void _brackets(Canvas c, Rect r, double len, Paint p) {
    final path = Path()
      ..moveTo(r.left, r.top + len)
      ..lineTo(r.left, r.top)
      ..lineTo(r.left + len, r.top)
      ..moveTo(r.right - len, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right, r.top + len)
      ..moveTo(r.right, r.bottom - len)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.right - len, r.bottom)
      ..moveTo(r.left + len, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..lineTo(r.left, r.bottom - len);
    c.drawPath(path, p);
  }

  void _dashed(Canvas c, Rect r, Paint p) {
    const dash = 10.0, gap = 7.0;
    void line(Offset a, Offset b) {
      final total = (b - a).distance;
      final dir = (b - a) / total;
      for (var d = 0.0; d < total; d += dash + gap) {
        c.drawLine(a + dir * d, a + dir * min(d + dash, total), p);
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  void _chip(Canvas c, Rect r, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: max(80, r.width + 60));
    final chip = RRect.fromRectAndRadius(
      Rect.fromLTWH(r.left, r.top - tp.height - 12, tp.width + 14, tp.height + 6),
      const Radius.circular(6),
    );
    c.drawRRect(chip, Paint()..color = color);
    tp.paint(c, Offset(chip.left + 7, chip.top + 3));
  }

  @override
  bool shouldRepaint(FaceOverlayPainter old) => true; // a new frame every time
}
