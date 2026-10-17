import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/event_repository.dart';
import '../../data/identity.dart';
import '../../widgets/common.dart';
import '../enrollment/enrollment_view.dart';
import 'pin_setup_view.dart';

enum _Step { welcome, enroll, pin }

/// First launch: what the app does + consent → register the owner's face →
/// choose a backup PIN. Nothing is written until the last step, so quitting
/// half-way leaves no partial owner behind.
class SetupPage extends ConsumerStatefulWidget {
  const SetupPage({super.key});

  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  _Step _step = _Step.welcome;
  final _name = TextEditingController();
  bool _consent = false;
  List<Float32List> _embeddings = const [];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _finish(String pin) async {
    final s = ref.read(servicesProvider);
    final name = _name.text.trim();
    await s.identities.clearAll(); // leftovers of an earlier, unfinished setup
    await s.pin.setPin(pin);
    final id = await s.identities.create(
      name: name,
      role: Role.supervisor,
      embeddings: _embeddings,
      modelId: s.modelId,
      isOwner: true,
    );
    await s.events.log(EventType.setupComplete, identityId: id, name: name);
    await ref.read(galleryProvider.notifier).reload();
    await ref.read(lockProvider.notifier).completeSetup(); // router moves to /home
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == _Step.welcome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step = _Step.values[_step.index - 1]);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(switch (_step) {
            _Step.welcome => 'Welcome',
            _Step.enroll => 'Register your face',
            _Step.pin => 'Backup PIN',
          }),
          automaticallyImplyLeading: false,
          leading: _step == _Step.welcome
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _step = _Step.values[_step.index - 1]),
                ),
        ),
        body: SafeArea(
          child: switch (_step) {
            _Step.welcome => _welcome(context),
            _Step.enroll => EnrollmentView(
                personName: '${_name.text.trim()} · Owner',
                onComplete: (e) async => setState(() {
                  _embeddings = e;
                  _step = _Step.pin;
                }),
              ),
            _Step.pin => SecureScreen(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [PinSetupView(onComplete: _finish)],
                ),
              ),
          },
        ),
      ),
    );
  }

  Widget _welcome(BuildContext context) {
    final ready = _consent && _name.text.trim().isNotEmpty;
    final placeholder = ref.watch(modelInfoProvider).placeholderEmbedder;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Row(
          children: [
            const Icon(Icons.shield_outlined, color: AppColors.cyan, size: 30),
            const SizedBox(width: 10),
            Text('Operator Pass', style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
        const SizedBox(height: 6),
        const Text('Offline face ID for people who work with robots.',
            style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 20),
        const _InfoCard(
          icon: Icons.wifi_off_rounded,
          title: 'Fully offline',
          body: 'Detection and recognition run on this phone. The app has no '
              'internet permission, so nothing can leave the device.',
        ),
        const SizedBox(height: 10),
        const _InfoCard(
          icon: Icons.lock_outline,
          title: 'Private by design',
          body: 'Faces are stored as encrypted numbers (embeddings), never as '
              'photos. You can delete everything at any time in Settings.',
        ),
        const SizedBox(height: 10),
        const _InfoCard(
          icon: Icons.verified_user_outlined,
          title: 'What it does',
          body: 'You become the owner. The app opens only for your face (or your '
              'backup PIN), and you register the operators who work at your robot cell.',
        ),
        if (placeholder) ...[
          const SizedBox(height: 10),
          const PlaceholderMatcherBanner(),
        ],
        const SectionLabel('Your name'),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          maxLength: 40,
          decoration: const InputDecoration(hintText: 'e.g. Nguyen Van An', counterText: ''),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _consent,
          onChanged: (v) => setState(() => _consent = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'I agree that my face data (embeddings) is stored encrypted on this '
            'device to verify my identity.',
            style: TextStyle(fontSize: 14, height: 1.35),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: ready ? () => setState(() => _step = _Step.enroll) : null,
          child: const Text('Register my face'),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title, body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.cyan),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(body, style: const TextStyle(color: AppColors.muted, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
