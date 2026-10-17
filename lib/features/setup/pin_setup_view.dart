import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../widgets/pin_pad.dart';

/// Enter a new 6-digit PIN twice. Rejects PINs that are trivial to guess.
class PinSetupView extends StatefulWidget {
  const PinSetupView({super.key, required this.onComplete});
  final Future<void> Function(String pin) onComplete;

  @override
  State<PinSetupView> createState() => _PinSetupViewState();
}

class _PinSetupViewState extends State<PinSetupView> {
  String? _first;
  String? _message;
  bool _error = false;

  static bool isWeak(String pin) {
    if (pin.split('').toSet().length == 1) return true; // 000000, 111111
    const asc = '0123456789', desc = '9876543210';
    return asc.contains(pin) || desc.contains(pin); // 123456, 987654
  }

  Future<void> _entered(String pin) async {
    final first = _first;
    if (first == null) {
      if (isWeak(pin)) {
        HapticFeedback.heavyImpact();
        setState(() {
          _error = true;
          _message = 'That PIN is too easy to guess. Pick another.';
        });
        return;
      }
      setState(() {
        _first = pin;
        _error = false;
        _message = 'Enter it again to confirm';
      });
      return;
    }
    if (pin != first) {
      HapticFeedback.heavyImpact();
      setState(() {
        _first = null;
        _error = true;
        _message = "The PINs didn't match. Start again.";
      });
      return;
    }
    await widget.onComplete(pin);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_first == null ? 'Choose a backup PIN' : 'Confirm your PIN',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Used when face unlock is not possible. Only a salted hash is stored.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, height: 1.4),
        ),
        const SizedBox(height: 22),
        PinPad(
          key: ValueKey(_first == null),
          onCompleted: _entered,
          message: _message ?? '6 digits',
          error: _error,
        ),
      ],
    );
  }
}
