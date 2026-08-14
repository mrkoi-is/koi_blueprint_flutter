import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koi_api_bootstrap/koi_api_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KoiSecureTokenSession', () {
    test('hydrates the persisted token on load', () async {
      final store = _FakeTokenStore(persisted: 'persisted-token');

      final session = await KoiSecureTokenSession.load(store);

      expect(session.getToken(), 'persisted-token');
      expect(session.hasToken, isTrue);
    });

    test('treats a missing or empty persisted value as no token', () async {
      final empty = await KoiSecureTokenSession.load(_FakeTokenStore());
      final blank = await KoiSecureTokenSession.load(
        _FakeTokenStore(persisted: ''),
      );

      expect(empty.getToken(), isNull);
      expect(empty.hasToken, isFalse);
      expect(blank.getToken(), isNull);
      expect(blank.hasToken, isFalse);
    });

    test('saves through the store before exposing the token', () async {
      final store = _FakeTokenStore();
      final session = await KoiSecureTokenSession.load(store);

      await session.saveToken('access-token');

      expect(store.persisted, 'access-token');
      expect(session.getToken(), 'access-token');

      await session.clearToken();

      expect(store.persisted, isNull);
      expect(session.getToken(), isNull);
      expect(session.hasToken, isFalse);
    });

    test('rejects an empty token', () async {
      final session = await KoiSecureTokenSession.load(_FakeTokenStore());

      await expectLater(session.saveToken(''), throwsArgumentError);
    });

    test('keeps the in-memory token when persistence fails', () async {
      final store = _FakeTokenStore(persisted: 'old-token')..failWrites = true;
      final session = await KoiSecureTokenSession.load(store);

      await expectLater(session.saveToken('new-token'), throwsStateError);

      expect(session.getToken(), 'old-token');
      expect(store.persisted, 'old-token');
    });

    test('keeps the in-memory token when deletion fails', () async {
      final store = _FakeTokenStore(persisted: 'old-token')..failDeletes = true;
      final session = await KoiSecureTokenSession.load(store);

      await expectLater(session.clearToken(), throwsStateError);

      expect(session.getToken(), 'old-token');
      expect(store.persisted, 'old-token');
    });
  });

  group('createDefaultTokenSession', () {
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final secureStorage = <String, String>{};

    setUp(() {
      secureStorage.clear();
      messenger.setMockMethodCallHandler(channel, (call) async {
        final arguments = (call.arguments as Map).cast<String, Object?>();
        final key = arguments['key'] as String;
        return switch (call.method) {
          'read' => secureStorage[key],
          'write' => secureStorage[key] = arguments['value'] as String,
          'delete' => secureStorage.remove(key),
          _ => throw UnimplementedError(call.method),
        };
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('restores the token persisted in secure storage', () async {
      secureStorage['koi_api_auth_token'] = 'stored-token';

      final session = await createDefaultTokenSession();

      expect(session, isA<KoiSecureTokenSession>());
      expect(session.getToken(), 'stored-token');
    });

    test('persists and clears the token through secure storage', () async {
      final session = await createDefaultTokenSession();
      expect(session.getToken(), isNull);

      await session.saveToken('fresh-token');
      expect(secureStorage['koi_api_auth_token'], 'fresh-token');

      final reloaded = await createDefaultTokenSession();
      expect(reloaded.getToken(), 'fresh-token');

      await reloaded.clearToken();
      expect(secureStorage.containsKey('koi_api_auth_token'), isFalse);
      expect(reloaded.getToken(), isNull);
    });
  });
}

final class _FakeTokenStore implements KoiTokenStore {
  _FakeTokenStore({this.persisted});

  String? persisted;
  bool failWrites = false;
  bool failDeletes = false;

  @override
  Future<String?> read() async => persisted;

  @override
  Future<void> write(String token) async {
    if (failWrites) {
      throw StateError('write failed');
    }
    persisted = token;
  }

  @override
  Future<void> delete() async {
    if (failDeletes) {
      throw StateError('delete failed');
    }
    persisted = null;
  }
}
