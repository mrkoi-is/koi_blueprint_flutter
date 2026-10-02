import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:network_lab/features/images/domain/image_source.dart';

LocalImageReader createLocalImageReader() => BrowserImageReader();

final class BrowserImageReader implements LocalImageReader {
  Uint8List? _selected;
  int _sequence = 0;
  bool _closed = false;
  Completer<String?>? _pick;
  @override
  Future<String?> pick({required int maxBytes}) async {
    if (_closed) throw StateError('Local reader closed');
    if (_pick != null) throw StateError('A picker is already open');
    final result = _pick = Completer<String?>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'image/*';
    input.onchange = ((web.Event event) {
      unawaited(() async {
        try {
          final file = input.files?.item(0);
          if (file == null) {
            result.complete(null);
            return;
          }
          if (file.size > maxBytes) {
            throw StateError('Local image exceeds byte budget');
          }
          final buffer = await file.arrayBuffer().toDart;
          if (_closed) return;
          final bytes = buffer.toDart.asUint8List();
          if (bytes.length > maxBytes) {
            throw StateError('Local image exceeds byte budget');
          }
          _selected = Uint8List.fromList(bytes);
          if (!result.isCompleted) result.complete('picked-${++_sequence}');
        } catch (error, stack) {
          if (!result.isCompleted) result.completeError(error, stack);
        }
      }());
    }).toJS;
    input.oncancel = ((web.Event event) {
      if (!result.isCompleted) result.complete(null);
    }).toJS;
    try {
      input.click();
      return await result.future;
    } finally {
      input.onchange = null;
      input.oncancel = null;
      _pick = null;
    }
  }

  @override
  Future<Uint8List> read(String key, {required int maxBytes}) async {
    if (_closed || key != 'picked-$_sequence' || _selected == null) {
      throw StateError('Pick a local browser image first');
    }
    if (_selected!.length > maxBytes) {
      throw StateError('Local image exceeds byte budget');
    }
    return Uint8List.fromList(_selected!);
  }

  @override
  void close() {
    _closed = true;
    _selected = null;
    if (_pick != null && !_pick!.isCompleted) _pick!.complete(null);
  }
}
