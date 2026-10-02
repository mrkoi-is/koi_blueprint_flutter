import 'package:feature_lab/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CatalogPage extends ConsumerWidget {
  const CatalogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(catalogControllerProvider);
    final busy =
        value.isLoading ||
        ((value.value?.isRefreshing ?? false) ||
            (value.value?.isAppending ?? false));
    return Scaffold(
      appBar: AppBar(title: const Text('Catalog')),
      body: Column(
        children: [
          TextField(
            decoration: const InputDecoration(labelText: 'Search catalog'),
            onChanged: (query) =>
                ref.read(catalogQueryProvider.notifier).setQuery(query),
          ),
          if (busy) const LinearProgressIndicator(),
          if (value.hasError || value.value?.operationFailure != null)
            const Text('Unable to load catalog'),
          Expanded(
            child: value.hasValue
                ? value.value!.items.isEmpty
                      ? const Center(child: Text('No items'))
                      : ListView.builder(
                          itemCount: value.value!.items.length,
                          itemBuilder: (context, index) => ListTile(
                            title: Text(value.value!.items[index].label),
                          ),
                        )
                : const SizedBox.shrink(),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () => ref.read(catalogControllerProvider.notifier).refresh(),
            child: const Text('Refresh'),
          ),
          TextButton(
            onPressed:
                busy || !value.hasValue || value.value?.nextCursor == null
                ? null
                : () => ref.read(catalogControllerProvider.notifier).loadMore(),
            child: const Text('Load more'),
          ),
        ],
      ),
    );
  }
}
