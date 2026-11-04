final RegExp _statementDatePattern = RegExp(
  r'\b(?:\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}[-/]\d{2,4})\b',
  caseSensitive: false,
);

final RegExp _labeledReferencePattern = RegExp(
  r'\b(?:WEB|PPD|ACH|TRACE|REF(?:ERENCE)?|CONF(?:IRMATION)?|'
  r'TRAN(?:SACTION)?|TXN|CHECK|CHK|CHEQUE|AUTH(?:ORIZATION)?|'
  r'CONFIRMATION)\s*(?:ID|NO|NUM|NUMBER|#)?\s*[:#-]?\s*'
  r'[A-Z0-9][A-Z0-9_-]*',
  caseSensitive: false,
);

final RegExp _checkNumberPattern = RegExp(
  r'\b(?:CHECK|CHK|CHEQUE)\s*#?\s*\d+\b',
  caseSensitive: false,
);

final RegExp _numericTokenPattern = RegExp(r'\b\d+\b');
final RegExp _alphanumericIdPattern = RegExp(
  r'\b(?=[A-Z0-9_-]*\d)[A-Z0-9][A-Z0-9_-]*\b',
  caseSensitive: false,
);
final RegExp _punctuationPattern = RegExp(r'[^A-Z0-9]+');
final RegExp _spacesPattern = RegExp(r'\s+');

const _statementBoilerplate = <String>{
  'ACH',
  'AUTOMATIC',
  'BILLPAY',
  'BILL',
  'CHECK',
  'CHK',
  'DEBIT',
  'ID',
  'ONLINE',
  'PAYMENT',
  'PURCHASE',
  'PYMT',
  'RECURRING',
  'RCR',
  'RECUR',
  'TRANSFER',
  'UTIL',
  'UTILITIES',
  'WEB',
};

const _locationAndChannelCodes = <String>{
  'ATM',
  'BR',
  'BRANCH',
  'LOC',
  'LOCATION',
  'POS',
  'STORE',
  'US',
};

/// Returns an uppercase merchant fingerprint with statement metadata removed.
String normalizeMerchant(String rawStatement) {
  var cleaned = rawStatement.toUpperCase();
  cleaned = cleaned.replaceAll(_statementDatePattern, ' ');
  cleaned = cleaned.replaceAll(_checkNumberPattern, ' ');
  cleaned = cleaned.replaceAll(_labeledReferencePattern, ' ');
  cleaned = cleaned.replaceAll(_alphanumericIdPattern, ' ');
  cleaned = cleaned.replaceAll(_numericTokenPattern, ' ');
  cleaned = cleaned.replaceAll(_punctuationPattern, ' ');

  final tokens = cleaned
      .split(_spacesPattern)
      .where((token) => token.isNotEmpty)
      .where(
        (token) =>
            !_statementBoilerplate.contains(token) &&
            !_locationAndChannelCodes.contains(token),
      )
      .toList(growable: false);
  return tokens.join(' ').trim();
}

class MerchantNormalizer {
  const MerchantNormalizer();

  String normalize(String rawStatement) => normalizeMerchant(rawStatement);
}
