import 'dart:typed_data';

import 'geometry.dart';

/// Image quality of a face crop, measured on the grayscale crop.
class FaceQuality {
  final double brightness; // mean gray level, 0..255
  final double sharpness; // variance of the Laplacian; low = blurry
  const FaceQuality(this.brightness, this.sharpness);
}

FaceQuality measureQuality(Uint8List g, int size) =>
    FaceQuality(brightness(g), sharpness(g, size, size));

double brightness(Uint8List g) {
  var s = 0;
  for (final v in g) {
    s += v;
  }
  return s / g.length;
}

/// Variance of the Laplacian on a grayscale image: low = blurry.
double sharpness(Uint8List g, int w, int h) {
  var sum = 0.0, sq = 0.0, n = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final lap = 4 * g[i] - g[i - 1] - g[i + 1] - g[i - w] - g[i + w];
      sum += lap;
      sq += lap * lap;
      n++;
    }
  }
  final mean = sum / n;
  return sq / n - mean * mean;
}

/// Limits for a usable face. Calibrate [minSharpness] on your phone in Dev Lab.
class QualityLimits {
  final double minScore, minWidth, maxWidth, centerTolerance;
  final double minBrightness, maxBrightness, minSharpness;

  const QualityLimits({
    required this.minScore,
    required this.minWidth,
    required this.maxWidth,
    required this.centerTolerance,
    this.minBrightness = 50,
    this.maxBrightness = 215,
    this.minSharpness = 25,
  });

  /// Strict: every enrollment sample becomes part of the template.
  static const enroll = QualityLimits(
      minScore: .55, minWidth: .28, maxWidth: .85, centerTolerance: .18);

  /// Looser: the voting window absorbs the odd bad frame.
  static const unlock = QualityLimits(
      minScore: .45, minWidth: .18, maxWidth: .95, centerTolerance: .3);
}

/// Returns a short instruction for the user, or null if the frame is usable.
/// [faces] are in upright pixels of a [uw]×[uh] frame.
String? faceHint(List<Box> faces, int uw, int uh, FaceQuality? q,
    {QualityLimits limits = QualityLimits.enroll}) {
  if (faces.isEmpty) return 'Move your face into the circle';
  if (faces.length > 1) return 'Only one person in the frame, please';
  final f = faces.first;
  if (f.score < limits.minScore) return 'Hold still';
  if (f.w < limits.minWidth * uw) return 'Move closer';
  if (f.w > limits.maxWidth * uw) return 'Move back a little';
  final cx = f.cx / uw, cy = f.cy / uh;
  if ((cx - .5).abs() > limits.centerTolerance ||
      (cy - .45).abs() > limits.centerTolerance) {
    return 'Center your face';
  }
  if (q != null) {
    if (q.brightness < limits.minBrightness) return 'Too dark. Face a light source';
    if (q.brightness > limits.maxBrightness) return 'Too bright';
    if (q.sharpness < limits.minSharpness) return 'Image is blurry. Hold still';
  }
  return null;
}
