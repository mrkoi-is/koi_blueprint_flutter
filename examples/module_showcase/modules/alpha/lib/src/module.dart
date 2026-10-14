import 'package:showcase_alpha/src/features/welcome/presentation/providers/alpha_providers.dart';
import 'package:riverpod_annotation/experimental/scope.dart';
import 'package:koi_modules/koi_modules.dart';
import 'package:showcase_contracts/showcase_contracts.dart';
import 'package:showcase_alpha/src/core/router/app_routes.dart';
import 'package:showcase_alpha/src/features/welcome/data/alpha_repository.dart';

@Dependencies([alphaMessage])
KoiModule<ShowcaseRepository> createAlphaModule(
  ShowcaseServices services, {
  CapabilityAvailability Function()? checkAvailability,
}) => KoiModule(
  id: 'alpha',
  capabilities: const {'message.read', 'refresh.observe'},
  checkAvailability: checkAvailability,
  routes: $appRoutes,
  navigation: [
    ModuleNavigationItem(
      id: 'alpha.home',
      label: 'Alpha',
      location: const AlphaRoute().location,
    ),
  ],
  createSession: (context) => AlphaRepository(context, services),
);
