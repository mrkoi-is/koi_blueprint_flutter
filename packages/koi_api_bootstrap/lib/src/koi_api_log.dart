enum KoiApiLogLevel { debug, info, warning, error, fatal }

typedef KoiApiLogCallback =
    void Function(
      KoiApiLogLevel level,
      String message,
      Object? error,
      StackTrace? stackTrace,
    );
