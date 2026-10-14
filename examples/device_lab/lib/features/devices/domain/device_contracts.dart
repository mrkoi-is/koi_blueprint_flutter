import 'dart:async';

enum DeviceCommand { summary, pauseTask, resumeTask }

final class DeviceSummary {
  const DeviceSummary({
    required this.name,
    required this.completed,
    required this.paused,
  });
  final String name;
  final int completed;
  final bool paused;
  Map<String, Object?> toJson() => {
    'name': name,
    'completed': completed,
    'paused': paused,
  };
}

abstract interface class DeviceCommandTarget {
  Future<Map<String, Object?>> execute(DeviceCommand command);
}

abstract interface class DeviceHost {
  Uri get uri;
  String get pairingCode;
  Future<void> close();
}

abstract interface class DeviceSettingsStore {
  Future<Map<String, Object?>> read();
  Future<void> write(Map<String, Object?> values);
  Future<void> close();
}

enum IncomingAction { openDocument, showTasks, importFile }

final class IncomingIntent {
  const IncomingIntent({required this.id, required this.action, this.value});
  final String id;
  final IncomingAction action;
  final String? value;
  factory IncomingIntent.fromUri(Uri uri) {
    if (uri.scheme == 'file' || uri.scheme == 'content') {
      return IncomingIntent(
        id: uri.toString(),
        action: IncomingAction.importFile,
        value: uri.scheme == 'content' ? uri.toString() : uri.toFilePath(),
      );
    }
    if (!['koi', 'http', 'https'].contains(uri.scheme)) {
      throw const FormatException('Unsupported incoming URI scheme');
    }
    final path = uri.scheme == 'koi' ? '/${uri.host}${uri.path}' : uri.path;
    if (path == '/tasks') {
      return IncomingIntent(
        id: uri.toString(),
        action: IncomingAction.showTasks,
      );
    }
    if (path != '/document') {
      throw const FormatException('Unknown incoming command');
    }
    final id = uri.queryParameters['id'];
    if (id == null || !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException('Invalid document ID');
    }
    return IncomingIntent(
      id: uri.toString(),
      action: IncomingAction.openDocument,
      value: id,
    );
  }
}

enum IncomingResult { accepted, duplicate, queued, blocked }

final class DiscoveredDevice {
  const DiscoveredDevice(this.name, this.uri);
  final String name;
  final Uri uri;
}

abstract interface class DeviceDiscovery {
  Stream<List<DiscoveredDevice>> get changes;
  Future<void> start();
  Future<void> close();
}

abstract interface class DeviceAdvertisement {
  Future<void> close();
}

abstract interface class IncomingLinkSource {
  Stream<Uri> get links;
  Future<Uri?> initial();
}

final class ImportedDocument {
  const ImportedDocument(this.name, this.text);
  final String name;
  final String text;
}

enum DeviceConnectionState {
  disconnected,
  connecting,
  paired,
  reconnecting,
  failed,
  closed,
}
