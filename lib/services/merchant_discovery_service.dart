import '../models/transaction.dart';
import 'financial_baseline_service.dart';
import 'merchant_normalizer.dart';

class DiscoveredMerchant {
  const DiscoveredMerchant({
    required this.merchantFingerprint,
    required this.occurrenceCount,
    required this.averageAmount,
  });

  final String merchantFingerprint;
  final int occurrenceCount;
  final double averageAmount;
}

class MerchantDiscoveryService {
  MerchantDiscoveryService({FinancialBaselineService? financialBaselineService})
    : _financialBaselineService =
          financialBaselineService ?? FinancialBaselineService();

  final FinancialBaselineService _financialBaselineService;
  final MerchantNormalizer _normalizer = const MerchantNormalizer();

  List<DiscoveredMerchant> discover(Iterable<Transaction> transactions) {
    final history = transactions.toList(growable: false);
    final ignored = _financialBaselineService
        .classify(transactions: history, mappings: const [])
        .where((match) => match.isIgnored)
        .map((match) => match.transaction)
        .toSet();
    final totals = <String, (int, double)>{};
    for (final transaction in history) {
      if (ignored.contains(transaction)) continue;
      final fingerprint = _normalizer.normalize(transaction.description);
      if (fingerprint.isEmpty || fingerprint == 'GENERAL') continue;
      final current = totals[fingerprint] ?? (0, 0.0);
      totals[fingerprint] = (current.$1 + 1, current.$2 + transaction.amount);
    }

    final merchants = [
      for (final entry in totals.entries)
        DiscoveredMerchant(
          merchantFingerprint: entry.key,
          occurrenceCount: entry.value.$1,
          averageAmount: entry.value.$2 / entry.value.$1,
        ),
    ];
    merchants.sort((first, second) {
      final countOrder = second.occurrenceCount.compareTo(
        first.occurrenceCount,
      );
      return countOrder != 0
          ? countOrder
          : first.merchantFingerprint.compareTo(second.merchantFingerprint);
    });
    return List.unmodifiable(merchants);
  }
}
