import 'package:riverpod_annotation/experimental/scope.dart';

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:network_lab/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_lab/features/images/domain/image_source.dart';
import 'package:network_lab/features/images/presentation/providers/images_providers.dart';

@Dependencies([loadedImage, imageRepository, ImageSelection])
class ImagesPage extends ConsumerStatefulWidget {
  const ImagesPage({required this.localReader, super.key});
  final LocalImageReader localReader;
  @override
  ConsumerState<ImagesPage> createState() => _ImagesPageState();
}

class _ImagesPageState extends ConsumerState<ImagesPage> {
  late final TextEditingController _input;
  @override
  void initState() {
    super.initState();
    _input = TextEditingController(
      text: ref.read(imageSelectionProvider).input,
    );
  }

  ImageSelection get _selection => ref.read(imageSelectionProvider.notifier);
  ImageSource get _source => ref.watch(imageSelectionProvider).source;
  double get _width => ref.watch(imageSelectionProvider).width;
  Object? get _inputError => ref.watch(imageSelectionProvider).error;
  bool get _invalidUrl => ref.watch(imageSelectionProvider).invalidUrl;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _select(ImageSource source) => _selection.select(source);
  Future<void> _memory() => _selection.memory();
  Future<void> _local() => _selection.pick(widget.localReader);

  @override
  Widget build(BuildContext context) {
    ref.listen(imageSelectionProvider.select((value) => value.input), (
      _,
      value,
    ) {
      if (_input.text != value) _input.text = value;
    });
    final strings = AppLocalizations.of(context)!;
    final state = ref.watch(loadedImageProvider(_source));
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final target = (_width * dpr).round().clamp(1, 2048);
    return Scaffold(
      appBar: AppBar(title: Text(strings.imagesTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _input,
            onChanged: _selection.setInput,
            decoration: InputDecoration(labelText: strings.imagesInputLabel),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () =>
                    _select(const AssetImageSource('assets/images/sample.png')),
                child: Text(strings.imagesAsset),
              ),
              TextButton(onPressed: _memory, child: Text(strings.imagesMemory)),
              TextButton(
                onPressed: _local,
                child: Text(strings.imagesPickLocal),
              ),
              if (!kIsWeb)
                TextButton(
                  onPressed: () => _select(
                    LocalImageSource(ref.read(imageSelectionProvider).input),
                  ),
                  child: Text(strings.imagesReadPath),
                ),
              TextButton(
                onPressed: () {
                  _selection.selectUrl();
                },
                child: Text(strings.imagesNetwork),
              ),
            ],
          ),
          if (_invalidUrl) Text(strings.imagesInvalidUrl),
          if (_inputError != null)
            Text(strings.imagesReadError('$_inputError')),
          Slider(
            value: _width,
            min: 80,
            max: 360,
            onChanged: (value) => _selection.setWidth(value),
          ),
          Text(
            strings.imagesLayout(
              _width.round(),
              dpr.toStringAsFixed(2),
              target,
            ),
          ),
          state.when(
            loading: () => const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => Column(
              children: [
                Text(strings.imagesReadError('$error')),
                FilledButton(
                  onPressed: () => ref.invalidate(loadedImageProvider(_source)),
                  child: Text(strings.imagesRetry),
                ),
              ],
            ),
            data: (payload) => Column(
              children: [
                Text(
                  payload.fromCache
                      ? strings.imagesCacheHit
                      : strings.imagesValidated,
                ),
                DecodedImage(
                  bytes: payload.bytes,
                  logicalWidth: _width,
                  decodeWidth: target,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              ref.read(imageRepositoryProvider).clear();
              ref.invalidate(loadedImageProvider(_source));
            },
            child: Text(strings.imagesClearCache),
          ),
        ],
      ),
    );
  }
}

class DecodedImage extends StatefulWidget {
  const DecodedImage({
    required this.bytes,
    required this.logicalWidth,
    required this.decodeWidth,
    super.key,
  });
  final Uint8List bytes;
  final double logicalWidth;
  final int decodeWidth;
  @override
  State<DecodedImage> createState() => _DecodedImageState();
}

class _DecodedImageState extends State<DecodedImage> {
  ui.Image? _image;
  Object? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_decode());
  }

  @override
  void didUpdateWidget(DecodedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.decodeWidth != widget.decodeWidth ||
        !listEquals(oldWidget.bytes, widget.bytes)) {
      unawaited(_decode());
    }
  }

  Future<void> _decode() async {
    final generation = ++_generation;
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(
        widget.bytes,
        targetWidth: widget.decodeWidth,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      if (!mounted || generation != _generation) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = frame.image;
        _error = null;
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      codec?.dispose();
    }
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _error != null
      ? Text(AppLocalizations.of(context)!.imagesDecodeFailed('$_error'))
      : _image == null
      ? const SizedBox(
          height: 160,
          child: Center(child: CircularProgressIndicator()),
        )
      : Column(
          children: [
            Text(
              AppLocalizations.of(context)!
                  .imagesDecodedSize(_image!.width, _image!.height),
            ),
            RawImage(
              image: _image,
              width: widget.logicalWidth,
              fit: BoxFit.contain,
            ),
          ],
        );
}
