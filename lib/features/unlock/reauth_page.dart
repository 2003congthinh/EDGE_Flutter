import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/event_repository.dart';
import '../../widgets/common.dart';
import 'owner_face_scan.dart';
import 'pin_entry.dart';

/// Asks the owner to confirm with a fresh face scan or the PIN before a
/// sensitive action (registering someone, changing the login face or PIN).
/// Returns true when confirmed.
Future<bool> confirmOwner(BuildContext context, String reason) async =>
    await context.push<bool>('/reauth', extra: reason) ?? false;

class ReauthPage extends ConsumerStatefulWidget {
  const ReauthPage({super.key, required this.reason});
  final String reason;

  @override
  ConsumerState<ReauthPage> createState() => _ReauthPageState();
}

class _ReauthPageState extends ConsumerState<ReauthPage> {
  bool _usePin = false;

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(ownerProvider);
    final faceUnavailable = owner == null || owner.needsRescan;
    final showPin = _usePin || faceUnavailable;

    return SecureScreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Confirm it's you"),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.pop(false),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(widget.reason,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, height: 1.4)),
            const SizedBox(height: 22),
            if (showPin) ...[
              PinEntry(unlock: false, onSuccess: () => context.pop(true)),
              if (!faceUnavailable)
                TextButton.icon(
                  onPressed: () => setState(() => _usePin = false),
                  icon: const Icon(Icons.face_retouching_natural),
                  label: const Text('Use face instead'),
                ),
            ] else ...[
              OwnerFaceScan(
                onMatched: (score) async {
                  await ref
                      .read(servicesProvider)
                      .events
                      .log(EventType.reauth, score: score, detail: 'face');
                  if (context.mounted) context.pop(true);
                },
                onTimeout: (_) async {},
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () => setState(() => _usePin = true),
                icon: const Icon(Icons.dialpad),
                label: const Text('Use PIN instead'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
