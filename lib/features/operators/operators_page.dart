import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../widgets/common.dart';

class OperatorsPage extends ConsumerWidget {
  const OperatorsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(galleryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Operators')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/operators/new'),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Register person'),
      ),
      body: people.length <= 1
          ? _Empty(hasOwner: people.isNotEmpty)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              itemCount: people.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = people[i];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: InitialsAvatar(p),
                    title: Text(p.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text(p.isOwner ? 'Owner · ${p.role.label}' : p.role.label,
                        style: const TextStyle(color: AppColors.muted)),
                    trailing: p.needsRescan
                        ? const StatusPill('Re-scan', color: AppColors.amber)
                        : const Icon(Icons.chevron_right, color: AppColors.muted),
                    onTap: () => context.push('/operators/${p.id}'),
                  ),
                );
              },
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.hasOwner});
  final bool hasOwner;

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_outlined, size: 48, color: AppColors.muted),
            SizedBox(height: 12),
            Text('No operators yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            SizedBox(height: 6),
            Text(
              'Register the people who work at this robot cell. Each scan takes '
              'about 20 seconds and needs your confirmation.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
