import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:showcase_contracts/showcase_contracts.dart';

part 'beta_providers.g.dart';

@Riverpod(keepAlive: true, dependencies: [])
ShowcaseRepository showcaseRepository(Ref ref) {
  throw UnimplementedError('Inject the active module session in bootstrap.');
}

@Riverpod(dependencies: [showcaseRepository])
Future<String> betaMessage(Ref ref) =>
    ref.watch(showcaseRepositoryProvider).loadMessage();
