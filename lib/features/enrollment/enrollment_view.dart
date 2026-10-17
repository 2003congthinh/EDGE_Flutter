import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/auth/enrollment_session.dart';
import '../../core/ml/ml_worker.dart';
import '../../data/event_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/live_camera_view.dart';
import '../../widgets/scan_ring.dart';

/// The guided face scan used by owner setup, new operators, re-scan, add
/// appearance and change-my-face. It only produces embeddings; the caller
/// decides what to save, so a cancelled or failed scan never touches the DB.
class EnrollmentView extends ConsumerStatefulWidget {
  const EnrollmentView({
    super.key,
    required this.personName,
    required this.onComplete,
    this.excludeId,
  });

  final String personName;

  /// The person being re-scanned, left out of the duplicate check.
  final String? excludeId;
  final Future<void> Function(List<Float32List> embeddings) onComplete;

  @override
  ConsumerState<EnrollmentView> createState() => _EnrollmentViewState();
}

class _EnrollmentViewState extends ConsumerState<EnrollmentView> {
  late EnrollmentSession _s;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final gallery = ref.read(galleryProvider);
    _s = EnrollmentSession(
      thresholds: ref.read(settingsProvider).thresholds,
      others: [
        for (final p in gallery)
          if (p.id != widget.excludeId && !p.needsRescan) p
      ],
    );
  }

  void _onResult(FrameResult r) {
    final before = _s.phase;
    final captured = _s.onFrame(r, DateTime.now());
    if (captured) HapticFeedback.selectionClick();
    if (before != _s.phase) _onPhaseChanged();
    setState(() {});
  }

  Future<void> _onPhaseChanged() async {
    switch (_s.phase) {
      case EnrollPhase.verifying:
        HapticFeedback.lightImpact();
      case EnrollPhase.failed:
        HapticFeedback.heavyImpact();
        final dup = _s.duplicateId;
        if (dup != null) {
          final match = ref.read(galleryProvider).where((p) => p.id == dup).firstOrNull;
          await ref.read(servicesProvider).events.log(EventType.duplicateBlocked,
              identityId: dup,
              name: match?.name,
              detail: 'while registering ${widget.personName}');
        }
      case EnrollPhase.done:
        HapticFeedback.mediumImpact();
        setState(() => _saving = true);
        try {
          await widget.onComplete(_s.result);
        } finally {
          if (mounted) setState(() => _saving = false);
        }
      case EnrollPhase.capturing:
        break;
    }
  }

  IconData get _promptIcon => switch (_s.promptIndex) {
        1 => Icons.arrow_back_rounded,
        2 => Icons.arrow_forward_rounded,
        3 => Icons.arrow_upward_rounded,
        4 => Icons.arrow_downward_rounded,
        _ => Icons.center_focus_strong_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final placeholder = ref.watch(modelInfoProvider).placeholderEmbedder;
    final phase = _s.phase;
    final stopped = phase == EnrollPhase.done || phase == EnrollPhase.failed || _saving;
    final ringColor = phase == EnrollPhase.capturing ? AppColors.amber : AppColors.cyan;

    return SecureScreen(
      child: LayoutBuilder(builder: (context, c) {
        final ring = c.maxWidth.clamp(0.0, 340.0) * .82;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.personName,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text('${_s.samples.length} / ${_s.total}',
                    style: const TextStyle(fontFamily: monoFont, color: AppColors.muted)),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: SizedBox(
                width: ring,
                child: ScanRing(
                  segments: _s.total,
                  filled: phase == EnrollPhase.capturing ? _s.samples.length : _s.total,
                  color: phase == EnrollPhase.failed ? AppColors.red : ringColor,
                  scanning: !stopped,
                  child: LiveCameraView(onResult: _onResult, embed: true, paused: stopped),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (phase == EnrollPhase.failed)
              _failure(context)
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (phase == EnrollPhase.capturing) ...[
                    Icon(_promptIcon, color: AppColors.amber),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      _saving ? 'Saving…' : _s.instruction,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 32,
                child: Center(
                  child: _s.pausedBetweenPrompts
                      ? const StatusPill('Got it. Next pose…', color: AppColors.cyan)
                      : _s.hint != null
                          ? StatusPill(_s.hint!, color: AppColors.amber)
                          : const SizedBox.shrink(),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 14, color: AppColors.muted),
                SizedBox(width: 6),
                Text('Stored as encrypted numbers, never as photos',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
            if (placeholder) ...[
              const SizedBox(height: 10),
              const Center(child: PlaceholderMatcherBanner(compact: true)),
            ],
          ],
        );
      }),
    );
  }

  Widget _failure(BuildContext context) {
    final dup = _s.duplicateId;
    final match = dup == null
        ? null
        : ref.read(galleryProvider).where((p) => p.id == dup).firstOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_s.failure ?? 'Registration stopped',
                style: Theme.of(context).textTheme.titleMedium),
            if (match != null) ...[
              const SizedBox(height: 6),
              Text(
                'It matches ${match.name} (${match.isOwner ? 'Owner' : match.role.label}). '
                'One person can only be registered once. To update their face, '
                'use Re-scan on their profile.',
                style: const TextStyle(color: AppColors.muted, height: 1.35),
              ),
            ],
            const SizedBox(height: 14),
            if (_s.canRetry)
              FilledButton(
                onPressed: () => setState(_s.restart),
                child: const Text('Try again'),
              ),
          ],
        ),
      ),
    );
  }
}
