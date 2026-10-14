import 'package:flutter/widgets.dart';

@immutable
class AppCapabilityPage {
  const AppCapabilityPage({
    required this.id,
    required this.title,
    required this.builder,
    this.titleBuilder,
  });
  final String id;
  final String title;
  final WidgetBuilder builder;
  final String Function(BuildContext)? titleBuilder;

  String titleFor(BuildContext context) => titleBuilder?.call(context) ?? title;
}
