import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:showcase_contracts/showcase_contracts.dart';

final class ReplacementRepository implements ShowcaseRepository {
  @override
  String get moduleId => 'replacement';
  @override
  int get generation => 42;
  @override
  Future<String> loadMessage({Duration delay = Duration.zero}) async =>
      'injected';
}

void main() {
  test('missing bootstrap injection fails explicitly', () {
    final container = ProviderContainer(retry: (_, _) => null);
    addTearDown(container.dispose);
    expect(
      () => container.read(activeShowcaseRepositoryProvider),
      throwsA(
        predicate<Object>(
          (error) =>
              error.toString().contains('Inject the active module session'),
        ),
      ),
    );
  });

  test('host can replace the capability through the public contract', () async {
    final replacement = ReplacementRepository();
    final container = ProviderContainer(
      overrides: [
        activeShowcaseRepositoryProvider.overrideWithValue(replacement),
      ],
    );
    addTearDown(container.dispose);
    final repository = container.read(activeShowcaseRepositoryProvider);
    expect(repository, same(replacement));
    expect(await repository.loadMessage(), 'injected');
  });
}
