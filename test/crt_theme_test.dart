import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pipstats/theme.dart';
import 'package:pipstats/widgets/boot_sequence.dart';
import 'package:pipstats/widgets/crt_overlay.dart';

Widget _wrap(DeviceStatsColors colors, Widget child) => MaterialApp(
  theme: buildDeviceStatsTheme(colors),
  home: Scaffold(body: child),
);

void main() {
  group('CRT is scoped to the Pip-Boy palette', () {
    test('only the pipboy palette enables the CRT treatment', () {
      // highContrast exists for legibility and light would look broken under
      // scanlines; both must stay clean so the palette switcher remains an
      // escape hatch from the CRT.
      expect(DeviceStatsColors.pipboy.crt, isTrue);
      expect(DeviceStatsColors.highContrast.crt, isFalse);
      expect(DeviceStatsColors.light.crt, isFalse);
    });

    testWidgets('overlay paints for pipboy', (tester) async {
      await tester.pumpWidget(
        _wrap(DeviceStatsColors.pipboy, const CrtOverlay(child: Text('x'))),
      );
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('x'), findsOneWidget);
    });

    testWidgets('overlay adds nothing for the light palette', (tester) async {
      await tester.pumpWidget(
        _wrap(DeviceStatsColors.light, const CrtOverlay(child: Text('x'))),
      );
      expect(find.text('x'), findsOneWidget);
      // The child is returned unwrapped: no Stack is introduced.
      expect(
        find.descendant(
          of: find.byType(CrtOverlay),
          matching: find.byType(Stack),
        ),
        findsNothing,
      );
    });

    testWidgets('overlay never intercepts taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          DeviceStatsColors.pipboy,
          CrtOverlay(
            child: GestureDetector(
              onTap: () => taps++,
              child: const SizedBox.expand(child: Text('tap me')),
            ),
          ),
        ),
      );
      await tester.tap(find.text('tap me'));
      expect(taps, 1, reason: 'the decorative layer must be hit-test invisible');
    });
  });

  group('BootSequence', () {
    testWidgets('a tap skips straight to the app', (tester) async {
      var done = 0;
      await tester.pumpWidget(
        _wrap(
          DeviceStatsColors.pipboy,
          BootSequence(onDone: () => done++),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byType(BootSequence));
      expect(done, 1, reason: 'a boot animation must be dismissible');

      // Timers keep firing until dispose; onDone must not fire twice.
      await tester.pump(const Duration(seconds: 3));
      expect(done, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('completes on its own and reports once', (tester) async {
      var done = 0;
      await tester.pumpWidget(
        _wrap(
          DeviceStatsColors.pipboy,
          BootSequence(
            onDone: () => done++,
            lineDelay: const Duration(milliseconds: 1),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(done, 1);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('PipText', () {
    test('every size clears the floor VT323 needs to stay legible', () {
      // VT323 has a small x-height, so anything under ~16 renders like 10px of
      // a normal face — that is what made the old 12-15px rows hard to read.
      for (final size in [
        PipText.note,
        PipText.label,
        PipText.body,
        PipText.value,
        PipText.heading,
        PipText.title,
        PipText.hero,
      ]) {
        expect(size, greaterThanOrEqualTo(16));
      }
      expect(PipText.heading, greaterThan(PipText.body));
      expect(PipText.hero, greaterThan(PipText.heading));
    });
  });
}
