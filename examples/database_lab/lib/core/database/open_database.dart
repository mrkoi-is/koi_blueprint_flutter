export 'package:database_lab/core/database/open_database_unsupported.dart'
    if (dart.library.io) 'package:database_lab/core/database/open_database_native.dart'
    if (dart.library.js_interop) 'package:database_lab/core/database/open_database_web.dart';
