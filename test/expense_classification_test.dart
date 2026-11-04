
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/local_transaction_store.dart';
import 'package:pocket_ledger/services/monthly_rollover_service.dart';
import 'package:pocket_ledger/services/spending_insights_service.dart';
import 'package:pocket_ledger/utils/transaction_period_format.dart';
import 'package:pocket_ledger/widgets/monthly_budget_card.dart';
import 'package:pocket_ledger/widgets/spending_summary_widget.dart';

void main() {
  test('legacy negative sheet amounts are parsed as positive expenses', () {
    final transactions = [
      Transaction.tryParseSheetRow([
        '2026-10-29',
        '-12.50',
        'Food / Household',
        'Groceries',
      ])!,
      Transaction.tryParseSheetRow(['2026-10-15', -25, 'Transport', 'Fuel'])!,
      Transaction.tryParseSheetRow([
        '2026-02-01',
        '-40',
        'Housing / Bills',
        'Utility',
      ])!,
    ];

    expect(transactions.map((transaction) => transaction.amount), [
      12.5,
      25,
      40,
    ]);
    expect(
      Transaction.fromJson({'date': '2026-10-29', 'amount': -12.5}).amount,
      12.5,
    );
    expect(
      transactions
          .where((transaction) => transaction.date.day == 29)
          .fold<double>(0, (total, transaction) => total + transaction.amount),
      12.5,
    );
    expect(
      transactions
          .where((transaction) => transaction.date.month == 10)
          .fold<double>(0, (total, transaction) => total + transaction.amount),
      37.5,
    );
    expect(
      transactions
          .where((transaction) => transaction.date.year == 2026)
          .fold<double>(0, (total, transaction) => total + transaction.amount),
      77.5,
    );
  });

  test('today expense count uses calendar dates and updates with the list', () {
    final today = DateTime(2026, 10, 28, 12);
    final transactions = [
      Transaction(
        date: DateTime(2026, 10, 28, 8),
        amount: 10,
        category: 'Food / Household',
      ),
      Transaction(
        date: DateTime(2026, 10, 28, 21),
        amount: 20,
        category: 'Transport',
        expenseType: ExpenseType.unexpectedOccasional,
      ),
      Transaction(
        date: DateTime(2026, 10, 27, 23, 59),
        amount: 30,
        category: 'Housing / Bills',
      ),
    ];

    expect(countTransactionsOnDate(transactions, today), 2);
    expect(formatExpenseCount(1), '1 expense recorded');
    expect(formatExpenseCount(3), '3 expenses recorded');
    expect(formatExpenseCount(0), 'No expenses recorded today');
    expect(countTransactionsOnDate(transactions.skip(1), today), 1);
  });

  test(
    'local transaction outbox survives reload and replaces an edited item',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalTransactionStore();
      final transaction = Transaction(
        date: DateTime(2025, 6, 3),
        amount: 25,
        category: 'Food / Household',
        id: 'offline-1',
      );
      await store.upsertPending(transaction);
      await store.upsertPending(transaction.copyWith(amount: 30));

      final pending = await store.loadPending();
      expect(pending, hasLength(1));
      expect(pending.single.id, 'offline-1');
      expect(pending.single.amount, 30);
    },
  );

  group('Transaction expense classification', () {
    test('legacy sheet rows default to regular and retain their fields', () {
      final transaction = Transaction.tryParseSheetRow([
        '2025-06-03T08:30:00',
        '42.50',
        'Food / Household',
        'Groceries',
      ]);

      expect(transaction, isNotNull);
      expect(transaction!.expenseType, ExpenseType.regular);
      expect(transaction.category, 'Food / Household');
      expect(transaction.amount, 42.5);
      expect(transaction.id, isNull);
    });

    test('reads occasional type and stable ID from optional sheet columns', () {
      final transaction = Transaction.tryParseSheetRow([
        '2025-06-03T08:30:00',
        '8000',
        'Housing / Bills',
        'Planned repair',
        'Planned Occasional',
        'stable-entry-1',
      ]);

      expect(transaction, isNotNull);
      expect(transaction!.expenseType, ExpenseType.plannedOccasional);
      expect(transaction.id, 'stable-entry-1');
    });

    test('parses Google Sheets formatted timestamps for legacy rows', () {
      final transaction = Transaction.tryParseSheetRow([
        '6/3/2025 8:30:00 PM',
        '10',
        'Transport',
      ]);

      expect(transaction?.date, DateTime(2025, 6, 3, 20, 30));
      expect(transaction?.expenseType, ExpenseType.regular);
    });

    test('serializes dates without time and parses legacy datetime JSON', () {
      final transaction = Transaction(
        date: DateTime(2026, 10, 29, 17, 47, 19),
        amount: 12.5,
        category: 'Food / Household',
      );

      expect(transaction.toJson()['date'], '2026-10-29');

      final legacyTransaction = Transaction.fromJson({
        ...transaction.toJson(),
        'date': '2026-10-29T17:47:19.000',
      });
      expect(legacyTransaction.date, DateTime(2026, 10, 29, 17, 47, 19));
    });

    test('parses comma-grouped amounts from formatted sheet rows', () {
      final transaction = Transaction.tryParseSheetRow([
        '2025-06-03T08:30:00',
        '1,234.50',
        'Housing / Bills',
      ]);

      expect(transaction?.amount, 1234.5);
    });
  });

  test('averages report actual and regular spending separately', () {
    final average = SpendingAverageData.calculate(
      transactions: [
        Transaction(
          date: DateTime(2025, 1, 1),
          amount: 4500,
          category: 'Housing / Bills',
        ),
        Transaction(
          date: DateTime(2025, 1, 2),
          amount: 9500,
          category: 'Health & Wellness',
          expenseType: ExpenseType.plannedOccasional,
        ),
        Transaction(
          date: DateTime(2025, 2, 1),
          amount: 4500,
          category: 'Housing / Bills',
        ),
        Transaction(
          date: DateTime(2025, 2, 2),
          amount: 1500,
          category: 'Health & Wellness',
          expenseType: ExpenseType.unexpectedOccasional,
        ),
        Transaction(
          date: DateTime(2025, 3, 10),
          amount: 4500,
          category: 'Housing / Bills',
        ),
        Transaction(
          date: DateTime(2025, 3, 11),
          amount: 9500,
          category: 'Health & Wellness',
          expenseType: ExpenseType.plannedOccasional,
        ),
      ],
      frequency: SummaryFrequency.monthly,
      now: DateTime(2025, 3, 15),
    );

    expect(average.currentSpend, 14000);
    expect(average.regularCurrentSpend, 4500);
    expect(average.average, 10000);
    expect(average.regularAverage, 4500);
  });

  test('spike insight separates occasional outflows from regular spending', () {
    final insight = SpendingInsightsService().getSpendingInsight(
      history: [
        Transaction(
          date: DateTime(2025, 6, 1),
          amount: 100,
          category: 'Health & Wellness',
        ),
        Transaction(
          date: DateTime(2025, 7, 1),
          amount: 100,
          category: 'Health & Wellness',
        ),
      ],
      category: 'Health & Wellness',
      currentSpend: 100,
      currentActualSpend: 500,
      currentPlannedOccasionalSpend: 400,
      now: DateTime(2025, 8, 15),
    );

    expect(
      insight,
      contains('regular spending is near its historical average'),
    );
    expect(insight, contains('Occasional outflows account for 400.00'));
  });

  test('rollover budget comparison excludes occasional expenses', () {
    final recap = MonthlyRolloverRecap.calculate(
      transactions: [
        Transaction(
          date: DateTime(2025, 5, 10),
          amount: 4500,
          category: 'Housing / Bills',
        ),
        Transaction(
          date: DateTime(2025, 5, 11),
          amount: 8000,
          category: 'Health & Wellness',
          expenseType: ExpenseType.plannedOccasional,
        ),
        Transaction(
          date: DateTime(2025, 5, 12),
          amount: 1500,
          category: 'Transport',
          expenseType: ExpenseType.unexpectedOccasional,
        ),
      ],
      monthlyBudget: 6000,
      now: DateTime(2025, 6, 1),
    );

    expect(recap, isNotNull);
    expect(recap!.previousMonthSpend, 14000);
    expect(recap.regularSpend, 4500);
    expect(recap.difference, 1500);
    expect(recap.stayedUnderBudget, isTrue);
    expect(recap.previousMonthPlannedOccasionalSpend, 8000);
    expect(recap.previousMonthUnexpectedOccasionalSpend, 1500);
  });

  testWidgets(
    'monthly dashboard keeps actual spend and regular budget separate',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MonthlyBudgetCard(
              currentSpent: 14000,
              regularSpent: 4500,
              plannedOccasionalSpent: 8000,
              unexpectedOccasionalSpent: 1500,
              currencySymbol: r'$',
              monthlyTarget: 6000,
              now: DateTime(2025, 3, 15),
              onCalendarPressed: () {},
              onSetTargetPressed: () {},
            ),
          ),
        ),
      );

      expect(find.text(r'$14,000'), findsOneWidget);
      expect(find.textContaining(r'Regular $4,500'), findsOneWidget);
      expect(find.textContaining(r'Planned $8,000'), findsOneWidget);
      expect(find.textContaining(r'Unexpected $1,500'), findsOneWidget);
      expect(find.text('17 (including today)'), findsOneWidget);
      expect(find.text('\$88.24'), findsOneWidget);
      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.value, 0.75);
    },
  );
}
