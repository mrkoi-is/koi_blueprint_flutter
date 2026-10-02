@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:network_lab/features/network/data/transfer_store.dart';
import 'package:network_lab/features/network/domain/network_ports.dart';

void main() {
  late Directory directory;
  late TransferStore store;
  const metadata = TransferMetadata(
    source: 'http://fixture/file',
    etag: '"v1"',
    total: 4,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('network-store-');
    store = await openTransferStore(nativeDirectory: directory.path);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  test('disk staging persists through reopen, commit stays separate from cancelled attempt', () async {
    expect(await store.metadata('x'), isNull);
    expect(await store.length('x'), 0);
    await store.begin('x', metadata);
    await store.append('x', [1, 2]);
    await store.close();
    store = await openTransferStore(nativeDirectory: directory.path);
    expect((await store.metadata('x'))!.matches(metadata), true);
    expect(await store.length('x'), 2);
    await store.append('x', [3, 4]);
    await store.commit('x', 'digest');
    expect(await store.read('x').expand((bytes) => bytes).toList(), [
      1,
      2,
      3,
      4,
    ]);
    expect(await store.metadata('x'), isNull);
    await store.begin('x', metadata);
    await store.append('x', [9]);
    await store.discard('x');
    expect(await store.read('x').expand((bytes) => bytes).toList(), [
      1,
      2,
      3,
      4,
    ]);
  });
  test('second owner and escaping IDs are rejected', () async {
    await expectLater(
      openTransferStore(nativeDirectory: directory.path),
      throwsStateError,
    );
    await expectLater(
      store.begin('../user-data', metadata),
      throwsArgumentError,
    );
    await expectLater(store.append('missing', [1]), throwsStateError);
    await store.close();
    await expectLater(store.length('x'), throwsStateError);
  });
  test(
    'committing replacement preserves prior artifact when write fails',
    () async {
      await store.begin('x', metadata);
      await store.append('x', [1]);
      await store.commit('x', 'original');
      await File('${directory.path}/x.sha256').delete();
      await Directory('${directory.path}/x.sha256').create();
      await store.begin('x', metadata);
      await store.append('x', [9]);
      await expectLater(
        store.commit('x', 'new'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File('${directory.path}/x.bin').readAsBytes(), [1]);
    },
  );
}
