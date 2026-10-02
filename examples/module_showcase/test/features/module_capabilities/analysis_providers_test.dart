import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_modules/koi_modules.dart';
import 'package:module_showcase/features/module_capabilities/application/analysis_session.dart';
import 'package:module_showcase/features/module_capabilities/presentation/providers/analysis_providers.dart';

void main() {
  test('composition must supply the session', () {
    final container = ProviderContainer(retry: (_, _) => null);
    addTearDown(container.dispose);
    expect(() => container.read(analysisSessionProvider), throwsA(anything));
  });

  test('state bridge follows real activation, denial and recovery', () async {
    final owner = AnalysisSession();
    addTearDown(owner.close);
    final container = ProviderContainer(
      overrides: [analysisSessionProvider.overrideWithValue(owner)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(analysisStateProvider, (_, _) {});
    addTearDown(subscription.close);
    expect(
      (await container.read(analysisStateProvider.future)).session,
      isNull,
    );
    await owner.activate('words');
    await container.pump();
    expect(
      container.read(analysisStateProvider).value?.session?.moduleId,
      'words',
    );

    owner.charactersEnabled = false;
    await expectLater(
      owner.activate('characters'),
      throwsA(isA<ModuleUnavailableException>()),
    );
    await container.pump();
    final denied = container.read(analysisStateProvider).value!;
    expect(denied.session, isNull);
    expect(denied.availability?.status, CapabilityStatus.unavailable);
    owner.charactersEnabled = true;
    await owner.activate('characters');
    await container.pump();
    expect(
      container.read(analysisStateProvider).value?.session?.moduleId,
      'characters',
    );
    expect((await owner.analyze('鲤🐟')).count, 2);
  });

  test(
    'disposing the bridge detaches its listener without closing borrowed owner',
    () async {
      final owner = AnalysisSession();
      addTearDown(owner.close);
      final container = ProviderContainer(
        overrides: [analysisSessionProvider.overrideWithValue(owner)],
      );
      final subscription = container.listen(analysisStateProvider, (_, _) {});
      await container.read(analysisStateProvider.future);
      subscription.close();
      await container.pump();
      container.dispose();
      // A retained callback would add to the now-closed bridge stream here.
      await owner.activate('words');
      expect((await owner.analyze('still usable')).count, 2);
      expect(owner.closedEngines, 0);
      await owner.activate('characters');
      expect((await owner.analyze('鲤🐟')).count, 2);
    },
  );
}
