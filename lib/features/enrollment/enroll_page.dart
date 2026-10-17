import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/event_repository.dart';
import '../../data/identity.dart';
import 'enrollment_view.dart';

/// What a registration scan is for.
sealed class EnrollRequest {
  const EnrollRequest();
}

class NewPersonRequest extends EnrollRequest {
  final String name;
  final Role role;
  const NewPersonRequest(this.name, this.role);
}

class RescanRequest extends EnrollRequest {
  final Identity person;
  const RescanRequest(this.person);
}

class AddAppearanceRequest extends EnrollRequest {
  final Identity person;
  const AddAppearanceRequest(this.person);
}

/// Settings → Change my face.
class ChangeOwnerFaceRequest extends EnrollRequest {
  final Identity owner;
  const ChangeOwnerFaceRequest(this.owner);
}

/// Runs a scan for an [EnrollRequest] and saves the result. Pops `true` on success.
class EnrollPage extends ConsumerWidget {
  const EnrollPage({super.key, required this.request});
  final EnrollRequest request;

  (String title, String name, String? excludeId) get _labels => switch (request) {
        NewPersonRequest(:final name) => ('Register face', name, null),
        RescanRequest(:final person) => ('Re-scan face', person.name, person.id),
        AddAppearanceRequest(:final person) => ('Add appearance', person.name, person.id),
        ChangeOwnerFaceRequest(:final owner) => ('Change my face', owner.name, owner.id),
      };

  Future<void> _save(BuildContext context, WidgetRef ref, List<Float32List> e) async {
    final s = ref.read(servicesProvider);
    final repo = s.identities;
    final String message;
    switch (request) {
      case NewPersonRequest(:final name, :final role):
        final id = await repo.create(name: name, role: role, embeddings: e, modelId: s.modelId);
        await s.events.log(EventType.enrolled, identityId: id, name: name, detail: role.label);
        message = '$name registered';
      case RescanRequest(:final person):
        await repo.replaceEmbeddings(person.id, e, s.modelId);
        await s.events.log(EventType.rescanned, identityId: person.id, name: person.name);
        message = '${person.name} re-scanned';
      case AddAppearanceRequest(:final person):
        await repo.addEmbeddings(person.id, e, s.modelId);
        await s.events.log(EventType.appearanceAdded, identityId: person.id, name: person.name);
        message = 'Appearance added for ${person.name}';
      case ChangeOwnerFaceRequest(:final owner):
        await repo.replaceEmbeddings(owner.id, e, s.modelId);
        await s.events.log(EventType.faceChanged, identityId: owner.id, name: owner.name);
        message = 'Your login face was updated';
    }
    await ref.read(galleryProvider.notifier).reload();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    context.pop(true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (title, name, excludeId) = _labels;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: EnrollmentView(
        personName: name,
        excludeId: excludeId,
        onComplete: (e) => _save(context, ref, e),
      ),
    );
  }
}
