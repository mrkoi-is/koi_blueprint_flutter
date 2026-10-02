import 'package:flutter_test/flutter_test.dart';
import 'package:koi_modules/koi_modules.dart';
import 'package:module_showcase/features/module_capabilities/application/analysis_session.dart';

void main() {
  test('installed typed engines execute different operations and invalidate replaced references', () async {
    final owner = AnalysisSession();
    addTearDown(owner.close);
    await owner.activate('words');
    final first = owner.runtime.state.session!.capability;
    expect((await first.analyze('a bb')).count, 2);
    await owner.activate('characters');
    expect((await owner.analyze('a bb')).count, 4);
    expect(owner.closedEngines, 1);
    await expectLater(
      first.analyze('stale'),
      throwsA(isA<StaleModuleSessionException>()),
    );
  });
  test('configuration denial and initialization failure recover without replacing runtime', () async {
    final owner = AnalysisSession();
    addTearDown(owner.close);
    final runtime = owner.runtime;
    owner.charactersEnabled = false;
    await expectLater(
      owner.activate('characters'),
      throwsA(isA<ModuleUnavailableException>()),
    );
    expect(owner.closedEngines, 0);
    owner.charactersEnabled = true;
    owner.failNextCreation = true;
    await expectLater(owner.activate('characters'), throwsStateError);
    expect(owner.closedEngines, 1);
    expect(runtime.state.availability!.status, CapabilityStatus.unavailable);
    await owner.activate('characters');
    expect(owner.runtime, same(runtime));
    expect((await owner.analyze('🦊')).count, 1);
  });
}
