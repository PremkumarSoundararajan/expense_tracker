import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/services/suggested_budget_service.dart';
import 'package:pocket_ledger/widgets/suggested_budget_sheet.dart';

SuggestedBudget suggestion({int months = 10, double? coverage = 96.2}) =>
    SuggestedBudget(
      amount: 2327.13,
      completedMonths: months,
      recurringTotal: 2036.34,
      miscAverage: 79.23,
      buffer: 211.56,
      recurringItems: const [],
      miscItems: const [],
      unknownCount: 12,
      unknownAmount: 756.69,
      historyCoveragePercent: coverage,
    );

void main() {
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets(
      'compact budget shows actual lookback and retains review/apply at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var reviews = 0;
        double? applied;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    applied = await showSuggestedBudgetSheet(
                      context: context,
                      suggestion: suggestion(),
                      currencySymbol: r'$',
                      onReviewUnclassified: () => reviews++,
                    );
                  },
                  child: const Text('Open budget'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open budget'));
        await tester.pumpAndSettle();
        expect(
          find.text('Based on 6 months · 96.2% of spending classified.'),
          findsOneWidget,
        );
        expect(find.textContaining('Historical Expense Types:'), findsNothing);
        expect(find.text('Buffer (10%)'), findsOneWidget);
        await tester.tap(find.text('Classify remaining expenses'));
        await tester.pumpAndSettle();
        expect(reviews, 1);
        await tester.tap(find.text('Use this budget'));
        await tester.pumpAndSettle();
        expect(applied, 2327.13);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'short history and unavailable coverage use accurate compact text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SuggestedBudgetBreakdown(
              suggestion: suggestion(months: 2, coverage: null),
              currencySymbol: r'$',
              allowApply: false,
            ),
          ),
        ),
      );
      expect(
        find.text('Based on 2 months of regular spending.'),
        findsOneWidget,
      );
      expect(find.textContaining('null%'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
