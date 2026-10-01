import 'package:koi_modules/koi_modules.dart';
import 'package:showcase_contracts/showcase_contracts.dart';
import 'package:showcase_beta/src/core/router/app_routes.dart';
import 'package:showcase_beta/src/features/welcome/data/beta_repository.dart';

KoiModule<ShowcaseRepository> createBetaModule(ShowcaseServices services) =>
    KoiModule(
      id: 'beta',
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
