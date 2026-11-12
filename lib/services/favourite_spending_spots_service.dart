import 'dart:collection';

import '../models/transaction.dart';
import 'transaction_filter.dart';

enum SpendingSpotFilter { actual, regular, occasional }

class SpendingSpotTransaction {
  const SpendingSpotTransaction({
    required this.transaction,
    required this.netAmount,
  });

  final Transaction transaction;
  final double netAmount;
}

class FavouriteSpendingSpot {
  const FavouriteSpendingSpot({
    required this.key,
    required this.name,
    required this.total,
    required this.averageMonthly,
    required this.transactions,
  });

  final String key;
  final String name;
  final double total;
  final double averageMonthly;
  final List<SpendingSpotTransaction> transactions;

  int get transactionCount => transactions.length;
}

class FavouriteSpendingSpotsData {
  const FavouriteSpendingSpotsData({
    required this.periodStart,
    required this.periodEnd,
    required this.completedMonths,
    required this.actual,
    required this.regular,
    required this.occasional,
  });

  final DateTime? periodStart;
  final DateTime periodEnd;
  final int completedMonths;
  final List<FavouriteSpendingSpot> actual;
  final List<FavouriteSpendingSpot> regular;
  final List<FavouriteSpendingSpot> occasional;

  List<FavouriteSpendingSpot> spotsFor(SpendingSpotFilter filter) {
    return switch (filter) {
      SpendingSpotFilter.actual => actual,
      SpendingSpotFilter.regular => regular,
      SpendingSpotFilter.occasional => occasional,
    };
  }
}

class FavouriteSpendingSpotsService {
  static const _monthsToShow = 6;

  const FavouriteSpendingSpotsService();

  FavouriteSpendingSpotsData calculate({
    required List<Transaction> transactions,
    DateTime? now,
    bool allHistory = false,
  }) {
    final currentDate = now ?? DateTime.now();
    final currentMonth = DateTime(currentDate.year, currentDate.month);
    final historical = transactions
        .where((transaction) => !transaction.date.isAfter(currentDate))
        .toList(growable: false);
    if (historical.isEmpty) {
      return FavouriteSpendingSpotsData(
        periodStart: null,
        periodEnd: currentMonth,
        completedMonths: 0,
        actual: const [],
        regular: const [],
        occasional: const [],
      );
    }

    final firstDate = historical
        .map((transaction) => transaction.date)
        .reduce((first, date) => date.isBefore(first) ? date : first);
    final firstEligibleMonth = DateTime(
      firstDate.year,
      firstDate.month + (firstDate.day == 1 ? 0 : 1),
    );
    final sixMonthWindowStart = DateTime(
      currentMonth.year,
      currentMonth.month - _monthsToShow,
    );
    final periodStart = allHistory
        ? DateTime(firstDate.year, firstDate.month)
        : firstEligibleMonth.isAfter(sixMonthWindowStart)
        ? firstEligibleMonth
        : sixMonthWindowStart;
    final completedMonths = allHistory
        ? (currentMonth.year - periodStart.year) * 12 +
              currentMonth.month -
              periodStart.month +
              1
        : periodStart.isBefore(currentMonth)
        ? (currentMonth.year - periodStart.year) * 12 +
              currentMonth.month -
              periodStart.month
        : 0;
    if (completedMonths == 0) {
      return FavouriteSpendingSpotsData(
        periodStart: periodStart,
        periodEnd: currentMonth,
        completedMonths: 0,
        actual: const [],
        regular: const [],
        occasional: const [],
      );
    }

    final seenIds = <String>{};
    final seenRows = <int>{};
    final seenObjects = HashSet<Transaction>.identity();

    // Pass 1: keep the rows that count as spending.
    final eligible = <_EligibleTransaction>[];
    for (final transaction in historical) {
      if (transaction.date.isBefore(periodStart) ||
          (!allHistory && !transaction.date.isBefore(currentMonth)) ||
          isTransferTransaction(transaction) ||
          !_markAsUnique(transaction, seenIds, seenRows, seenObjects) ||
          !transaction.amount.isFinite ||
          transaction.amount <= 0) {
        continue;
      }
      final isRefund = _isRefundOrReversal(transaction.description);
      eligible.add(
        _EligibleTransaction(
          transaction: transaction,
          isRefund: isRefund,
          merchantText: _merchantText(
            transaction.description,
            isRefund: isRefund,
          ),
        ),
      );
    }

    // Merchant names are resolved across every eligible row at once so that
    // shared city suffixes can be spotted and variants of one merchant
    // ("PENNYMAC" and "PennyMac home loan") collapse to the shortest name.
    // Stored descriptions are never changed; this only affects grouping and
    // the label shown in this insight.
    final merchantNames = _MerchantNames(
      eligible.map((item) => item.merchantText),
    );

    // Pass 2: group.
    final actualTotals = <String, _SpendingSpotAccumulator>{};
    final regularTotals = <String, _SpendingSpotAccumulator>{};
    final occasionalTotals = <String, _SpendingSpotAccumulator>{};
    var unidentifiedSpotNumber = 0;

    for (final item in eligible) {
      final transaction = item.transaction;
      final merchantKey = merchantNames.keyFor(item.merchantText);
      final hasMerchant = merchantKey.isNotEmpty;
      final key = hasMerchant
          ? merchantKey.toLowerCase()
          : 'unidentified-${unidentifiedSpotNumber++}';
      final description = transaction.description.trim();
      final name = hasMerchant
          ? _MerchantNames.titleCase(merchantKey)
          : (description.isEmpty ? 'Unspecified spending spot' : description);
      final signedAmount = item.isRefund
          ? -transaction.amount
          : transaction.amount;
      final spotTransaction = SpendingSpotTransaction(
        transaction: transaction,
        netAmount: signedAmount,
      );

      _addToTotals(actualTotals, key, name, spotTransaction);
      if (transaction.expenseType == ExpenseType.regular) {
        _addToTotals(regularTotals, key, name, spotTransaction);
      } else if (transaction.expenseType != ExpenseType.unknown) {
        _addToTotals(occasionalTotals, key, name, spotTransaction);
      }
    }

    return FavouriteSpendingSpotsData(
      periodStart: periodStart,
      periodEnd: currentMonth,
      completedMonths: completedMonths,
      actual: _rankSpots(actualTotals, completedMonths),
      regular: _rankSpots(regularTotals, completedMonths),
      occasional: _rankSpots(occasionalTotals, completedMonths),
    );
  }

