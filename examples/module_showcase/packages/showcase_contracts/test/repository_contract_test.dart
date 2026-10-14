import 'package:flutter_test/flutter_test.dart';
import 'package:showcase_contracts/showcase_contracts.dart';

final class _FakeRepository implements ShowcaseRepository {
  @override
  String get moduleId => 'fake';

  @override
  int get generation => 1;

  @override
  Future<String> loadMessage({Duration delay = Duration.zero}) async =>
      'contract';
}

void main() {
  test('shared contract exposes identity and a message', () async {
    final repository = _FakeRepository();
    expect(repository.moduleId, 'fake');
    expect(repository.generation, 1);
    expect(await repository.loadMessage(), 'contract');
  });
}
