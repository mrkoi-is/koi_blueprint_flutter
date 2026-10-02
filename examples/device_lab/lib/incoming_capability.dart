import 'package:device_lab/features/devices/data/incoming_links.dart';
import 'package:device_lab/local_capabilities.dart';
import 'package:flutter/widgets.dart';

Future<void> initializeIncomingIntents() async =>
    IncomingLinkInbox.instance.start();
Future<void> disposeIncomingIntents() => IncomingLinkInbox.instance.close();
Widget buildIncomingIntentsCapability(BuildContext context) {
  IncomingLinkInbox.instance.start();
  return LocalCapability(onboarding: false, links: IncomingLinkInbox.instance);
}
