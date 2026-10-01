import 'package:flutter/foundation.dart';

enum AppFlavor { dev, staging, prod }

class AppEnvironment {
  const AppEnvironment({
    required this.flavor,
    required this.name,
    required this.appTitle,
    required this.apiBaseUrl,
    required this.enableNetworkLog,
  });

  final AppFlavor flavor;
  final String name;
  final String appTitle;
  final String apiBaseUrl;
  final bool enableNetworkLog;

  bool get usesMockAuth => flavor == AppFlavor.dev;

  static AppEnvironment get current =>
      resolve(const String.fromEnvironment('ENV'), isRelease: kReleaseMode);

  static AppEnvironment resolve(String value, {required bool isRelease}) {
    final requested = value.trim();
    if (requested.isEmpty) {
      if (isRelease) {
        throw StateError(
          'Release 构建必须通过 --dart-define=ENV=staging 或 prod 指定环境',
        );
      }
      return fromName('dev');
    }

    final environment = fromName(requested);
    if (isRelease && environment.usesMockAuth) {
      throw StateError('Release 构建禁止启用 dev Mock 认证');
    }
    return environment;
  }

  static AppEnvironment fromName(String value) {
    final env = value.trim().toLowerCase();
    return switch (env) {
      'prod' => const AppEnvironment(
        flavor: AppFlavor.prod,
        name: 'prod',
        appTitle: 'Koi Blueprint Admin',
        apiBaseUrl: 'https://api.example.com/',
        enableNetworkLog: false,
      ),
      'staging' => const AppEnvironment(
        flavor: AppFlavor.staging,
        name: 'staging',
        appTitle: 'Koi Blueprint Admin',
        apiBaseUrl: 'https://staging-api.example.com/',
        enableNetworkLog: false,
      ),
      'dev' => const AppEnvironment(
        flavor: AppFlavor.dev,
        name: 'dev',
        appTitle: 'Koi Blueprint Admin',
        apiBaseUrl: 'https://dev-api.example.com/',
        enableNetworkLog: true,
      ),
      _ => throw ArgumentError.value(value, 'ENV', '仅支持 dev、staging 或 prod'),
    };
  }
}
