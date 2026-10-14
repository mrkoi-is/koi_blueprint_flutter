import 'package:device_lab/features/devices/domain/device_contracts.dart';

enum OnboardingStep { language, directory, device, complete }

final class OnboardingState {
  const OnboardingState({
    this.step = OnboardingStep.language,
    this.language = 'system',
    this.directory,
    this.device,
    this.skipped = false,
  });
  final OnboardingStep step;
  final String language;
  final String? directory;
  final String? device;
  final bool skipped;
  Map<String, Object?> toJson() => {
    'step': step.name,
    'language': language,
    'directory': directory,
    'device': device,
    'skipped': skipped,
  };
  factory OnboardingState.fromJson(Map<String, Object?> json) =>
      OnboardingState(
        step: OnboardingStep.values.byName(
          json['step'] as String? ?? 'language',
        ),
        language: json['language'] as String? ?? 'system',
        directory: json['directory'] as String?,
        device: json['device'] as String?,
        skipped: json['skipped'] as bool? ?? false,
      );
}

final class OnboardingCoordinator {
  OnboardingCoordinator(this.store);
  final DeviceSettingsStore store;
  OnboardingState state = const OnboardingState();
  Map<String, Object?> _values = {};
  Future<void> _pending = Future.value();
  Future<void> restore() async {
    _values = await store.read();
    state = OnboardingState.fromJson(
      Map<String, Object?>.from(_values['onboarding'] as Map? ?? {}),
    );
  }

  Future<void> save(OnboardingState next) {
    final operation = _pending.then((_) async {
      final values = {...await store.read(), 'onboarding': next.toJson()};
      await store.write(values);
      _values = values;
      state = next;
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> skip() => save(
    OnboardingState(
      step: OnboardingStep.complete,
      language: state.language,
      directory: state.directory,
      device: state.device,
      skipped: true,
    ),
  );
  Future<void> close() => _pending;
}
