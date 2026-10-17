/// A sliding window of per-frame verdicts. Passes when [need] of the last
/// [window] frames agreed, so one lucky frame can't unlock and one blurry
/// frame can't block.
class FaceVote {
  final int window, need;
  final _frames = <bool>[];

  FaceVote({this.window = 6, this.need = 4});

  /// Adds a frame verdict and returns true once the vote passes.
  bool add(bool ok) {
    _frames.add(ok);
    if (_frames.length > window) _frames.removeAt(0);
    return passed;
  }

  int get hits => _frames.where((ok) => ok).length;
  bool get passed => hits >= need;
  double get progress => (hits / need).clamp(0.0, 1.0);

  void reset() => _frames.clear();
}
