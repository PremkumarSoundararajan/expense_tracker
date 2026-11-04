import '../models/transaction.dart';
import 'transaction_filter.dart';

class SpendingInsightsService {
  String? getSpendingInsight({
    required List<Transaction> history,
    required String category,
    required double currentSpend,
    double? currentActualSpend,
    double currentPlannedOccasionalSpend = 0,
    double currentUnexpectedOccasionalSpend = 0,
    DateTime? now,
  }) {
    final spendingHistory = history
        .where((transaction) => !isTransferTransaction(transaction))
        .toList(growable: false);
    if (spendingHistory.isEmpty) return null;

    final currentDate = now ?? DateTime.now();
    final firstDate = spendingHistory
        .map((transaction) => transaction.date)
        .reduce((first, date) => date.isBefore(first) ? date : first);

    final currentMonthStart = DateTime(currentDate.year, currentDate.month);
    final firstCompletedMonth = DateTime(
      firstDate.year,
      firstDate.month + (firstDate.day == 1 ? 0 : 1),
    );
    final completedMonths =
        (currentMonthStart.year - firstCompletedMonth.year) * 12 +
        currentMonthStart.month -
        firstCompletedMonth.month;
    if (completedMonths < 2) return null;

    final historicalSpend = spendingHistory
        .where(
          (transaction) =>
              transaction.category == category &&
              transaction.expenseType == ExpenseType.regular &&
              !transaction.date.isBefore(firstCompletedMonth) &&
              transaction.date.isBefore(currentMonthStart),
        )
        .fold<double>(0, (total, transaction) => total + transaction.amount);
    final averageSpend = historicalSpend / completedMonths;

    if (averageSpend <= 0) return null;

    final actualSpend = currentActualSpend ?? currentSpend;
    final occasionalSpend =
        currentPlannedOccasionalSpend + currentUnexpectedOccasionalSpend;
    if (actualSpend >= averageSpend * 1.2 &&
        currentSpend < averageSpend * 1.2 &&
        occasionalSpend > 0) {
      return 'Actual spending in $category is elevated this month, while '
          'regular spending is near its historical average. Occasional '
          'outflows account for ${occasionalSpend.toStringAsFixed(2)}.';
    }

    final spikePercentage =
        ((currentSpend - averageSpend) / averageSpend) * 100;
    if (spikePercentage >= 20) {
      return 'We noticed your spending in $category jumped '
          '${spikePercentage.round()}% higher than your historical average '
          'this period. Reviewing recent entries here might help spot savings '
          'opportunities.';
    }

    return null;
  }
}
