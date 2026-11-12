import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/transaction.dart';
import '../utils/currency_format.dart';
import 'spending_averages_chart.dart';

enum SummaryFrequency { daily, monthly, yearly }

/// Which spending series the trends chart and observations describe.
enum SpendSeries { regular, actual }

class SpendPeriodPoint {
  const SpendPeriodPoint({
    required this.start,
    required this.label,
    required this.actual,
    required this.regular,
    this.isCurrent = false,
  });

  final DateTime start;
  final String label;
  final double actual;
  final double regular;
  final bool isCurrent;

  double valueFor(SpendSeries series) =>
      series == SpendSeries.regular ? regular : actual;
}

class SpendingAverageData {
  const SpendingAverageData({
    required this.average,
    required this.currentSpend,
    required this.averageLabel,
    required this.currentLabel,
    required this.periodCount,
    this.regularAverage = 0,
    this.regularCurrentSpend = 0,
    this.recentPeriods = const [],
  });

  final double average;
  final double currentSpend;
  final String averageLabel;
  final String currentLabel;
  final int periodCount;
  final double regularAverage;
  final double regularCurrentSpend;
  final List<SpendPeriodPoint> recentPeriods;

  factory SpendingAverageData.calculate({
    required List<Transaction> transactions,
    required SummaryFrequency frequency,
    DateTime? now,
  }) {
    final actual = _calculateSingle(
      transactions: transactions,
      frequency: frequency,
      now: now,
    );
    final regular = _calculateSingle(
      transactions: transactions,
      frequency: frequency,
      now: now,
      regularOnly: true,
    );
    return SpendingAverageData(
      average: actual.average,
      currentSpend: actual.currentSpend,
      averageLabel: actual.averageLabel,
      currentLabel: actual.currentLabel,
      periodCount: actual.periodCount,
      regularAverage: regular.average,
      regularCurrentSpend: regular.currentSpend,
      recentPeriods: _recentPeriods(
        transactions: transactions,
        frequency: frequency,
        now: now ?? DateTime.now(),
      ),
    );
  }

  static List<SpendPeriodPoint> _recentPeriods({
    required List<Transaction> transactions,
    required SummaryFrequency frequency,
    required DateTime now,
  }) {
    final history = transactions
        .where((transaction) => !transaction.date.isAfter(now))
        .toList(growable: false);
    return switch (frequency) {
      SummaryFrequency.daily => List.generate(7, (index) {
        final day = DateTime(now.year, now.month, now.day - (6 - index));
        final start = DateTime(day.year, day.month, day.day);
        final end = start.add(const Duration(days: 1));
        return SpendPeriodPoint(
          start: start,
          label: '${start.month}/${start.day}',
          actual: _sumBetween(history, start, end),
          regular: _sumBetween(history, start, end, regularOnly: true),
          isCurrent: index == 6,
        );
      }),
      SummaryFrequency.monthly => List.generate(6, (index) {
        final start = DateTime(now.year, now.month - (5 - index));
        final end = DateTime(start.year, start.month + 1);
        final isCurrent = index == 5;
        return SpendPeriodPoint(
          start: start,
          label: _shortMonthLabel(start),
          actual: _sumBetween(
            history,
            start,
            isCurrent ? now.add(const Duration(microseconds: 1)) : end,
          ),
          regular: _sumBetween(
            history,
            start,
            isCurrent ? now.add(const Duration(microseconds: 1)) : end,
            regularOnly: true,
          ),
          isCurrent: isCurrent,
        );
      }),
      SummaryFrequency.yearly => List.generate(4, (index) {
        final start = DateTime(now.year - (3 - index));
        final end = DateTime(start.year + 1);
        final isCurrent = index == 3;
        return SpendPeriodPoint(
          start: start,
          label: '${start.year}',
          actual: _sumBetween(
            history,
            start,
            isCurrent ? now.add(const Duration(microseconds: 1)) : end,
          ),
          regular: _sumBetween(
            history,
            start,
            isCurrent ? now.add(const Duration(microseconds: 1)) : end,
            regularOnly: true,
          ),
          isCurrent: isCurrent,
        );
      }),
    };
  }

