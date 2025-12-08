// Widget test untuk Smart Trash Monitor App

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aplikasi_iot/main.dart';

void main() {
  testWidgets('Smart Trash Monitor loads correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SmartTrashApp());

    // Verify that the app title is displayed
    expect(find.text('Smart Trash Monitor'), findsOneWidget);

    // Verify that we can find trash bin cards
    expect(find.text('BIN-001'), findsOneWidget);
    
    // Verify that statistics section exists
    expect(find.text('📈 Today\'s Statistics'), findsOneWidget);
    
    // Verify that status overview exists
    expect(find.text('Total Bins'), findsOneWidget);
    expect(find.text('Need Emptying'), findsOneWidget);
  });

  testWidgets('Refresh button works', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartTrashApp());

    // Find and tap the refresh button
    final refreshButton = find.byIcon(Icons.refresh);
    expect(refreshButton, findsOneWidget);
    
    await tester.tap(refreshButton);
    await tester.pump();
    
    // Verify snackbar appears
    expect(find.text('✓ Data refreshed successfully'), findsOneWidget);
  });

  testWidgets('Alert banner can be closed', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartTrashApp());
    await tester.pumpAndSettle();

    // Check if alert banner exists (depends on data)
    final alertBanner = find.text('⚠️ Attention Required!');
    
    if (alertBanner.evaluate().isNotEmpty) {
      // Find and tap close button
      final closeButton = find.byIcon(Icons.close);
      await tester.tap(closeButton.first);
      await tester.pumpAndSettle();
    }
  });
}