import 'package:device_lab/l10n/generated/app_localizations.dart';

import 'dart:async';

import 'package:device_lab/features/devices/data/device_settings.dart';
import 'package:device_lab/features/devices/data/incoming_file.dart';
import 'package:device_lab/features/devices/domain/device_contracts.dart';
import 'package:device_lab/features/devices/data/pick_directory.dart';
import 'package:device_lab/features/local_setup/application/local_setup_session.dart';
import 'package:device_lab/features/local_setup/presentation/screens/local_setup_page.dart';
import 'package:device_lab/features/local_setup/presentation/providers/local_setup_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koi_core/koi_core.dart';

class LocalCapability extends StatefulWidget {
  const LocalCapability({super.key, required this.onboarding, this.links});
  final bool onboarding;
  final IncomingLinkSource? links;
  @override
  State<LocalCapability> createState() => _LocalCapabilityState();
}

class _LocalCapabilityState extends State<LocalCapability> {
  LocalSetupSession? _session;
  Object? _error;
  late final void Function() _unregister;
  late Future<void> _opening;

  @override
  void initState() {
    super.initState();
    _unregister = CapabilityLifecycle.instance.register(
      prepare: () async {
        await _opening;
        return await _session?.prepare() ?? true;
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
    LocalSetupSession? pending;
    try {
      pending = LocalSetupSession(
        store: await openDeviceSettings(
          namespace: widget.onboarding ? 'onboarding' : 'incoming_intents',
        ),
        links: widget.links,
        pickDirectory: pickSetupDirectory,
        pickDocument: pickIncomingDocument,
        importFile: readIncomingFile,
        requireOnboarding: widget.onboarding,
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
        overrides: [localSetupSessionProvider.overrideWithValue(session)],
        child: LocalSetupPage(onboarding: widget.onboarding),
      );
    }
    return Scaffold(
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_error'),
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
