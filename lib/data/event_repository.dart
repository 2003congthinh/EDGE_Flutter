import 'package:sqflite_sqlcipher/sqflite.dart';

import 'database.dart';

/// Kinds of entries in the offline audit log.
enum EventType {
  setupComplete('Owner registered'),
  unlockFace('Unlocked by face'),
  unlockPin('Unlocked by PIN'),
  unlockFail('Face not recognized'),
  pinFail('Wrong PIN'),
  pinLockout('PIN locked out'),
  pinChanged('PIN changed'),
  enrolled('Person registered'),
  rescanned('Face re-scanned'),
  appearanceAdded('Appearance added'),
  faceChanged('Owner face changed'),
  duplicateBlocked('Duplicate face blocked'),
  personUpdated('Person updated'),
  personDeleted('Person deleted'),
  reauth('Owner confirmed'),
  settingsChanged('Settings changed');

  const EventType(this.label);
  final String label;

  static EventType? parse(String s) =>
      EventType.values.where((t) => t.name == s).firstOrNull;
}

class AppEvent {
  final int id;
  final DateTime ts;
  final EventType? type;
  final String rawType;
  final String? identityId, name, detail;
  final double? score;

  const AppEvent({
    required this.id,
    required this.ts,
    required this.type,
    required this.rawType,
    this.identityId,
    this.name,
    this.detail,
    this.score,
  });

  String get label => type?.label ?? rawType;
}

class EventRepository {
  EventRepository(this._h);
  final DbHandle _h;
  Database get _db => _h.db;

  Future<void> log(EventType type,
      {String? identityId, String? name, double? score, String? detail}) async {
    await _db.insert('events', {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'type': type.name,
      'identity_id': identityId,
      'name': name,
      'score': score,
      'detail': detail,
    });
  }

  Future<List<AppEvent>> recent({int limit = 500}) async {
    final rows = await _db.query('events', orderBy: 'ts DESC, id DESC', limit: limit);
    return [
      for (final r in rows)
        AppEvent(
          id: r['id'] as int,
          ts: DateTime.fromMillisecondsSinceEpoch(r['ts'] as int),
          type: EventType.parse(r['type'] as String),
          rawType: r['type'] as String,
          identityId: r['identity_id'] as String?,
          name: r['name'] as String?,
          score: (r['score'] as num?)?.toDouble(),
          detail: r['detail'] as String?,
        )
    ];
  }

  Future<int> countSince(DateTime since) async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS n FROM events WHERE ts >= ?',
        [since.millisecondsSinceEpoch]);
    return (r.first['n'] as int?) ?? 0;
  }
}
