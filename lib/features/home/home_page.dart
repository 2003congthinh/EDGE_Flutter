import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/auth/lock_controller.dart';
import '../../widgets/common.dart';

String hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Events logged today, for the Activity tile.
final todayEventsProvider = FutureProvider.autoDispose<int>((ref) {
  ref.watch(galleryProvider); // refresh after registrations
  ref.watch(lockProvider);
  final now = DateTime.now();
  return ref
      .read(servicesProvider)
      .events
      .countSince(DateTime(now.year, now.month, now.day));
});

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(lockProvider);
    final gallery = ref.watch(galleryProvider);
    final owner = ref.watch(ownerProvider);
    final placeholder = ref.watch(modelInfoProvider).placeholderEmbedder;
    final today = ref.watch(todayEventsProvider).value;
    final operators = gallery.where((p) => !p.isOwner).length;
    final rescans = gallery.where((p) => p.needsRescan).length;

    final last = lock.lastUnlock;
    final status = last == null
        ? 'Unlocked'
        : switch (last.method) {
            UnlockMethod.face => 'Unlocked by face · ${hhmm(last.at)}'
                '${last.score != null ? ' · ${last.score!.toStringAsFixed(2)}' : ''}',
            UnlockMethod.pin => 'Unlocked by PIN · ${hhmm(last.at)}',
          };

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: AppColors.cyan),
            SizedBox(width: 8),
            Text('Operator Pass'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Lock now',
            icon: const Icon(Icons.lock_outline),
            onPressed: () => ref.read(lockProvider.notifier).lock(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text('Hello, ${owner?.name ?? 'owner'}',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(status, color: AppColors.cyan, icon: Icons.verified_user_outlined),
              const StatusPill('offline', icon: Icons.wifi_off_rounded),
            ],
          ),
          if (placeholder) ...[
            const SizedBox(height: 14),
            const PlaceholderMatcherBanner(),
          ],
          if (rescans > 0) ...[
            const SizedBox(height: 14),
            _Notice(
              text: owner?.needsRescan == true
                  ? 'Your login face was registered with a different model. '
                      'Re-scan it so face unlock works again.'
                  : '$rescans ${rescans == 1 ? 'person needs' : 'people need'} a re-scan '
                      'because the face model changed.',
              action: owner?.needsRescan == true ? 'Settings' : 'Operators',
              onTap: () => context.push(owner?.needsRescan == true ? '/settings' : '/operators'),
            ),
          ],
          const SizedBox(height: 18),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.25,
            children: [
              _Tile(
                icon: Icons.badge_outlined,
                title: 'Operators',
                subtitle: '$operators registered',
                onTap: () => context.push('/operators'),
              ),
              _Tile(
                icon: Icons.history,
                title: 'Activity',
                subtitle: today == null ? ' ' : '$today today',
                onTap: () => context.push('/activity'),
              ),
              _Tile(
                icon: Icons.tune,
                title: 'Settings',
                subtitle: 'Face, PIN',
                onTap: () => context.push('/settings'),
              ),
              _Tile(
                icon: Icons.science_outlined,
                title: 'Dev Lab',
                subtitle: 'Scores, timings',
                onTap: () => context.push('/dev'),
              ),
              const _Tile(
                icon: Icons.smart_toy_outlined,
                title: 'Robot View',
                subtitle: 'Next phase',
              ),
              const _Tile(
                icon: Icons.how_to_reg_outlined,
                title: 'Check-in',
                subtitle: 'Next phase',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.subtitle, this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1 : .45,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.cyan),
                const Spacer(),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.action, required this.onTap});
  final String text, action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            const Icon(Icons.refresh, color: AppColors.amber),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
            TextButton(onPressed: onTap, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
