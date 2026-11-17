/// Small shared vocabulary used by the native and LAN viewers.
final class DiagnosticStrings {
  const DiagnosticStrings(this.language);
  final String language;

  /// BCP 47 tag for the vocabulary actually displayed, including legacy tags.
  String get languageTag {
    final parts = language.replaceAll('_', '-').toLowerCase().split('-');
    if (parts.first != 'zh') return 'en';
    if (parts.contains('hant')) return 'zh-Hant';
    if (parts.contains('hans')) return 'zh-Hans';
    return parts.any({'tw', 'hk', 'mo'}.contains) ? 'zh-Hant' : 'zh-Hans';
  }

  String text(String en, String zh, String hant) => languageTag == 'zh-Hant'
      ? hant
      : languageTag == 'zh-Hans'
      ? zh
      : en;
  String get title => text('Diagnostics', '诊断', '診斷');
  String get notificationTitle => text('LAN diagnostics', '局域网诊断', '區域網路診斷');
  String get notificationText =>
      text('LAN viewer is running', '局域网查看服务正在运行', '區域網路檢視服務執行中');

  /// The viewer substitutes the HTTP status into this complete sentence.
  String get exportFailure => text(
    'Export failed (HTTP {status}).',
    '导出失败（HTTP {status}）。',
    '匯出失敗（HTTP {status}）。',
  );
  String get logs => text('Logs', '日志', '日誌');
  String get network => text('Network', '网络', '網路');
  String get lan => text('LAN viewer', '局域网查看', '區域網路檢視');
  String get start => text('Start', '开启', '開啟');
  String get stop => text('Stop', '停止', '停止');
  String get credential => text('Access credential', '访问凭证', '存取憑證');
  String get unsupported => text(
    'LAN hosting is unavailable in a browser.',
    '浏览器不支持启动局域网服务。',
    '瀏覽器不支援啟動區域網路服務。',
  );
  String get failed => text('Diagnostic service failed', '诊断服务失败', '診斷服務失敗');
  String get allLevels => text('All levels', '全部级别', '全部層級');
  String get source => text('Source', '来源', '來源');
  String get search => text('Search', '搜索', '搜尋');
  String get export => text('Export', '导出', '匯出');
  String get loadMore => text('Load more', '加载更多', '載入更多');
  String get empty => text('No records', '暂无记录', '暫無記錄');
  String get connect => text('Connect', '连接', '連線');
  String get connected => text('Connected', '已连接', '已連線');
  String get disconnected =>
      text('Disconnected; reconnecting', '连接已断开，正在重连', '連線中斷，正在重連');
  String get denied => text('Access denied', '访问被拒绝', '存取遭拒');
  String get notificationDenied => text(
    'Notifications are disabled; the background service may be hidden.',
    '通知未授权，后台服务通知可能不可见。',
    '通知未授權，背景服務通知可能無法顯示。',
  );
  String get batteryLimited => text(
    'Battery optimization is enabled; background access may be interrupted.',
    '电池优化仍开启，后台访问可能中断。',
    '電池最佳化仍開啟，背景存取可能中斷。',
  );
}
