import '../ml/matcher.dart';
import '../ml/ml_worker.dart';
import '../ml/quality.dart';
import '../ml/thresholds.dart';

/// The verdict for one frame on the unlock or re-auth screen.
class FrameVerdict {
  final bool ok;
  final double? score; // similarity to the owner, if a face was embedded
  final String? hint;
  const FrameVerdict(this.ok, this.score, this.hint);
}

/// A frame counts toward unlocking only when it has exactly one usable face,
/// that face's closest match in the whole gallery is the owner, and the score
/// clears the unlock threshold.
FrameVerdict checkOwnerFrame(FrameResult r, List<Enrolled> gallery,
    String ownerId, Thresholds t) {
  final hint = faceHint(r.faces, r.uprightW, r.uprightH, r.quality,
      limits: QualityLimits.unlock);
  final e = r.embedding;
  if (hint != null || e == null) return FrameVerdict(false, null, hint);

  final owner = gallery.where((p) => p.id == ownerId).firstOrNull;
  if (owner == null || owner.embeddings.isEmpty) {
    return const FrameVerdict(false, null, null);
  }
  final ownerScore = scoreAgainst(e, owner);
  final best = bestMatch(e, gallery, threshold: t.unlock);
  final ok = best.bestId == ownerId && ownerScore >= t.unlock;
  return FrameVerdict(ok, ownerScore, null);
}
