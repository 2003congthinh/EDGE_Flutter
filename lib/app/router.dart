import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/activity/activity_page.dart';
import '../features/dev_lab/dev_lab_page.dart';
import '../features/enrollment/enroll_page.dart';
import '../features/home/home_page.dart';
import '../features/operators/new_operator_page.dart';
import '../features/operators/operator_detail_page.dart';
import '../features/operators/operators_page.dart';
import '../features/settings/settings_page.dart';
import '../features/setup/setup_page.dart';
import '../features/unlock/reauth_page.dart';
import '../features/unlock/unlock_page.dart';
import 'providers.dart';

/// Every route is behind the lock guard: until setup is done only /setup is
/// reachable, and while locked only /unlock. Deep links and the back button
/// can't get past it because the redirect runs on every navigation and
/// whenever the lock state changes.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(lockProvider, (prev, next) {
    if (prev?.locked != next.locked || prev?.setupDone != next.setupDone) refresh.value++;
  });
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, s) {
      final lock = ref.read(lockProvider);
      final at = s.matchedLocation;
      if (!lock.setupDone) return at == '/setup' ? null : '/setup';
      if (lock.locked) return at == '/unlock' ? null : '/unlock';
      if (at == '/unlock' || at == '/setup') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/setup', builder: (_, _) => const SetupPage()),
      GoRoute(path: '/unlock', builder: (_, _) => const UnlockPage()),
      GoRoute(path: '/home', builder: (_, _) => const HomePage()),
      GoRoute(
        path: '/reauth',
        builder: (_, s) => ReauthPage(reason: s.extra as String? ?? ''),
      ),
      GoRoute(
        path: '/enroll',
        redirect: (_, s) => s.extra is EnrollRequest ? null : '/home',
        builder: (_, s) => EnrollPage(request: s.extra as EnrollRequest),
      ),
      GoRoute(
        path: '/operators',
        builder: (_, _) => const OperatorsPage(),
        routes: [
          GoRoute(path: 'new', builder: (_, _) => const NewOperatorPage()),
          GoRoute(
            path: ':id',
            builder: (_, s) => OperatorDetailPage(id: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsPage(),
        routes: [
          GoRoute(path: 'pin', builder: (_, _) => const ChangePinPage()),
        ],
      ),
      GoRoute(path: '/activity', builder: (_, _) => const ActivityPage()),
      GoRoute(path: '/dev', builder: (_, _) => const DevLabPage()),
    ],
  );
});
