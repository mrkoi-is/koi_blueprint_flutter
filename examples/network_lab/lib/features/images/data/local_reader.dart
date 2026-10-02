export 'local_reader_stub.dart'
    if (dart.library.io) 'local_reader_native.dart'
    if (dart.library.js_interop) 'local_reader_web.dart';
