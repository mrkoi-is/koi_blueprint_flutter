@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:koi_diagnostics/src/viewer_html.dart';
import 'package:web/web.dart' as web;

void main() {
  for (final (locale, tag, title, failure) in [
    ('en', 'en', 'Diagnostics', 'Export failed (HTTP 503).'),
    ('zh', 'zh-Hans', '诊断', '导出失败（HTTP 503）。'),
    ('zh_Hant', 'zh-Hant', '診斷', '匯出失敗（HTTP 503）。'),
  ]) {
    test('$locale renders metadata and a localized export failure in a browser', () async {
      final frame = web.HTMLIFrameElement()..style.width = '320px';
      final ready = Completer<void>();
      frame.onload = ((web.Event _) => ready.complete()).toJS;
      frame.srcdoc = viewerHtml(locale)
          .replaceFirst(
            '<script>',
            '<script>window.fetch=async()=>({ok:false,status:503});</script><script>',
          )
          .toJS;
      web.document.body!.appendChild(frame);
      try {
        await ready.future.timeout(const Duration(seconds: 10));
        final document = frame.contentDocument!;
        expect(document.documentElement!.getAttribute('lang'), tag);
        expect(document.title, title);
        (document.getElementById('export')! as web.HTMLElement).click();
        // The production handler awaits fetch; allow its microtask to complete.
        await Future<void>.delayed(Duration.zero);
        expect(document.getElementById('status')!.textContent, failure);
        expect(document.documentElement!.scrollWidth, lessThanOrEqualTo(320));
      } finally {
        frame.remove();
      }
    });
  }
}
