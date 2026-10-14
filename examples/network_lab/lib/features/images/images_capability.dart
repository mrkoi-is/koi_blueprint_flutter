import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_core/koi_core.dart' show CapabilityLifecycle;
import 'package:network_lab/features/images/data/image_repository.dart';
import 'package:network_lab/features/images/data/image_validator.dart';
import 'package:network_lab/features/images/data/local_reader.dart';
import 'package:network_lab/features/images/domain/image_source.dart';
import 'package:network_lab/features/images/presentation/providers/images_providers.dart';
import 'package:network_lab/features/images/presentation/screens/images_page.dart';
import 'package:network_lab/shared/network/http_transport.dart';

Widget buildImagesCapabilityPage(BuildContext context) =>
    const ImagesCapabilityPage();

class ImagesCapabilityPage extends StatefulWidget {
  const ImagesCapabilityPage({super.key});
  @override
  State<ImagesCapabilityPage> createState() => _ImagesCapabilityPageState();
}

class _ImagesCapabilityPageState extends State<ImagesCapabilityPage> {
  late final LocalImageReader _local = createLocalImageReader();
  late final ImageRepository _repository = ImageRepositoryImpl(
    transport: createHttpTransport(),
    localReader: _local,
    assetReader: (path) async {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    },
    validator: const FlutterImageValidator(),
  );
  late final VoidCallback _unregister;
  Future<void>? _closing;
  Future<void> _close() => _closing ??= _repository.close();
  @override
  void initState() {
    super.initState();
    _unregister = CapabilityLifecycle.instance.register(
      prepare: () async => true,
      close: _close,
    );
  }

  @override
  void dispose() {
    _unregister();
    unawaited(_close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [imageRepositoryProvider.overrideWithValue(_repository)],
    child: ImagesPage(localReader: _local),
  );
}
