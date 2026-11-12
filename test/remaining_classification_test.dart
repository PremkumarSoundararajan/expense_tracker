import 'support/baseline_navigation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/merchant_classification_store.dart';
import 'package:pocket_ledger/services/suggested_budget_service.dart';
import 'package:pocket_ledger/widgets/merchant_baseline_panel.dart';
import 'package:pocket_ledger/widgets/monthly_budget_card.dart';
import 'package:pocket_ledger/widgets/monthly_budget_target_dialog.dart';
import 'package:pocket_ledger/widgets/suggested_budget_sheet.dart';

Transaction expense(
  String name,
  double amount, {
  bool complete = false,
  String? id,
}) => Transaction(
  id: id ?? name,
  date: DateTime(2026, 10, 5),
  amount: amount,
  description: name,
  category: 'Food',
  categoryId: 'food',
  baselineGroup: complete ? 'Essential' : null,
  expenseType: complete ? ExpenseType.regular : ExpenseType.unknown,
);

const suggestion = SuggestedBudget(
  amount: 100,
  completedMonths: 2,
  recurringTotal: 50,
  miscAverage: 40,
  buffer: 10,
  recurringItems: [],
  miscItems: [],
  unknownCount: 2,
  unknownAmount: 200,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> panel(
    WidgetTester tester, {
    bool direct = false,
    List<Transaction>? rows,
  }) async {
    // Keep queue membership checks independent of mobile list virtualization.
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MerchantBaselinePanel(
            showRemainingInitially: direct,
            transactions:
                rows ??
                [
                  expense('Alpha', 800, complete: true),
                  expense('Beta', 150),
                  expense('Gamma', 50),
                ],
            categories: const [
              ExpenseCategory(
                id: 'food',
                parentId: 'food-household',
                name: 'Food',
              ),
            ],
            legacyMappings: const [],
            store: MerchantClassificationStore('queue'),
            currencySymbol: r'$',
            historyComplete: true,
            onSaved: (_) async => 'Saved',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    '80 percent is an optional stopping point; remaining and classified are separate',
    (tester) async {
      await panel(tester);
      expect(find.text('80.0% of spending'), findsOneWidget);
      expect(find.byKey(const ValueKey('baseline-classified')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('baseline-unclassified')),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Merchant'), findsNothing);
      expect(find.text('20.0% of spending'), findsOneWidget);
      expect(find.text('80.0% of spending'), findsOneWidget);
      expect(find.text('0 unsaved classifications'), findsNothing);
      expect(find.textContaining('You can stop here'), findsOneWidget);
      expect(find.byTooltip('View transactions'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('baseline-unclassified')));
      await tester.pumpAndSettle();
      expect(find.text('Beta · 1'), findsOneWidget);
      expect(find.text('Gamma · 1'), findsOneWidget);
      expect(find.text('Alpha · 1'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Beta · 1')).dy,
        lessThan(tester.getTopLeft(find.text('Gamma · 1')).dy),
      );
      await tester.tap(find.byKey(const ValueKey('baseline-classified')));
      await tester.pumpAndSettle();
      await openClassifiedTable(tester);
      expect(find.text('Alpha · 1'), findsOneWidget);
      expect(find.text('Beta · 1'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('budget entry bypasses the 80 percent stopping point', (
    tester,
  ) async {
    await panel(tester, direct: true);
    expect(find.text('Beta · 1'), findsOneWidget);
    expect(find.text('Gamma · 1'), findsOneWidget);
    expect(find.text('Alpha · 1'), findsNothing);
    expect(find.textContaining('You can stop here'), findsNothing);
  });

  testWidgets(
    'a merchant stays unfinished if any transaction lacks any one field',
    (tester) async {
      await panel(
        tester,
        direct: true,
        rows: [
          expense('Alpha', 800, complete: true),
          expense('Alpha', 1, id: 'second'),
          expense(
            'Beta',
            100,
            complete: true,
          ).copyWith(baselineGroup: 'Unclassified'),
          expense(
            'Gamma',
            50,
            complete: true,
          ).copyWith(category: 'Unknown', categoryId: ''),
        ],
      );
      expect(find.text('Alpha · 2'), findsOneWidget);
      expect(find.text('Beta · 1'), findsOneWidget);
      expect(find.text('Gamma · 1'), findsOneWidget);
    },
  );

  for (final surface in ['monthly', 'target', 'suggestion']) {
    testWidgets('$surface warning offers classification navigation', (
      tester,
    ) async {
      var opened = false;
      void review() => opened = true;
      final child = switch (surface) {
        'monthly' => SingleChildScrollView(
          child: MonthlyBudgetCard(
            currentSpent: 200,
            regularSpent: 0,
            currencySymbol: r'$',
            monthlyTarget: 500,
            onCalendarPressed: () {},
            onSetTargetPressed: () {},
            onReviewUnclassified: review,
          ),
        ),
        'target' => MonthlyBudgetTargetDialog(
          currencySymbol: r'$',
          initialTarget: 500,
          unknownCount: 2,
          onReviewUnclassified: review,
        ),
        _ => SuggestedBudgetBreakdown(
          suggestion: suggestion,
          currencySymbol: r'$',
          onReviewUnclassified: review,
        ),
      };
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
      await tester.pumpAndSettle();
      final reviewLink = surface == 'monthly'
          ? find.textContaining('unclassified · Review')
          : find.text('Classify remaining expenses');
      await tester.ensureVisible(reviewLink);
      await tester.tap(reviewLink);
      expect(opened, true);
      expect(tester.takeException(), isNull);
    });
  }
}
