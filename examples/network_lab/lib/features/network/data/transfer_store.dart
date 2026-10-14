import 'package:network_lab/features/network/data/transfer_store_stub.dart'
    if (dart.library.io) 'package:network_lab/features/network/data/transfer_store_native.dart'
    if (dart.library.js_interop) 'package:network_lab/features/network/data/transfer_store_web.dart'
    as platform;
import 'package:network_lab/features/network/domain/network_ports.dart';

Future<TransferStore> openTransferStore({
  String? nativeDirectory,
  String databaseName = 'koi_network_lab',
}) => platform.openTransferStore(
  nativeDirectory: nativeDirectory,
  databaseName: databaseName,
);
