import 'dart:typed_data';

import '../core/ml/matcher.dart';

enum Role {
  operator('Operator'),
  technician('Technician'),
  supervisor('Supervisor');

  const Role(this.label);
  final String label;

  static Role parse(String s) =>
      Role.values.firstWhere((r) => r.name == s, orElse: () => Role.operator);
}

/// A registered person. [embeddings] holds only vectors from the current
/// embedding model; [staleCount] counts vectors from an older model.
class Identity implements Enrolled {
  @override
  final String id;
  final String name;
  final Role role;
  final bool isOwner;
  final DateTime createdAt;
  @override
  final List<Float32List> embeddings;
  final int staleCount;

  const Identity({
    required this.id,
    required this.name,
    required this.role,
    required this.isOwner,
    required this.createdAt,
    required this.embeddings,
    this.staleCount = 0,
  });

  /// Registered with a different model (or never scanned): face matching can't use it.
  bool get needsRescan => embeddings.isEmpty;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
