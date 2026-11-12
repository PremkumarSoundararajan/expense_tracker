import 'favourite_spending_spots_service.dart';
import 'merchant_classification_service.dart';
import '../models/transaction.dart';

class MerchantNaPreview {
  MerchantNaPreview(this.groups, this.totalSpending, this.totalTransactions);
  final List<FavouriteSpendingSpot> groups;
  final double totalSpending;
  final int totalTransactions;
  double get amount => groups.fold(0, (s, g) => s + g.total);
  int get transactions => groups.fold(0, (s, g) => s + g.transactionCount);
  double get spendingPercent =>
      totalSpending <= 0 ? 0 : (amount / totalSpending * 100).clamp(0, 100);
  double get transactionPercent =>
      totalTransactions == 0 ? 0 : transactions / totalTransactions * 100;
}

double? merchantNaThreshold(String value) {
  final number = double.tryParse(value.trim());
  return number != null &&
          number.isFinite &&
          number >= .01 &&
          (number * 100).isFinite &&
          number * 100 <= 9007199254740991
      ? (number * 100).round() / 100
      : null;
}

MerchantNaPreview previewMerchantNa(
  List<FavouriteSpendingSpot> groups,
  double threshold,
) => MerchantNaPreview(
  groups
      .where(
        (g) =>
            g.total > 0 && (g.total * 100).round() < (threshold * 100).round(),
      )
      .toList(),
  groups.fold(0, (s, g) => s + g.total),
  groups.fold(0, (s, g) => s + g.transactionCount),
);

Map<String, dynamic> merchantNaRecord(
  FavouriteSpendingSpot group,
  MerchantClassificationIndex index, {
  double? threshold,
}) {
  final previous = index.merchantFor(
    group.transactions.first.transaction.description,
  );
  if (previous?['na'] == true) return Map<String, dynamic>.from(previous!);
  return {
    ...?previous,
    'id': previous?['id'] ?? 'm:${group.key}',
    'kind': 'merchant',
    'deleted': false,
    'name': group.name,
    'aliases': {
      ...?(previous?['aliases'] as List?),
      for (final t in group.transactions) t.transaction.description,
    }.toList(),
    'category': 'NA',
    'categoryId': 'na',
    'expenseType': 'Unknown',
    'group': 'Unclassified',
    'na': true,
    if (threshold != null) 'naThreshold': threshold,
    'naOptOut': false,
    'naReviewRequired': false,
    'naBackup': {
      'merchant': previous,
      'transactions': {
        for (final entry in group.transactions)
          if (entry.transaction.id != null)
            entry.transaction.id!: {
              'category': index.apply(entry.transaction).category,
              'categoryId': index.apply(entry.transaction).categoryId,
              'group': index.apply(entry.transaction).baselineGroup,
              'expenseType': index
                  .apply(entry.transaction)
                  .expenseType
                  .sheetValue,
            },
      },
    },
  };
}

List<Map<String, dynamic>> removeMerchantNa(
  Map<String, dynamic> record,
  MerchantClassificationIndex index,
) {
  final backup = record['naBackup'] as Map?;
  final original = backup?['merchant'] as Map?;
  return [
    {
      ...?original,
      'id': record['id'],
      'kind': 'merchant',
      'name': record['name'],
      'aliases': record['aliases'],
      if (original == null) ...{
        'category': 'Uncategorized',
        'categoryId': '',
        'group': 'Unclassified',
        'expenseType': 'Unknown',
      },
      'deleted': false,
      'na': false,
      'naOptOut': true,
      'naBackup': null,
    },
    for (final entry in (backup?['transactions'] as Map? ?? {}).entries)
      {
        'id': 't:${entry.key}',
        'kind': 'transaction',
        'transactionId': entry.key,
        ...Map<String, dynamic>.from(entry.value as Map),
        ...?index.exceptions[entry.key],
        'deleted': false,
      },
  ];
}

const merchantNaPolicyId = 'policy:small-merchant-exclusion';
Map<String, dynamic> merchantNaPolicyRecord(double threshold) => {
  'id': merchantNaPolicyId,
  'kind': 'policy',
  'threshold': threshold,
  'deleted': false,
};

/// Run only against a complete committed ledger. No dates/amounts or explicit
/// transaction exceptions are edited. Unknown legacy limits are never guessed.
List<Map<String, dynamic>> reconcileMerchantNaPolicy(
  Iterable<Map<String, dynamic>> records,
  List<Transaction> transactions, {
  DateTime? now,
}) {
  final snapshot = records.toList();
  final index = MerchantClassificationIndex(snapshot);
  final policy = snapshot
      .where((r) => r['id'] == merchantNaPolicyId && r['deleted'] != true)
      .firstOrNull;
  final policyThreshold = merchantNaThreshold('${policy?['threshold'] ?? ''}');
  final groups = const FavouriteSpendingSpotsService()
      .calculate(transactions: transactions, allHistory: true, now: now)
      .actual;
  final byId = <String, List<FavouriteSpendingSpot>>{};
  for (final group in groups) {
    if (group.transactions.any(
      (t) => index.isAmbiguous(t.transaction.description),
    ))
      continue;
    final rules = {
      for (final t in group.transactions)
        if (index.merchantFor(t.transaction.description) case final r?)
          r['id']: r,
    };
    if (rules.length > 1)
      continue; // Ambiguous grouping is never changed automatically.
    final rule = rules.values.firstOrNull;
    final id = (rule?['id'] ?? 'm:${group.key}') as String;
    byId.putIfAbsent(id, () => []).add(group);
  }
  final changes = <Map<String, dynamic>>[];
  for (final entry in byId.entries) {
    final group = entry.value.first;
    final rule = index.merchantFor(
      group.transactions.first.transaction.description,
    );
    final threshold = merchantNaThreshold(
      '${policyThreshold ?? rule?['naThreshold'] ?? ''}',
    );
    if (threshold == null) continue;
    final total = entry.value.fold<double>(0, (sum, g) => sum + g.total);
    if (rule?['na'] == true) {
      if ((total * 100).round() >= (threshold * 100).round()) {
        changes.add({
          ...rule!,
          'na': false,
          'naBackup': null,
          'naThreshold': threshold,
          'category': 'Uncategorized',
          'categoryId': '',
          'expenseType': 'Unknown',
          'group': 'Unclassified',
          'naReviewRequired': true,
        });
      } else if (rule?['naThreshold'] != threshold && policyThreshold != null) {
        changes.add({...rule!, 'naThreshold': threshold});
      }
      continue;
    }
    if (policyThreshold == null ||
        rule?['naOptOut'] == true ||
        rule?['naReviewRequired'] == true ||
        total <= 0 ||
        (total * 100).round() >= (policyThreshold * 100).round())
      continue;
    final entries = entry.value.expand((g) => g.transactions).toList();
    final classified = entries.every((e) {
      final t = index.apply(e.transaction);
      return t.category.isNotEmpty &&
          !['Uncategorized', 'NA', 'Other'].contains(t.category) &&
          ['Essential', 'Potentially Flexible'].contains(t.baselineGroup) &&
          t.expenseType != ExpenseType.unknown;
    });
    if (classified) continue;
    final record = merchantNaRecord(group, index, threshold: policyThreshold);
    record['aliases'] = {
      ...(record['aliases'] as List).cast<String>(),
      for (final e in entries) e.transaction.description,
    }.toList();
    changes.add(record);
  }
  return changes;
}
