import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/experimental/scope.dart';
import 'package:network_lab/features/images/domain/image_source.dart';
import 'package:network_lab/features/images/presentation/providers/images_providers.dart';

@Dependencies([ImageSelection])
void main() {
  test('迟到文件选择不能覆盖更新的图片源', () async {
    final container = ProviderContainer(
      overrides: [imageRepositoryProvider.overrideWithValue(_Repository())],
    );
    addTearDown(container.dispose);
    container.listen(imageSelectionProvider, (_, _) {});
    final selection = container.read(imageSelectionProvider.notifier);
    final reader = _Reader();
    final pending = selection.pick(reader);
    selection.select(const AssetImageSource('new.png'));
    reader.result.complete('old.png');
    await pending;
    expect(
      (container.read(imageSelectionProvider).source as AssetImageSource).path,
      'new.png',
    );
  });
  test('释放后迟到的选择错误不会访问 ref', () async {
    final container = ProviderContainer(
      overrides: [imageRepositoryProvider.overrideWithValue(_Repository())],
    );
    container.listen(imageSelectionProvider, (_, _) {});
    final selection = container.read(imageSelectionProvider.notifier);
    final reader = _Reader();
    final pending = selection.pick(reader);
    container.dispose();
    reader.result.completeError(StateError('late'));
    await pending;
  });
}

final class _Reader implements LocalImageReader {
  final result = Completer<String?>();
  @override
  Future<String?> pick({required int maxBytes}) => result.future;
  @override
  Future<Uint8List> read(String key, {required int maxBytes}) =>
      throw UnimplementedError();
  @override
  void close() {}
}

final class _Repository extends Fake implements ImageRepository {}
