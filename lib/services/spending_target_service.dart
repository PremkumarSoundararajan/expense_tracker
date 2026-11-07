import '../models/spending_target.dart';
import '../models/financial_baseline.dart';
import '../models/expense_category.dart';
import '../models/transaction.dart';
import 'financial_baseline_service.dart';
import 'merchant_normalizer.dart';

enum TargetStatus { within, approaching, reached, over }

class TargetUsage {
  const TargetUsage(
    this.target,
    this.month,
    this.actual, {
    this.needsReview = false,
  });
  final SpendingTarget target;
  final DateTime month;
  final double actual;
  final bool needsReview;
  double get remaining => target.monthlyAmount - actual;
  double get progress => target.monthlyAmount == 0
      ? (actual > 0 ? 1 : 0)
      : actual / target.monthlyAmount;
  TargetStatus get status => actual > target.monthlyAmount
      ? TargetStatus.over
      : actual == target.monthlyAmount && actual > 0
      ? TargetStatus.reached
      : progress >= .8
      ? TargetStatus.approaching
      : TargetStatus.within;
  String get label => switch (status) {
    TargetStatus.within => 'Within target',
    TargetStatus.approaching => 'Approaching target',
    TargetStatus.reached => 'Target reached',
    TargetStatus.over => 'Over target',
  };
}

class TargetAwareness {
  const TargetAwareness(this.before, this.after);
  final TargetUsage before;
  final TargetUsage after;
  bool get crossed80 => before.progress < .8 && after.progress >= .8;
  bool get crossed100 =>
      (before.actual < before.target.monthlyAmount &&
          after.actual >= after.target.monthlyAmount) ||
      (before.target.monthlyAmount == 0 &&
          before.actual == 0 &&
          after.actual > 0);
  bool get prominent => crossed80 || crossed100;
}

class SpendingTargetService {
  final FinancialBaselineService _baseline = FinancialBaselineService();
  final MerchantNormalizer _normalizer = const MerchantNormalizer();

