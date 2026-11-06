import '../models/financial_baseline.dart';
import '../models/transaction.dart';
import 'financial_baseline_service.dart';
import 'merchant_normalizer.dart';

class DiscoveredMerchant {
  const DiscoveredMerchant({
    required this.merchantFingerprint,
    required this.occurrenceCount,
    required this.averageAmount,
    required this.totalAmount,
    required this.transactionCategories,
  });

  final String merchantFingerprint;
  final int occurrenceCount;
  final double averageAmount;
  final double totalAmount;
  final List<String> transactionCategories;
}

enum MerchantClassificationState { confirmed, suggested, needsReview, unknown }

enum MerchantSuggestionConfidence { high, medium, low }

enum MerchantSuggestionSource { userMapping, systemRule }

extension MerchantClassificationStateLabel on MerchantClassificationState {
  String get label => switch (this) {
    MerchantClassificationState.confirmed => 'Confirmed',
    MerchantClassificationState.suggested => 'Suggested',
    MerchantClassificationState.needsReview => 'Needs review',
    MerchantClassificationState.unknown => 'Unknown',
  };
}

extension MerchantSuggestionConfidenceLabel on MerchantSuggestionConfidence {
  String get label => switch (this) {
    MerchantSuggestionConfidence.high => 'High confidence',
    MerchantSuggestionConfidence.medium => 'Medium confidence',
    MerchantSuggestionConfidence.low => 'Low confidence',
  };
}

extension MerchantSuggestionSourceLabel on MerchantSuggestionSource {
  String get label => switch (this) {
    MerchantSuggestionSource.userMapping => 'User-confirmed mapping',
    MerchantSuggestionSource.systemRule => 'System rule',
  };
}

class MerchantClassificationSuggestion {
  const MerchantClassificationSuggestion({
    required this.merchant,
    required this.state,
    required this.group,
    required this.confidence,
    required this.reason,
    required this.source,
  });

  final DiscoveredMerchant merchant;
  final MerchantClassificationState state;
  final BaselineGroup? group;
  final MerchantSuggestionConfidence confidence;
  final String reason;
  final MerchantSuggestionSource source;
}

class MerchantDiscoveryService {
  MerchantDiscoveryService({FinancialBaselineService? financialBaselineService})
    : _financialBaselineService =
          financialBaselineService ?? FinancialBaselineService();

  final FinancialBaselineService _financialBaselineService;
  final MerchantNormalizer _normalizer = const MerchantNormalizer();

  static const _highConfidenceRules = <(String, BaselineGroup, String)>[
    ('ATMOS ENERGY', BaselineGroup.essential, 'Recognized natural gas utility'),
    (
      'NETFLIX',
      BaselineGroup.discretionary,
      'Recognized entertainment subscription',
    ),
    ('SPOTIFY', BaselineGroup.discretionary, 'Recognized music subscription'),
    (
      'DISNEY PLUS',
      BaselineGroup.discretionary,
      'Recognized entertainment subscription',
    ),
    (
      'YOUTUBE PREMIUM',
      BaselineGroup.discretionary,
      'Recognized entertainment subscription',
    ),
  ];

  static const _mediumConfidenceRules = <(String, BaselineGroup, String)>[
    (
      'EXXON',
      BaselineGroup.potentiallyFlexible,
      'Recognized fuel merchant; fuel spending needs vary',
    ),
    (
      'SHELL',
      BaselineGroup.potentiallyFlexible,
      'Recognized fuel merchant; fuel spending needs vary',
    ),
    (
      'BP',
      BaselineGroup.potentiallyFlexible,
      'Recognized fuel merchant; fuel spending needs vary',
    ),
    (
      'TOTALENERGIES',
      BaselineGroup.potentiallyFlexible,
      'Recognized fuel merchant; fuel spending needs vary',
    ),
    (
      'VERIZON',
      BaselineGroup.potentiallyFlexible,
      'Phone service matters, but plan and provider costs can vary',
    ),
    (
      'AT T',
      BaselineGroup.potentiallyFlexible,
      'Phone service matters, but plan and provider costs can vary',
    ),
    (
      'T MOBILE',
      BaselineGroup.potentiallyFlexible,
      'Phone service matters, but plan and provider costs can vary',
    ),
    (
      'VODAFONE',
      BaselineGroup.potentiallyFlexible,
      'Phone service matters, but plan and provider costs can vary',
    ),
    (
      'AIRTEL',
      BaselineGroup.potentiallyFlexible,
      'Phone service matters, but plan and provider costs can vary',
    ),
    (
      'MAXIS',
      BaselineGroup.potentiallyFlexible,
      'Phone service matters, but plan and provider costs can vary',
    ),
    (
      'ELECTRICITY',
      BaselineGroup.essential,
      'Description indicates an electricity utility; confirm the merchant',
    ),
    (
      'WATER UTILITY',
      BaselineGroup.essential,
      'Description indicates a water utility; confirm the merchant',
    ),
    (
      'NATURAL GAS',
      BaselineGroup.essential,
      'Description indicates a gas utility; confirm the merchant',
    ),
  ];