  static String _shortMonthLabel(DateTime month) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${names[month.month - 1]} ${month.year % 100}';
  }

  static SpendingAverageData _calculateSingle({
    required List<Transaction> transactions,
    required SummaryFrequency frequency,
    DateTime? now,
    bool regularOnly = false,
  }) {
    final currentDate = now ?? DateTime.now();
    final today = DateTime(
      currentDate.year,
      currentDate.month,
      currentDate.day,
    );
    final history = transactions
        .where((transaction) => !transaction.date.isAfter(currentDate))
        .toList(growable: false);
    if (history.isEmpty) {
      return SpendingAverageData(
        average: 0,
        currentSpend: 0,
        averageLabel: 'No expense history yet',
        currentLabel: _currentPeriodLabel(frequency),
        periodCount: 0,
      );
    }

    final firstDate = history
        .map((transaction) => transaction.date)
        .reduce((first, date) => date.isBefore(first) ? date : first);
    return switch (frequency) {
      SummaryFrequency.daily => () {
        final firstDay = DateTime(
          firstDate.year,
          firstDate.month,
          firstDate.day,
        );
        final completedDays = today.difference(firstDay).inDays;
        final average = completedDays <= 0
            ? 0.0
            : _sumBetween(history, firstDay, today, regularOnly: regularOnly) /
                  completedDays;
        return SpendingAverageData(
          average: average,
          currentSpend: _sumBetween(
            history,
            today,
            currentDate.add(const Duration(microseconds: 1)),
            regularOnly: regularOnly,
          ),
          averageLabel: completedDays > 0
              ? 'Daily average'
              : 'No completed days yet',
          currentLabel: 'Today',
          periodCount: completedDays,
        );
      }(),
      SummaryFrequency.monthly => _monthlyAverage(
        history: history,
        firstDate: firstDate,
        now: currentDate,
        regularOnly: regularOnly,
      ),
      SummaryFrequency.yearly => _yearlyAverage(
        history: history,
        firstDate: firstDate,
        now: currentDate,
        regularOnly: regularOnly,
      ),
    };
  }

  static SpendingAverageData _monthlyAverage({
    required List<Transaction> history,
    required DateTime firstDate,
    required DateTime now,
    required bool regularOnly,
  }) {
    final firstMonth = DateTime(
      firstDate.year,
      firstDate.month + (firstDate.day == 1 ? 0 : 1),
    );
    final currentMonth = DateTime(now.year, now.month);
    final completedMonths =
        (currentMonth.year - firstMonth.year) * 12 +
        currentMonth.month -
        firstMonth.month;
    final currentSpend = _sumBetween(
      history,
      currentMonth,
      now.add(const Duration(microseconds: 1)),
      regularOnly: regularOnly,
    );
    if (completedMonths <= 0) {
      return SpendingAverageData(
        average: 0,
        currentSpend: currentSpend,
        averageLabel: 'No completed months yet',
        currentLabel: 'Month to date',
        periodCount: 0,
      );
    }

    final total = _sumBetween(
      history,
      firstMonth,
      currentMonth,
      regularOnly: regularOnly,
    );
    return SpendingAverageData(
      average: total / completedMonths,
      currentSpend: currentSpend,
      averageLabel: 'Monthly average',
      currentLabel: 'Month to date',
      periodCount: completedMonths,
    );
  }

  static SpendingAverageData _yearlyAverage({
    required List<Transaction> history,
    required DateTime firstDate,
    required DateTime now,
    required bool regularOnly,
  }) {
    final firstYear = DateTime(
      firstDate.year + (firstDate.month == 1 && firstDate.day == 1 ? 0 : 1),
    );
    final currentYear = DateTime(now.year);
    final completedYears = currentYear.year - firstYear.year;
    final currentSpend = _sumBetween(
      history,
      currentYear,
      now.add(const Duration(microseconds: 1)),
      regularOnly: regularOnly,
    );
    if (completedYears <= 0) {
      return SpendingAverageData(
        average: 0,
        currentSpend: currentSpend,
        averageLabel: 'No completed years yet',
        currentLabel: 'Year to date',
        periodCount: 0,
      );
    }

    final total = _sumBetween(
      history,
      firstYear,
      currentYear,
      regularOnly: regularOnly,
    );
    return SpendingAverageData(
      average: total / completedYears,
      currentSpend: currentSpend,
      averageLabel: 'Yearly average',
      currentLabel: 'Year to date',
      periodCount: completedYears,
    );
  }

  static String _currentPeriodLabel(SummaryFrequency frequency) {
    return switch (frequency) {
      SummaryFrequency.daily => 'Today',
      SummaryFrequency.monthly => 'Month to date',
      SummaryFrequency.yearly => 'Year to date',
    };
  }

  static double _sumBetween(
    List<Transaction> transactions,
    DateTime start,
    DateTime end, {
    bool regularOnly = false,
  }) {
    return transactions
        .where(
          (transaction) =>
              !transaction.date.isBefore(start) &&
              transaction.date.isBefore(end) &&
              (!regularOnly || transaction.expenseType == ExpenseType.regular),
        )
        .fold<double>(0, (total, transaction) => total + transaction.amount);
  }
}

