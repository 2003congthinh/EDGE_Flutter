import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../core/auth/pin_service.dart';

/// Six dots and a numeric keypad. Calls [onCompleted] when all digits are in,
/// then clears itself.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.onCompleted, this.message, this.error = false, this.enabled = true});

  final Future<void> Function(String pin) onCompleted;
  final String? message;
  final bool error;
  final bool enabled;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  bool _busy = false;

  Future<void> _tap(String d) async {
    if (_busy || !widget.enabled || _pin.length >= PinService.length) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    if (_pin.length == PinService.length) {
      setState(() => _busy = true);
      try {
        await widget.onCompleted(_pin);
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _pin = '';
          });
        }
      }
    }
  }

  void _back() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final msgColor = widget.error ? AppColors.red : AppColors.muted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < PinService.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? AppColors.cyan : Colors.transparent,
                  border: Border.all(
                      color: i < _pin.length ? AppColors.cyan : AppColors.muted, width: 1.5),
                ),
              ),
          ],
        ),
        SizedBox(
          height: 40,
          child: Center(
            child: _busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(widget.message ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: msgColor, fontSize: 13)),
          ),
        ),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', '<'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final k in row)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: SizedBox(
                    width: 72,
                    height: 60,
                    child: k.isEmpty
                        ? null
                        : TextButton(
                            onPressed: !widget.enabled
                                ? null
                                : k == '<'
                                    ? _back
                                    : () => _tap(k),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.text,
                              backgroundColor: k == '<' ? null : AppColors.surface,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: k == '<'
                                ? const Icon(Icons.backspace_outlined, size: 22)
                                : Text(k,
                                    style: const TextStyle(
                                        fontSize: 24, fontWeight: FontWeight.w500)),
                          ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
