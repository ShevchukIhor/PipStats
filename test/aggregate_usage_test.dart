import 'package:flutter_test/flutter_test.dart';
import 'package:pipstats/stats_db.dart';

void main() {
  group('aggregateUsage - regression test', () {
    Map<String, Object?> ev(String pkg, int type, int ts) => {
      'package': pkg,
      'event_type': type,
      'ts': ts,
    };

    test('ongoing session at the end of events list is currently undercounted', () {
      // Scenario: 
      // - Session 'a' starts at -1000.
      // - Window starts at 0.
      // - NO events in the window.
      // If we provide an observationEnd, it should work.

      final rows = aggregateUsage(
        [],
        openSessions: {'a': -1000},
        windowStart: 0,
        observationEnd: 1000,
      );
      expect(rows, isNotEmpty, reason: 'Should show ongoing session if observationEnd provided');
      final a = rows.firstWhere((r) => r['package'] == 'a');
      expect(a['fg_ms'], 1000);
    });

    test('ongoing session with events is counted up to last event timestamp', () {
       // - Session 'a' starts at -1000.
       // - Event: foreground at 500.
       // - No more events.
        // Expected duration in window [0, 500]: 500 ms (since it's still open and last event was at 500).

        // The real problem is when NO events occur for that package in the window.
       final rows2 = aggregateUsage(
         [ev('b', 0, 1000)], // background for 'b' at 1000
         openSessions: {'a': -1000}, // but 'a' stays open!
         windowStart: 0,
       );
       // For 'a', it should count from 0 to 1000 (the last event timestamp).

       final a = rows2.firstWhere((r) => r['package'] == 'a');
       expect(a['fg_ms'], 1000, reason: 'Should count ongoing session until last event in list');
    });
  });
}