/// Number of most recent completed periods used for the trend comparison.
const _trendWindow = 3;

/// Changes smaller than this (as a fraction) are reported as "in line".
const _trendTolerance = 0.05;

/// Mean after dropping the single highest and lowest value (needs 3+ values,
/// otherwise the plain mean). With the 3-period trend window this is the
/// middle value, which keeps one unusual period from swinging the result.
double spendingTrimmedMean(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final kept = sorted.length >= 3
      ? sorted.sublist(1, sorted.length - 1)
      : sorted;
  return kept.fold<double>(0, (sum, value) => sum + value) / kept.length;
}

/// Short, deterministic observations about [data] for the chosen [series].
///
/// 1. Trimmed average of the last 3 completed periods vs the overall average.
/// 2. Current-period spend as a share of the overall average.
///
/// Returns an empty list when there is not enough history to say anything.
List<String> buildSpendingObservations({
  required SpendingAverageData data,
  required SpendSeries series,
  required SummaryFrequency frequency,
  required String currencySymbol,
}) {
  final isRegular = series == SpendSeries.regular;
  final average = isRegular ? data.regularAverage : data.average;
  final currentSpend = isRegular ? data.regularCurrentSpend : data.currentSpend;
  if (data.periodCount <= 0 || !average.isFinite || average <= 0) {
    return const [];
  }

  final seriesName = isRegular ? 'Regular' : 'Actual';
  final adjective = switch (frequency) {
    SummaryFrequency.daily => 'daily',
    SummaryFrequency.monthly => 'monthly',
    SummaryFrequency.yearly => 'yearly',
  };
  final observations = <String>[];

  // Need the recent window plus at least one earlier period behind the average.
  final completed = data.recentPeriods
      .where((point) => !point.isCurrent)
      .toList(growable: false);
  if (completed.length >= _trendWindow && data.periodCount > _trendWindow) {
    final recent = completed
        .sublist(completed.length - _trendWindow)
        .map((point) => point.valueFor(series))
        .toList(growable: false);
    final recentAverage = spendingTrimmedMean(recent);
    final change = (recentAverage - average) / average;
    final window = '$_trendWindow ${_periodUnit(frequency, _trendWindow)}';
    final amounts =
        '(${formatFullCurrency(recentAverage, currencySymbol)} vs '
        '${formatFullCurrency(average, currencySymbol)})';
    if (change.abs() < _trendTolerance) {
      observations.add(
        '$seriesName spending over the last $window is in line with your '
        '$adjective average $amounts.',
      );
    } else {
      final percent = (change.abs() * 100).round();
      final direction = change > 0 ? 'above' : 'below';
      observations.add(
        '$seriesName spending over the last $window is $percent% '
        '$direction your $adjective average $amounts.',
      );
    }
  }

  if (currentSpend > 0) {
    final percent = (currentSpend / average * 100).round();
    observations.add(
      '${data.currentLabel}: ${formatFullCurrency(currentSpend, currencySymbol)} '
      'so far, $percent% of your $adjective average.',
    );
  }
  return observations;
}

/// Singular/plural unit name for [count] periods of [frequency].
String _periodUnit(SummaryFrequency frequency, int count) {
  final unit = switch (frequency) {
    SummaryFrequency.daily => 'day',
    SummaryFrequency.monthly => 'month',
    SummaryFrequency.yearly => 'year',
  };
  return count == 1 ? unit : '${unit}s';
}

class SpendingSummaryWidget extends StatefulWidget {
  const SpendingSummaryWidget({
    required this.transactions,
    required this.currencySymbol,
    this.now,
    this.cardMargin,
    this.cornerRadius,
    this.contentPadding = 16,
    super.key,
  });

  final List<Transaction> transactions;
  final String currencySymbol;
  final DateTime? now;

  /// Optional styling hooks so a wide layout can match its neighbouring
  /// panels. Defaults keep the original (Material default) card look.
  final EdgeInsetsGeometry? cardMargin;
  final double? cornerRadius;
  final double contentPadding;

  @override
  State<SpendingSummaryWidget> createState() => _SpendingSummaryWidgetState();
}

