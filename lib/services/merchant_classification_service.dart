import '../models/transaction.dart';
import 'merchant_normalizer.dart';
import 'favourite_spending_spots_service.dart';

String merchantClassificationKey(String description) {
  final normalized = normalizeMerchant(description);
  if (normalized.isNotEmpty) return normalized;
  final raw = description.toUpperCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  return raw.isEmpty ? '' : 'RAW:$raw';
}

/// Shared spending-spot families plus exact aliases. Collisions stay unresolved.
class MerchantClassificationIndex {
  MerchantClassificationIndex(Iterable<Map<String, dynamic>> records) {
    final snapshot = records.toList(growable: false);
    for (final record in snapshot) {
      if (record['deleted'] == true) continue;
      if (record['kind'] == 'merchant' && record['aliases'] is! List)
        throw const FormatException('Invalid merchant aliases.');
      if ((record['category'] != null && record['category'] is! String) ||
          (record['categoryId'] != null && record['categoryId'] is! String))
        throw const FormatException('Invalid merchant category.');
    }
    _names = SpendingMerchantNameIndex([
      for (final r in snapshot)
        if (r['kind'] == 'merchant' && r['deleted'] != true) ...[
          if (r['name'] is String) r['name'] as String,
          for (final alias in r['aliases'] as List? ?? const [])
            alias.toString(),
        ],
    ]);
    for (final record in snapshot) {
      if (record['deleted'] == true) continue;
      if (record['group'] != null &&
          ![
            'Essential',
            'Potentially Flexible',
            'Unclassified',
          ].contains(record['group'])) {
        throw const FormatException('Invalid merchant essentiality.');
      }
      if (record['kind'] == 'transaction' &&
          (record['transactionId'] is! String ||
              (record['transactionId'] as String).isEmpty)) {
        throw const FormatException(
          'Transaction exception is missing its stable ID.',
        );
      }
      if (record['kind'] == 'merchant' && record['aliases'] is! List) {
        throw const FormatException('Invalid merchant aliases.');
      }
      if (record['kind'] == 'transaction') {
        exceptions[record['transactionId'] as String] = record;
      } else if (record['kind'] == 'merchant') {
        for (final description in [
          if (record['name'] is String) record['name'] as String,
          for (final alias in record['aliases'] as List) alias.toString(),
        ]) {
          final canonical = _names.keyFor(description);
          if (canonical.isEmpty) continue;
          final previous = canonicalMerchants[canonical];
          if (previous != null && previous['id'] != record['id'])
            ambiguousNames.add(canonical);
          else
            canonicalMerchants[canonical] = record;
        }
        for (final alias in (record['aliases'] as List? ?? const [])) {
          final key = merchantClassificationKey(alias.toString());
          if (key.isEmpty) continue;
          final previous = merchants[key];
          if (previous != null && previous['id'] != record['id']) {
            ambiguous.add(key);
          } else {
            merchants[key] = record;
          }
        }
      }
    }
  }
  late final SpendingMerchantNameIndex _names;
  final canonicalMerchants = <String, Map<String, dynamic>>{};
  final ambiguousNames = <String>{};
  final merchants = <String, Map<String, dynamic>>{};
  final exceptions = <String, Map<String, dynamic>>{};
  final ambiguous = <String>{};

  bool isAmbiguous(String description) =>
      ambiguous.contains(merchantClassificationKey(description)) ||
      ambiguousNames.contains(_names.keyFor(description));

  Map<String, dynamic>? merchantFor(String description) {
    final key = merchantClassificationKey(description);
    final canonical = _names.keyFor(description);
    if (ambiguous.contains(key) || ambiguousNames.contains(canonical))
      return null;
    return merchants[key] ?? canonicalMerchants[canonical];
  }

  Transaction apply(Transaction transaction) {
    final merchant = merchantFor(transaction.description);
    final exception = exceptions[transaction.id];
    final category = exception?['category'] ?? merchant?['category'];
    final categoryId = exception?['categoryId'] ?? merchant?['categoryId'];
    final group = exception?['group'] ?? merchant?['group'];
    final type = exception?['expenseType'] ?? merchant?['expenseType'];
    return transaction.copyWith(
      expenseType: type == null ? null : ExpenseType.parse(type),
      category: category as String?,
      categoryId: categoryId as String?,
      baselineGroup: group as String?,
      clearBaselineGroup: group == null,
    );
  }
}
