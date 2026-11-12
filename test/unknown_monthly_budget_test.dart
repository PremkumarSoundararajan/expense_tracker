import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/monthly_rollover_service.dart';
import 'package:pocket_ledger/widgets/monthly_budget_card.dart';

void main() {
  test('Unknown historical spending counts against the budget without false savings', () {
    final rows = [
      Transaction(
        date: DateTime(2026, 10, 15),
        amount: 7508,
        category: 'Food',
        expenseType: ExpenseType.unknown,
      ),
    ];
    final unknownRecap = MonthlyRolloverRecap.calculate(transactions: rows, monthlyBudget: 5000, now: DateTime(2026, 11, 9))!;
    expect(unknownRecap.stayedUnderBudget, false);
    expect(unknownRecap.difference, 2508);
    final classified = rows
        .map((t) => t.copyWith(expenseType: ExpenseType.regular))
        .toList();
    final recap = MonthlyRolloverRecap.calculate(
      transactions: classified,
      monthlyBudget: 5000,
      now: DateTime(2026, 11, 9),
    )!;
    expect(recap.stayedUnderBudget, isFalse);
    expect(recap.difference, 2508);
  });
  test('empty history does not establish a completed-month savings result', () {
    expect(
      MonthlyRolloverRecap.calculate(
        transactions: [],
        monthlyBudget: 5000,
        now: DateTime(2026, 11, 9),
      ),
      isNull,
    );
  });
  for (final current in [true, false]) {
    testWidgets(
      'Unknown spending makes ${current ? 'current' : 'past'} comparison includes unclassified expenses',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MonthlyBudgetCard(
                  currentSpent: 7508,
                  regularSpent: 0,
                  currencySymbol: r'$',
                  monthlyTarget: 5000,
                  now: DateTime(2026, 11, 9),
                  selectedMonth: DateTime(2026, current ? 11 : 10),
                  onCalendarPressed: () {},
                  onSetTargetPressed: () {},
                ),
              ),
            ),
          ),
        );
        expect(find.textContaining(r'Over budget by $2,508'), findsOneWidget);
        expect(find.textContaining(r'$7,508 unclassified'), findsOneWidget);
        expect(find.textContaining('Under budget by'), findsNothing);
        expect(
          find.byKey(const ValueKey('daily-allowance-pill')),
          current ? findsOneWidget : findsNothing,
        );
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      },
    );
  }
  testWidgets('classified past spending compares against recorded budget', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MonthlyBudgetCard(
              currentSpent: 7508,
              regularSpent: 7508,
              currencySymbol: r'$',
              monthlyTarget: 5000,
              now: DateTime(2026, 11, 9),
              selectedMonth: DateTime(2026, 10),
              onCalendarPressed: () {},
              onSetTargetPressed: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining(r'Over budget by $2,508'), findsOneWidget);
    expect(find.text('Classification incomplete'), findsNothing);
  });
}
