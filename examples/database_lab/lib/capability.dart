import 'package:database_lab/l10n/generated/app_localizations.dart';

import 'dart:async';

import 'package:database_lab/core/database/open_database.dart';
import 'package:database_lab/features/library/application/library_session.dart';
import 'package:database_lab/features/library/presentation/providers/library_providers.dart';
import 'package:database_lab/features/library/presentation/screens/library_page.dart';
import 'package:flutter/material.dart';
import 'package:koi_core/koi_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Widget buildDatabaseLabCapability(BuildContext context) =>
    const DatabaseLabBootstrap();

class DatabaseLabBootstrap extends StatefulWidget {
  const DatabaseLabBootstrap({super.key});
  @override
  State<DatabaseLabBootstrap> createState() => _DatabaseLabBootstrapState();
}

class _DatabaseLabBootstrapState extends State<DatabaseLabBootstrap> {
  LibrarySession? _session;
  Object? _error;
  late final void Function() _unregister;
  Future<void>? _opening;
  @override
  void initState() {
    super.initState();
    _unregister = CapabilityLifecycle.instance.register(
      prepare: () async {
        await _opening;
        return true;
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
    LibrarySession? pending;
    try {
      pending = LibrarySession(await openDatabase());
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
        overrides: [
          libraryRepositoryProvider.overrideWithValue(session.repository),
        ],
        child: LibraryPage(availability: session.availability),
      );
    }
    return Scaffold(
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(strings.databaseOpenFailed('$_error')),
                  FilledButton(
                    onPressed: () => _opening = _open(),
                    child: Text(strings.databaseRetry),
                  ),
                ],
              ),
      ),
    );
  }
}
