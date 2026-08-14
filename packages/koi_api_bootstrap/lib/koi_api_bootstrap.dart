library;

import 'package:koi_api_bootstrap/src/backend/web_backend.dart'
    if (dart.library.io) 'package:koi_api_bootstrap/src/backend/native_backend.dart'
    as backend;
import 'package:koi_api_bootstrap/src/koi_api_bindings.dart';
import 'package:koi_api_bootstrap/src/koi_api_bootstrap_options.dart';
import 'package:koi_api_bootstrap/src/koi_api_runtime.dart';
import 'package:koi_api_bootstrap/src/koi_memory_token_session.dart';
import 'package:koi_api_bootstrap/src/token_storage/web_token_session.dart'
    if (dart.library.io) 'package:koi_api_bootstrap/src/token_storage/native_token_session.dart'
    as token_storage;

export 'src/koi_api_bindings.dart';
export 'src/koi_api_bootstrap_options.dart';
export 'src/koi_api_log.dart';
export 'src/koi_api_runtime.dart';
export 'src/koi_memory_token_session.dart';
export 'src/koi_secure_token_session.dart';

/// Initializes the platform-appropriate API runtime.
///
/// Native platforms initialize `koi_network`. Web receives an explicit no-op
/// runtime so importing this public library never pulls native-only networking
/// code into a web build.
Future<KoiApiRuntime> bootstrapKoiApi(
  KoiApiBootstrapOptions options, {
  KoiApiBindings? bindings,
}) {
  return backend.bootstrapKoiApiBackend(options, bindings ?? KoiApiBindings());
}

/// Disposes the active API runtime, if one exists.
Future<void> disposeKoiApi() => backend.disposeKoiApiBackend();

/// Creates the platform-default token session.
///
/// Native platforms persist the token in secure storage so a restart keeps
/// the session. Web keeps the token in memory only, so a refresh starts a
/// fresh login. The concrete storage implementation never leaks into the
/// public API.
Future<KoiTokenSession> createDefaultTokenSession() {
  return token_storage.loadDefaultTokenSession();
}
