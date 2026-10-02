import 'package:device_lab/l10n/generated/app_localizations.dart';

import 'dart:async';

import 'package:device_lab/features/devices/application/device_lab_session.dart';
import 'package:device_lab/features/devices/data/device_discovery.dart';
import 'package:device_lab/features/devices/data/device_host.dart';
import 'package:device_lab/features/devices/data/device_settings.dart';
import 'package:device_lab/features/devices/data/incoming_file.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';
import 'package:device_lab/features/devices/data/pick_directory.dart';
import 'package:device_lab/features/devices/presentation/providers/device_providers.dart';
import 'package:device_lab/features/devices/presentation/screens/device_page.dart';
import 'package:flutter/material.dart';
import 'package:koi_core/koi_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Widget buildDeviceLabCapability(BuildContext context) =>
    const DeviceLabBootstrap();

class DeviceLabBootstrap extends StatefulWidget {
  const DeviceLabBootstrap({super.key, this.links});
  final IncomingLinkSource? links;
  @override
  State<DeviceLabBootstrap> createState() => _DeviceLabBootstrapState();
}

class _DeviceLabBootstrapState extends State<DeviceLabBootstrap> {
  DeviceLabSession? _session;
  Object? _error;
  late final void Function() _unregister;
  Future<void>? _opening;
  @override
  void initState() {
    super.initState();
    _unregister = CapabilityLifecycle.instance.register(
      prepare: () async {
        await _opening;
        try {
          if (_session?.state.dirty ?? false) await _session!.saveDraft();
          return true;
        } catch (_) {
          return false;
        }
      },
      close: () async {
        await _opening;
        await _session?.close();
      },
    );
    _opening = _open();
  }

  Future<void> _open() async {
    setState(() => _error = null);
    DeviceLabSession? pending;
    try {
      pending = DeviceLabSession(
        settings: await openDeviceSettings(),
        discovery: createDeviceDiscovery(),
        startHost: startDeviceHost,
        advertise: advertiseDevice,
        importFile: readIncomingFile,
        links: widget.links,
        canHost: canHostDevices,
        pickDirectory: pickSetupDirectory,
        pickDocument: pickIncomingDocument,
      );
      await pending.initialize();
      if (!mounted) {
        await pending.close();
        return;
      }
      setState(() => _session = pending);
    } catch (error) {
      await pending?.close();
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _unregister();
    unawaited(_session?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final session = _session;
    if (session != null) {
      return ProviderScope(
        overrides: [deviceSessionProvider.overrideWithValue(session)],
        child: const DevicePage(),
      );
    }
    return Scaffold(
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(strings.devicesOpenFailed('$_error')),
                  FilledButton(
                    onPressed: () => _opening = _open(),
                    child: Text(strings.devicesRetry),
                  ),
                ],
              ),
      ),
    );
  }
}
