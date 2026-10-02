import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:network_lab/l10n/generated/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_lab/features/images/domain/image_source.dart';
import 'package:network_lab/features/images/presentation/providers/images_providers.dart';

class ImagesPage extends ConsumerStatefulWidget {
  const ImagesPage({required this.localReader, super.key});
  final LocalImageReader localReader;
  @override
  ConsumerState<ImagesPage> createState() => _ImagesPageState();
}

class _ImagesPageState extends ConsumerState<ImagesPage> {
  ImageSource _source = const AssetImageSource('assets/images/sample.png');
  final _input = TextEditingController();
  double _width = 240;
  Object? _inputError;
  bool _invalidUrl = false;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _select(ImageSource source) => setState(() {
    _source = source;
    _inputError = null;
    _invalidUrl = false;
  });
  Future<void> _memory() async {
    final data = await rootBundle.load('assets/images/sample.png');
    if (mounted) {
      _select(
        MemoryImageSource(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
    }
  }

  Future<void> _local() async {
    try {
      final key = await widget.localReader.pick(maxBytes: 8 * 1024 * 1024);
      if (mounted && key != null && key.isNotEmpty) {
        _select(LocalImageSource(key));
      }
    } catch (error) {
      if (mounted) setState(() => _inputError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  onPressed: () => _select(LocalImageSource(_input.text)),
                  child: Text(strings.imagesReadPath),
                ),
              TextButton(
                onPressed: () {
                  final uri = Uri.tryParse(_input.text);
                  if (uri == null) {
                    setState(() {
                      _invalidUrl = true;
                      _inputError = null;
                    });
                  } else {
                    _select(NetworkImageSource(uri));
                  }
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
            onChanged: (value) => setState(() => _width = value),
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
