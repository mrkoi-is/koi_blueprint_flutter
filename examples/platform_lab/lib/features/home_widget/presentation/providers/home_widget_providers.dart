import 'package:platform_lab/features/home_widget/data/home_widget_configuration.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:platform_lab/features/home_widget/data/plugin_home_widget.dart';
import 'package:platform_lab/features/home_widget/domain/widget_snapshot.dart';
part 'home_widget_providers.g.dart';

@Riverpod(keepAlive: true)
HomeWidgetPort homeWidgetPort(Ref ref) =>
    PluginHomeWidget(appGroup: homeWidgetAppGroup);

@riverpod
class HomeWidgetPublisher extends _$HomeWidgetPublisher {
  @override
  AsyncValue<void> build() => const AsyncData(null);
  Future<void> publish(WidgetSnapshot snapshot) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => ref.read(homeWidgetPortProvider).publish(snapshot),
    );
    if (ref.mounted) state = result;
  }
}
