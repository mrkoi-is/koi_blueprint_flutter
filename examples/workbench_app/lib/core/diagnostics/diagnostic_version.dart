import 'package:flutter/material.dart';

/// The host owns navigation; this widget owns only the tap sequence.
class DiagnosticVersion extends StatefulWidget {
  const DiagnosticVersion({super.key, required this.version, this.onUnlocked});
  final String version;
  final VoidCallback? onUnlocked;
  @override
  State<DiagnosticVersion> createState() => _DiagnosticVersionState();
}

class _DiagnosticVersionState extends State<DiagnosticVersion> {
  DateTime? _lastTap;
  int _count = 0;
  void _tap() {
    final now = DateTime.now();
    if (_lastTap == null ||
        now.difference(_lastTap!) > const Duration(seconds: 3)) {
      _count = 0;
    }
    _lastTap = now;
    if (++_count == 7) {
      _count = 0;
      widget.onUnlocked?.call();
    }
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: widget.onUnlocked == null ? null : _tap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(widget.version),
    ),
  );
}
