import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:showcase_contracts/src/domain/showcase_repository.dart';

part 'showcase_providers.g.dart';

/// The host overrides this adapter with the active session capability.
@Riverpod(keepAlive: true)
ShowcaseRepository activeShowcaseRepository(Ref ref) {
  throw UnimplementedError('Inject the active module session in bootstrap.');
}
