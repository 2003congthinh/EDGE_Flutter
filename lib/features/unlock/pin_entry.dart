import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/auth/lock_controller.dart';
import '../../widgets/pin_pad.dart';

/// PIN check with the shared wrong-PIN counter and lockout countdown.
/// [unlock] false = re-auth inside the app (doesn't change the lock state).
class PinEntry extends ConsumerStatefulWidget {
  const PinEntry({super.key, required this.onSuccess, this.unlock = true});
  final VoidCallback onSuccess;
  final bool unlock;

  @override
  ConsumerState<PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends ConsumerState<PinEntry> {
  String? _message;
  bool _error = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _startCountdownIfLocked();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _startCountdownIfLocked() {
    _tick?.cancel();
    if (ref.read(lockProvider).lockoutUntil == null) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (ref.read(lockProvider).lockoutUntil == null) {
        _tick?.cancel();
        setState(() {
          _message = 'Enter your PIN';
          _error = false;
        });
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _submit(String pin) async {
    final outcome =
        await ref.read(lockProvider.notifier).submitPin(pin, unlock: widget.unlock);
    if (!mounted) return;
    switch (outcome) {
      case PinOk():
        HapticFeedback.mediumImpact();
        widget.onSuccess();
      case PinWrong(:final attemptsLeft):
        HapticFeedback.heavyImpact();
        setState(() {
          _error = true;
          _message = 'Wrong PIN. $attemptsLeft '
              '${attemptsLeft == 1 ? 'attempt' : 'attempts'} before a lockout.';
        });
      case PinLockedOut():
        HapticFeedback.heavyImpact();
        setState(() => _error = true);
        _startCountdownIfLocked();
    }
  }

  @override
  Widget build(BuildContext context) {
    final until = ref.watch(lockProvider).lockoutUntil;
    String? message = _message ?? 'Enter your 6-digit PIN';
    if (until != null) {
      final left = until.difference(DateTime.now());
      final m = left.inMinutes, s = left.inSeconds % 60;
      message = 'Too many wrong PINs. Try again in '
          '${m > 0 ? '${m}m ' : ''}${s.toString().padLeft(m > 0 ? 2 : 1, '0')}s';
    }
    return PinPad(
      onCompleted: _submit,
      message: message,
      error: _error || until != null,
      enabled: until == null,
    );
  }
}
