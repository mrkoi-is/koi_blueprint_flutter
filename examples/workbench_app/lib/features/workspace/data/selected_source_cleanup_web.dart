import 'package:web/web.dart' as web;

void releaseSelectedSource(String path) {
  if (path.startsWith('blob:')) web.URL.revokeObjectURL(path);
}
