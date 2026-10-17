import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/event_repository.dart';
import '../../widgets/common.dart';
import '../enrollment/enroll_page.dart';
import '../setup/pin_setup_view.dart';
import '../unlock/reauth_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _changeFace(BuildContext context, WidgetRef ref) async {
    final owner = ref.read(ownerProvider);
    if (owner == null) return;
    if (!await confirmOwner(context, 'Confirm before changing your login face.') ||
        !context.mounted) {
      return;
    }
    await context.push<bool>('/enroll', extra: ChangeOwnerFaceRequest(owner));
  }

  Future<void> _changePin(BuildContext context) async {
    if (!await confirmOwner(context, 'Confirm before changing your PIN.') ||
        !context.mounted) {
      return;
    }
    await context.push('/settings/pin');
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all data?'),
        content: const Text(
          'Every registered face, your PIN, settings and the activity log are '
          'erased from this device, and the database key is replaced. This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    if (!await confirmOwner(context, 'Confirm before deleting all data.')) return;
    await ref.read(servicesProvider).dbh.wipe();
    await ref.read(galleryProvider.notifier).reload();
    await ref.read(settingsProvider.notifier).reload();
    ref.read(lockProvider.notifier).resetToSetup(); // router moves to /setup
  }

  Future<void> _saveSettings(WidgetRef ref, Future<void> Function() save, String what) async {
    await save();
    await ref.read(servicesProvider).events.log(EventType.settingsChanged, detail: what);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final info = ref.watch(modelInfoProvider);
    final owner = ref.watch(ownerProvider);
    final t = settings.thresholds;
    final ctrl = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SectionLabel('Security'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.face_retouching_natural),
                  title: const Text('Change my face'),
                  subtitle: Text(owner?.needsRescan == true
                      ? 'Needed: the face model changed'
                      : 'Replace the face that unlocks the app'),
                  trailing: owner?.needsRescan == true
                      ? const StatusPill('Re-scan', color: AppColors.amber)
                      : null,
                  onTap: () => _changeFace(context, ref),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.dialpad),
                  title: const Text('Change PIN'),
                  onTap: () => _changePin(context),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Lock after leaving the app'),
                  trailing: DropdownButton<int>(
                    value: settings.relockSeconds,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Immediately')),
                      DropdownMenuItem(value: 30, child: Text('30 s')),
                      DropdownMenuItem(value: 60, child: Text('1 min')),
                      DropdownMenuItem(value: 300, child: Text('5 min')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        _saveSettings(ref, () => ctrl.update(settings.copyWith(relockSeconds: v)),
                            'relock ${v}s');
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SectionLabel('Matching thresholds'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Calibrate in Dev Lab: set Unlock above every score another '
                    'person gets, plus a margin. Values are saved for the current model only.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
                  ),
                  _ThresholdSlider(
                    label: 'Unlock (strict)',
                    value: t.unlock,
                    onChanged: (v) => ctrl.update(settings.copyWith(
                        thresholds: t.copyWith(unlock: v, label: v < t.label ? v : null))),
                    onChangeEnd: (v) => ref
                        .read(servicesProvider)
                        .events
                        .log(EventType.settingsChanged, detail: 'unlock ${v.toStringAsFixed(2)}'),
                  ),
                  _ThresholdSlider(
                    label: 'Name label',
                    value: t.label,
                    max: t.unlock,
                    onChanged: (v) =>
                        ctrl.update(settings.copyWith(thresholds: t.copyWith(label: v))),
                  ),
                ],
              ),
            ),
          ),
          const SectionLabel('Models'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.center_focus_weak),
                  title: const Text('Face detector'),
                  subtitle: Text('face_detector.tflite · ${info.detectorInput} px · ${info.detectorHead}'),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.fingerprint),
                  title: const Text('Face embedder'),
                  subtitle: Text(info.placeholderEmbedder
                      ? 'Placeholder LBP matcher (${info.embedderDim}-d). Not secure.'
                      : 'face_embedder.tflite · ${info.embedderDim}-d · ${info.embedderId}'),
                  trailing: info.placeholderEmbedder
                      ? const Icon(Icons.warning_amber_rounded, color: AppColors.amber)
                      : null,
                ),
              ],
            ),
          ),
          const SectionLabel('Data'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete_forever_outlined, color: AppColors.red),
              title: const Text('Delete all data', style: TextStyle(color: AppColors.red)),
              subtitle: const Text('Faces, PIN, settings and activity log'),
              onTap: () => _deleteAll(context, ref),
            ),
          ),
          const SectionLabel('About'),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Operator Pass 1.0 · offline face ID for people who work with robots.\n\n'
                'This build has no internet permission. Faces are stored only as '
                'encrypted embeddings in an SQLCipher database whose key lives in the '
                'Android Keystore. Without liveness detection this is a convenience '
                'lock: a good photo of the owner may pass.',
                style: TextStyle(color: AppColors.muted, height: 1.45),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThresholdSlider extends StatelessWidget {
  const _ThresholdSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.max = .95,
  });

  final String label;
  final double value, max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    const min = .2;
    final hi = max < min + .05 ? min + .05 : max;
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label)),
        Expanded(
          child: Slider(
            min: min,
            max: hi,
            value: value.clamp(min, hi),
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        Text(value.toStringAsFixed(2), style: const TextStyle(fontFamily: monoFont)),
      ],
    );
  }
}

/// Reached after re-auth from Settings → Change PIN.
class ChangePinPage extends ConsumerWidget {
  const ChangePinPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SecureScreen(
      child: Scaffold(
        appBar: AppBar(title: const Text('Change PIN')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            PinSetupView(onComplete: (pin) async {
              final s = ref.read(servicesProvider);
              await s.pin.setPin(pin);
              await s.events.log(EventType.pinChanged);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('PIN changed')));
              context.pop();
            }),
          ],
        ),
      ),
    );
  }
}