  bool _markAsUnique(
    Transaction transaction,
    Set<String> seenIds,
    Set<int> seenRows,
    HashSet<Transaction> seenObjects,
  ) {
    final id = transaction.id?.trim();
    if (id != null && id.isNotEmpty) return seenIds.add(id);
    final sheetRow = transaction.sheetRow;
    if (sheetRow != null) return seenRows.add(sheetRow);
    return seenObjects.add(transaction);
  }

  void _addToTotals(
    Map<String, _SpendingSpotAccumulator> totals,
    String key,
    String name,
    SpendingSpotTransaction spotTransaction,
  ) {
    totals
        .putIfAbsent(key, () => _SpendingSpotAccumulator(name: name))
        .add(spotTransaction);
  }

  List<FavouriteSpendingSpot> _rankSpots(
    Map<String, _SpendingSpotAccumulator> totals,
    int completedMonths,
  ) {
    final spots = totals.entries
        .where((entry) => entry.value.total > 0)
        .map(
          (entry) => FavouriteSpendingSpot(
            key: entry.key,
            name: entry.value.name,
            total: entry.value.total,
            averageMonthly: entry.value.total / completedMonths,
            transactions: List.unmodifiable(entry.value.transactions),
          ),
        )
        .toList(growable: false);
    spots.sort((a, b) {
      final byTotal = b.total.compareTo(a.total);
      return byTotal != 0 ? byTotal : a.key.compareTo(b.key);
    });
    return List.unmodifiable(spots);
  }

  bool _isRefundOrReversal(String description) {
    return RegExp(
      r'\b(refund|reversal|chargeback)\b',
      caseSensitive: false,
    ).hasMatch(description);
  }

  /// Removes refund wording so "Refund from Amazon" groups with "Amazon".
  String _merchantText(String description, {required bool isRefund}) {
    var text = description.trim();
    if (isRefund) {
      text = text
          .replaceAll(
            RegExp(
              r'\b(?:refund|reversal|chargeback)\s+(?:from|at|for|by)\b',
              caseSensitive: false,
            ),
            ' ',
          )
          .replaceAll(
            RegExp(r'\b(?:refund|reversal|chargeback)\b', caseSensitive: false),
            ' ',
          )
          .replaceFirst(RegExp(r'^\s*from\s+', caseSensitive: false), '');
    }
    return text.trim();
  }
}

class _EligibleTransaction {
  const _EligibleTransaction({
    required this.transaction,
    required this.isRefund,
    required this.merchantText,
  });

  final Transaction transaction;
  final bool isRefund;
  final String merchantText;
}

