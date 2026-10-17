import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/identity.dart';
import '../../widgets/common.dart';
import '../enrollment/enroll_page.dart';
import '../unlock/reauth_page.dart';

/// Name + role → owner confirms (face or PIN) → guided face scan.
class NewOperatorPage extends ConsumerStatefulWidget {
  const NewOperatorPage({super.key});

  @override
  ConsumerState<NewOperatorPage> createState() => _NewOperatorPageState();
}

class _NewOperatorPageState extends ConsumerState<NewOperatorPage> {
  final _name = TextEditingController();
  Role _role = Role.operator;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final name = _name.text.trim();
    final ok = await confirmOwner(context, 'Confirm before registering $name.');
    if (!ok || !mounted) return;
    final saved = await context.push<bool>('/enroll', extra: NewPersonRequest(name, _role));
    if (saved == true && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register person')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          const SectionLabel('Name'),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Full name', counterText: ''),
            onChanged: (_) => setState(() {}),
          ),
          const SectionLabel('Role'),
          SegmentedButton<Role>(
            segments: [
              for (final r in Role.values) ButtonSegment(value: r, label: Text(r.label)),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 24),
          const Text(
            'Next, you confirm it\'s you, then the person looks at the camera and '
            'follows 5 short prompts. Only encrypted face embeddings are saved.',
            style: TextStyle(color: AppColors.muted, height: 1.4),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _name.text.trim().isEmpty ? null : _continue,
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
