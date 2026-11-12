import 'favourite_spending_spots_service.dart';
import 'merchant_classification_service.dart';

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
  MerchantClassificationIndex index,
) {
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
    if (original != null)
      Map<String, dynamic>.from(original)
    else
      {
        'id': record['id'],
        'kind': 'merchant',
        'name': record['name'],
        'aliases': record['aliases'],
        'deleted': true,
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
