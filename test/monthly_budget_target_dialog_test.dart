import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/widgets/monthly_budget_target_dialog.dart';
import 'package:pocket_ledger/services/suggested_budget_service.dart';

void main() {
  const suggestion = SuggestedBudget(
    amount: 2813.51,
    completedMonths: 6,
    recurringTotal: 2500,
    miscAverage: 100,
    buffer: 213.51,
    recurringItems: [],
    miscItems: [],
  );
  for (final width in [320.0, 390.0, 1200.0]) {
    for (final dark in [false, true]) {
      testWidgets('target dialog matches grouped layout at $width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        double? saved;
        var reviewed = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    saved = await showDialog<double>(
                      context: context,
                      builder: (_) => MonthlyBudgetTargetDialog(
                        currencySymbol: r'$',
                        initialTarget: 7092.95,
                        unknownCount: 158,
                        suggestion: suggestion,
                        onReviewUnclassified: () => reviewed = true,
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '7,092.95',
        );
        expect(
          tester.widget<Text>(find.text('Set Monthly Target')).textAlign,
          TextAlign.center,
        );
        expect(
          find.byKey(const ValueKey('budget-classification-note')),
          findsOneWidget,
        );
        final panel = find.byKey(const ValueKey('suggested-budget-panel'));
        expect(
          find.descendant(
            of: panel,
            matching: find.text(r'Suggested: $2,813.51'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: panel,
            matching: find.text('Use suggested amount'),
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Classify remaining expenses'));
        await tester.tap(find.text('Classify remaining expenses'));
        expect(reviewed, isTrue);
        await tester.ensureVisible(find.text('Use suggested amount'));
        await tester.tap(find.text('Use suggested amount'));
        await tester.pumpAndSettle();
        expect(saved, isNull);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '2,813.51',
        );
        await tester.tap(find.text('Save Target'));
        await tester.pumpAndSettle();
        expect(saved, 2813.51);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('validates input and returns a saved target', (tester) async {
    double? savedTarget;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                savedTarget = await showDialog<double>(
                  context: context,
                  builder: (_) => const MonthlyBudgetTargetDialog(
                    currencySymbol: '\$',
                    initialTarget: null,
                  ),
                );
              },
              child: const Text('Open target dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open target dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Target'));
    await tester.pump();
    expect(find.text('Enter a target greater than zero.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '12,50');
    await tester.tap(find.text('Save Target'));
    await tester.pump();
    expect(find.text('Enter a target greater than zero.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '250');
    await tester.tap(find.text('Save Target'));
    await tester.pumpAndSettle();

    expect(savedTarget, 250);
    expect(tester.takeException(), isNull);
  });
}
