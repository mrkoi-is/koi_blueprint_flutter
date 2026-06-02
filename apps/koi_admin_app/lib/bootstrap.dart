import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_admin_app/app.dart';
import 'package:koi_admin_app/core/config/app_environment.dart';
import 'package:koi_admin_app/core/providers/bootstrap_providers.dart';
import 'package:koi_api_bootstrap/koi_api_bootstrap.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sharedPreferences = await SharedPreferences.getInstance();

  await bootstrapKoiApi(
    KoiApiBootstrapOptions(
      baseUrl: AppEnvironment.current.apiBaseUrl,
      environment: AppEnvironment.current.name,
      enableLogging: AppEnvironment.current.enableNetworkLog,
    ),
  );

  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(sharedPreferences)],
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const KoiBlueprintAdminApp(),
    ),
  );
}
