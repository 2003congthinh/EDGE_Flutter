import 'dart:typed_data';

import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/ml/vectors.dart';
import 'database.dart';
import 'identity.dart';

class IdentityRepository {
  IdentityRepository(this._h);
  final DbHandle _h;
  Database get _db => _h.db;

  /// Everyone, with only the embeddings produced by [modelId].
  Future<List<Identity>> all(String modelId) async {
    final people = await _db.query('identities',
        orderBy: 'is_owner DESC, created_at ASC');
    final rows = await _db.query('embeddings',
        columns: ['identity_id', 'vector', 'model']);
    final current = <String, List<Float32List>>{};
    final stale = <String, int>{};
    for (final r in rows) {
      final id = r['identity_id'] as String;
      if (r['model'] == modelId) {
        (current[id] ??= []).add(fromBlob(r['vector'] as Uint8List));
      } else {
        stale[id] = (stale[id] ?? 0) + 1;
      }
    }
    return [
      for (final p in people)
        Identity(
          id: p['id'] as String,
          name: p['name'] as String,
          role: Role.parse(p['role'] as String),
          isOwner: (p['is_owner'] as int) == 1,
          createdAt: DateTime.fromMillisecondsSinceEpoch(p['created_at'] as int),
          embeddings: current[p['id']] ?? const [],
          staleCount: stale[p['id']] ?? 0,
        )
    ];
  }

  Future<bool> ownerExists() async =>
      (await _db.query('identities', where: 'is_owner = 1', limit: 1)).isNotEmpty;

  /// Registers a person and their embeddings in one transaction. Returns the new id.
  Future<String> create({
    required String name,
    required Role role,
    required List<Float32List> embeddings,
    required String modelId,
    bool isOwner = false,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((tx) async {
      if (isOwner) await tx.update('identities', {'is_owner': 0});
      await tx.insert('identities', {
        'id': id,
        'name': name,
        'role': role.name,
        'is_owner': isOwner ? 1 : 0,
        'created_at': now,
      });
      await _insertEmbeddings(tx, id, embeddings, modelId, now);
    });
    return id;
  }

  /// Re-scan / change my face: old vectors are deleted and new ones inserted in
  /// a single transaction, so a failure never leaves the person without a face.
  Future<void> replaceEmbeddings(
      String id, List<Float32List> embeddings, String modelId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((tx) async {
      await tx.delete('embeddings', where: 'identity_id = ?', whereArgs: [id]);
      await _insertEmbeddings(tx, id, embeddings, modelId, now);
    });
  }

  /// "Add appearance" (glasses, different light): keeps the newest [cap] vectors.
  Future<void> addEmbeddings(String id, List<Float32List> embeddings,
      String modelId, {int cap = 30}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((tx) async {
      await _insertEmbeddings(tx, id, embeddings, modelId, now);
      await tx.rawDelete('''
        DELETE FROM embeddings WHERE identity_id = ? AND model = ? AND id NOT IN (
          SELECT id FROM embeddings WHERE identity_id = ? AND model = ?
          ORDER BY id DESC LIMIT ?)''', [id, modelId, id, modelId, cap]);
    });
  }

  Future<void> update(String id, {String? name, Role? role}) async {
    await _db.update(
      'identities',
      {'name': ?name, 'role': ?role?.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes a person and (by cascade) their embeddings. The owner can't be deleted.
  Future<void> delete(String id) async {
    await _db.delete('identities', where: 'id = ? AND is_owner = 0', whereArgs: [id]);
  }

  /// Removes every person (used only to discard an unfinished setup).
  Future<void> clearAll() async {
    await _db.delete('identities');
  }

  static Future<void> _insertEmbeddings(Transaction tx, String id,
      List<Float32List> embeddings, String modelId, int now) async {
    final batch = tx.batch();
    for (final e in embeddings) {
      batch.insert('embeddings', {
        'identity_id': id,
        'vector': toBlob(e),
        'model': modelId,
        'created_at': now,
      });
    }
    await batch.commit(noResult: true);
  }
}
