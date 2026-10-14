import 'dart:async';

import 'package:device_lab/features/devices/application/incoming_intents.dart';
import 'package:device_lab/features/devices/application/onboarding.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  test('cold/warm links deduplicate, wait for readiness and retain dirty-draft events', () async {
    var canNavigate = false;
    final handled = <IncomingIntent>[];
    var now = DateTime.utc(2026);
    final coordinator = IncomingIntentCoordinator(
      dispatch: (intent) async => handled.add(intent),
      canNavigate: () async => canNavigate,
      clock: () => now,
    );
    final document = IncomingIntent.fromUri(
      Uri.parse('koi://document?id=welcome'),
    );
    expect(await coordinator.receive(document), IncomingResult.queued);
    expect(await coordinator.receive(document), IncomingResult.duplicate);
    await coordinator.markReady();
    expect(handled, isEmpty);
    expect(
      await coordinator.receive(
        IncomingIntent.fromUri(Uri.parse('koi://tasks')),
      ),
      IncomingResult.blocked,
    );
    canNavigate = true;
    await coordinator.drain();
    expect(handled.map((intent) => intent.action), [
      IncomingAction.openDocument,
      IncomingAction.showTasks,
    ]);
    now = now.add(const Duration(seconds: 3));
    expect(await coordinator.receive(document), IncomingResult.accepted);
    expect(handled, hasLength(3));
    await coordinator.close();
    await expectLater(coordinator.receive(document), throwsStateError);
    expect(
      () => IncomingIntent.fromUri(Uri.parse('koi://document?id=../bad')),
      throwsFormatException,
    );
    expect(
      () => IncomingIntent.fromUri(Uri.parse('javascript:bad')),
      throwsFormatException,
    );
    expect(
      IncomingIntent.fromUri(Uri.file('/tmp/资料.txt')).action,
      IncomingAction.importFile,
    );
  });
  test(
    'close waits for accepted dispatch and suppresses queued work',
    () async {
      final started = Completer<void>();
      final done = Completer<void>();
      var dispatches = 0;
      final coordinator = IncomingIntentCoordinator(
        dispatch: (_) async {
          dispatches++;
          started.complete();
          await done.future;
        },
        canNavigate: () async => true,
      );
      await coordinator.markReady();
      final incoming = coordinator.receive(
        const IncomingIntent(id: '1', action: IncomingAction.showTasks),
      );
      await started.future;
      var closed = false;
      final closing = coordinator.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      done.complete();
      await incoming;
      await closing;
      expect(dispatches, 1);
      expect(coordinator.pendingCount, 0);
    },
  );
  test('onboarding restores incomplete progress, failed writes preserve state and unrelated documents', () async {
    final store = MemorySettings();
    final first = OnboardingCoordinator(store);
    await first.restore();
    await first.save(
      const OnboardingState(step: OnboardingStep.directory, language: 'en'),
    );
    store.values['documents'] = {
      'welcome': {'title': 'Kept', 'text': 'Text'},
    };
    final second = OnboardingCoordinator(store);
    await second.restore();
    expect(second.state.step, OnboardingStep.directory);
    expect(second.state.language, 'en');
    store.fail = true;
    await expectLater(second.skip(), throwsStateError);
    expect(second.state.step, OnboardingStep.directory);
    store.fail = false;
    await second.skip();
    expect(second.state.skipped, isTrue);
    expect(store.values['documents'], isNotNull);
    final third = OnboardingCoordinator(store);
    await third.restore();
    expect(third.state.step, OnboardingStep.complete);
    await third.save(const OnboardingState(language: 'zh'));
    expect(third.state.step, OnboardingStep.language);
  });
}
