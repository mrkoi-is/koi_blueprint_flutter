import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window')
external JSObject get _window;

void registerAiWebDriver(
  Future<Map<String, dynamic>> Function(Map<String, String>) call,
) {
  _window.setProperty(r'$flutterDriverResult'.toJS, null);
  _window.setProperty(
    r'$flutterDriver'.toJS,
    (JSAny message) {
      final params = Map<String, String>.from(
        jsonDecode((message as JSString).toDart) as Map,
      );
      call(params).then((result) {
        _window.setProperty(
          r'$flutterDriverResult'.toJS,
          jsonEncode(result).toJS,
        );
      });
    }.toJS,
  );
}
