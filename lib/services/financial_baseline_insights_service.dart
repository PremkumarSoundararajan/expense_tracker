import '../models/financial_baseline.dart';
import '../models/transaction.dart';
import '../utils/currency_format.dart';
import 'financial_baseline_service.dart';

class BaselineMonthlySpending {
  const BaselineMonthlySpending({
    required this.month,
    required this.baseline,
    required this.adjustable,
    required this.unclassified,
  });

  final DateTime month;
  final double baseline;
  final double adjustable;
  final double unclassified;

  double get total => baseline + adjustable + unclassified;
}

class BaselineSpendingInsights {
  const BaselineSpendingInsights({
    required this.months,
    required this.observation,
    required this.hasSixMonthsOfHistory,
    required this.isTrendProvisional,
    required this.recentCoveragePercentage,
    required this.previousCoveragePercentage,
  });

  final List<BaselineMonthlySpending> months;
  final String observation;
  final bool hasSixMonthsOfHistory;
  final bool isTrendProvisional;
  final double recentCoveragePercentage;
  final double previousCoveragePercentage;
}

/// Builds actual spending totals for the six completed calendar months and a
/// draft-aware adjustable spending comparison. Transactions are classified by
/// the same eligibility and merchant matching rules used by the baseline.
class FinancialBaselineInsightsService {
  FinancialBaselineInsightsService({FinancialBaselineService? baselineService})
    : _baselineService = baselineService ?? FinancialBaselineService();

  final FinancialBaselineService _baselineService;

  BaselineSpendingInsights build({
    required Iterable<Transaction> transactions,
    required Iterable<FinancialBaselineMapping> mappings,
    required DateTime now,
    String currencySymbol = r'$',
    Iterable<FinancialBaselineMatch>? classifiedTransactions,
  }) {
    final currentMonth = DateTime(now.year, now.month);
    final firstMonth = DateTime(now.year, now.month - 6);
    final months = [
      for (var offset = 0; offset < 6; offset++)
        BaselineMonthlySpending(
          month: DateTime(firstMonth.year, firstMonth.month + offset),
          baseline: 0,
          adjustable: 0,
          unclassified: 0,
        ),
    ];
    final totals = List.generate(
      months.length,
      (_) => <String, double>{
        'baseline': 0,
        'adjustable': 0,
        'unclassified': 0,
      },
    );
    final eligibleDates = <DateTime>[];
    final matches =
        classifiedTransactions ??
        _baselineService.classify(
          transactions: transactions,
          mappings: mappings,
        );
    for (final match in matches) {
      if (match.isIgnored) continue;
      final date = match.transaction.date;
      final monthStart = DateTime(date.year, date.month);
      eligibleDates.add(date);
      if (monthStart.isBefore(firstMonth) ||
          !monthStart.isBefore(currentMonth)) {
        continue;
      }
      final index =
          (monthStart.year - firstMonth.year) * 12 +
          monthStart.month -
          firstMonth.month;
      final bucket = match.assignedGroup;
      final segment = switch (bucket) {
        BaselineGroup.essential => 'baseline',
        BaselineGroup.potentiallyFlexible => 'adjustable',
        null => 'unclassified',
      };
      totals[index][segment] =
          totals[index][segment]! + match.transaction.amount;
    }

    final monthly = [
      for (var index = 0; index < months.length; index++)
        BaselineMonthlySpending(
          month: months[index].month,
          baseline: totals[index]['baseline']!,
          adjustable: totals[index]['adjustable']!,
          unclassified: totals[index]['unclassified']!,
        ),
    ];
    final older = monthly.take(3).toList(growable: false);
    final recent = monthly.skip(3).toList(growable: false);
    final previousCoverage = _coverage(older);
    final recentCoverage = _coverage(recent);
    final hasFullHistory = eligibleDates.any(
      (date) => !DateTime(date.year, date.month).isAfter(firstMonth),
    );
    final provisional = previousCoverage < 80 || recentCoverage < 80;
    final observation = !hasFullHistory && provisional
        ? 'More spending history is needed, and the trend is provisional because some spending remains unclassified.'
        : !hasFullHistory
        ? 'More spending history is needed to identify a meaningful trend.'
        : provisional
        ? 'The adjustable spending trend is provisional because some spending remains unclassified.'
        : _adjustableObservation(older, recent, currencySymbol);

    return BaselineSpendingInsights(
      months: List.unmodifiable(monthly),
      observation: observation,
      hasSixMonthsOfHistory: hasFullHistory,
      isTrendProvisional: provisional,
      recentCoveragePercentage: recentCoverage,
      previousCoveragePercentage: previousCoverage,
    );
  }

  double _coverage(List<BaselineMonthlySpending> months) {
    final eligible = months.fold<double>(0, (sum, month) => sum + month.total);
    if (eligible <= 0) return 100;
    final classified = months.fold<double>(
      0,
      (sum, month) => sum + month.baseline + month.adjustable,
    );
    return classified / eligible * 100;
  }

  String _adjustableObservation(
    List<BaselineMonthlySpending> older,
    List<BaselineMonthlySpending> recent,
    String currencySymbol,
  ) {
    final previousAverage =
        older.fold<double>(0, (sum, month) => sum + month.adjustable) / 3;
    final recentAverage =
        recent.fold<double>(0, (sum, month) => sum + month.adjustable) / 3;
    if (previousAverage == 0 && recentAverage == 0) {
      return 'No adjustable spending was recorded in these six months.';
    }
    if (previousAverage == 0) {
      return 'Adjustable spending increased by ${_format(recentAverage, currencySymbol)} per month; the previous three-month average was zero.';
    }
    final change = (recentAverage - previousAverage) / previousAverage * 100;
    if (change.abs() < 5) {
      return 'Your adjustable spending has remained relatively stable over the last six months.';
    }
    final rounded = change.abs().round();
    final direction = change < 0 ? 'decreased' : 'increased';
    return 'Your adjustable spending $direction $rounded% over the last three months compared with the previous three.';
  }

  String _format(double value, String currencySymbol) =>
      formatFullCurrency(value, currencySymbol);
}
