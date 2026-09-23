import 'dart:async';

import 'package:flutter/material.dart';

import 'package:pipstats/theme.dart';

/// RobCo-style boot screen shown once on a cold start.
///
/// Lines type out one after another, then the widget calls [onDone]. A tap
/// anywhere skips straight to the end — a startup animation that cannot be
/// dismissed is an obstacle, not atmosphere.
class BootSequence extends StatefulWidget {
  final VoidCallback onDone;

  /// Delay between lines. Exposed so tests can run it without waiting.
  final Duration lineDelay;

  const BootSequence({
    super.key,
    required this.onDone,
    this.lineDelay = const Duration(milliseconds: 180),
  });

  @override
  State<BootSequence> createState() => _BootSequenceState();
}

class _BootSequenceState extends State<BootSequence> {
  static const List<String> _lines = [
    '*** ROBCO INDUSTRIES (TM) TERMLINK ***',
    'PIP-BOY 3000 MK IV',
    '',
    'INITIALIZING SUBSYSTEMS...',
    '> USAGE MONITOR      [ OK ]',
    '> BATTERY TELEMETRY  [ OK ]',
    '> SEED VAULT LINK    [ OK ]',
    '',
    'READY.',
  ];

  int _visible = 0;
  Timer? _timer;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.lineDelay, (t) {
      if (!mounted) return;
      if (_visible >= _lines.length) {
        _finish();
      } else {
        setState(() => _visible++);
      }
    });
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      // Material ancestor: without one, Flutter renders Text with its debug
      // underline decoration, which showed up as a rule under every boot line.
      child: Material(
        color: ds.bg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _visible && i < _lines.length; i++)
                  Text(
                    _lines[i],
                    style: TextStyle(
                      color: ds.primary,
                      fontSize: PipText.body,
                      height: 1.4,
                    ),
                  ),
                if (_visible <= _lines.length) _Cursor(color: ds.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Blinking block cursor.
class _Cursor extends StatefulWidget {
  final Color color;

  const _Cursor({required this.color});

  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Opacity(
        opacity: _controller.value < 0.5 ? 1 : 0,
        child: Container(
          width: 12,
          height: PipText.body,
          color: widget.color,
        ),
      ),
    );
  }
}
