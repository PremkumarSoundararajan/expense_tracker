import '../models/transaction.dart';
import 'transaction_filter.dart';
import '../utils/transaction_period_format.dart';

const suggestedBudgetBufferRate = 0.10;

/// Minimum completed months of history before a suggestion is offered.
const suggestedBudgetMinCompletedMonths = 2;

/// Only the most recent N completed months feed the suggestion, so old
/// behaviour doesn't dominate.
const suggestedBudgetLookbackMonths = 6;

/// A merchant must be billed in at least this many distinct months to count
/// as recurring (or be billed in both of the two most recent completed months).
const suggestedBudgetRecurringMinMonths = 3;

/// A recurring candidate whose last charge is older than this many months
/// (counted back from the current month) is treated as cancelled.
/// 2 = last charge was in the latest completed month or the one before it.
const suggestedBudgetMaxMonthsSinceLast = 2;

class SuggestedBudgetItem {
  const SuggestedBudgetItem({
    required this.label,
    required this.category,
    required this.monthlyAverage,
    required this.monthsSeen,
    required this.sourceTransactions,
    this.rationale = '',
  });

  final String label;
  final String category;
  final double monthlyAverage;
  final int monthsSeen;
  final List<Transaction> sourceTransactions;

  /// Human-readable explanation for the UI, e.g.
  /// "Billed across 4 active months at $327.50/mo".
  final String rationale;
}

class SuggestedBudget {
  const SuggestedBudget({
    required this.amount,
    required this.completedMonths,
    required this.recurringTotal,
    required this.miscAverage,
    required this.buffer,
    required this.recurringItems,
    required this.miscItems,
    this.excludedItems = const [],
  });

  final double amount;
  final int completedMonths;
  final double recurringTotal;
  final double miscAverage;
  final double buffer;
  final List<SuggestedBudgetItem> recurringItems;

  /// Variable spending, grouped by category (trimmed monthly average).
  final List<SuggestedBudgetItem> miscItems;

  /// Items deliberately left out of the total (cancelled subscriptions,
  /// one-off spikes). Shown for transparency; monthlyAverage is informational.
  final List<SuggestedBudgetItem> excludedItems;
}

