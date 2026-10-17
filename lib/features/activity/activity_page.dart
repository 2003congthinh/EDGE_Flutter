import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/event_repository.dart';
import '../home/home_page.dart';

final _eventsProvider = FutureProvider.autoDispose<List<AppEvent>>(
    (ref) => ref.read(servicesProvider).events.recent());

enum _Filter {
  all('All'),
  unlocks('Unlocks'),
  failures('Failures'),
  people('People');

  const _Filter(this.label);
  final String label;

  bool accepts(EventType? t) => switch (this) {
        _Filter.all => true,
        _Filter.unlocks => t == EventType.unlockFace || t == EventType.unlockPin,
        _Filter.failures => t == EventType.unlockFail ||
            t == EventType.pinFail ||
            t == EventType.pinLockout ||
            t == EventType.duplicateBlocked,
        _Filter.people => t == EventType.enrolled ||
            t == EventType.rescanned ||
            t == EventType.appearanceAdded ||
            t == EventType.faceChanged ||
            t == EventType.personUpdated ||
            t == EventType.personDeleted,
      };
}

/// The offline audit log, grouped by day.
class ActivityPage extends ConsumerStatefulWidget {
  const ActivityPage({super.key});

  @override
  ConsumerState<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends ConsumerState<ActivityPage> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(_eventsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in _Filter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: events.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (all) {
                final list = all.where((e) => _filter.accepts(e.type)).toList();
                if (list.isEmpty) {
                  return const Center(
                      child: Text('Nothing yet', style: TextStyle(color: AppColors.muted)));
                }
                final rows = <Widget>[];
                String? day;
                for (final e in list) {
                  final d = _dayLabel(e.ts);
                  if (d != day) {
                    day = d;
                    rows.add(Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                      child: Text(d.toUpperCase(),
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 12, letterSpacing: 1.1)),
                    ));
                  }
                  rows.add(_EventTile(e));
                }
                return ListView(padding: const EdgeInsets.only(bottom: 24), children: rows);
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _dayLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${t.day}/${t.month}/${t.year}';
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile(this.e);
  final AppEvent e;

  (IconData, Color) get _look => switch (e.type) {
        EventType.unlockFace || EventType.reauth => (Icons.face, AppColors.cyan),
        EventType.unlockPin => (Icons.dialpad, AppColors.cyan),
        EventType.unlockFail ||
        EventType.pinFail ||
        EventType.pinLockout ||
        EventType.duplicateBlocked =>
          (Icons.block, AppColors.red),
        EventType.enrolled ||
        EventType.rescanned ||
        EventType.appearanceAdded ||
        EventType.faceChanged ||
        EventType.setupComplete =>
          (Icons.person_add_alt, AppColors.amber),
        EventType.personDeleted => (Icons.person_remove_outlined, AppColors.muted),
        _ => (Icons.settings_outlined, AppColors.muted),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _look;
    final sub = [
      ?e.name,
      if (e.score != null) 'score ${e.score!.toStringAsFixed(2)}',
      ?e.detail,
    ].join(' · ');
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(e.label),
      subtitle: sub.isEmpty ? null : Text(sub, style: const TextStyle(color: AppColors.muted)),
      trailing: Text(hhmm(e.ts),
          style: const TextStyle(fontFamily: monoFont, color: AppColors.muted)),
    );
  }
}
