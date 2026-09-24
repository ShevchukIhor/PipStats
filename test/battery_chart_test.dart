import 'package:flutter_test/flutter_test.dart';

import 'package:pipstats/widgets/battery_chart.dart';

void main() {
  group('BatteryPoint.fromRows', () {
    test('drops rows that cannot be plotted', () {
      // A zero counter is not "empty battery", it is a failed read; plotting
      // it would draw a cliff to the floor that never happened.
      final out = BatteryPoint.fromRows([
        {'ts': 1000, 'counter_uah': 3000000, 'charging': 0},
        {'ts': 0, 'counter_uah': 2900000, 'charging': 0},
        {'ts': 2000, 'counter_uah': 0, 'charging': 0},
        {'ts': 3000, 'counter_uah': 2800000, 'charging': 1},
      ]);
      expect(out, hasLength(2));
      expect(out.first.ts, 1000);
      expect(out.last.charging, isTrue);
    });

    test('survives missing keys instead of throwing', () {
      expect(BatteryPoint.fromRows([{}]), isEmpty);
      expect(BatteryPoint.fromRows([]), isEmpty);
    });

    test('keeps the order it was given', () {
      final out = BatteryPoint.fromRows([
        {'ts': 3, 'counter_uah': 1, 'charging': 0},
        {'ts': 1, 'counter_uah': 2, 'charging': 0},
      ]);
      expect(out.map((p) => p.ts), [3, 1]);
    });
  });
  group('BatteryChart axis scale', () {
    List<BatteryPoint> pts(List<int> counters) => [
      for (var i = 0; i < counters.length; i++)
        BatteryPoint(ts: i * 1000, counterUah: counters[i], charging: false),
    ];

    test('uses the given capacity when it covers the samples', () {
      final c = BatteryChart(points: pts([1000, 900]), capacityUah: 2000);
      expect(c.debugScale, 2000);
    });

    test('falls back to the tallest sample when capacity is too small', () {
      // Passing design capacity for gauge-scale samples drew a full battery
      // at two thirds height; a capacity below the data is always wrong.
      final c = BatteryChart(points: pts([3000, 2900]), capacityUah: 1000);
      expect(c.debugScale, 3000);
    });

    test('handles a missing capacity', () {
      final c = BatteryChart(points: pts([500, 400]), capacityUah: 0);
      expect(c.debugScale, 500);
    });
  });
}