  List<SpendingTarget> effective(
    Iterable<SpendingTarget> targets,
    DateTime asOf,
  ) {
    final result = <String, SpendingTarget>{};
    final day = DateTime(asOf.year, asOf.month, asOf.day);
    for (final t in targets) {
      if (t.effectiveDate.isAfter(day)) continue;
      final old = result[t.scopeKey];
      if (old == null ||
          t.effectiveDate.isAfter(old.effectiveDate) ||
          (t.effectiveDate == old.effectiveDate &&
              t.updatedAt.isAfter(old.updatedAt))) {
        result[t.scopeKey] = t;
      }
    }
    return result.values.where((t) => t.active).toList()..sort((a, b) {
      if (a.type != b.type) {
        return a.type == SpendingTargetType.merchant ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
  }

  bool matches(
    SpendingTarget target,
    Transaction transaction,
    Iterable<ExpenseCategory> categories,
  ) {
    if (target.type == SpendingTargetType.merchant) {
      return _normalizer
              .normalize(transaction.description)
              .trim()
              .toLowerCase() ==
          target.scopeId;
    }
    final map = <String, ExpenseCategory>{
      for (final entry in defaultExpenseParents.entries)
        entry.key: ExpenseCategory(
          id: entry.key,
          parentId: entry.key,
          name: entry.value,
        ),
      for (final c in categories) c.id: c,
    };
    // An explicit deleted ID must never fall back to an unrelated label.
    String? id = transaction.categoryId;
    if (id == null || id.isEmpty) {
      id = map.values
          .where(
            (c) =>
                c.name.trim().toLowerCase() ==
                transaction.category.trim().toLowerCase(),
          )
          .firstOrNull
          ?.id;
    }
    final seen = <String>{};
    while (id != null && seen.add(id)) {
      if (id == target.scopeId && map.containsKey(id)) return true;
      final category = map[id];
      if (category == null || category.parentId == id) break;
      id = category.parentId;
    }
    return false;
  }

  List<TargetUsage> usage({
    required Iterable<SpendingTarget> targets,
    required Iterable<Transaction> transactions,
    required Iterable<FinancialBaselineMapping> mappings,
    required Iterable<ExpenseCategory> categories,
    required DateTime asOf,
  }) {
    final matches = _baseline.classify(
      transactions: transactions,
      mappings: mappings,
    );
    final eligible = matches
        .where((m) => m.assignedGroup == BaselineGroup.potentiallyFlexible)
        .map((m) => m.transaction);
    return [
      for (final target in effective(targets, asOf))
        TargetUsage(
          target,
          DateTime(asOf.year, asOf.month),
          eligible
              .where((t) {
                final date = t.date.isUtc ? t.date.toLocal() : t.date;
                return date.year == asOf.year &&
                    date.month == asOf.month &&
                    this.matches(target, t, categories);
              })
              .fold<double>(0, (s, t) => s + t.amount),
          needsReview: _needsReview(target, matches, categories),
        ),
    ];
  }

  bool _needsReview(
    SpendingTarget target,
    List<FinancialBaselineMatch> rows,
    Iterable<ExpenseCategory> categories,
  ) {
    if (target.type == SpendingTargetType.category) {
      final c = categories.where((c) => c.id == target.scopeId).firstOrNull;
      final unavailable = c == null
          ? !defaultExpenseParents.containsKey(target.scopeId)
          : !c.active || c.archived;
      return unavailable ||
          rows.any(
            (row) =>
                matches(target, row.transaction, categories) &&
                row.assignedGroup == BaselineGroup.essential,
          );
    }
    final scoped = rows
        .where((r) => matches(target, r.transaction, categories))
        .toList();
    return scoped.isEmpty ||
        !scoped.any(
          (r) => r.assignedGroup == BaselineGroup.potentiallyFlexible,
        );
  }

  List<TargetAwareness> preview({
    required Transaction proposed,
    required Iterable<SpendingTarget> targets,
    required Iterable<Transaction> transactions,
    required Iterable<FinancialBaselineMapping> mappings,
    required Iterable<ExpenseCategory> categories,
    DateTime? now,
  }) {
    final rows = transactions
        .where((t) => !sameLedgerTransaction(t, proposed))
        .toList();
    final date = proposed.date.isUtc ? proposed.date.toLocal() : proposed.date;
    final clock = now ?? DateTime.now();
    final end = DateTime(date.year, date.month + 1, 0);
    final asOf = end.isAfter(clock) ? clock : end;
    if (asOf.year != date.year || asOf.month != date.month) return [];
    final before = usage(
      targets: targets,
      transactions: transactions,
      mappings: mappings,
      categories: categories,
      asOf: asOf,
    );
    final after = usage(
      targets: targets,
      transactions: [...rows, proposed],
      mappings: mappings,
      categories: categories,
      asOf: asOf,
    );
    return [
      for (var i = 0; i < after.length; i++)
        if (after[i].actual > before[i].actual)
          TargetAwareness(before[i], after[i]),
    ];
  }

  /// Compare committed ledgers, never preview/import input rows. No change in
  /// eligible scope totals means no summary (including duplicate-only imports).
  List<TargetAwareness> importChanges({
    required Iterable<SpendingTarget> targets,
    required List<Transaction> before,
    required List<Transaction> after,
    required Iterable<FinancialBaselineMapping> mappings,
    required Iterable<ExpenseCategory> categories,
    required DateTime now,
  }) {
    final months = <DateTime>{};
    final prior = {
      for (final t in before)
        if (t.id != null) t.id!: t,
    };
    for (final t in after) {
      final old = t.id == null
          ? before
                .where((b) => b.toJsonString() == t.toJsonString())
                .firstOrNull
          : prior[t.id];
      if (old != null && old.toJsonString() == t.toJsonString()) continue;
      final d = t.date.isUtc ? t.date.toLocal() : t.date;
      months.add(DateTime(d.year, d.month));
      if (old != null) months.add(DateTime(old.date.year, old.date.month));
    }
    final result = <TargetAwareness>[];
    for (final month in months) {
      final end = DateTime(month.year, month.month + 1, 0);
      final asOf = end.isAfter(now) ? now : end;
      if (asOf.year != month.year || asOf.month != month.month) continue;
      final a = usage(
        targets: targets,
        transactions: before,
        mappings: mappings,
        categories: categories,
        asOf: asOf,
      );
      final b = usage(
        targets: targets,
        transactions: after,
        mappings: mappings,
        categories: categories,
        asOf: asOf,
      );
      for (var i = 0; i < a.length; i++) {
        if ((a[i].actual - b[i].actual).abs() > .005) {
          result.add(TargetAwareness(a[i], b[i]));
        }
      }
    }
    result.sort((a, b) => a.after.month.compareTo(b.after.month));
    return result;
  }
}
