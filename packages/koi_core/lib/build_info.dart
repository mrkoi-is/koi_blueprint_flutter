/// One build identity supplied by blueprint build; channels are not API environments.
final class BuildInfo {
  const BuildInfo({
    this.version = 'development',
    this.build = '0',
    this.source = 'unknown',
    this.channel = 'local',
    this.platform = 'unknown',
    this.architecture = 'unknown',
  });
  static const current = BuildInfo(
    version: String.fromEnvironment(
      'BUILD_VERSION',
      defaultValue: 'development',
    ),
    build: String.fromEnvironment('BUILD_NUMBER', defaultValue: '0'),
    source: String.fromEnvironment('BUILD_SOURCE', defaultValue: 'unknown'),
    channel: String.fromEnvironment('BUILD_CHANNEL', defaultValue: 'local'),
    platform: String.fromEnvironment('BUILD_PLATFORM', defaultValue: 'unknown'),
    architecture: String.fromEnvironment('BUILD_ARCH', defaultValue: 'unknown'),
  );
  final String version;
  final String build;
  final String source;
  final String channel;
  final String platform;
  final String architecture;
  Map<String, Object> toJson() => {
    'version': version,
    'build': build,
    'source': source,
    'channel': channel,
    'platform': platform,
    'architecture': architecture,
  };
}
