import 'package:koi_core/koi_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:__APP_PACKAGE__/core/diagnostics/app_diagnostics.dart';

part 'diagnostic_providers.g.dart';

@riverpod
BoundedDiagnosticStore diagnosticStore(Ref ref) =>
    AppDiagnostics.instance.store;

@riverpod
Stream<int> diagnosticRevision(Ref ref) =>
    ref.watch(diagnosticStoreProvider).watchChanges();
