import 'package:sqflite_sqlcipher/sqflite.dart';

import '../core/ml/thresholds.dart';
import 'database.dart';

class AppSettings {
  final Thresholds thresholds;
  final int relockSeconds;
  const AppSettings({required this.thresholds, required this.relockSeconds});

  AppSettings copyWith({Thresholds? thresholds, int? relockSeconds}) => AppSettings(
        thresholds: thresholds ?? this.thresholds,
        relockSeconds: relockSeconds ?? this.relockSeconds,
      );
}

/// Key/value settings in the encrypted DB. Thresholds are stored per
/// embedding model because their values only make sense for one model.
class SettingsRepository {
  SettingsRepository(this._h);
  final DbHandle _h;
  Database get _db => _h.db;

  Future<AppSettings> load(String modelId, {required bool placeholder}) async {
    final rows = await _db.query('settings');
    final m = {for (final r in rows) r['key'] as String: r['value'] as String};
    final d = Thresholds.defaultsFor(placeholder: placeholder);
    double read(String k, double def) =>
        double.tryParse(m['$k:$modelId'] ?? '') ?? def;
    return AppSettings(
      thresholds: Thresholds(
        unlock: read('unlock', d.unlock),
        label: read('label', d.label),
        outlier: read('outlier', d.outlier),
      ),
      relockSeconds: int.tryParse(m['relock_seconds'] ?? '') ?? 30,
    );
  }

  Future<void> save(AppSettings s, String modelId) async {
    final batch = _db.batch();
    void put(String k, Object v) => batch.insert('settings', {'key': k, 'value': '$v'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    put('unlock:$modelId', s.thresholds.unlock);
    put('label:$modelId', s.thresholds.label);
    put('outlier:$modelId', s.thresholds.outlier);
    put('relock_seconds', s.relockSeconds);
    await batch.commit(noResult: true);
  }
}
