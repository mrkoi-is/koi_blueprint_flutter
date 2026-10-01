import 'package:koi_core/koi_core.dart';

abstract interface class DraftRepository {
  FutureResult<String> read();
  FutureResult<void> save(String text);
}

abstract interface class DraftSubmission {
  FutureResult<void> submit(String text);
}
