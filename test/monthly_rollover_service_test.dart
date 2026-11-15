import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/monthly_rollover_service.dart';

void main() {
  group('MonthlyBudgetSnapshotStore', () {
    test(
      'editing a past month preserves the active and other historical budgets',
      () async {
        SharedPreferences.setMockInitialValues({
          'monthly_target': 6000.0,
          'budget_snapshot_2026_10': 5000.0,
        });
        final store = MonthlyBudgetSnapshotStore();
        await store.saveMonthBudget(
          month: DateTime(2026, 9),
          budget: 4500,
          now: DateTime(2026, 11, 15),
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getDouble('monthly_target'), 6000);
        expect(prefs.getDouble('budget_snapshot_2026_10'), 5000);
        expect(prefs.getDouble('budget_snapshot_2026_09'), 4500);
        await store.saveMonthBudget(
          month: DateTime(2026, 11),
          budget: 7000,
          now: DateTime(2026, 11, 15),
        );
        expect(prefs.getDouble('monthly_target'), 7000);
        expect(await store.budgetForMonth(DateTime(2026, 9)), 4500);
      },
    );
    test(
      'keeps the previous month budget when the active budget changes',
      () async {
        SharedPreferences.setMockInitialValues({'monthly_target': 5000});
        final store = MonthlyBudgetSnapshotStore();

        final previousBudget = await store.initialize(
          currentBudget: 5000,
          now: DateTime(2025, 11, 1),
        );
        await store.saveCurrentMonthBudget(
          budget: 6000,
          now: DateTime(2025, 11, 1),
        );

        final preferences = await SharedPreferences.getInstance();
        expect(previousBudget, 5000);
        expect(preferences.getDouble('budget_snapshot_2025_10'), 5000);
        expect(preferences.getDouble('budget_snapshot_2025_11'), 6000);
        expect(preferences.getDouble('monthly_target'), 6000);

        final recap = MonthlyRolloverRecap.calculate(
          transactions: [
            Transaction(
              date: DateTime(2025, 10, 15),
              amount: 4900,
              category: 'Housing / Bills',
              expenseType: ExpenseType.regular,
            ),
          ],
          monthlyBudget: previousBudget,
          now: DateTime(2025, 11, 1),
        );

        expect(recap, isNotNull);
        expect(recap!.difference, 100);
      },
    );

    test(
      'uses the legacy active budget to initialize a missing snapshot',
      () async {
        SharedPreferences.setMockInitialValues({'monthly_target': 5000});

        final previousBudget = await MonthlyBudgetSnapshotStore().initialize(
          currentBudget: 5000,
          now: DateTime(2025, 11, 1),
        );

        expect(previousBudget, 5000);
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getDouble('budget_snapshot_2025_10'), 5000);
      },
    );
  });

  group('MonthlyRolloverRecap', () {
    final now = DateTime(2025, 3, 1);

    test('calculates amount under budget for the previous calendar month', () {
      final recap = MonthlyRolloverRecap.calculate(
        transactions: [
          Transaction(
            date: DateTime(2025, 2, 1),
            amount: 40,
            category: 'Food / Household',
            expenseType: ExpenseType.regular,
          ),
          Transaction(
            date: DateTime(2025, 2, 28, 23, 59),
            amount: 35,
            category: 'Transport',
            expenseType: ExpenseType.regular,
          ),
          Transaction(
            date: DateTime(2025, 1, 31),
            amount: 200,
            category: 'Housing / Bills',
            expenseType: ExpenseType.regular,
          ),
        ],
        monthlyBudget: 100,
        now: now,
      );

      expect(recap, isNotNull);
      expect(recap!.previousMonthSpend, 75);
      expect(recap.stayedUnderBudget, isTrue);
      expect(recap.difference, 25);
    });

    test(
      'calculates over-budget amount when previous spend exceeds budget',
      () {
        final recap = MonthlyRolloverRecap.calculate(
          transactions: [
            Transaction(
              date: DateTime(2025, 2, 15),
              amount: 125,
              category: 'Housing / Bills',
              expenseType: ExpenseType.regular,
            ),
          ],
          monthlyBudget: 100,
          now: now,
        );

        expect(recap, isNotNull);
        expect(recap!.stayedUnderBudget, isFalse);
        expect(recap.difference, 25);
      },
    );

    test('hides recap after the first expense of the current month', () {
      final recap = MonthlyRolloverRecap.calculate(
        transactions: [
          Transaction(
            date: DateTime(2025, 2, 15),
            amount: 75,
            category: 'Food / Household',
            expenseType: ExpenseType.regular,
          ),
          Transaction(
            date: DateTime(2025, 3, 1),
            amount: 10,
            category: 'Transport',
            expenseType: ExpenseType.regular,
          ),
        ],
        monthlyBudget: 100,
        now: now,
      );

      expect(recap, isNull);
    });

    test('does not show a recap without a usable budget', () {
      expect(
        MonthlyRolloverRecap.calculate(
          transactions: const [],
          monthlyBudget: null,
          now: now,
        ),
        isNull,
      );
      expect(
        MonthlyRolloverRecap.calculate(
          transactions: const [],
          monthlyBudget: 0,
          now: now,
        ),
        isNull,
      );
    });
  });
}
