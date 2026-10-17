import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The backup PIN. Only a PBKDF2-HMAC-SHA256 hash with a random salt is kept,
/// in the Android Keystore-backed secure storage. The PIN itself is never stored.
class PinService {
  PinService(this._secure);
  final FlutterSecureStorage _secure;

  static const length = 6;
  static const _iterations = 100000;
  static const _saltKey = 'pin_salt', _hashKey = 'pin_hash', _iterKey = 'pin_iter';

  Future<bool> isSet() async => await _secure.read(key: _hashKey) != null;

  Future<void> setPin(String pin) async {
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final hash = await _derive(pin, salt, _iterations);
    await _secure.write(key: _saltKey, value: base64Encode(salt));
    await _secure.write(key: _iterKey, value: '$_iterations');
    await _secure.write(key: _hashKey, value: base64Encode(hash));
  }

  Future<bool> verify(String pin) async {
    final salt = await _secure.read(key: _saltKey);
    final hash = await _secure.read(key: _hashKey);
    if (salt == null || hash == null) return false;
    final iter = int.tryParse(await _secure.read(key: _iterKey) ?? '') ?? _iterations;
    final candidate = await _derive(pin, base64Decode(salt), iter);
    return _constantTimeEquals(candidate, base64Decode(hash));
  }

  /// 100k iterations take a moment in Dart, so they run off the UI isolate.
  static Future<List<int>> _derive(String pin, List<int> salt, int iterations) =>
      Isolate.run(() async {
        final kdf = Pbkdf2(
            macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
        final key = await kdf.deriveKeyFromPassword(password: pin, nonce: salt);
        return key.extractBytes();
      });

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