class _SpendingSpotAccumulator {
  _SpendingSpotAccumulator({required this.name});

  final String name;
  final List<SpendingSpotTransaction> transactions = [];
  double total = 0;

  void add(SpendingSpotTransaction transaction) {
    transactions.add(transaction);
    total += transaction.netAmount;
  }
}

/// Turns raw bank, card, or hand-typed descriptions into short merchant names.
///
/// Steps: pull the merchant out of bank-specific layouts (ACH metadata,
/// PayPal, Zelle/Venmo), clean it, drop tokens containing digits and bank
/// boilerplate, remove a "city + state" suffix that repeats across several
/// merchants, then merge names that are whole-word prefixes of each other
/// into the shortest one. Cleaning is Unicode-aware so non-Latin merchant
/// names are kept.
class _MerchantNames {
  _MerchantNames(Iterable<String> merchantTexts, {int minLocationStems = 3}) {
    final tokensByText = {
      for (final text in merchantTexts.toSet()) text: _tokens(text),
    };

    // City detection with no city list: when the same trailing words plus a
    // state code ("FORT WORTH TX") follow several different merchants, they
    // are a location, not part of the name.
    final stemsByLocation = <String, Set<String>>{};
    for (final tokens in tokensByText.values) {
      for (final cityWords in _locationLengths) {
        final split = _locationSplit(tokens, cityWords);
        if (split == null) continue;
        stemsByLocation
            .putIfAbsent(split.location, () => <String>{})
            .add(split.stem);
      }
    }
    _locations = {
      for (final entry in stemsByLocation.entries)
        if (entry.value.length >= minLocationStems) entry.key,
    };

    // Shortest-name merge: "PENNYMAC" absorbs "PENNYMAC HOME LOAN".
    final names = <String>{
      for (final tokens in tokensByText.values)
        _stripLocation(tokens).join(' '),
    }.where((name) => name.isNotEmpty).toList();
    names.sort((a, b) => a.split(' ').length.compareTo(b.split(' ').length));
    for (final name in names) {
      if (!_canonicals.any((canonical) => _isPrefix(canonical, name))) {
        _canonicals.add(name);
      }
    }

    for (final entry in tokensByText.entries) {
      _keys[entry.key] = _resolve(entry.value);
    }
  }

  static const _locationLengths = [2, 1, 0];
  late final Set<String> _locations;
  final List<String> _canonicals = [];
  final Map<String, String> _keys = {};

  /// Uppercase grouping key, or '' when nothing usable is left.
  String keyFor(String merchantText) =>
      _keys[merchantText] ?? _resolve(_tokens(merchantText));

  String _resolve(List<String> tokens) {
    final name = _stripLocation(tokens).join(' ');
    if (name.isEmpty) return '';
    for (final canonical in _canonicals) {
      if (_isPrefix(canonical, name)) return canonical;
    }
    return name;
  }

  List<String> _stripLocation(List<String> tokens) {
    for (final cityWords in _locationLengths) {
      final split = _locationSplit(tokens, cityWords);
      if (split != null && _locations.contains(split.location)) {
        return tokens.sublist(0, tokens.length - 1 - cityWords);
      }
    }
    return tokens;
  }

  static ({String location, String stem})? _locationSplit(
    List<String> tokens,
    int cityWords,
  ) {
    final cutAt = tokens.length - 1 - cityWords;
    if (cutAt < 1 || !_usStates.contains(tokens.last)) return null;
    return (
      location: tokens.sublist(cutAt).join(' '),
      stem: tokens.sublist(0, cutAt).join(' '),
    );
  }

  static bool _isPrefix(String canonical, String name) =>
      name == canonical || name.startsWith('$canonical ');

  // --- single-description cleanup -----------------------------------------

  /// "Zelle payment to Joseph Kalaivanan for tmobile apr" -> "Joseph Kalaivanan"
  static final _person = RegExp(
    r'^(?:zelle|venmo)\b.*?\b(?:to|from)\s+(.+?)(?:\s+for\b|\s+conf#|[;"]|$)',
    caseSensitive: false,
  );

  /// "PAYPAL DES:INST XFER ID:DISNEY PLUS INDN:..." -> "DISNEY PLUS"
  static final _paypal = RegExp(
    r'^paypal\b.*?\bID:\s*(.+?)\s+INDN:',
    caseSensitive: false,
  );

  /// In ACH lines everything after these markers is metadata (trace IDs, the
  /// account holder's own name, company IDs), not the merchant.
  static final _metadataMarker = RegExp(
    r'\b(?:DES|INDN|CO ID|ID)\s*:',
    caseSensitive: false,
  );

