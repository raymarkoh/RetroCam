import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:retro_cam/main.dart';

void main() {
  testWidgets('RetroCam camera controls render with Material 3', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RetroCamApp());
    await tester.pump();

    expect(find.text('RETROCAM'), findsOneWidget);
    expect(find.bySemanticsLabel('Capture photo'), findsOneWidget);
    expect(find.byTooltip('Switch camera'), findsOneWidget);
    expect(find.byTooltip('Turn flash on'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Warm'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.useMaterial3,
      isTrue,
    );
  });

  testWidgets('RetroCam filter selection updates the active filter', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RetroCamApp());

    await tester.tap(find.text('Mono'));
    await tester.pump();

    final monoChip = tester.widget<ChoiceChip>(find.byType(ChoiceChip).last);
    expect(monoChip.selected, isTrue);
  });
}
