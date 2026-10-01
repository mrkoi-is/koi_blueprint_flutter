import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:showcase_contracts/showcase_contracts.dart';

part 'alpha_providers.g.dart';

@riverpod
Future<String> alphaMessage(Ref ref) =>
    ref.watch(activeShowcaseRepositoryProvider).loadMessage();
