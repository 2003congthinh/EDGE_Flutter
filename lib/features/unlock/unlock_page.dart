import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/auth/lock_controller.dart';
import '../../widgets/common.dart';
import 'owner_face_scan.dart';
import 'pin_entry.dart';

/// The lock screen. Face first; the PIN is always one tap away, and becomes
/// the only option after 5 failed scans or when the owner's face needs a re-scan.
class UnlockPage extends ConsumerStatefulWidget {
  const UnlockPage({super.key});

  @override
  ConsumerState<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends ConsumerState<UnlockPage> {
  bool _usePin = false;

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(lockProvider);
    final owner = ref.watch(ownerProvider);
    final placeholder = ref.watch(modelInfoProvider).placeholderEmbedder;
    final faceUnavailable = owner == null || owner.needsRescan;
    final pinOnly = lock.faceBlocked || faceUnavailable;
    final showPin = _usePin || pinOnly;
    final attemptsLeft = LockController.maxFaceFailures - lock.faceFailures;

    return SecureScreen(
      child: PopScope(
        canPop: false, // the back button never gets past the lock
        child: Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: AppColors.cyan),
                    const SizedBox(width: 8),
                    Text('Operator Pass', style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    const StatusPill('offline', icon: Icons.wifi_off_rounded),
                  ],
                ),
                const SizedBox(height: 28),
                if (showPin) ...[
                  if (pinOnly)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Text(
                        faceUnavailable
                            ? 'Face unlock needs a new scan (the face model changed). '
                                'Unlock with your PIN, then re-scan in Settings.'
                            : 'Face unlock is paused after ${LockController.maxFaceFailures} '
                                'failed scans. Unlock with your PIN.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.muted, height: 1.4),
                      ),
                    ),
                  PinEntry(onSuccess: () {}),
                  if (!pinOnly)
                    TextButton.icon(
                      onPressed: () => setState(() => _usePin = false),
                      icon: const Icon(Icons.face_retouching_natural),
                      label: const Text('Use face instead'),
                    ),
                ] else ...[
                  OwnerFaceScan(
                    onMatched: (score) =>
                        ref.read(lockProvider.notifier).faceUnlocked(score),
                    onTimeout: (best) =>
                        ref.read(lockProvider.notifier).faceScanFailed(bestScore: best),
                  ),
                  const SizedBox(height: 4),
                  if (lock.faceFailures > 0)
                    Text('$attemptsLeft face ${attemptsLeft == 1 ? 'attempt' : 'attempts'} '
                        'left before PIN is required',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _usePin = true),
                    icon: const Icon(Icons.dialpad),
                    label: const Text('Use PIN instead'),
                  ),
                ],
                const SizedBox(height: 22),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.memory, size: 14, color: AppColors.muted),
                    SizedBox(width: 6),
                    Text('on-device · no network',
                        style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
                if (placeholder) ...[
                  const SizedBox(height: 10),
                  const Center(child: PlaceholderMatcherBanner(compact: true)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