  static const _ambiguousMerchants = <String>[
    'WALMART',
    'WAL MART',
    'AMAZON',
    'TARGET',
    'COSTCO',
    'CVS',
    'WALGREENS',
  ];

  static const _paymentProviders = <String>['ZELLE', 'VENMO', 'PAYPAL'];

  List<MerchantClassificationSuggestion> suggestClassifications({
    required Iterable<DiscoveredMerchant> merchants,
    required Iterable<FinancialBaselineMapping> confirmedMappings,
  }) {
    final mappingsByMerchant = <String, Set<BaselineGroup>>{};
    for (final mapping in confirmedMappings) {
      final key = _normalized(mapping.merchantFingerprint);
      if (key.isEmpty) continue;
      mappingsByMerchant.putIfAbsent(key, () => {}).add(mapping.group);
    }

    return merchants
        .map((merchant) {
          final name = _normalized(merchant.merchantFingerprint);
          final groups = mappingsByMerchant[name];
          if (groups != null && groups.length == 1) {
            return MerchantClassificationSuggestion(
              merchant: merchant,
              state: MerchantClassificationState.confirmed,
              group: groups.single,
              confidence: MerchantSuggestionConfidence.high,
              reason: 'Previously confirmed by you',
              source: MerchantSuggestionSource.userMapping,
            );
          }
          if (groups != null && groups.length > 1) {
            return MerchantClassificationSuggestion(
              merchant: merchant,
              state: MerchantClassificationState.needsReview,
              group: null,
              confidence: MerchantSuggestionConfidence.low,
              reason:
                  'This merchant has confirmed mappings in more than one group',
              source: MerchantSuggestionSource.userMapping,
            );
          }

          for (final (keyword, group, reason) in _highConfidenceRules) {
            if (_containsMerchant(name, keyword)) {
              return MerchantClassificationSuggestion(
                merchant: merchant,
                state: MerchantClassificationState.suggested,
                group: group,
                confidence: MerchantSuggestionConfidence.high,
                reason: reason,
                source: MerchantSuggestionSource.systemRule,
              );
            }
          }
          if (_ambiguousMerchants.any(
            (keyword) => _containsMerchant(name, keyword),
          )) {
            return MerchantClassificationSuggestion(
              merchant: merchant,
              state: MerchantClassificationState.needsReview,
              group: null,
              confidence: MerchantSuggestionConfidence.low,
              reason:
                  'This retailer sells a mix of essential and optional items',
              source: MerchantSuggestionSource.systemRule,
            );
          }
          for (final (keyword, group, reason) in _mediumConfidenceRules) {
            if (_containsMerchant(name, keyword)) {
              return MerchantClassificationSuggestion(
                merchant: merchant,
                state: MerchantClassificationState.suggested,
                group: group,
                confidence: MerchantSuggestionConfidence.medium,
                reason: reason,
                source: MerchantSuggestionSource.systemRule,
              );
            }
          }
          if (_paymentProviders.any(
            (provider) => _containsMerchant(name, provider),
          )) {
            return MerchantClassificationSuggestion(
              merchant: merchant,
              state: MerchantClassificationState.unknown,
              group: null,
              confidence: MerchantSuggestionConfidence.low,
              reason: 'Payment provider identified without a reliable underlying merchant',
              source: MerchantSuggestionSource.systemRule,
            );
          }
          final categorySuggestion = _suggestFromTransactionCategories(
            merchant,
          );
          if (categorySuggestion != null) return categorySuggestion;
          return MerchantClassificationSuggestion(
            merchant: merchant,
            state: MerchantClassificationState.unknown,
            group: null,
            confidence: MerchantSuggestionConfidence.low,
            reason: 'No reliable lifestyle group rule matched this merchant',
            source: MerchantSuggestionSource.systemRule,
          );
        })
        .toList(growable: false);
  }