  static final _processorPrefix = RegExp(
    r'^(?:sq|tst|pp)\s*\*\s*',
    caseSensitive: false,
  );

  static final _containsNumber = RegExp(r'\p{N}', unicode: true);

  /// Bank boilerplate that is never part of a merchant name.
  static const _noise = <String>{
    'ID',
    'WEB',
    'PPD',
    'ARC',
    'CCD',
    'TEL',
    'DES',
    'INDN',
    'CONF',
    'CONFIRMATION',
    'PURCHASE',
    'PAYMENT',
    'PMT',
    'PYMT',
    'TRANSFER',
    'XFER',
    'WITHDRAWAL',
    'WITHDRWL',
    'CHECK',
    'CHK',
    'ONLINE',
    'RECURRING',
    'MONEYLINE',
    'CASH',
    'ACCTVERIFY',
    'EPAY',
    'DEBIT',
    'POS',
    'CHECKCARD',
    'ACH',
  };

  static const _usStates = <String>{
    'AL',
    'AK',
    'AZ',
    'AR',
    'CA',
    'CO',
    'CT',
    'DE',
    'FL',
    'GA',
    'HI',
    'ID',
    'IL',
    'IN',
    'IA',
    'KS',
    'KY',
    'LA',
    'ME',
    'MD',
    'MA',
    'MI',
    'MN',
    'MS',
    'MO',
    'MT',
    'NE',
    'NV',
    'NH',
    'NJ',
    'NM',
    'NY',
    'NC',
    'ND',
    'OH',
    'OK',
    'OR',
    'PA',
    'RI',
    'SC',
    'SD',
    'TN',
    'TX',
    'UT',
    'VT',
    'VA',
    'WA',
    'WV',
    'WI',
    'WY',
    'DC',
  };

  static String _extract(String raw) {
    var text = raw.trim();
    final person = _person.firstMatch(text);
    if (person != null) return person.group(1)!;
    final paypal = _paypal.firstMatch(text);
    if (paypal != null) return paypal.group(1)!;
    final marker = _metadataMarker.firstMatch(text);
    if (marker != null && marker.start > 0) {
      text = text.substring(0, marker.start);
    }
    return text.replaceFirst(_processorPrefix, '');
  }

  /// The service's original cleanup (reference/auth cut-offs, trailing dates,
  /// punctuation), kept as-is because it is Unicode-aware.
  static String _basicClean(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceFirst(
          RegExp(r'\b(?:web|ppd)\s+id\b.*$', caseSensitive: false),
          ' ',
        )
        .replaceFirst(
          RegExp(
            r'\b(?:reference|ref|authorization|auth|trace|confirmation|transaction)'
            r'\s*(?:id|no|number)?\s*[:#-]\s*\S+.*$',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'#\s*\d+\b'), ' ')
        .replaceFirst(RegExp(r'\s+\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?\s*$'), ' ')
        .replaceFirst(RegExp(r'\s+\d{5,}\s*$'), ' ')
        .replaceAll(
          RegExp(
            r"""[.,;:!?()\[\]{}"'`~@\$%^&*_+=<>|\\/—–、。，．！？：；（）［］｛｝〈〉《》「」『』【】؟،؛।॥・-]+""",
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> _tokens(String raw) {
    return _basicClean(_extract(raw))
        .split(' ')
        // Drops dates, store numbers, auth codes, confirmation/reference IDs.
        .where((token) => token.isNotEmpty && !_containsNumber.hasMatch(token))
        .map((token) => token.toUpperCase())
        .where((token) => !_noise.contains(token))
        .toList(growable: false);
  }

  static const _keepUpper = {'LLC', 'INC', 'LTD', 'LP', 'USA'};

  static String titleCase(String value) => value
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map(
        (word) => _keepUpper.contains(word)
            ? word
            : word.substring(0, 1) + word.substring(1).toLowerCase(),
      )
      .join(' ');
}

/// Reuses the exact bank-layout, recipient, location and prefix consolidation
/// used by Favourite Spending Spots, without restricting the date window.
class SpendingMerchantNameIndex {
  SpendingMerchantNameIndex(Iterable<String> descriptions)
    : _names = _MerchantNames(descriptions.map(_clean));
  final _MerchantNames _names;
  static String _clean(String description) {
    const service = FavouriteSpendingSpotsService();
    return service._merchantText(
      description,
      isRefund: service._isRefundOrReversal(description),
    );
  }

  String keyFor(String description) => _names.keyFor(_clean(description));
}
