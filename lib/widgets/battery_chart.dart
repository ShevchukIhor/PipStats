import 'package:flutter/material.dart';

import 'package:pipstats/theme.dart';

/// One point on the battery chart.
class BatteryPoint {
  /// Milliseconds since epoch.
  final int ts;

  /// Charge in µAh at that moment.
  final int counterUah;

  /// Whether the phone was on charger.
  final bool charging;

  const BatteryPoint({
    required this.ts,
    required this.counterUah,
    required this.charging,
  });

  /// Builds points from `battery_samples` rows, dropping unusable ones.
  static List<BatteryPoint> fromRows(List<Map<String, Object?>> rows) {
    final out = <BatteryPoint>[];
    for (final r in rows) {
      final ts = r['ts'] as int? ?? 0;
      final counter = r['counter_uah'] as int? ?? 0;
      if (ts <= 0 || counter <= 0) continue;
      out.add(
        BatteryPoint(
          ts: ts,
          counterUah: counter,
          charging: (r['charging'] as int? ?? 0) == 1,
        ),
      );
    }
    return out;
  }
}

/// A discharge curve drawn from the recorded battery samples.
///
/// Charging stretches are drawn in the battery accent so a refill is not
/// mistaken for a flat period of low use; discharge is drawn in the primary
/// colour. Nothing is interpolated — each point is a real sample — because the
/// gaps themselves are informative: a long straight segment means the app was
/// not running to sample.
class BatteryChart extends StatelessWidget {
  final List<BatteryPoint> points;

  /// Capacity to scale the vertical axis against, µAh.
  ///
  /// Must be on the **same scale as the samples**, i.e. the fuel gauge's own
  /// full-charge value — not the design capacity. Passing design here plotted
  /// a full battery at 65% of the axis, because this gauge reports 2946 mAh
  /// full against a declared 4500 mAh. When it is unavailable the chart
  /// normalises against the highest sample it holds instead.
  final int capacityUah;

  const BatteryChart({
    super.key,
    required this.points,
    required this.capacityUah,
  });

  /// The denominator actually used for the vertical axis.
  @visibleForTesting
  int get debugScale => _scale;

  /// Whether the samples actually vary.
  ///
  /// A phone left on the charger produces a perfectly straight line, which
  /// looks like a broken chart rather than the "nothing happened" it means.
  /// Callers use this to show a one-line note instead of drawing it.
  bool get hasVariation {
    if (points.length < 2) return false;
    var lo = points.first.counterUah;
    var hi = lo;
    for (final p in points) {
      if (p.counterUah < lo) lo = p.counterUah;
      if (p.counterUah > hi) hi = p.counterUah;
    }
    final scale = _scale;
    if (scale <= 0) return false;
    // Half a percent of the axis: below that the line is visually flat anyway.
    return (hi - lo) / scale > 0.005;
  }

  int get _scale {
    var maxSeen = 0;
    for (final p in points) {
      if (p.counterUah > maxSeen) maxSeen = p.counterUah;
    }
    if (capacityUah >= maxSeen && capacityUah > 0) return capacityUah;
    return maxSeen;
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return SizedBox(
      height: 140,
      child: CustomPaint(
        painter: _ChartPainter(
          points: points,
          capacityUah: _scale,
          line: ds.primary,
          chargingLine: ds.battery,
          grid: ds.dark,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<BatteryPoint> points;
  final int capacityUah;
  final Color line;
  final Color chargingLine;
  final Color grid;

  const _ChartPainter({
    required this.points,
    required this.capacityUah,
    required this.line,
    required this.chargingLine,
    required this.grid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (points.length < 2 || capacityUah <= 0) return;

    final firstTs = points.first.ts;
    final spanMs = points.last.ts - firstTs;
    if (spanMs <= 0) return;

    Offset at(BatteryPoint p) {
      final x = size.width * (p.ts - firstTs) / spanMs;
      final frac = (p.counterUah / capacityUah).clamp(0.0, 1.0);
      return Offset(x, size.height * (1 - frac));
    }

    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final paint = Paint()
        ..color = (a.charging || b.charging) ? chargingLine : line
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(at(a), at(b), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.points != points ||
      old.capacityUah != capacityUah ||
      old.line != line;
}
