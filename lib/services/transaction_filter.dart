import '../models/transaction.dart';

/// User context configuration for account-scoped and household rules.
class UserTransferContext {
  final List<String> ownNames;
  final List<String> ownLast4;
  final List<String> ownInstitutions;
  final List<String> householdNames;
  final Map<String, String> userOverrides; // Key: exact description, Value: classification ('TRANSFER', 'EXPENSE', 'INCOME')

  const UserTransferContext({
    this.ownNames = const [],
    this.ownLast4 = const [],
    this.ownInstitutions = const [],
    this.householdNames = const [],
    this.userOverrides = const {},
  });
}

/// Generic TRANSFER indicators based on explicit transfer language,
/// credit card payments, investment moves, and P2P app cash-outs.
const Set<String> _explicitTransferKeywords = {
  // Explicit transfer wording & regional codes
  'TRANSFER', 'XFER', 'TRNSFR', 'TFR', 'TRF', 'RMT', 'REMITTANCE',
  'WIRE', 'ACH',
  'ONLINE TRANSFER', 'MOBILE TRANSFER', 'INTERNAL TRANSFER', 'FUNDS TRANSFER',
  'BOOK TRANSFER', 'ACCOUNT TRANSFER', 'ACCT TRANSFER', 'ACCT XFER',
  'ACCT TO ACCT', 'ACCOUNT TO ACCOUNT', 'A2A', 'A2A XFER', 'A2A XFERS',
  'BETWEEN ACCOUNTS', 'OWN ACCOUNT', 'SELF TRANSFER',
  'FROM CHECKING',
  'TO CHECKING',
  'FROM SAVINGS',
  'TO SAVINGS',
  'FROM SAV',
  'TO SAV',
  'SWEEP',
  'AUTO SWEEP',
  'CASH MANAGEMENT',
  'MONEY MARKET SWEEP',
  'OVERDRAFT PROTECTION TRANSFER',

  // Regional Payment Rails (Specific to Transfers/Remittances)
  'NEFT', 'IMPS', 'EFT TRANSFER', 'FEDWIRE', 'FAST PAY',

  // Brokerage / investing / retirement movements
  'MONEYLINE', 'JOURNAL', 'JNL', 'CONTRIBUTION', 'DISTRIBUTION', 'ROLLOVER',
  'RECHARACTERIZATION', 'DEPOSIT TO BROKERAGE', 'WITHDRAWAL FROM BROKERAGE',
  'INVESTMENT TRANSFER',
  'IRA',
  'ROTH',
  '401K',
  'HSA CONTRIBUTION',
  '529 CONTRIBUTION',
  'FUNDING', 'BROKERAGE', 'MMF',
  'FID BKG SVC',

  // Credit card and loan payments from own bank to own card
  'CRD EPAY', 'CREDIT CRD EPAY', 'EPAYMENT', 'E-PAYMENT', 'AUTOPAY', 'AUTO PAY',
  'CREDIT CARD PAYMENT', 'CC PAYMENT', 'CARD PAYMENT', 'PAYMENT THANK YOU',
  'PAYMENT - THANK YOU',
  'ONLINE PAYMENT RECEIVED',
  'MOBILE BANKING PAYMENT TO CRD',

  // P2P Cash-outs & funding balance moves
  'CASHOUT',
  'CASH OUT',
  'INSTANT TRANSFER',
  'STANDARD TRANSFER',
  'ADD MONEY',
  'WITHDRAW TO BANK',
  'TOP UP', 'LOAD', 'WITHDRAWAL TO', 'DEPOSIT FROM',
};

/// Financial institution name hints (used ONLY in combination with user context or explicit rules)
const List<String> _genericInstitutionHints = [
  'FIDELITY',
  'FID BKG SVC',
  'SCHWAB',
  'VANGUARD',
  'ROBINHOOD',
  'E*TRADE',
  'MERRILL',
  'TD AMERITRADE',
  'ALLY',
  'MARCUS',
  'SOFI',
  'WEALTHFRONT',
  'BETTERMENT',
  'CREDIT UNION',
  'FEDERAL',
  'BANK',
];

/// Evaluates whether a transaction description qualifies as an internal transfer
/// following the strict multi-step decision hierarchy.
bool isInternalTransfer(
  String description, {
  UserTransferContext context = const UserTransferContext(),
}) {
  final upper = description.trim().toUpperCase();

  // 1. User Override Rules
  if (context.userOverrides.containsKey(upper)) {
    return context.userOverrides[upper] == 'TRANSFER';
  }

  // 2. Own-Account Identifier (e.g. last 4s or nicknames)
  for (final last4 in context.last4sOrNicknames(context.ownLast4)) {
    if (upper.contains(last4.toUpperCase())) return true;
  }

  // 3. Explicit Transfer Wording & Brokerage/Card Payment keywords.
  // PayPal labels merchant payments "INST XFER" (Disney+, Uber, ...). That is
  // an expense, so remove it before keyword matching.
  final keywordText = upper.replaceAll(RegExp(r'\bINST XFER\b'), ' ');
  for (final keyword in _explicitTransferKeywords) {
    if (RegExp(r'\b' + RegExp.escape(keyword) + r'\b').hasMatch(keywordText)) {
      return true;
    }
  }

  // 4. Own-Name + Financial Institution Hint in ACH/Wire text
  bool matchesOwnName = context.ownNames.any(
    (name) => upper.contains(name.toUpperCase()),
  );
  bool matchesInstitution =
      context.ownInstitutions.any(
        (inst) => upper.contains(inst.toUpperCase()),
      ) ||
      _genericInstitutionHints.any((inst) => upper.contains(inst));

  if (matchesOwnName && matchesInstitution) {
    return true;
  }

  return false;
}

/// Helper extension to normalize user context lists
extension _UserTransferContextHelpers on UserTransferContext {
  List<String> last4sOrNicknames(List<String> last4s) {
    return last4s.where((l) => l.trim().isNotEmpty).toList();
  }
}

/// Helper to check if a transaction object is a transfer by category or description rule
bool isTransferTransaction(
  Transaction transaction, {
  UserTransferContext context = const UserTransferContext(),
}) {
  final category = transaction.category.trim().toUpperCase();
  if (category == 'TRANSFERS') return true;
  final hasExplicitCategory =
      category.isNotEmpty &&
      category != 'LIFESTYLE / MISC' &&
      category != 'UNCATEGORIZED';
  if (hasExplicitCategory) return false;
  return isInternalTransfer(transaction.description, context: context);
}

/// Tags a transaction as 'Transfers' if it matches transfer logic
Transaction tagInternalTransfer(
  Transaction transaction, {
  UserTransferContext context = const UserTransferContext(),
}) {
  final category = transaction.category.trim();
  final hasExplicitCategory =
      category.isNotEmpty &&
      category.toUpperCase() != 'LIFESTYLE / MISC' &&
      category.toUpperCase() != 'UNCATEGORIZED';
  if (!isInternalTransfer(transaction.description, context: context) ||
      hasExplicitCategory ||
      category.toUpperCase() == 'TRANSFERS') {
    return transaction;
  }
  return transaction.copyWith(category: 'Transfers');
}
