import 'dart:math';
import 'dart:typed_data';

Float32List l2Normalize(Float32List v) {
  var s = 0.0;
  for (final x in v) {
    s += x * x;
  }
  final n = sqrt(s) + 1e-10;
  return Float32List.fromList([for (final x in v) x / n]);
}

/// Dot product. Equals cosine similarity for unit vectors.
double dot(Float32List a, Float32List b) {
  var s = 0.0;
  final n = min(a.length, b.length);
  for (var i = 0; i < n; i++) {
    s += a[i] * b[i];
  }
  return s;
}

Uint8List toBlob(Float32List v) =>
    Uint8List.fromList(v.buffer.asUint8List(v.offsetInBytes, v.lengthInBytes));

/// Copies first: a blob from SQLite may not be 4-byte aligned.
Float32List fromBlob(Uint8List b) =>
    Float32List.view(Uint8List.fromList(b).buffer, 0, b.lengthInBytes ~/ 4);

/// FNV-1a over the bytes; used to fingerprint a model file.
int fnv1a32(Uint8List bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h ^= b;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}
