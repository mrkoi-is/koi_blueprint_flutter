import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:platform_lab/features/home_widget/domain/widget_snapshot.dart';

/// The native templates read one versioned JSON snapshot, never a live provider.
class PluginHomeWidget implements HomeWidgetPort {
  PluginHomeWidget({required this.appGroup});
  final String appGroup;
  @override
  Future<void> publish(WidgetSnapshot snapshot) async {
    if (kIsWeb ||
        !const {
          TargetPlatform.android,
          TargetPlatform.iOS,
        }.contains(defaultTargetPlatform)) {
      throw UnsupportedError('Home widgets require Android or iOS');
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (appGroup.isEmpty) {
        throw StateError('HOME_WIDGET_APP_GROUP is not configured');
      }
      await HomeWidget.setAppGroupId(appGroup);
    }
    if (await HomeWidget.saveWidgetData<String>(
          'koi_snapshot',
          jsonEncode(snapshot.toJson()),
        ) !=
        true) {
      throw StateError('Widget snapshot was not saved');
    }
    if (await HomeWidget.updateWidget(
          androidName: 'KoiHomeWidgetProvider',
          iOSName: 'KoiHomeWidget',
        ) !=
        true) {
      throw StateError('Native widget update was not accepted');
    }
  }
}
