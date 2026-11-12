import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/budget_comparison.dart';
import 'package:pocket_ledger/services/merchant_classification_service.dart';
import 'package:pocket_ledger/services/suggested_budget_service.dart';
import 'package:pocket_ledger/widgets/monthly_budget_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/services/merchant_classification_store.dart';
import 'package:pocket_ledger/widgets/merchant_baseline_panel.dart';

Transaction row(
  String id,
  double amount,
  ExpenseType type, {
  String category = 'Food',
  DateTime? date,
}) => Transaction(
  id: id,
  description: 'Market',
  amount: amount,
  date: date ?? DateTime(2026, 10, 1),
  category: category,
  expenseType: type,
);

void main() {
  testWidgets(
    'Unknown review ranks Unknown amounts and retains transaction overrides on merchant edit',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MerchantClassificationStore('unknown-order');
      await store.save([
        {
          'id': 'm:alpha',
          'kind': 'merchant',
          'name': 'Alpha',
          'aliases': ['Alpha'],
          'category': 'Food',
          'categoryId': 'food',
          'group': 'Essential',
          'expenseType': 'Regular',
        },
        {
          'id': 't:override',
          'kind': 'transaction',
          'transactionId': 'override',
          'expenseType': 'Unknown',
        },
      ]);
      final rows = [
        row('known', 900, ExpenseType.regular).copyWith(description: 'Alpha'),
        row(
          'override',
          100,
          ExpenseType.unknown,
        ).copyWith(description: 'Alpha'),
        row('beta', 200, ExpenseType.unknown).copyWith(description: 'Beta'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MerchantBaselinePanel(
              transactions: rows,
              categories: const [
                ExpenseCategory(
                  id: 'food',
                  parentId: 'food-household',
                  name: 'Food',
                ),
              ],
              legacyMappings: const [],
              store: store,
              currencySymbol: r'$',
              historyComplete: true,
              reviewUnknownInitially: true,
              onSaved: (changes) async {
                await store.save(changes);
                return 'Saved';
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Beta · 1')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha · 2')).dy),
      );
      expect(find.textContaining('Unknown Expense Types (2)'), findsOneWidget);
      final alphaType = find.byKey(const ValueKey('merchant-type-alpha'));
      await tester.ensureVisible(alphaType);
      await tester.tap(alphaType);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Planned Occasional').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(
        store.index.apply(rows.first).expenseType,
        ExpenseType.plannedOccasional,
      );
      expect(store.index.apply(rows[1]).expenseType, ExpenseType.unknown);
      expect(find.text('Alpha · 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('comparison includes unknown and planned but excludes unexpected spending', () {
    for (final data in [
      (110.0, 20.0, 100.0, BudgetOutcome.over),
      (70.0, 20.0, 100.0, BudgetOutcome.within),
      (90.0, 20.0, 100.0, BudgetOutcome.over),
      (100.0, 0.0, 100.0, BudgetOutcome.exact),
      (0.0, 0.0, 0.0, BudgetOutcome.exact),
      (0.01, 0.0, 0.0, BudgetOutcome.over),
      (99.99, 0.02, 100.0, BudgetOutcome.over),
    ]) {
      final amounts = BudgetSpending.fromAmounts(
        total: data.$1 + data.$2 + 500,
        regular: data.$1,
        unexpected: 500,
      );
      expect(amounts.outcome(data.$3), data.$4);
      expect(amounts.minimum, closeTo(data.$1 + data.$2, .000001));
      expect(amounts.maximum, closeTo(data.$1 + data.$2, .000001));
    }
    final amounts = BudgetSpending.fromTransactions([
      row('a', 60, ExpenseType.regular),
      row('b', 50, ExpenseType.plannedOccasional),
      row('c', 300, ExpenseType.unexpectedOccasional),
      row('d', 10, ExpenseType.unknown),
    ]);
    expect(amounts.knownBudget, 110);
    expect(amounts.outcome(100), BudgetOutcome.over);
    expect(
      amounts.total,
      amounts.knownBudget + amounts.unexpected + amounts.unknown,
    );
  });
  test(
    'effective merchant type and explicit override control budget and coverage',
    () {
      final index = MerchantClassificationIndex([
        {
          'id': 'm:market',
          'kind': 'merchant',
          'aliases': ['Market'],
          'expenseType': 'Regular',
        },
        {
          'id': 't:override',
          'kind': 'transaction',
          'transactionId': 'override',
          'expenseType': 'Unexpected Occasional',
        },
      ]);
      final data = BudgetSpending.fromTransactions(
        [
          row('large', 960, ExpenseType.unknown),
          row('override', 20, ExpenseType.unknown),
          row(
            'small',
            20,
            ExpenseType.unknown,
          ).copyWith(description: 'New merchant'),
        ].map(index.apply),
      );
      expect(data.regular, 960);
      expect(data.unexpected, 20);
      expect(data.unknown, 20);
      expect(data.classifiedPercent, 98);
      expect(data.coverageLabel, 'High classification coverage');
    },
  );
  test('refunds transfers duplicates and zero spending stay reconciled', () {
    final data = BudgetSpending.fromTransactions([
      row('a', 100, ExpenseType.regular),
      row('a', 100, ExpenseType.regular),
      row('refund', -20, ExpenseType.regular),
      row('u', 30, ExpenseType.unknown),
      row('ur', -10, ExpenseType.unknown),
      row('transfer', 500, ExpenseType.unknown, category: 'Transfers'),
    ]);
    expect(data.total, 100);
    expect(data.unknown, 20);
    expect(data.classifiedPercent, 80);
    expect(data.minimum, 100);
    expect(data.maximum, 100);
    expect(data.outcome(75), BudgetOutcome.over);
    expect(data.total, data.knownBudget + data.unexpected + data.unknown);
    final empty = BudgetSpending.fromTransactions([]);
    expect(empty.classifiedPercent, 0);
    expect(empty.coverageLabel, 'No spending to classify');
    expect(empty.outcome(0), BudgetOutcome.exact);
  });
  test(
    'historical unknown is excluded from suggestion and coverage is reported',
    () {
      final service = SuggestedBudgetService();
      final regular = [
        for (final month in [7, 8, 9, 10])
          row(
            'known$month',
            100,
            ExpenseType.regular,
            date: DateTime(2026, month, 1),
          ),
      ];
      final base = service.suggest(
        transactions: regular,
        now: DateTime(2026, 11, 10),
      )!;
      final mixed = service.suggest(
        transactions: [...regular, row('unknown', 100, ExpenseType.unknown)],
        now: DateTime(2026, 11, 10),
      )!;
      expect(mixed.amount, base.amount);
      expect(mixed.unknownAmount, 100);
      expect(mixed.historyCoveragePercent, 80);
    },
  );
  for (final scenario in [
    (900.0, 60.0, 40.0, 950.0, 'Over budget'),
    (800.0, 100.0, 100.0, 1100.0, 'Within budget'),
    (800.0, 100.0, 100.0, 950.0, 'Over budget'),
  ]) {
    testWidgets('partial coverage shows ${scenario.$5} on mobile', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MonthlyBudgetCard(
                currentSpent: 1000,
                regularSpent: scenario.$1,
                plannedOccasionalSpent: scenario.$2,
                currencySymbol: r'$',
                monthlyTarget: scenario.$4,
                now: DateTime(2026, 11, 10),
                selectedMonth: DateTime(2026, 10),
                onCalendarPressed: () {},
                onSetTargetPressed: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining(scenario.$5), findsOneWidget);
      expect(find.text('Classification incomplete'), findsNothing);
      expect(
        find.byKey(const ValueKey('monthly-budget-coverage')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
