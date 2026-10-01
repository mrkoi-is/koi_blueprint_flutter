import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:workbench_app/app.dart';
import 'package:workbench_app/bootstrap.dart';
import 'package:workbench_app/core/router/app_routes.dart';
import 'package:workbench_app/features/workspace/domain/workspace_models.dart';

import 'support/fixture_import_port.dart';
import 'support/runtime_frame_probe.dart';
import 'support/runtime_sandbox.dart';
import 'support/tracking_storage.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('real content, image, Player, screenshots and reopening smoke', (
    tester,
  ) async {
    final sandbox = await createRuntimeSandbox();
    final input = FixtureImportPort();
    WorkbenchBootstrap? owned;
    final evidence = <String, Object?>{
      'storage': sandbox.description,
      'file_picker': 'NOT_EXERCISED_fixture_adapter',
    };
    binding.reportData = evidence;
    try {
      final storage = TrackingStorage(await sandbox.open());
      final bootstrap = await WorkbenchBootstrap.create(
        openStorage: () async => storage,
        fileImportPort: input,
        initialLocation: '/media',
      );
      owned = bootstrap;
      final session = bootstrap.session;
      await session.importFiles(ImportKind.text);
      await session.importFiles(ImportKind.media);
      expect(session.state.error, isNull);
      expect(session.state.snapshot.assets, hasLength(4));
      expect(
        session.state.snapshot.documents.single.text,
        utf8.decode(await loadFixture('中文资料.md')),
      );
      expect(input.sources.every((source) => source.closed), isTrue);
      expect(
        session.state.snapshot.jobs
            .where((job) => job.kind == JobKind.importFiles)
            .every(
              (job) =>
                  job.status == JobStatus.succeeded &&
                  job.processedBytes == job.totalBytes,
            ),
        isTrue,
      );
      session.addTodo('真实存储与播放验收');
      evidence['imported_bytes'] = input.sources.fold<int>(
        0,
        (count, source) => count + source.byteLength,
      );

      final image = session.state.snapshot.assets.first;
      session.updatePreferences(
        session.state.snapshot.preferences.copyWith(selectedAssetId: image.id),
      );
      await tester.pumpWidget(WorkbenchApp(bootstrap: bootstrap));
      await _pumpUntil(
        tester,
        () => find
            .byWidgetPredicate(
              (widget) =>
                  widget is Image &&
                  _hasSourceBytes(widget.image, image.byteLength),
            )
            .evaluate()
            .isNotEmpty,
        label: 'real image data visible',
      );
      expect(find.byKey(ValueKey('image-viewer-${image.id}')), findsOneWidget);
      final codec = await ui.instantiateImageCodec(
        await storage.assetStore.readBytes(image.storageKey),
      );
      final frame = await codec.getNextFrame();
      evidence['image_dimensions'] = [frame.image.width, frame.image.height];
      expect(frame.image.width, 160);
      expect(frame.image.height, 96);
      final sourceColors = await _pixelColorCount(frame.image);
      evidence['image_source_colors'] = sourceColors;
      expect(sourceColors, greaterThan(16));
      frame.image.dispose();
      codec.dispose();
      evidence['image_thumbnail_error'] = image.thumbnailError;
      expect(
        image.thumbnailStatus,
        ThumbnailStatus.ready,
        reason: image.thumbnailError,
      );

      final imageEvidence = <Map<String, Object?>>[];
      evidence['images'] = imageEvidence;
      for (final photo in session.state.snapshot.assets.where(
        (asset) => asset.kind == MediaKind.image,
      )) {
        expect(
          photo.thumbnailStatus,
          ThumbnailStatus.ready,
          reason: photo.thumbnailError,
        );
        session.updatePreferences(
          session.state.snapshot.preferences.copyWith(
            selectedAssetId: photo.id,
          ),
        );
        await _pumpUntil(
          tester,
          () => find
              .byKey(ValueKey('image-viewer-${photo.id}'))
              .evaluate()
              .isNotEmpty,
          label: '${photo.name} image viewer',
        );
        final thumbnail = await storage.assetStore.readBytes(
          photo.thumbnailKey!,
        );
        final thumbnailCodec = await ui.instantiateImageCodec(thumbnail);
        final thumbnailFrame = await thumbnailCodec.getNextFrame();
        expect(thumbnailFrame.image.width, lessThanOrEqualTo(320));
        expect(thumbnailFrame.image.height, lessThanOrEqualTo(320));
        final thumbnailColors = await _pixelColorCount(thumbnailFrame.image);
        imageEvidence.add({
          'name': photo.name,
          'thumbnail_bytes': thumbnail.length,
          'thumbnail_colors': thumbnailColors,
          'thumbnail_dimensions': [
            thumbnailFrame.image.width,
            thumbnailFrame.image.height,
          ],
        });
        thumbnailFrame.image.dispose();
        thumbnailCodec.dispose();
        expect(
          thumbnailColors,
          greaterThan(16),
          reason: '${photo.name} thumbnail must preserve actual image pixels',
        );
      }

      final videoEvidence = <Map<String, Object?>>[];
      evidence['videos'] = videoEvidence;
      for (final name in ['landscape.mp4', 'portrait.mp4']) {
        final asset = session.state.snapshot.assets.singleWhere(
          (value) => value.name == name,
        );
        final videoRecord = <String, Object?>{'name': name};
        videoEvidence.add(videoRecord);
        session.updatePreferences(
          session.state.snapshot.preferences.copyWith(
            selectedAssetId: asset.id,
          ),
        );
        final selecting = bootstrap.preview.select(asset);
        await _pumpUntil(
          tester,
          () =>
              session.state.snapshot.assets
                      .singleWhere((value) => value.id == asset.id)
                      .thumbnailStatus ==
                  ThumbnailStatus.ready ||
              bootstrap.preview.error != null,
          label: '$name first frame and thumbnail',
        );
        await selecting;
        videoRecord['first_frame_probe'] = probeVideoFrame();
        videoRecord['preview_error'] = bootstrap.preview.error;
        expect(
          bootstrap.preview.error,
          isNull,
          reason: '$name actual preview failed',
        );
        final player = bootstrap.preview.playback!;
        expect(player.playing, isFalse);
        expect(player.duration.inMilliseconds, greaterThan(1500));
        final screenshot = await player.screenshot().timeout(
          const Duration(seconds: 10),
        );
        expect(screenshot, isNotNull);
        expect(screenshot, isNotEmpty);
        final screenshotCodec = await ui.instantiateImageCodec(screenshot!);
        final screenshotFrame = await screenshotCodec.getNextFrame();
        expect(screenshotFrame.image.width, name == 'landscape.mp4' ? 160 : 96);
        expect(
          screenshotFrame.image.height,
          name == 'landscape.mp4' ? 96 : 160,
        );
        final pixels = await screenshotFrame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(pixels, isNotNull);
        final colors = <int>{};
        for (var offset = 0; offset + 4 <= pixels!.lengthInBytes; offset += 4) {
          colors.add(pixels.getUint32(offset));
        }
        videoRecord.addAll({
          'screenshot_bytes': screenshot.length,
          'first_screenshot_colors': colors.length,
          'first_frame_probe': probeVideoFrame(),
          if (colors.length <= 16)
            'blank_screenshot_base64': base64Encode(screenshot),
        });
        screenshotFrame.image.dispose();
        screenshotCodec.dispose();
        await bootstrap.preview.setVisible(true);
        await bootstrap.preview.setVolume(
          0,
        ); // Muted playback also obeys Web autoplay policy.
        await bootstrap.preview.togglePlaying();
        await _pumpUntil(
          tester,
          () => player.playing && player.position.inMilliseconds > 0,
          label: '$name actual playback advances',
        );
        await bootstrap.preview.pause();
        await _pumpUntil(tester, () => !player.playing, label: '$name pauses');
        await bootstrap.preview.seek(const Duration(milliseconds: 1000));
        await _pumpUntil(
          tester,
          () => (player.position.inMilliseconds - 1000).abs() < 300,
          label: '$name seeks',
        );
        await bootstrap.preview.setVolume(25);
        await _pumpUntil(
          tester,
          () => (player.volume - 25).abs() < .1,
          label: '$name volume',
        );
        videoRecord['after_play_seek_probe'] = probeVideoFrame();
        expect(
          colors.length,
          greaterThan(16),
          reason: 'Screenshot must contain the real synthetic frame, not a blank surface',
        );
        final stored = session.state.snapshot.assets.singleWhere(
          (value) => value.id == asset.id,
        );
        expect(stored.thumbnailStatus, ThumbnailStatus.ready);
        final thumbnail = await storage.assetStore.readBytes(
          stored.thumbnailKey!,
        );
        final thumbnailCodec = await ui.instantiateImageCodec(thumbnail);
        final thumbnailFrame = await thumbnailCodec.getNextFrame();
        expect(thumbnailFrame.image.width, lessThanOrEqualTo(320));
        expect(thumbnailFrame.image.height, lessThanOrEqualTo(320));
        final storedThumbnailColors = await _pixelColorCount(
          thumbnailFrame.image,
        );
        thumbnailFrame.image.dispose();
        thumbnailCodec.dispose();
        expect(
          storedThumbnailColors,
          greaterThan(16),
          reason: '$name persisted thumbnail must preserve real frame pixels',
        );
        final lease = storage.leases.last;
        session.updatePreferences(
          session.state.snapshot.preferences.copyWith(selectedAssetId: null),
        );
        await bootstrap.preview.select(null);
        await _pumpUntil(
          tester,
          () => bootstrap.preview.playback == null,
          label: '$name releases playback',
        );
        expect(lease.releaseCount, 1);
        await sandbox.verifyReleasedUri(lease.uri);
        videoRecord.addAll({
          'first_frame': true,
          'play_pause_seek_volume': true,
          'thumbnail_bytes': thumbnail.length,
          'thumbnail_colors': storedThumbnailColors,
          'lease_released': true,
        });
      }
      await session.save();
      expect(session.state.error, isNull);
      final expectedSnapshot = session.state.snapshot;
      await tester.pumpWidget(const SizedBox.shrink());
      await bootstrap.disposeAsync();
      owned = null;
      final reopened = await WorkbenchBootstrap.create(
        openStorage: sandbox.open,
        fileImportPort: FixtureImportPort(),
      );
      owned = reopened;
      expect(reopened.session.state.snapshot, expectedSnapshot);
      for (final asset in reopened.session.state.snapshot.assets) {
        expect(
          await reopened.storageOwner.assetStore.readBytes(asset.storageKey),
          await loadFixture(asset.name),
        );
      }
      await tester.pumpWidget(WorkbenchApp(bootstrap: reopened));
      await tester.pump();
      const TextRoute().go(tester.element(find.byType(Scaffold).first));
      await _pumpUntil(
        tester,
        () => reopened.session.state.snapshot.preferences.navId == 'text',
        label: 'typed text route persists preference',
      );
      expect(find.textContaining('中文资料.md'), findsWidgets);
      await reopened.session.save();
      expect(
        (await reopened.storageOwner.repository.load()).preferences.navId,
        'text',
      );
      evidence['reopened_snapshot_and_content'] = true;
      expect(tester.takeException(), isNull);
      debugPrint('KOI_RUNTIME_EVIDENCE ${jsonEncode(evidence)}');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await owned?.disposeAsync();
      await sandbox.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}

Future<int> _pixelColorCount(ui.Image image) async {
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(pixels, isNotNull);
  final colors = <int>{};
  for (var offset = 0; offset + 4 <= pixels!.lengthInBytes; offset += 4) {
    colors.add(pixels.getUint32(offset));
  }
  return colors.length;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String label,
}) async {
  final elapsed = Stopwatch()..start();
  while (!condition()) {
    if (elapsed.elapsed > const Duration(seconds: 30)) {
      fail('Timeout waiting for $label');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump();
}

bool _hasSourceBytes(ImageProvider<Object> provider, int byteLength) {
  if (provider is ResizeImage) {
    return _hasSourceBytes(provider.imageProvider, byteLength);
  }
  return provider is MemoryImage && provider.bytes.length == byteLength;
}
