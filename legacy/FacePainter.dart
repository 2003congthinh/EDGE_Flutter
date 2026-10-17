import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/rendering/custom_paint.dart';

class FacePainter extends CustomPainter {
  final List<dynamic> facesList;
  final Size cameraSize; // raw resolution of the camera frame

  FacePainter({required this.facesList, required this.cameraSize});

  @override
  void paint(Canvas canvas, Size size) {
    // calculate how much the camera image was stretched to fit the screen
    final double scaleX = size.width / cameraSize.width;
    final double scaleY = size.height / cameraSize.height;

    Paint p = Paint();
    p.color = Colors.red;
    p.style = PaintingStyle.stroke;
    p.strokeWidth = 4.0;

    for (var face in facesList) {
      // flutter_vision returns the bounding box as an array: [left, top, right, bottom]
      List<dynamic> box = face['box'];

      // Multiply the raw YOLO coordinates by the screen scale
      double left = box[0].toDouble() * scaleX;
      double top = (cameraSize.height - box[1].toDouble()) * scaleY;
      double right = box[2].toDouble() * scaleX;
      double bottom = (cameraSize.height - box[3].toDouble()) * scaleY;

      Rect rect = Rect.fromLTRB(left, top, right, bottom);
      canvas.drawRect(rect, p);

      // show the confidence score above the box
      TextSpan span = TextSpan(
        style: const TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold),
        text: "${(face['score'] * 100).toStringAsFixed(0)}%",
      );
      TextPainter tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(left, top - 20));
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true; // We want to repaint every time a new frame arrives
  }
}