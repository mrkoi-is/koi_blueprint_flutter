import 'package:device_lab/features/local_setup/application/local_setup_session.dart';
import 'package:device_lab/features/devices/application/onboarding.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  test('local-only setup persists real configuration and imports from selected directory', () async {
    final store = MemorySettings();
    String? usedDirectory;
    final session = LocalSetupSession(
      store: store,
      pickDirectory: () async => '/chosen',
      pickDocument: (directory) async {
        usedDirectory = directory;
        return const ImportedDocument('note.txt', 'actual content');
      },
      importFile: (_) async =>
          const ImportedDocument('external.txt', 'incoming'),
    );
    await session.initialize();
    await session.configure(
      const OnboardingState(step: OnboardingStep.directory, language: 'en'),
    );
    await session.chooseDirectory();
    await session.configure(
      OnboardingState(
        step: OnboardingStep.complete,
        language: 'en',
        directory: session.onboarding.state.directory,
      ),
    );
    await session.importPicked();
    expect(usedDirectory, '/chosen');
    expect(session.draft, 'actual content');
    expect(store.values['documents'], isNotEmpty);
    final held = session.changes.listen((_) {})..pause();
    await session.close().timeout(const Duration(seconds: 1));
    await held.cancel();
    final restored = OnboardingCoordinator(store);
    await restored.restore();
    expect(restored.state.language, 'en');
    expect(restored.state.directory, '/chosen');
  });
  test(
    'draft blocks incoming, failed exit prepare stays usable and retry drains',
    () async {
      final store = MemorySettings();
      final session = LocalSetupSession(
        store: store,
        requireOnboarding: false,
        pickDirectory: () async => null,
        pickDocument: (_) async => null,
        importFile: (_) async =>
            const ImportedDocument('external.txt', 'incoming'),
      );
      await session.initialize();
      session.edit('keep draft');
      await session.receive(Uri.parse('koi://tasks'));
      expect(session.incoming.pendingCount, 1);
      store.fail = true;
      expect(await session.prepare(), false);
      expect(session.draft, 'keep draft');
      expect(session.dirty, true);
      store.fail = false;
      expect(await session.prepare(), true);
      expect(session.incoming.pendingCount, 0);
      expect(session.tab, 'tasks');
      await session.close();
    },
  );
}
