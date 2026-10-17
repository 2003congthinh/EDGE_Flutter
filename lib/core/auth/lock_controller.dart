import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../app/providers.dart';
import '../../data/event_repository.dart';

enum UnlockMethod { face, pin }

class UnlockInfo {
  final UnlockMethod method;
  final DateTime at;
  final double? score;
  const UnlockInfo(this.method, this.at, this.score);
}

/// Counters persisted in secure storage so killing the app doesn't reset them.
class LockCounters {
  final int faceFailures, pinFailures, lockoutLevel;
  final DateTime? lockoutUntil;
  const LockCounters({
    this.faceFailures = 0,
    this.pinFailures = 0,
    this.lockoutLevel = 0,
    this.lockoutUntil,
  });
}

class LockState {
  final bool setupDone;
  final bool locked;
  final LockCounters counters;
  final UnlockInfo? lastUnlock;

  const LockState({
    required this.setupDone,
    required this.locked,
    this.counters = const LockCounters(),
    this.lastUnlock,
  });

  int get faceFailures => counters.faceFailures;

  /// After too many failed face scans only the PIN can unlock.
  bool get faceBlocked => counters.faceFailures >= LockController.maxFaceFailures;

  DateTime? get lockoutUntil {
    final u = counters.lockoutUntil;
    return u != null && u.isAfter(DateTime.now()) ? u : null;
  }

  LockState copyWith({
    bool? setupDone,
    bool? locked,
    LockCounters? counters,
    UnlockInfo? lastUnlock,
  }) =>
      LockState(
        setupDone: setupDone ?? this.setupDone,
        locked: locked ?? this.locked,
        counters: counters ?? this.counters,
        lastUnlock: lastUnlock ?? this.lastUnlock,
      );
}

sealed class PinOutcome {
  const PinOutcome();
}

class PinOk extends PinOutcome {
  const PinOk();
}

class PinWrong extends PinOutcome {
  final int attemptsLeft; // before the next lockout
  const PinWrong(this.attemptsLeft);
}

class PinLockedOut extends PinOutcome {
  final DateTime until;
  const PinLockedOut(this.until);
}

/// The app lock state machine:
///   no owner → setup;  owner → locked → face (4 of 6 frames) or PIN → unlocked;
///   5 failed face scans → PIN only;  5 wrong PINs → lockout 60 s, doubling;
///   app hidden longer than the relock timeout → locked.
class LockController extends Notifier<LockState> {
  static const maxFaceFailures = 5;
  static const pinsPerLockout = 5;
  static const _baseLockout = Duration(seconds: 60);

  static const _kFace = 'lock_face_failures',
      _kPin = 'lock_pin_failures',
      _kLevel = 'lock_level',
      _kUntil = 'lock_until';

  DateTime? _hiddenAt;

  @override
  LockState build() {
    final services = ref.read(servicesProvider);
    final life = AppLifecycleListener(
      onHide: () => _hiddenAt = DateTime.now(),
      onShow: () {
        final hidden = _hiddenAt;
        _hiddenAt = null;
        final timeout = Duration(seconds: ref.read(settingsProvider).relockSeconds);
        if (hidden != null && DateTime.now().difference(hidden) > timeout) lock();
      },
    );
    ref.onDispose(life.dispose);
    return LockState(
      setupDone: services.boot.setupDone,
      locked: true,
      counters: services.boot.counters,
    );
  }

  EventRepository get _events => ref.read(servicesProvider).events;

  static Future<LockCounters> readCounters(FlutterSecureStorage s) async {
    int i(String? v) => int.tryParse(v ?? '') ?? 0;
    final until = int.tryParse(await s.read(key: _kUntil) ?? '');
    return LockCounters(
      faceFailures: i(await s.read(key: _kFace)),
      pinFailures: i(await s.read(key: _kPin)),
      lockoutLevel: i(await s.read(key: _kLevel)),
      lockoutUntil: until == null ? null : DateTime.fromMillisecondsSinceEpoch(until),
    );
  }

  Future<void> _setCounters(LockCounters c) async {
    state = state.copyWith(counters: c);
    final s = ref.read(servicesProvider).secure;
    await s.write(key: _kFace, value: '${c.faceFailures}');
    await s.write(key: _kPin, value: '${c.pinFailures}');
    await s.write(key: _kLevel, value: '${c.lockoutLevel}');
    final until = c.lockoutUntil;
    if (until == null) {
      await s.delete(key: _kUntil);
    } else {
      await s.write(key: _kUntil, value: '${until.millisecondsSinceEpoch}');
    }
  }

  void lock() {
    if (state.setupDone && !state.locked) state = state.copyWith(locked: true);
  }

  Future<void> completeSetup() async {
    await _setCounters(const LockCounters());
    state = state.copyWith(
      setupDone: true,
      locked: false,
      lastUnlock: UnlockInfo(UnlockMethod.face, DateTime.now(), null),
    );
  }

  /// After Settings → Delete all data.
  void resetToSetup() {
    state = const LockState(setupDone: false, locked: true);
  }

  Future<void> faceUnlocked(double score) async {
    final c = state.counters;
    await _setCounters(LockCounters(
        pinFailures: c.pinFailures, lockoutLevel: c.lockoutLevel, lockoutUntil: c.lockoutUntil));
    state = state.copyWith(
      locked: false,
      lastUnlock: UnlockInfo(UnlockMethod.face, DateTime.now(), score),
    );
    await _events.log(EventType.unlockFace, score: score);
  }

  /// One scan window (several seconds) ended without a match.
  Future<void> faceScanFailed({double? bestScore}) async {
    final c = state.counters;
    await _setCounters(LockCounters(
      faceFailures: c.faceFailures + 1,
      pinFailures: c.pinFailures,
      lockoutLevel: c.lockoutLevel,
      lockoutUntil: c.lockoutUntil,
    ));
    await _events.log(EventType.unlockFail, score: bestScore);
  }

  /// Checks the PIN. With [unlock] false (re-auth inside the app) a correct PIN
  /// only confirms the owner, but wrong PINs still count toward the lockout.
  Future<PinOutcome> submitPin(String pin, {bool unlock = true}) async {
    final until = state.lockoutUntil;
    if (until != null) return PinLockedOut(until);

    final ok = await ref.read(servicesProvider).pin.verify(pin);
    final c = state.counters;
    if (ok) {
      await _setCounters(const LockCounters());
      if (unlock) {
        state = state.copyWith(
            locked: false, lastUnlock: UnlockInfo(UnlockMethod.pin, DateTime.now(), null));
        await _events.log(EventType.unlockPin);
      } else {
        await _events.log(EventType.reauth, detail: 'pin');
      }
      return const PinOk();
    }

    final failures = c.pinFailures + 1;
    await _events.log(EventType.pinFail);
    if (failures % pinsPerLockout == 0) {
      final level = c.lockoutLevel + 1;
      final secs = min(_baseLockout.inSeconds * pow(2, level - 1).toInt(), 3600);
      final lockUntil = DateTime.now().add(Duration(seconds: secs));
      await _setCounters(LockCounters(
        faceFailures: c.faceFailures,
        pinFailures: failures,
        lockoutLevel: level,
        lockoutUntil: lockUntil,
      ));
      await _events.log(EventType.pinLockout, detail: '${secs}s');
      return PinLockedOut(lockUntil);
    }
    await _setCounters(LockCounters(
      faceFailures: c.faceFailures,
      pinFailures: failures,
      lockoutLevel: c.lockoutLevel,
    ));
    return PinWrong(pinsPerLockout - failures % pinsPerLockout);
  }
}
