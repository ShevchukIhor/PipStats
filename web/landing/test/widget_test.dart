// This is a basic Flutter widget test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pipstats_landing/main.dart';

void main() {
  testWidgets('Landing page loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PipStatsLandingApp());

    // Verify that the hero section loads
    expect(find.text('PIPSTATS'), findsOneWidget);
    expect(find.text('LOCAL DEVICE STATISTICS'), findsOneWidget);
  });
}