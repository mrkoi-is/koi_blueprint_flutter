import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workbench_app/bootstrap.dart';
import 'package:workbench_app/features/workspace/presentation/providers/navigation_providers.dart';
import 'package:workbench_app/features/workspace/presentation/providers/workspace_providers.dart';

import 'presentation_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'initialization failure closes every constructed storage owner',
    () async {
      final storage = MemoryStorage()..repository.failLoad = true;
      await expectLater(
        WorkbenchBootstrap.create(
          openStorage: () async => storage,
          fileImportPort: CancelImport(),
          createPlayback: FakePlayback.new,
        ),
        throwsStateError,
      );
      expect(storage.closes, 1);
    },
  );

  test('router and injected owners close once; borrowed provider does not close session', () async {
    final storage = MemoryStorage();
    final bootstrap = await WorkbenchBootstrap.create(
      openStorage: () async => storage,
      fileImportPort: CancelImport(),
      createPlayback: FakePlayback.new,
    );
    final container = ProviderContainer(
      overrides: [
        workspaceSessionProvider.overrideWithValue(bootstrap.session),
      ],
    );
    final subscription = container.listen(workspaceStateProvider, (_, _) {});
    await container.read(workspaceStateProvider.future);
    subscription.close();
    container.dispose();
    bootstrap.session.createDocument(text: 'provider is only a borrower');
    final router = bootstrap.router;
    bootstrap.session.addTodo('still alive');
    expect(bootstrap.router, same(router));
    final closing = bootstrap.disposeAsync();
    expect(bootstrap.disposeAsync(), same(closing));
    await closing;
    expect(storage.closes, 1);
    expect(() => bootstrap.session.createDocument(), throwsStateError);
  });

  test('missing bootstrap overrides fail instead of making fake data', () {
    final container = ProviderContainer(retry: (_, _) => null);
    expect(() => container.read(workspaceSessionProvider), throwsA(anything));
    expect(
      () => container.read(mediaPreviewSessionProvider),
      throwsA(anything),
    );
    expect(() => container.read(navigationHistoryProvider), throwsA(anything));
    container.dispose();
  });
}
