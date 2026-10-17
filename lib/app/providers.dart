import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/auth/lock_controller.dart';
import '../core/auth/pin_service.dart';
import '../core/ml/ml_worker.dart';
import '../data/database.dart';
import '../data/event_repository.dart';
import '../data/identity.dart';
import '../data/identity_repository.dart';
import '../data/settings_repository.dart';

/// What the app knows at launch, read once before the first frame.
class BootSnapshot {
  final bool setupDone;
  final LockCounters counters;
  final List<Identity> gallery;
  final AppSettings settings;
  const BootSnapshot(this.setupDone, this.counters, this.gallery, this.settings);
}

/// Long-lived services, created once at start-up (see [AppServices.init]).
class AppServices {
  AppServices._(this.secure, this.dbh, this.worker, this.boot)
      : identities = IdentityRepository(dbh),
        events = EventRepository(dbh),
        settings = SettingsRepository(dbh),
        pin = PinService(secure);

  final FlutterSecureStorage secure;
  final DbHandle dbh;
  final MlWorker worker;
  final IdentityRepository identities;
  final EventRepository events;
  final SettingsRepository settings;
  final PinService pin;
  final BootSnapshot boot;

  String get modelId => worker.info.embedderId;

  static Future<AppServices> init() async {
    const secure = FlutterSecureStorage();
    final dbh = await DbHandle.open(secure);
    final worker = await MlWorker.start(); // loads models, warms the isolate
    final ids = IdentityRepository(dbh);
    final modelId = worker.info.embedderId;
    final setupDone = await ids.ownerExists() && await PinService(secure).isSet();
    final boot = BootSnapshot(
      setupDone,
      await LockController.readCounters(secure),
      await ids.all(modelId),
      await SettingsRepository(dbh)
          .load(modelId, placeholder: worker.info.placeholderEmbedder),
    );
    return AppServices._(secure, dbh, worker, boot);
  }
}

final servicesProvider = Provider<AppServices>(
    (ref) => throw UnimplementedError('Overridden in main()'));

final modelInfoProvider = Provider<ModelInfo>((ref) => ref.watch(servicesProvider).worker.info);

final lockProvider = NotifierProvider<LockController, LockState>(LockController.new);

final galleryProvider =
    NotifierProvider<GalleryController, List<Identity>>(GalleryController.new);

/// The owner (admin) identity, or null before setup.
final ownerProvider = Provider<Identity?>(
    (ref) => ref.watch(galleryProvider).where((p) => p.isOwner).firstOrNull);

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Everyone registered, with embeddings for the current model. The single
/// source the matchers read from; call [reload] after any DB change.
class GalleryController extends Notifier<List<Identity>> {
  @override
  List<Identity> build() => ref.read(servicesProvider).boot.gallery;

  Future<void> reload() async {
    final s = ref.read(servicesProvider);
    state = await s.identities.all(s.modelId);
  }
}

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(servicesProvider).boot.settings;

  Future<void> update(AppSettings next) async {
    final s = ref.read(servicesProvider);
    state = next;
    await s.settings.save(next, s.modelId);
  }

  Future<void> reload() async {
    final s = ref.read(servicesProvider);
    state = await s.settings.load(s.modelId, placeholder: s.worker.info.placeholderEmbedder);
  }
}
