import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:koi_ui/koi_ui.dart';

/// Exposes successful native toolbar ownership without leaking AppKit into UI.
class WorkbenchWindowInfo extends InheritedWidget {
  const WorkbenchWindowInfo({
    required this.hasNativeToolbar,
    this.panels,
    this.title = 'Koi 工作区',
    required super.child,
    super.key,
  });
  final bool hasNativeToolbar;
  final String title;
  final KoiWorkbenchController? panels;
  static KoiWorkbenchController? panelsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkbenchWindowInfo>()?.panels;
  static String titleOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WorkbenchWindowInfo>()
          ?.title ??
      'Koi 工作区';
  static bool nativeToolbarOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WorkbenchWindowInfo>()
          ?.hasNativeToolbar ??
      false;
  @override
  bool updateShouldNotify(WorkbenchWindowInfo oldWidget) =>
      hasNativeToolbar != oldWidget.hasNativeToolbar ||
      panels != oldWidget.panels ||
      title != oldWidget.title;
}

/// App-owned macOS toolbar bridge. All platforms share the same history owner.
class WorkbenchWindowChrome extends StatefulWidget {
  const WorkbenchWindowChrome({
    super.key,
    required this.child,
    this.title = 'Koi 工作区',
    this.canGoBack = false,
    this.canGoForward = false,
    this.onBack,
    this.onForward,
    this.onSave,
    this.panels,
  });
  final Widget child;
  final String title;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback? onSave;
  final KoiWorkbenchController? panels;

  @override
  State<WorkbenchWindowChrome> createState() => _WorkbenchWindowChromeState();
}

class _WorkbenchWindowChromeState extends State<WorkbenchWindowChrome> {
  static const _channel = MethodChannel('koi/workbench_window');
  Color? _lastColor;
  Brightness? _lastBrightness;
  TextStyle? _lastTitleStyle;
  double _titlebarHeight = 0;
  int _generation = 0;
  bool _ready = false;
  bool _navigationScheduled = false;
  bool _panelsScheduled = false;
  bool get _isNative =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    if (_isNative) _channel.setMethodCallHandler(_handleNativeCall);
    widget.panels?.addListener(_schedulePanels);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'navigateBack':
        if (widget.canGoBack) widget.onBack?.call();
      case 'navigateForward':
        if (widget.canGoForward) widget.onForward?.call();
      case 'saveWorkspace':
        widget.onSave?.call();
      case 'toggleSidebar':
        widget.panels?.toggleSidebar();
      case 'toggleDetail':
        widget.panels?.toggleDetail();
      default:
        throw MissingPluginException('Unknown window command: ${call.method}');
    }
  }

  @override
  void didUpdateWidget(WorkbenchWindowChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.panels != oldWidget.panels) {
      oldWidget.panels?.removeListener(_schedulePanels);
      widget.panels?.addListener(_schedulePanels);
      _schedulePanels();
    }
    if (_isNative && widget.title != oldWidget.title && _lastColor != null) {
      final generation = ++_generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation) {
          unawaited(_apply(_lastColor!, _lastBrightness!, generation));
        }
      });
    }
    if (widget.canGoBack != oldWidget.canGoBack ||
        widget.canGoForward != oldWidget.canGoForward) {
      _scheduleNavigation();
    }
  }

  void _scheduleNavigation() {
    if (!_ready || _navigationScheduled) return;
    _navigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigationScheduled = false;
      if (mounted && _ready) unawaited(_updateNavigation());
    });
  }

  void _schedulePanels() {
    if (!_isNative || !_ready || _panelsScheduled) return;
    _panelsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _panelsScheduled = false;
      if (mounted && _ready) unawaited(_updatePanels());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _updatePanels() async {
    if (widget.panels == null) return;
    try {
      await _channel.invokeMethod<void>('updatePanels', {
        'canToggleSidebar': widget.panels!.canToggleSidebar,
        'canToggleDetail': widget.panels!.canToggleDetail,
        'sidebarOpen': widget.panels!.sidebarOpen,
        'detailOpen': widget.panels!.detailOpen,
      });
    } on MissingPluginException catch (error) {
      debugPrint('macOS panel toolbar unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint('macOS panel toolbar failed: $error');
    }
  }

  Future<void> _updateNavigation() async {
    try {
      await _channel.invokeMethod<void>('updateNavigation', {
        'canGoBack': widget.canGoBack,
        'canGoForward': widget.canGoForward,
      });
    } on MissingPluginException catch (error) {
      debugPrint('macOS navigation toolbar unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint('macOS navigation toolbar failed: $error');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isNative) return;
    final color = KoiThemeTokens.of(context).chromeBackground;
    final brightness = Theme.of(context).brightness;
    final titleStyle = Theme.of(context).textTheme.titleSmall;
    if (color == _lastColor &&
        brightness == _lastBrightness &&
        titleStyle == _lastTitleStyle) {
      return;
    }
    _lastTitleStyle = titleStyle;
    _lastColor = color;
    _lastBrightness = brightness;
    final generation = ++_generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) {
        unawaited(_apply(color, brightness, generation));
      }
    });
  }

  Future<void> _apply(
    Color color,
    Brightness brightness,
    int generation,
  ) async {
    try {
      final response = await _channel.invokeMethod<Object?>('applyChrome', {
        'color': color.toARGB32(),
        'dark': brightness == Brightness.dark,
        'title': widget.title,
        'titleFontSize': _lastTitleStyle?.fontSize ?? 14,
        'titleFontWeight': _lastTitleStyle?.fontWeight?.value ?? 500,
      });
      if (!mounted || generation != _generation) return;
      final height = switch (response) {
        {'titlebarHeight': final num value} => value.toDouble(),
        final num value => value.toDouble(),
        _ => null,
      };
      if (height == null) return;
      final ready =
          response is Map &&
          response['nativeToolbar'] == true &&
          response['panelToolbar'] == true;
      if (_ready != ready || _titlebarHeight != height) {
        setState(() {
          _titlebarHeight = height;
          _ready = ready;
        });
      }
      if (_ready) {
        await _updatePanels();
        await _updateNavigation();
      }
    } on MissingPluginException catch (error) {
      debugPrint('macOS window chrome unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint('macOS window chrome failed: $error');
    }
  }

  @override
  void dispose() {
    if (_isNative) _channel.setMethodCallHandler(null);
    widget.panels?.removeListener(_schedulePanels);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WorkbenchWindowInfo(
    hasNativeToolbar: _ready,
    title: widget.title,
    panels: widget.panels,
    child: ColoredBox(
      color: KoiThemeTokens.of(context).chromeBackground,
      child: Padding(
        padding: EdgeInsets.only(
          top: math.max(0, _titlebarHeight - MediaQuery.paddingOf(context).top),
        ),
        child: widget.child,
      ),
    ),
  );
}
