import 'dart:math';
import 'dart:typed_data';

import 'vectors.dart';

/// Anything with stored face embeddings (an enrolled person).
abstract interface class Enrolled {
  String get id;
  List<Float32List> get embeddings;
}

class MatchResult {
  final String? id; // null = below threshold (unknown)
  final String? bestId; // closest identity regardless of threshold
  final double score;
  const MatchResult(this.id, this.bestId, this.score);
  bool get matched => id != null;
}

/// Highest similarity between [e] and any stored embedding of [p].
double scoreAgainst(Float32List e, Enrolled p) {
  var best = -1.0;
  for (final v in p.embeddings) {
    best = max(best, dot(e, v));
  }
  return best;
}

/// Compares against every stored embedding of every person and keeps the best.
MatchResult bestMatch(Float32List e, Iterable<Enrolled> gallery,
    {required double threshold}) {
  String? bestId;
  var best = -1.0;
  for (final p in gallery) {
    final s = scoreAgainst(e, p);
    if (s > best) {
      best = s;
      bestId = p.id;
    }
  }
  return MatchResult(best >= threshold ? bestId : null, bestId, best);
}

/// Removes samples whose mean similarity to the others is below [minMean]:
/// a motion smear, bad light or a second person would poison the template.
List<Float32List> dropOutliers(List<Float32List> s, {required double minMean}) {
  if (s.length < 3) return [...s];
  return [
    for (var i = 0; i < s.length; i++)
      if ([
                for (var j = 0; j < s.length; j++)
                  if (j != i) dot(s[i], s[j])
              ].fold(0.0, (a, b) => a + b) /
              (s.length - 1) >=
          minMean)
        s[i]
  ];
}

/// How strongly a set of new samples matches [p]: the median over samples of
/// each sample's best score. Robust to one or two lucky or unlucky frames.
double setSimilarity(List<Float32List> samples, Enrolled p) {
  if (samples.isEmpty || p.embeddings.isEmpty) return -1;
  final scores = [for (final s in samples) scoreAgainst(s, p)]..sort();
  return scores[scores.length ~/ 2];
}
