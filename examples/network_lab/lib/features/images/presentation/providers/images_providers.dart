import 'package:network_lab/features/images/domain/image_source.dart';
import 'package:network_lab/shared/network/domain/http_ports.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'images_providers.g.dart';

@riverpod
ImageRepository imageRepository(Ref ref) =>
    throw UnimplementedError('Override imageRepositoryProvider at the owner');
@riverpod
Future<ImagePayload> loadedImage(Ref ref, ImageSource source) {
  final cancellation = Cancellation();
  ref.onDispose(cancellation.cancel);
  return ref
      .watch(imageRepositoryProvider)
      .load(source, cancellation: cancellation);
}