class SuggestedBudgetService {
  SuggestedBudget? suggest({
    required List<Transaction> transactions,
    DateTime? now,
  }) {
    final currentMonth = monthStart(now ?? DateTime.now());

    // Rule 3 / Rule 4: regular expenses only, completed months only, and no
    // duplicated import rows. Negative amounts (refunds/credits) are kept so
    // they can be netted against charges below.
    final candidates = _dedupe(
      transactions.where(
        (transaction) =>
            transaction.expenseType == ExpenseType.regular &&
            !isTransferTransaction(transaction) &&
            transaction.date.isBefore(currentMonth),
      ),
    );
    final charges = candidates.where((t) => t.amount > 0).toList();
    if (charges.isEmpty) return null;

    final firstDate = charges
        .map((transaction) => transaction.date)
        .reduce((first, date) => date.isBefore(first) ? date : first);
    final firstCompletedMonth = DateTime(
      firstDate.year,
      firstDate.month + (firstDate.day == 1 ? 0 : 1),
    );
    final completedMonths = _monthsBetween(firstCompletedMonth, currentMonth);
    if (completedMonths < suggestedBudgetMinCompletedMonths) return null;

    // Trailing window of complete months.
    final windowMonths = completedMonths < suggestedBudgetLookbackMonths
        ? completedMonths
        : suggestedBudgetLookbackMonths;
    final windowStart = DateTime(
      currentMonth.year,
      currentMonth.month - windowMonths,
    );
    final windowHistory = candidates
        .where((transaction) => !transaction.date.isBefore(windowStart))
        .toList(growable: false);
    if (!windowHistory.any((t) => t.amount > 0)) return null;

    final grouped = <String, List<Transaction>>{};
    for (final transaction in windowHistory) {
      grouped.putIfAbsent(_itemKey(transaction), () => []).add(transaction);
    }

    final latestCompleted = DateTime(currentMonth.year, currentMonth.month - 1);
    final previousCompleted = DateTime(
      currentMonth.year,
      currentMonth.month - 2,
    );

    final recurringItems = <SuggestedBudgetItem>[];
    final excludedItems = <SuggestedBudgetItem>[];

    // Variable pool: category -> month -> netted spend, plus source rows.
    final variableMonthly = <String, Map<DateTime, double>>{};
    final variableSources = <String, List<Transaction>>{};

    for (final entry in grouped.entries) {
      final txns = entry.value;
      final monthlyNet = _netByMonth(txns); // refunds netted, zero months gone
      if (monthlyNet.isEmpty) continue; // fully refunded -> $0

      final months = monthlyNet.keys.toList()..sort();
      final activeMonths = months.length;
      final total = monthlyNet.values.fold<double>(0, (s, v) => s + v);
      final category = _dominantCategory(txns);
      final label = _itemLabel(txns);
      final sorted = [...txns]..sort((a, b) => b.date.compareTo(a.date));

      final billedInLatestTwo =
          months.contains(latestCompleted) &&
          months.contains(previousCompleted);
      final isRecurring =
          activeMonths >= suggestedBudgetRecurringMinMonths ||
          (activeMonths == 2 && billedInLatestTwo);

      if (isRecurring) {
        final monthsSinceLast = _monthsBetween(months.last, currentMonth);
        if (monthsSinceLast > suggestedBudgetMaxMonthsSinceLast) {
          // Cancelled / defunct: seen often enough to be recurring, but gone.
          excludedItems.add(
            SuggestedBudgetItem(
              label: label,
              category: category,
              monthlyAverage: total / activeMonths,
              monthsSeen: activeMonths,
              sourceTransactions: sorted,
              rationale:
                  'Last charged ${monthsSinceLast - 1} months ago; '
                  'treated as cancelled',
            ),
          );
          continue;
        }

        // Rule 1: divide by the months the item has existed (first charge
        // through the latest completed month), not by total history. A bill
        // that started 4 months ago is averaged over 4, and a bi-monthly bill
        // is not overstated by dividing by active months only.
        final lifeMonths = _monthsBetween(months.first, currentMonth);
        final average = total / lifeMonths;
        recurringItems.add(
          SuggestedBudgetItem(
            label: label,
            category: category,
            monthlyAverage: average,
            monthsSeen: activeMonths,
            sourceTransactions: sorted,
            rationale:
                'Billed in $activeMonths of the last $lifeMonths months '
                'at \$${average.toStringAsFixed(2)}/mo',
          ),
        );
      } else {
        // Rule 3: 1-2 isolated months -> variable pool, not a fixed bill.
        final monthly = variableMonthly.putIfAbsent(category, () => {});
        monthlyNet.forEach((month, value) {
          monthly.update(month, (v) => v + value, ifAbsent: () => value);
        });
        variableSources.putIfAbsent(category, () => []).addAll(sorted);
      }
    }

    // Rule 2: variable categories use a trimmed mean of monthly totals so a
    // single spike month doesn't inflate the baseline.
    final miscItems = <SuggestedBudgetItem>[];
    for (final entry in variableMonthly.entries) {
      final perMonth = <double>[
        for (var i = 0; i < windowMonths; i++)
          entry.value[DateTime(windowStart.year, windowStart.month + i)] ?? 0,
      ];
      final average = _trimmedMean(perMonth);
      final seen = perMonth.where((v) => v > 0).length;
      final sources = variableSources[entry.key]!
        ..sort((a, b) => b.date.compareTo(a.date));

      if (average < 0.005) {
        excludedItems.add(
          SuggestedBudgetItem(
            label: entry.key,
            category: entry.key,
            monthlyAverage:
                perMonth.fold<double>(0, (s, v) => s + v) / windowMonths,
            monthsSeen: seen,
            sourceTransactions: sources,
            rationale:
                'One-off spending in $seen of $windowMonths months; '
                'not included in the baseline',
          ),
        );
        continue;
      }
      miscItems.add(
        SuggestedBudgetItem(
          label: entry.key,
          category: entry.key,
          monthlyAverage: average,
          monthsSeen: seen,
          sourceTransactions: sources,
          rationale:
              'Variable spending in $seen of $windowMonths months '
              '(trimmed average)',
        ),
      );
    }

    recurringItems.sort((a, b) => b.monthlyAverage.compareTo(a.monthlyAverage));
    miscItems.sort((a, b) => b.monthlyAverage.compareTo(a.monthlyAverage));
    excludedItems.sort((a, b) => b.monthlyAverage.compareTo(a.monthlyAverage));

    final recurringTotal = recurringItems.fold<double>(
      0,
      (sum, item) => sum + item.monthlyAverage,
    );
    final miscAverage = miscItems.fold<double>(
      0,
      (sum, item) => sum + item.monthlyAverage,
    );
    final buffer = (recurringTotal + miscAverage) * suggestedBudgetBufferRate;
    final amount =
        ((recurringTotal + miscAverage + buffer) * 100).round() / 100;
    if (amount <= 0) return null;

    return SuggestedBudget(
      amount: amount,
      completedMonths: completedMonths,
      recurringTotal: recurringTotal,
      miscAverage: miscAverage,
      buffer: buffer,
      recurringItems: recurringItems,
      miscItems: miscItems,
      excludedItems: excludedItems,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Whole months from [from] to [to] (both month starts).
  int _monthsBetween(DateTime from, DateTime to) =>
      (to.year - from.year) * 12 + to.month - from.month;

  /// Drops exact duplicate rows from overlapping statement imports.
  /// If Transaction exposes a stable id, prefer keying on that instead.
  List<Transaction> _dedupe(Iterable<Transaction> transactions) {
    final seen = <String>{};
    final result = <Transaction>[];
    for (final t in transactions) {
      final key =
          '${t.date.toIso8601String()}|'
          '${t.amount.toStringAsFixed(2)}|'
          '${t.category.toLowerCase()}|'
          '${normalizeMerchant(t.description)}';
      if (seen.add(key)) result.add(t);
    }
    return result;
  }

  /// Sums per month, then lets credits (negative months) offset the most
  /// recent charges before them. Months that net to zero are removed.
  Map<DateTime, double> _netByMonth(List<Transaction> transactions) {
    final net = <DateTime, double>{};
    for (final t in transactions) {
      net.update(
        monthStart(t.date),
        (v) => v + t.amount,
        ifAbsent: () => t.amount,
      );
    }
    final months = net.keys.toList()..sort((a, b) => b.compareTo(a));
    var credit = 0.0;
    for (final month in months) {
      final value = net[month]! + credit;
      if (value < 0) {
        credit = value;
        net[month] = 0;
      } else {
        credit = 0;
        net[month] = value;
      }
    }
    net.removeWhere((_, value) => value < 0.005);
    return net;
  }

  double _trimmedMean(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final trimmed = sorted.length >= 5
        ? sorted.sublist(1, sorted.length - 1)
        : sorted;
    return trimmed.fold<double>(0, (s, v) => s + v) / trimmed.length;
  }

  String _dominantCategory(List<Transaction> transactions) {
    final counts = <String, int>{};
    for (final t in transactions) {
      counts.update(t.category, (c) => c + 1, ifAbsent: () => 1);
    }
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  String _itemKey(Transaction transaction) {
    final normalized = normalizeMerchant(transaction.description);
    if (normalized.isNotEmpty) return 'desc:$normalized';
    return 'amt:${transaction.category.toLowerCase()}:${transaction.amount.abs().toStringAsFixed(2)}';
  }

  String _itemLabel(List<Transaction> transactions) {
    for (final transaction in transactions) {
      final description = transaction.description.trim();
      if (description.isNotEmpty) return description;
    }
    final first = transactions.first;
    return '${first.category} · repeating amount';
  }
}

String normalizeMerchant(String description) {
  var text = description.trim().toLowerCase();
  if (text.isEmpty) return '';
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  // Payment-processor prefixes: "sq *", "tst* ", "pp*".
  text = text.replaceAll(RegExp(r'^(sq|tst|pp)\s*\*\s*'), '');
  // Trailing reference suffixes and store/date noise.
  text = text.replaceAll(RegExp(r'\*+[a-z0-9]+$'), '');
  text = text.replaceAll(RegExp(r'\s+\d{1,2}/\d{1,2}$'), '');
  text = text.replaceAll(RegExp(r'\s+#\d+$'), '');
  text = text.replaceAll(RegExp(r'\s+#?\d{4,}$'), '');
  return text.trim();
}
