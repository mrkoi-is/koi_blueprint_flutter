import 'package:showcase_beta/src/features/welcome/presentation/providers/beta_providers.dart';
import 'package:riverpod_annotation/experimental/scope.dart';
import 'package:koi_modules/koi_modules.dart';
import 'package:showcase_contracts/showcase_contracts.dart';
import 'package:showcase_beta/src/core/router/app_routes.dart';
import 'package:showcase_beta/src/features/welcome/data/beta_repository.dart';

@Dependencies([betaMessage])
KoiModule<ShowcaseRepository> createBetaModule(
  ShowcaseServices services, {
  CapabilityAvailability Function()? checkAvailability,
}) => KoiModule(
  id: 'beta',
  capabilities: const {'message.read', 'refresh.observe'},
  checkAvailability: checkAvailability,
  routes: $appRoutes,
  navigation: [
    ModuleNavigationItem(
      id: 'beta.home',
      label: 'Beta',
      location: const BetaRoute().location,
    ),
  ],
  createSession: (context) => BetaRepository(context, services),
);