  String _normalized(String value) =>
      _normalizer.normalize(value).trim().toUpperCase();

  bool _containsMerchant(String normalizedName, String keyword) {
    final normalizedKeyword = _normalized(keyword);
    if (normalizedName.isEmpty || normalizedKeyword.isEmpty) return false;
    return normalizedName == normalizedKeyword ||
        normalizedName.startsWith('$normalizedKeyword ') ||
        normalizedName.endsWith(' $normalizedKeyword') ||
        normalizedName.contains(' $normalizedKeyword ');
  }

  MerchantClassificationSuggestion? _suggestFromTransactionCategories(
    DiscoveredMerchant merchant,
  ) {
    final categories = merchant.transactionCategories.map(_normalized).toSet();
    if (categories.length != 1) return null;
    final category = categories.single;
    final result = switch (category) {
      'ELECTRICITY' || 'ELECTRIC UTILITY' || 'UTILITIES' || 'WATER UTILITY' => (
        BaselineGroup.essential,
        'Transaction category indicates a utility service',
      ),
      'FUEL' || 'GASOLINE' || 'PETROL' => (
        BaselineGroup.potentiallyFlexible,
        'Transaction category indicates fuel; necessity varies',
      ),
      'FINANCIAL OBLIGATIONS' || 'LOAN' || 'LOAN PAYMENT' => (
        BaselineGroup.committed,
        'Transaction category indicates a financial obligation',
      ),
      _ => null,
    };
    if (result == null) return null;
    return MerchantClassificationSuggestion(
      merchant: merchant,
      state: MerchantClassificationState.suggested,
      group: result.$1,
      confidence: MerchantSuggestionConfidence.medium,
      reason: '${result.$2} (${merchant.transactionCategories.single})',
      source: MerchantSuggestionSource.systemRule,
    );
  }

  List<DiscoveredMerchant> discover(Iterable<Transaction> transactions) {
    final history = transactions.toList(growable: false);
    final ignored = _financialBaselineService
        .classify(transactions: history, mappings: const [])
        .where((match) => match.isIgnored)
        .map((match) => match.transaction)
        .toSet();
    final totals = <String, (int, double)>{};
    final transactionCategories = <String, Set<String>>{};
    for (final transaction in history) {
      if (ignored.contains(transaction)) continue;
      final fingerprint = _normalizer.normalize(transaction.description);
      if (fingerprint.isEmpty || fingerprint == 'GENERAL') continue;
      final current = totals[fingerprint] ?? (0, 0.0);
      totals[fingerprint] = (current.$1 + 1, current.$2 + transaction.amount);
      if (transaction.category.trim().isNotEmpty) {
        transactionCategories
            .putIfAbsent(fingerprint, () => <String>{})
            .add(transaction.category.trim());
      }
    }

    final merchants = [
      for (final entry in totals.entries)
        DiscoveredMerchant(
          merchantFingerprint: entry.key,
          occurrenceCount: entry.value.$1,
          averageAmount: entry.value.$2 / entry.value.$1,
          totalAmount: entry.value.$2,
          transactionCategories: List.unmodifiable(
            transactionCategories[entry.key] ?? const <String>{},
          ),
        ),
    ];
    merchants.sort((first, second) {
      final amountOrder = second.totalAmount.compareTo(first.totalAmount);
      return amountOrder != 0
          ? amountOrder
          : first.merchantFingerprint.compareTo(second.merchantFingerprint);
    });
    return List.unmodifiable(merchants);
  }
}
