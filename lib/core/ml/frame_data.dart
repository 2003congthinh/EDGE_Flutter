import 'dart:typed_data';

import 'package:camera/camera.dart';

/// A camera frame copied into plain bytes so it can be sent to the ML isolate.
///
/// [rotation] is the clockwise rotation that makes the sensor image upright
/// (the camera's sensorOrientation: 270 on most front cameras).
class FrameData {
  final int width, height, rotation;
  final Uint8List y, u, v;
  final int yRowStride, uvRowStride, uvPixelStride;

  const FrameData({
    required this.width,
    required this.height,
    required this.rotation,
    required this.y,
    required this.u,
    required this.v,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
  });

  int get uprightW => rotation % 180 == 0 ? width : height;
  int get uprightH => rotation % 180 == 0 ? height : width;

  /// Expects a YUV420 image (3 planes), as requested by LiveCameraView.
  factory FrameData.fromCamera(CameraImage img, int rotation) => FrameData(
        width: img.width,
        height: img.height,
        rotation: rotation,
        y: img.planes[0].bytes,
        u: img.planes[1].bytes,
        v: img.planes[2].bytes,
        yRowStride: img.planes[0].bytesPerRow,
        uvRowStride: img.planes[1].bytesPerRow,
        uvPixelStride: img.planes[1].bytesPerPixel ?? 1,
      );
}
