import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../data/identity.dart';

/// Blocks screenshots and the recent-apps preview while it is on screen
/// (Android FLAG_SECURE). Reference-counted, so nested screens are safe.
class SecureScreen extends StatefulWidget {
  const SecureScreen({super.key, required this.child});
  final Widget child;

  static const _channel = MethodChannel('operatorpass/window');
  static int _count = 0;

  static Future<void> _set(bool on) async {
    try {
      await _channel.invokeMethod('setSecure', {'secure': on});
    } on MissingPluginException {
      // Not on Android (tests, desktop): nothing to do.
    }
  }

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  @override
  void initState() {
    super.initState();
    if (SecureScreen._count++ == 0) SecureScreen._set(true);
  }

  @override
  void dispose() {
    if (--SecureScreen._count == 0) SecureScreen._set(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A small rounded status label: Recognized, Unknown, Scanning, Offline…
class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.color = AppColors.muted, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Initials in a circle. No photos are ever stored.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.person, {super.key, this.size = 44});
  final Identity person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = person.isOwner ? AppColors.cyan : AppColors.amber;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .14),
        border: Border.all(color: color.withValues(alpha: .5)),
      ),
      child: Text(person.initials,
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size * .36)),
    );
  }
}

/// Shown while the built-in placeholder matcher stands in for a real embedder.
class PlaceholderMatcherBanner extends StatelessWidget {
  const PlaceholderMatcherBanner({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const StatusPill('Test matcher: not secure',
          color: AppColors.amber, icon: Icons.science_outlined);
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.amber.withValues(alpha: .4)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, color: AppColors.amber, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Test matcher in use. No face embedding model was found, so a simple '
              'texture matcher stands in. It is fine for testing the flow but is not '
              'secure. Add assets/models/face_embedder.tflite to switch.',
              style: TextStyle(color: AppColors.text, fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Heading + body text used on info screens.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600)),
      );
}
