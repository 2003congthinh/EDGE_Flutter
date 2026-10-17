import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/event_repository.dart';
import '../../data/identity.dart';
import '../../widgets/common.dart';
import '../enrollment/enroll_page.dart';
import '../unlock/reauth_page.dart';

class OperatorDetailPage extends ConsumerWidget {
  const OperatorDetailPage({super.key, required this.id});
  final String id;

  Future<void> _scan(BuildContext context, EnrollRequest request, String reason) async {
    if (!await confirmOwner(context, reason) || !context.mounted) return;
    await context.push<bool>('/enroll', extra: request);
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Identity p) async {
    final ctrl = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty || name == p.name) return;
    await _update(ref, p, name: name);
  }

  Future<void> _update(WidgetRef ref, Identity p, {String? name, Role? role}) async {
    final s = ref.read(servicesProvider);
    await s.identities.update(p.id, name: name, role: role);
    await s.events.log(EventType.personUpdated,
        identityId: p.id,
        name: name ?? p.name,
        detail: [
          if (name != null) 'renamed from ${p.name}',
          if (role != null) 'role ${p.role.label} → ${role.label}',
        ].join(', '));
    await ref.read(galleryProvider.notifier).reload();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Identity p) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${p.name}?'),
        content: const Text(
            'Their face embeddings are erased from this device. Activity log entries stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    if (!await confirmOwner(context, 'Confirm before deleting ${p.name}.')) return;
    final s = ref.read(servicesProvider);
    await s.identities.delete(p.id);
    await s.events.log(EventType.personDeleted, identityId: p.id, name: p.name);
    await ref.read(galleryProvider.notifier).reload();
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(galleryProvider).where((x) => x.id == id).firstOrNull;
    if (p == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));
    }
    final d = p.createdAt;
    return Scaffold(
      appBar: AppBar(title: Text(p.isOwner ? 'Owner' : 'Operator')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            children: [
              InitialsAvatar(p, size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      '${p.isOwner ? 'Owner · ' : ''}${p.role.label} · since '
                      '${d.day}/${d.month}/${d.year}',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            p.needsRescan
                ? const StatusPill('Needs re-scan', color: AppColors.amber)
                : StatusPill('${p.embeddings.length} face samples',
                    color: AppColors.cyan, icon: Icons.lock_outline),
          ]),
          const SectionLabel('Details'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Name'),
                  subtitle: Text(p.name),
                  onTap: () => _rename(context, ref, p),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.work_outline),
                  title: const Text('Role'),
                  trailing: DropdownButton<Role>(
                    value: p.role,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final r in Role.values)
                        DropdownMenuItem(value: r, child: Text(r.label)),
                    ],
                    onChanged: (r) {
                      if (r != null && r != p.role) _update(ref, p, role: r);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SectionLabel('Face'),
          Card(
            child: Column(
              children: [
                if (p.isOwner)
                  ListTile(
                    leading: const Icon(Icons.face_retouching_natural),
                    title: const Text('Change my face'),
                    subtitle: const Text('Replaces your login face'),
                    onTap: () => _scan(context, ChangeOwnerFaceRequest(p),
                        'Confirm before changing your login face.'),
                  )
                else
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: const Text('Re-scan'),
                    subtitle: const Text('Replaces all stored samples'),
                    onTap: () => _scan(context, RescanRequest(p),
                        'Confirm before re-scanning ${p.name}.'),
                  ),
                if (!p.needsRescan) ...[
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.add_a_photo_outlined),
                    title: const Text('Add appearance'),
                    subtitle: const Text('Glasses, a hat, different light'),
                    onTap: () => _scan(context, AddAppearanceRequest(p),
                        'Confirm before adding an appearance for ${p.name}.'),
                  ),
                ],
              ],
            ),
          ),
          if (!p.isOwner) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => _delete(context, ref, p),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete person'),
            ),
          ],
        ],
      ),
    );
  }
}
