import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers.dart';
import 'app/router.dart';
import 'app/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const Bootstrap());
}

/// Opens the encrypted DB and loads both models in the ML isolate, then
/// starts the app. Shows a plain splash meanwhile, and the error if a model is missing.
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  late Future<AppServices> _init = AppServices.init();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppServices>(
      future: _init,
      builder: (context, snap) {
        final services = snap.data;
        if (services != null) {
          return ProviderScope(
            overrides: [servicesProvider.overrideWithValue(services)],
            child: const OperatorPassApp(),
          );
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: snap.hasError
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.red, size: 36),
                          const SizedBox(height: 12),
                          Text('Could not start: ${snap.error}', textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => setState(() => _init = AppServices.init()),
                            child: const Text('Retry'),
                          ),
                        ],
                      )
                    : const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shield_outlined, color: AppColors.cyan, size: 44),
                          SizedBox(height: 16),
                          Text('Operator Pass', style: TextStyle(fontSize: 22)),
                          SizedBox(height: 6),
                          Text('Loading models on device…',
                              style: TextStyle(color: AppColors.muted)),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class OperatorPassApp extends ConsumerWidget {
  const OperatorPassApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Operator Pass',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
