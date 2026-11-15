import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/monthly_rollover_service.dart';

void main() {
  group('MonthlyBudgetSnapshotStore shared monthly budget', () {
    test('editing from a past month updates every comparison and removes old overrides', () async {
      SharedPreferences.setMockInitialValues({
        'monthly_target': 1000.0,
        'budget_snapshot_2026_10': 1000.0,
        'budget_snapshot_2026_09': 5000.0,
      });
      final store = MonthlyBudgetSnapshotStore();
      await store.saveMonthBudget(
        month: DateTime(2026, 9),
        budget: 5000,
        now: DateTime(2026, 11, 15),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('monthly_target'), 5000);
      expect(
        prefs.getKeys().where((key) => key.startsWith('budget_snapshot_')),
        isEmpty,
      );
      for (final month in [
        DateTime(2026, 11),
        DateTime(2026, 10),
        DateTime(2026, 9),
        DateTime(2020, 1),
      ]) {
        expect(await store.budgetForMonth(month), 5000);
      }
      await store.saveCurrentMonthBudget(
        budget: 7000,
        now: DateTime(2026, 11, 15),
      );
      for (final month in [
        DateTime(2026, 11),
        DateTime(2026, 10),
        DateTime(2026, 9),
      ]) {
        expect(await store.budgetForMonth(month), 7000);
      }
    });

    test('startup and restart use the active budget instead of stale month snapshots', () async {
      SharedPreferences.setMockInitialValues({
        'monthly_target': 5000.0,
        'budget_snapshot_2026_10': 1000.0,
      });
      final store = MonthlyBudgetSnapshotStore();
      expect(
        await store.initialize(currentBudget: 5000, now: DateTime(2026, 11)),
        5000,
      );
      expect(await store.budgetForMonth(DateTime(2026, 10)), 5000);
      await store.saveBudget(budget: 6000);
      final reloaded = MonthlyBudgetSnapshotStore();
      expect(
        await reloaded.initialize(currentBudget: 5000, now: DateTime(2026, 12)),
        6000,
      );
      expect(await reloaded.budgetForMonth(DateTime(2026, 9)), 6000);
      expect((await SharedPreferences.getInstance()).getKeys(), {
        'monthly_target',
      });
    });

    test(
      'old snapshots alone do not resurrect a budget; zero is valid',
      () async {
        SharedPreferences.setMockInitialValues({
          'budget_snapshot_2026_10': 1000.0,
        });
        final store = MonthlyBudgetSnapshotStore();
        expect(await store.initialize(currentBudget: null), isNull);
        expect(await store.budgetForMonth(DateTime(2026, 10)), isNull);
        await store.saveBudget(budget: 0);
        expect(await store.budgetForMonth(DateTime(2026, 10)), 0);
        for (final invalid in [-1.0, double.nan, double.infinity]) {
          await expectLater(
            store.saveBudget(budget: invalid),
            throwsArgumentError,
          );
        }
        expect(await store.budgetForMonth(DateTime(2026, 10)), 0);
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
