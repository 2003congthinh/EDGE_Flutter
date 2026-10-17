/// Similarity thresholds. They depend on the embedding model, so they are
/// stored per model and should be calibrated in Dev Lab, not copied from tutorials.
class Thresholds {
  /// Strict: face unlock, re-auth, duplicate check at registration.
  final double unlock;

  /// Looser: showing a name label next to a face.
  final double label;

  /// Enrollment samples whose mean similarity to the rest is below this are dropped.
  final double outlier;

  const Thresholds({required this.unlock, required this.label, required this.outlier});

  /// Defaults for a MobileFaceNet-style model (cosine similarity).
  static const tflite = Thresholds(unlock: .60, label: .50, outlier: .45);

  /// Defaults for the LBP placeholder (rough, from an offline experiment).
  static const placeholder = Thresholds(unlock: .70, label: .60, outlier: .40);

  static Thresholds defaultsFor({required bool placeholder}) =>
      placeholder ? Thresholds.placeholder : Thresholds.tflite;

  Thresholds copyWith({double? unlock, double? label, double? outlier}) => Thresholds(
        unlock: unlock ?? this.unlock,
        label: label ?? this.label,
        outlier: outlier ?? this.outlier,
      );
}
