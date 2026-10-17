import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Holds the encrypted SQLite database (SQLCipher). The key is random, created
/// on first launch and kept in the Android Keystore via flutter_secure_storage.
/// Only face embeddings are stored, never photos.
class DbHandle {
  DbHandle._(this.db, this._secure);

  static const _keyName = 'db_key';
  static const _fileName = 'operatorpass.db';

  Database db;
  final FlutterSecureStorage _secure;

  static Future<DbHandle> open(FlutterSecureStorage secure) async {
    return DbHandle._(await _open(secure), secure);
  }

  static Future<String> _path() async =>
      p.join(await getDatabasesPath(), _fileName);

  static Future<Database> _open(FlutterSecureStorage secure) async {
    final path = await _path();
    var key = await secure.read(key: _keyName);
    if (key == null) {
      // No key means any existing file is unreadable: start clean.
      await deleteDatabase(path);
      key = _randomKey();
      await secure.write(key: _keyName, value: key);
    }
    try {
      return await _openWith(path, key);
    } catch (e) {
      debugPrint('Database could not be decrypted, recreating: $e');
      await deleteDatabase(path);
      return _openWith(path, key);
    }
  }

  static Future<Database> _openWith(String path, String key) => openDatabase(
        path,
        password: key,
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSchema,
      );

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE identities (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        is_owner INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE embeddings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        identity_id TEXT NOT NULL REFERENCES identities(id) ON DELETE CASCADE,
        vector BLOB NOT NULL,
        model TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    await db.execute(
        'CREATE INDEX idx_embeddings_identity ON embeddings(identity_id)');
    await db.execute('''
      CREATE TABLE events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts INTEGER NOT NULL,
        type TEXT NOT NULL,
        identity_id TEXT,
        name TEXT,
        score REAL,
        detail TEXT
      )''');
    await db.execute('CREATE INDEX idx_events_ts ON events(ts)');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
  }

  /// Settings → Delete all data: removes the database file and every secret
  /// (PIN hash, counters, old DB key), then starts a fresh database with a new key.
  Future<void> wipe() async {
    await db.close();
    await deleteDatabase(await _path());
    await _secure.deleteAll();
    db = await _open(_secure);
  }

  static String _randomKey() {
    final r = Random.secure();
    return base64Encode(List<int>.generate(32, (_) => r.nextInt(256)));
  }
}
