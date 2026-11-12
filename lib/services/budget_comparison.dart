import '../models/transaction.dart';
import 'transaction_filter.dart';

int _cents(double amount) => (amount * 100).round();

enum BudgetOutcome { over, within, exact, uncertain }

/// Counts all recorded spending except explicitly unexpected expenses.
/// Unknown types stay included, including their signed refunds.
class BudgetSpending {
  BudgetSpending.fromAmounts({
    required double total,
    required double regular,
    double planned = 0,
    double unexpected = 0,
    double? unknownCharges,
    double? unknownRefunds,
  }) : totalCents = _cents(total),
       regularCents = _cents(regular),
       plannedCents = _cents(planned),
       unexpectedCents = _cents(unexpected),
       unknownChargesCents = _cents(
         unknownCharges ??
             (total - regular - planned - unexpected).clamp(0, double.infinity),
       ),
       unknownRefundsCents = _cents(
         unknownRefunds ??
             (total - regular - planned - unexpected).clamp(
               double.negativeInfinity,
               0,
             ),
       );

  factory BudgetSpending.fromTransactions(Iterable<Transaction> transactions) {
    final amounts = {for (final type in ExpenseType.values) type: 0};
    final seen = <String>{};
    var charges = 0;
    var refunds = 0;
    for (final t in transactions) {
      if (isTransferTransaction(t) ||
          (t.id != null && t.id!.isNotEmpty && !seen.add(t.id!))) {
        continue;
      }
      final amount = _cents(t.amount);
      amounts[t.expenseType] = amounts[t.expenseType]! + amount;
      if (t.expenseType == ExpenseType.unknown) {
        if (amount > 0) {
          charges += amount;
        } else {
          refunds += amount;
        }
      }
    }
    return BudgetSpending.fromAmounts(
      total: amounts.values.fold<int>(0, (a, b) => a + b) / 100,
      regular: amounts[ExpenseType.regular]! / 100,
      planned: amounts[ExpenseType.plannedOccasional]! / 100,
      unexpected: amounts[ExpenseType.unexpectedOccasional]! / 100,
      unknownCharges: charges / 100,
      unknownRefunds: refunds / 100,
    );
  }
  final int totalCents,
      regularCents,
      plannedCents,
      unexpectedCents,
      unknownChargesCents,
      unknownRefundsCents;
  double get total => totalCents / 100;
  double get regular => regularCents / 100;
  double get planned => plannedCents / 100;
  double get unexpected => unexpectedCents / 100;
  double get unknown =>
      (totalCents - regularCents - plannedCents - unexpectedCents) / 100;
  bool get hasUnknown => unknownChargesCents != 0 || unknownRefundsCents != 0;
  double get knownBudget => (regularCents + plannedCents) / 100;
  double get budgetRelevant => (totalCents - unexpectedCents) / 100;
  double get minimum => budgetRelevant;
  double get maximum => budgetRelevant;
  double get classifiedPercent =>
      totalCents <= 0 ? 0 : ((total - unknown) / total * 100).clamp(0, 100);
  double get unknownPercent =>
      totalCents <= 0 ? 0 : (unknown / total * 100).clamp(0, 100);
  String get coverageLabel => totalCents <= 0
      ? 'No spending to classify'
      : !hasUnknown
      ? 'Fully classified'
      : classifiedPercent < 80
      ? 'Preliminary classification'
      : classifiedPercent <= 95
      ? 'Most spending classified'
      : 'High classification coverage';
  BudgetOutcome outcome(double budget) {
    final b = _cents(budget);
    final spent = totalCents - unexpectedCents;
    if (spent > b) return BudgetOutcome.over;
    if (spent == b) return BudgetOutcome.exact;
    return BudgetOutcome.within;
  }

  double remaining(double budget) => (_cents(budget) - _cents(maximum)) / 100;
}
