import 'package:shared_preferences/shared_preferences.dart';

import '../models/transaction.dart';
import 'transaction_filter.dart';
import 'budget_comparison.dart';

/// One monthly budget is used for current and historical comparisons.
/// The class name is retained for compatibility with existing callers.
class MonthlyBudgetSnapshotStore {
  static const _activeBudgetKey = 'monthly_target';

  // Legacy key format, used only to identify and remove old overrides.
  static String keyForMonth(DateTime month) =>
      'budget_snapshot_${month.year}_${month.month.toString().padLeft(2, '0')}';

  Future<double?> initialize({
    required double? currentBudget,
    DateTime? now,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getDouble(_activeBudgetKey);
    final budget = _isUsableBudget(saved) ? saved : currentBudget;
    if (!_isUsableBudget(budget)) {
      await _removeLegacySnapshots(preferences);
      return null;
    }
    if (!_isUsableBudget(saved)) {
      await saveBudget(budget: budget!);
    } else {
      await _removeLegacySnapshots(preferences);
    }
    return budget;
  }

  Future<void> saveBudget({required double budget}) async {
    if (!_isUsableBudget(budget)) throw ArgumentError.value(budget, 'budget');
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setDouble(_activeBudgetKey, budget)) {
      throw StateError('Could not save the monthly budget.');
    }
    await _removeLegacySnapshots(preferences);
  }

  Future<void> saveCurrentMonthBudget({
    required double budget,
    DateTime? now,
  }) => saveBudget(budget: budget);

  Future<double?> budgetForMonth(DateTime month) async {
    final budget = (await SharedPreferences.getInstance()).getDouble(
      _activeBudgetKey,
    );
    return _isUsableBudget(budget) ? budget : null;
  }

  /// The selected month never changes the scope: every edit updates all months.
  Future<void> saveMonthBudget({
    required DateTime month,
    required double budget,
    DateTime? now,
  }) => saveBudget(budget: budget);

  static Future<void> _removeLegacySnapshots(
    SharedPreferences preferences,
  ) async {
    for (final key
        in preferences
            .getKeys()
            .where((key) => key.startsWith('budget_snapshot_'))
            .toList()) {
      if (!await preferences.remove(key)) {
        throw StateError('Could not remove an old monthly budget override.');
      }
    }
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
      : spending!.recordedOutcome(monthlyBudget) != BudgetOutcome.over;

  double get difference => stayedUnderBudget
      ? monthlyBudget - budgetRelevantSpend
      : budgetRelevantSpend - monthlyBudget;

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
    if (previousMonthTransactions.isEmpty) {
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
