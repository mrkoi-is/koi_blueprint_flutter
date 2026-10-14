import 'package:network_lab/features/network/data/http_transport_stub.dart'
    if (dart.library.io) 'package:network_lab/features/network/data/http_transport_native.dart'
    if (dart.library.js_interop) 'package:network_lab/features/network/data/http_transport_web.dart'
    as platform;
import 'package:network_lab/shared/network/domain/http_ports.dart';

HttpTransport createHttpTransport() => platform.createHttpTransport();
