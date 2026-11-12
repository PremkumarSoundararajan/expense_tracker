import 'package:shared_preferences/shared_preferences.dart';

import '../models/transaction.dart';
import 'transaction_filter.dart';
import 'budget_comparison.dart';

class MonthlyBudgetSnapshotStore {
  static const _activeBudgetKey = 'monthly_target';

  static String keyForMonth(DateTime month) =>
      'budget_snapshot_${month.year}_${month.month.toString().padLeft(2, '0')}';

  Future<double?> initialize({
    required double? currentBudget,
    DateTime? now,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final currentDate = now ?? DateTime.now();
    final previousMonth = DateTime(currentDate.year, currentDate.month - 1);
    final previousMonthKey = keyForMonth(previousMonth);
    var previousMonthBudget = preferences.getDouble(previousMonthKey);

    if (previousMonthBudget == null &&
        currentBudget != null &&
        _isUsableBudget(currentBudget)) {
      await preferences.setDouble(previousMonthKey, currentBudget);
      previousMonthBudget = currentBudget;
    }

    final currentMonthKey = keyForMonth(currentDate);
    if (preferences.getDouble(currentMonthKey) == null &&
        currentBudget != null &&
        _isUsableBudget(currentBudget)) {
      await preferences.setDouble(currentMonthKey, currentBudget);
    }

    return previousMonthBudget;
  }

  Future<void> saveCurrentMonthBudget({
    required double budget,
    DateTime? now,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_activeBudgetKey, budget);
    await preferences.setDouble(keyForMonth(now ?? DateTime.now()), budget);
  }

  Future<double?> budgetForMonth(DateTime month) async {
    final preferences = await SharedPreferences.getInstance();

    // 1. Try exact month snapshot first
    var target = preferences.getDouble(keyForMonth(month));
    if (target != null && _isUsableBudget(target)) return target;

    // 2. Fallback: Search backwards through recorded history to find the closest prior budget
    var checkMonth = DateTime(month.year, month.month - 1);
    // Look back up to 24 months for a recorded snapshot
    for (var i = 0; i < 24; i++) {
      target = preferences.getDouble(keyForMonth(checkMonth));
      if (target != null && _isUsableBudget(target)) return target;
      checkMonth = DateTime(checkMonth.year, checkMonth.month - 1);
    }

    // 3. Ultimate Fallback: If looking backward fails (it's older than any snapshot),
    // use the earliest available snapshot, or default to the current active monthly target.
    final activeTarget = preferences.getDouble('monthly_target');
    if (activeTarget != null && _isUsableBudget(activeTarget)) {
      return activeTarget;
    }

    return null;
  }

  static bool _isUsableBudget(double? budget) =>
      budget != null && budget.isFinite && budget >= 0;
}

class MonthlyRolloverRecap {
  const MonthlyRolloverRecap({
    required this.previousMonthSpend,
    this.previousMonthRegularSpend,
    this.previousMonthPlannedOccasionalSpend = 0,
    this.previousMonthUnexpectedOccasionalSpend = 0,
    this.spending,
    required this.monthlyBudget,
  });

  final double previousMonthSpend;
  final double? previousMonthRegularSpend;
  final double previousMonthPlannedOccasionalSpend;
  final double previousMonthUnexpectedOccasionalSpend;
  final double monthlyBudget;
  final BudgetSpending? spending;

  double get regularSpend => previousMonthRegularSpend ?? previousMonthSpend;
  double get budgetRelevantSpend =>
      spending?.budgetRelevant ??
      previousMonthSpend - previousMonthUnexpectedOccasionalSpend;

  bool get stayedUnderBudget => spending == null
      ? budgetRelevantSpend <= monthlyBudget
      : spending!.outcome(monthlyBudget) != BudgetOutcome.over;

  double get difference => stayedUnderBudget
      ? monthlyBudget - (spending?.maximum ?? budgetRelevantSpend)
      : (spending?.minimum ?? budgetRelevantSpend) - monthlyBudget;

  static MonthlyRolloverRecap? calculate({
    required List<Transaction> transactions,
    required double? monthlyBudget,
    DateTime? now,
  }) {
    if (monthlyBudget == null || !monthlyBudget.isFinite || monthlyBudget < 0) {
      return null;
    }

    final currentDate = now ?? DateTime.now();
    final currentMonthStart = DateTime(currentDate.year, currentDate.month);
    final previousMonthStart = DateTime(
      currentDate.year,
      currentDate.month - 1,
    );
    final spendingTransactions = transactions
        .where((transaction) => !isTransferTransaction(transaction))
        .toList(growable: false);
    final hasCurrentMonthExpense = spendingTransactions.any(
      (transaction) =>
          !transaction.date.isBefore(currentMonthStart) &&
          transaction.date.isBefore(
            DateTime(currentMonthStart.year, currentMonthStart.month + 1),
          ),
    );
    if (hasCurrentMonthExpense) return null;

    final previousMonthTransactions = spendingTransactions
        .where(
          (transaction) =>
              !transaction.date.isBefore(previousMonthStart) &&
              transaction.date.isBefore(currentMonthStart),
        )
        .toList(growable: false);
    final spending = BudgetSpending.fromTransactions(previousMonthTransactions);
    if (previousMonthTransactions.isEmpty ||
        spending.outcome(monthlyBudget) == BudgetOutcome.uncertain) {
      return null;
    }

    return MonthlyRolloverRecap(
      spending: spending,
      previousMonthSpend: spending.total,
      previousMonthRegularSpend: spending.regular,
      previousMonthPlannedOccasionalSpend: spending.planned,
      previousMonthUnexpectedOccasionalSpend: spending.unexpected,
      monthlyBudget: monthlyBudget,
    );
  }
}
