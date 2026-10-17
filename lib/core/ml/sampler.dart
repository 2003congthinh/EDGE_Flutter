import 'dart:math';
import 'dart:typed_data';

import 'frame_data.dart';
import 'geometry.dart';

/// A square region of the upright image, in upright pixels.
class Region {
  final double left, top, size;
  const Region(this.left, this.top, this.size);

  /// A square centred on [face], [margin] times its longer side.
  factory Region.around(Box face, double margin) {
    final side = max(face.w, face.h) * margin;
    return Region(face.cx - side / 2, face.cy - side / 2, side);
  }
}

/// Letterbox = a square region centred on the image, as large as its longer side.
Region letterbox(FrameData f) {
  final side = max(f.uprightW, f.uprightH).toDouble();
  return Region((f.uprightW - side) / 2, (f.uprightH - side) / 2, side);
}

/// Upright pixel → sensor pixel is affine: sx = ax*ux + bx*uy + cx, same for sy.
/// Computing the coefficients once keeps the per-pixel loop branch-free.
class _Rot {
  final int ax, bx, cx, ay, by, cy;
  const _Rot(this.ax, this.bx, this.cx, this.ay, this.by, this.cy);

  factory _Rot.of(FrameData f) {
    final w = f.width, h = f.height;
    return switch (f.rotation % 360) {
      90 => _Rot(0, 1, 0, -1, 0, h - 1),
      180 => _Rot(-1, 0, w - 1, 0, -1, h - 1),
      270 => _Rot(0, -1, w - 1, 1, 0, 0),
      _ => const _Rot(1, 0, 0, 0, 1, 0),
    };
  }
}

/// Upright pixel (ux, uy) → raw sensor pixel. Exposed for tests.
(int, int) toSensor(int ux, int uy, FrameData f) {
  final r = _Rot.of(f);
  return (r.ax * ux + r.bx * uy + r.cx, r.ay * ux + r.by * uy + r.cy);
}

Int32List _axis(double start, double step, int n, {bool flip = false}) {
  final out = Int32List(n);
  for (var i = 0; i < n; i++) {
    final p = flip ? n - 1 - i : i;
    out[i] = (start + (p + .5) * step).floor();
  }
  return out;
}

/// Samples a square region of the upright image into [out] (NHWC RGB),
/// normalized as (value - mean) / std. Pixels outside the image get [fill].
/// Rotation, crop, resize and normalization all happen in one pass over the
/// output pixels, reading straight from the YUV planes.
void sampleRgb(FrameData f, Region r, int outSize, Float32List out,
    {double mean = 0, double std = 255, double fill = 114, bool flipX = false}) {
  final uw = f.uprightW, uh = f.uprightH, step = r.size / outSize;
  final pad = (fill - mean) / std;
  final rot = _Rot.of(f);
  final xs = _axis(r.left, step, outSize, flip: flipX);
  final ys = _axis(r.top, step, outSize);
  final yb = f.y, ub = f.u, vb = f.v;
  final yStride = f.yRowStride, uvStride = f.uvRowStride, uvPix = f.uvPixelStride;
  final inv = 1 / std;
  var o = 0;
  for (var py = 0; py < outSize; py++) {
    final uy = ys[py];
    final rowOut = uy < 0 || uy >= uh;
    for (var px = 0; px < outSize; px++) {
      final ux = xs[px];
      if (rowOut || ux < 0 || ux >= uw) {
        out[o++] = pad;
        out[o++] = pad;
        out[o++] = pad;
        continue;
      }
      final sx = rot.ax * ux + rot.bx * uy + rot.cx;
      final sy = rot.ay * ux + rot.by * uy + rot.cy;
      final yv = yb[sy * yStride + sx].toDouble();
      final uvi = (sy >> 1) * uvStride + (sx >> 1) * uvPix;
      final u = ub[uvi] - 128.0, v = vb[uvi] - 128.0;
      out[o++] = ((yv + 1.402 * v).clamp(0.0, 255.0) - mean) * inv;
      out[o++] = ((yv - 0.344 * u - 0.714 * v).clamp(0.0, 255.0) - mean) * inv;
      out[o++] = ((yv + 1.772 * u).clamp(0.0, 255.0) - mean) * inv;
    }
  }
}

/// Samples a square region of the upright image as 8-bit grayscale (the Y plane).
/// Pixels outside the image are clamped to the nearest edge pixel.
void sampleGray(FrameData f, Region r, int outSize, Uint8List out) {
  final uw = f.uprightW, uh = f.uprightH, step = r.size / outSize;
  final rot = _Rot.of(f);
  final xs = _axis(r.left, step, outSize);
  final ys = _axis(r.top, step, outSize);
  final yb = f.y, yStride = f.yRowStride;
  var o = 0;
  for (var py = 0; py < outSize; py++) {
    final uy = ys[py].clamp(0, uh - 1);
    for (var px = 0; px < outSize; px++) {
      final ux = xs[px].clamp(0, uw - 1);
      final sx = rot.ax * ux + rot.bx * uy + rot.cx;
      final sy = rot.ay * ux + rot.by * uy + rot.cy;
      out[o++] = yb[sy * yStride + sx];
    }
  }
}
