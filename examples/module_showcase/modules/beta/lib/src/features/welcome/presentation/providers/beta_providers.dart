import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:showcase_contracts/showcase_contracts.dart';

part 'beta_providers.g.dart';

@riverpod
Future<String> betaMessage(Ref ref) =>
    ref.watch(activeShowcaseRepositoryProvider).loadMessage();
