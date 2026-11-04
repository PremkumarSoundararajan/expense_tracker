import '../models/transaction.dart';

int countTransactionsOnDate(
  Iterable<Transaction> transactions,
  DateTime date,
) {
  return transactions.where((transaction) {
    final transactionDate = transaction.date;
    return transactionDate.year == date.year &&
        transactionDate.month == date.month &&
        transactionDate.day == date.day;
  }).length;
}

String formatExpenseCount(int count) {
  if (count <= 0) return 'No expenses recorded today';
  return '$count expense${count == 1 ? '' : 's'} recorded';
}

const _shortMonthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

DateTime monthStart(DateTime date) => DateTime(date.year, date.month);

DateTime nextMonthStart(DateTime date) => DateTime(date.year, date.month + 1);

bool isSameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

String formatMonthYearShort(DateTime month) =>
    '${_shortMonthNames[month.month - 1]} ${month.year % 100}';

String formatMonthHeading(DateTime month, {DateTime? now}) {
  final current = now ?? DateTime.now();
  if (isSameMonth(month, current)) return 'THIS MONTH';
  return '${_shortMonthNames[month.month - 1].toUpperCase()} ${month.year}';
}

List<DateTime> availableLedgerMonths(
  Iterable<Transaction> transactions, {
  DateTime? now,
  int limit = 12,
}) {
  final current = now ?? DateTime.now();
  final months = <DateTime>{monthStart(current)};
  for (final transaction in transactions) {
    months.add(monthStart(transaction.date));
  }
  final sorted = months.toList()..sort((a, b) => b.compareTo(a));
  if (sorted.length <= limit) return sorted;
  return sorted.take(limit).toList(growable: false);
}
