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

  static AppEnvironment get current {
    final env = const String.fromEnvironment('ENV', defaultValue: 'dev');

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
        enableNetworkLog: true,
      ),
      _ => const AppEnvironment(
        flavor: AppFlavor.dev,
        name: 'dev',
        appTitle: 'Koi Blueprint Admin',
        apiBaseUrl: 'https://dev-api.example.com/',
        enableNetworkLog: true,
      ),
    };
  }
}
