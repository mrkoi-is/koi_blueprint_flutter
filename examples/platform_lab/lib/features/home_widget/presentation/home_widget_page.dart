import 'package:platform_lab/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_lab/features/home_widget/domain/widget_snapshot.dart';
import 'package:platform_lab/features/home_widget/presentation/providers/home_widget_providers.dart';

Widget buildHomeWidgetPage(BuildContext context) => const HomeWidgetPage();

class HomeWidgetPage extends ConsumerStatefulWidget {
  const HomeWidgetPage({super.key});
  @override
  ConsumerState<HomeWidgetPage> createState() => _HomeWidgetPageState();
}

class _HomeWidgetPageState extends ConsumerState<HomeWidgetPage> {
  final _title = TextEditingController();
  bool _initializedTitle = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedTitle) {
      _title.text = AppLocalizations.of(context)!.platformSnapshotTitle;
      _initializedTitle = true;
    }
  }

  int _completed = 0;
  bool _published = false;
  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeWidgetPublisherProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.platformHomeWidget),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(AppLocalizations.of(context)!.platformWidgetDescription),
          TextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.platformTitle,
            ),
          ),
          ListTile(
            title: Text(
              AppLocalizations.of(context)!.platformCompleted(_completed),
            ),
            trailing: IconButton(
              tooltip: AppLocalizations.of(context)!.platformIncrementCompleted,
              icon: const Icon(Icons.add),
              onPressed: () => setState(() => _completed++),
            ),
          ),
          FilledButton(
            onPressed: state.isLoading
                ? null
                : () async {
                    setState(() => _published = false);
                    await ref
                        .read(homeWidgetPublisherProvider.notifier)
                        .publish(
                          WidgetSnapshot(
                            title: _title.text,
                            updatedAt: DateTime.now(),
                            completed: _completed,
                          ),
                        );
                    if (mounted &&
                        !ref.read(homeWidgetPublisherProvider).hasError) {
                      setState(() => _published = true);
                    }
                  },
            child: Text(AppLocalizations.of(context)!.platformUpdateWidget),
          ),
          if (_published)
            Text(AppLocalizations.of(context)!.platformSnapshotSent),
          if (state.isLoading) const LinearProgressIndicator(),
          if (state.hasError) SelectableText('${state.error}'),
        ],
      ),
    );
  }
}