class _SpendingSummaryWidgetState extends State<SpendingSummaryWidget> {
  static const _frequencyKey = 'periodic_summaries_frequency';
  static const _recentHistoryKey = 'periodic_summaries_recent_history';

  bool _showRecentHistory = false;
  bool _isLoadingPreferences = true;
  SummaryFrequency _frequency = SummaryFrequency.monthly;
  SpendSeries _series = SpendSeries.regular;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedFrequency = preferences.getString(_frequencyKey);
      if (!mounted) return;
      setState(() {
        _showRecentHistory = preferences.getBool(_recentHistoryKey) ?? false;
        _frequency = SummaryFrequency.values.firstWhere(
          (value) => value.name == savedFrequency,
          orElse: () => SummaryFrequency.monthly,
        );
        _isLoadingPreferences = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingPreferences = false);
      _showPreferenceError(error);
    }
  }

  Future<bool> _savePreference(String key, Object value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = switch (value) {
        bool enabled => await preferences.setBool(key, enabled),
        String selection => await preferences.setString(key, selection),
        _ => false,
      };
      if (!saved) throw StateError('The summary preference was not saved.');
      return true;
    } catch (error) {
      if (mounted) _showPreferenceError(error);
      return false;
    }
  }

  Future<void> _setFrequency(SummaryFrequency frequency) async {
    if (await _savePreference(_frequencyKey, frequency.name) && mounted) {
      setState(() => _frequency = frequency);
    }
  }

  Future<void> _setShowRecentHistory(bool enabled) async {
    if (await _savePreference(_recentHistoryKey, enabled) && mounted) {
      setState(() => _showRecentHistory = enabled);
    }
  }

  void _showPreferenceError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not save summary preference: $error')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final average = SpendingAverageData.calculate(
      transactions: widget.transactions,
      frequency: _frequency,
      now: widget.now,
    );
    final chartPoints = _showRecentHistory
        ? average.recentPeriods
        : average.recentPeriods.where((point) => point.isCurrent).toList();
    final observations = buildSpendingObservations(
      data: average,
      series: _series,
      frequency: _frequency,
      currencySymbol: widget.currencySymbol,
    );

    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: widget.cardMargin,
      color: colorScheme.surfaceContainerLow,
      elevation: widget.cornerRadius == null ? null : 1,
      shape: widget.cornerRadius == null
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(widget.cornerRadius!),
            ),
      child: Padding(
        padding: EdgeInsets.all(widget.contentPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Spending Trends',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_isLoadingPreferences)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<SummaryFrequency>(
                initialValue: _frequency,
                decoration: const InputDecoration(
                  labelText: 'Average frequency',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: SummaryFrequency.values
                    .map(
                      (frequency) => DropdownMenuItem(
                        value: frequency,
                        child: Text(_frequencyLabel(frequency)),
                      ),
                    )
                    .toList(),
                onChanged: (frequency) {
                  if (frequency != null) _setFrequency(frequency);
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    key: const ValueKey('recent-history-chip'),
                    label: Text(
                      _frequency == SummaryFrequency.monthly
                          ? 'Last 6 months'
                          : _frequency == SummaryFrequency.daily
                          ? 'Last 7 days'
                          : 'Last 4 years',
                    ),
                    selected: _showRecentHistory,
                    onSelected: _setShowRecentHistory,
                  ),
                  SegmentedButton<SpendSeries>(
                    key: const ValueKey('spending-series-selector'),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: SpendSeries.regular,
                        label: Text('Regular'),
                      ),
                      ButtonSegment(
                        value: SpendSeries.actual,
                        label: Text('Actual'),
                      ),
                    ],
                    selected: {_series},
                    onSelectionChanged: (selection) =>
                        setState(() => _series = selection.first),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SpendingAveragesChart(
                points: chartPoints,
                actualAverage: average.average,
                regularAverage: average.regularAverage,
                currencySymbol: widget.currencySymbol,
                series: _series,
              ),
              if (average.periodCount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Based on ${average.periodCount} '
                  '${_periodUnit(_frequency, average.periodCount)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (observations.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final observation in observations)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6, right: 8),
                          child: Icon(
                            Icons.circle,
                            size: 6,
                            color: colorScheme.primary,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            observation,
                            key: const ValueKey('spending-observation'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _frequencyLabel(SummaryFrequency frequency) {
    return switch (frequency) {
      SummaryFrequency.daily => 'Daily Average',
      SummaryFrequency.monthly => 'Monthly Average',
      SummaryFrequency.yearly => 'Yearly Average',
    };
  }
}
