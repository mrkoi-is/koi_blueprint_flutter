import 'package:network_lab/features/images/domain/image_source.dart';
import 'package:network_lab/features/images/application/image_selection_actions.dart';
import 'package:network_lab/shared/network/domain/http_ports.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'images_providers.g.dart';

@Riverpod(dependencies: [])
ImageRepository imageRepository(Ref ref) =>
    throw UnimplementedError('Override imageRepositoryProvider at the owner');

@Riverpod(dependencies: [imageRepository])
Future<ImagePayload> loadedImage(Ref ref, ImageSource source) {
  final cancellation = Cancellation();
  ref.onDispose(cancellation.cancel);
  return ref
      .watch(imageRepositoryProvider)
      .load(source, cancellation: cancellation);
}

@Riverpod(dependencies: [imageRepository])
class ImageSelection extends _$ImageSelection {
  int _generation = 0;
  @override
  ({
    ImageSource source,
    Object? error,
    bool invalidUrl,
    double width,
    String input,
  })
  build() {
    ref.watch(imageRepositoryProvider);
    ref.onDispose(() => _generation++);
    return (
      source: const AssetImageSource('assets/images/sample.png'),
      error: null,
      invalidUrl: false,
      width: 240,
      input: '',
    );
  }

  void select(ImageSource source) {
    _generation++;
    state = (
      source: source,
      error: null,
      invalidUrl: false,
      width: state.width,
      input: state.input,
    );
  }

  void setWidth(double value) => state = (
    source: state.source,
    error: state.error,
    invalidUrl: state.invalidUrl,
    width: value,
    input: state.input,
  );
  void setInput(String value) {
    _generation++;
    state = (
      source: state.source,
      error: null,
      invalidUrl: false,
      width: state.width,
      input: value,
    );
  }

  void selectUrl() {
    final uri = Uri.tryParse(state.input);
    if (uri == null) {
      _generation++;
      state = (
        source: state.source,
        error: null,
        invalidUrl: true,
        width: state.width,
        input: state.input,
      );
    } else {
      select(NetworkImageSource(uri));
    }
  }

  Future<void> memory() =>
      _load(() async => MemoryImageSource(await loadSampleImage()));
  Future<void> pick(LocalImageReader reader) => _load(() async {
    final key = await reader.pick(maxBytes: 8 * 1024 * 1024);
    return key == null || key.isEmpty ? null : LocalImageSource(key);
  });
  Future<void> _load(Future<ImageSource?> Function() action) async {
    final generation = ++_generation;
    try {
      final source = await action();
      if (!ref.mounted || generation != _generation || source == null) return;
      state = (
        source: source,
        error: null,
        invalidUrl: false,
        width: state.width,
        input: state.input,
      );
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = (
        source: state.source,
        error: error,
        invalidUrl: false,
        width: state.width,
        input: state.input,
      );
    }
  }
}
