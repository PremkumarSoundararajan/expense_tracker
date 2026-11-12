import 'dart:convert';
import 'dart:math';

enum ExpenseType {
  regular,
  plannedOccasional,
  unexpectedOccasional,
  unknown;

  String get sheetValue {
    switch (this) {
      case ExpenseType.regular:
        return 'Regular';
      case ExpenseType.plannedOccasional:
        return 'Planned Occasional';
      case ExpenseType.unexpectedOccasional:
        return 'Unexpected Occasional';
      case ExpenseType.unknown:
        return 'Unknown';
    }
  }

  static ExpenseType parse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    switch (normalized) {
      case 'planned occasional':
      case 'plannedoccasional':
      case 'planned':
        return ExpenseType.plannedOccasional;
      case 'unexpected occasional':
      case 'unexpectedoccasional':
      case 'unexpected':
        return ExpenseType.unexpectedOccasional;
      case 'regular':
        return ExpenseType.regular;
      default:
        return ExpenseType.unknown;
    }
  }
}

class Transaction {
  final DateTime date;
  final double amount;
  final String category;
  final String description;
  final ExpenseType expenseType;
  final String? originalExpenseType;
  String get expenseTypeStorageValue => expenseType == ExpenseType.unknown
      ? (originalExpenseType ?? expenseType.sheetValue)
      : expenseType.sheetValue;
  final String? id;
  final int? sheetRow;
  final String? categoryId;
  final String? baselineGroup;

  const Transaction({
    required this.date,
    required this.amount,
    required this.category,
    this.description = '',
    this.expenseType = ExpenseType.unknown,
    this.originalExpenseType,
    this.id,
    this.sheetRow,
    this.categoryId,
    this.baselineGroup,
  });

  String get dateOnlyIsoString => date.toIso8601String().split('T').first;

  static Transaction? tryParseSheetRow(List<Object?> row) {
    if (row.length < 2) return null;
    final date = _tryParseDate(row[0]);
    final amount = _parseAmount(row[1]);
    if (date == null || amount == null || !amount.isFinite) return null;
    return Transaction(
      date: date,
      amount: amount,
      category: row.length > 2 ? row[2].toString() : '',
      description: row.length > 3 ? row[3].toString() : '',
      expenseType: ExpenseType.parse(row.length > 4 ? row[4] : null),
      originalExpenseType: row.length > 4 ? row[4]?.toString() : null,
      id: row.length > 5 && row[5].toString().trim().isNotEmpty
          ? row[5].toString().trim()
          : null,
      categoryId: row.length > 6 && row[6].toString().trim().isNotEmpty
          ? row[6].toString().trim()
          : null,
    );
  }

  static String createId() {
    final random = Random.secure();
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final entropy = List.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return '$time-$entropy';
  }

  factory Transaction.fromSheetRow(List<Object?> row, {int? sheetRow}) {
    return Transaction(
      date: _parseDate(row.isNotEmpty ? row[0] : null),
      amount: _parseAmount(row.length > 1 ? row[1] : null) ?? 0,
      category: row.length > 2 ? row[2].toString() : '',
      description: row.length > 3 ? row[3].toString() : '',
      expenseType: ExpenseType.parse(row.length > 4 ? row[4] : null),
      originalExpenseType: row.length > 4 ? row[4]?.toString() : null,
      id: row.length > 5 && row[5].toString().trim().isNotEmpty
          ? row[5].toString().trim()
          : null,
      categoryId: row.length > 6 && row[6].toString().trim().isNotEmpty
          ? row[6].toString().trim()
          : null,
      sheetRow: sheetRow,
    );
  }
  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      date: _parseDate(json['date']),
      amount: _parseAmount(json['amount']) ?? 0,
      category: json['category']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      expenseType: ExpenseType.parse(json['expenseType']),
      originalExpenseType: json.containsKey('originalExpenseType')
          ? json['originalExpenseType']?.toString()
          : json['expenseType']?.toString(),
      id: json['id']?.toString(),
      sheetRow: (json['sheetRow'] as num?)?.toInt(),
      categoryId: json['categoryId']?.toString(),
      baselineGroup: json['baselineGroup']?.toString(),
    );
  }

  Transaction copyWith({
    DateTime? date,
    double? amount,
    String? category,
    String? description,
    ExpenseType? expenseType,
    String? categoryId,
    String? baselineGroup,
    bool clearBaselineGroup = false,
  }) {
    return Transaction(
      date: date ?? this.date,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      description: description ?? this.description,
      expenseType: expenseType ?? this.expenseType,
      originalExpenseType: expenseType == null ? originalExpenseType : null,
      id: id,
      sheetRow: sheetRow,
      categoryId: categoryId ?? this.categoryId,
      baselineGroup: clearBaselineGroup
          ? null
          : baselineGroup ?? this.baselineGroup,
    );
  }

  Map<String, Object?> toJson() => {
    'date': dateOnlyIsoString,
    'amount': amount,
    'category': category,
    'description': description,
    'expenseType': expenseType.sheetValue,
    'originalExpenseType': originalExpenseType,
    'id': id,
    'sheetRow': sheetRow,
    'categoryId': categoryId,
    'baselineGroup': baselineGroup,
  };

  String toJsonString() => jsonEncode(toJson());

  static DateTime _parseDate(Object? value) {
    return _tryParseDate(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static double? _parseAmount(Object? value) {
    if (value is num) return value.toDouble().abs();
    final text = value?.toString().trim() ?? '';
    final normalized = text
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^0-9eE+.-]'), '');
    return double.tryParse(normalized)?.abs();
  }

  static DateTime? _tryParseDate(Object? value) {
    if (value is DateTime) return value;
    if (value is num && value.isFinite) {
      return DateTime(1899, 12, 30).add(
        Duration(microseconds: (value * Duration.microsecondsPerDay).round()),
      );
    }

    final text = value?.toString().trim() ?? '';
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return parsed;
    final serialDate = double.tryParse(text);
    if (serialDate != null &&
        serialDate.isFinite &&
        serialDate >= 1 &&
        serialDate <= 100000) {
      return DateTime(1899, 12, 30).add(
        Duration(
          microseconds: (serialDate * Duration.microsecondsPerDay).round(),
        ),
      );
    }

    final formattedDate = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?)?$',
      caseSensitive: false,
    ).firstMatch(text);
    if (formattedDate == null) return null;

    final month = int.parse(formattedDate[1]!);
    final day = int.parse(formattedDate[2]!);
    final year = int.parse(formattedDate[3]!);
    var hour = int.tryParse(formattedDate[4] ?? '') ?? 0;
    final minute = int.tryParse(formattedDate[5] ?? '') ?? 0;
    final second = int.tryParse(formattedDate[6] ?? '') ?? 0;
    final meridiem = formattedDate[7]?.toUpperCase();
    if (meridiem != null) {
      if (hour < 1 || hour > 12) return null;
      if (meridiem == 'AM' && hour == 12) hour = 0;
      if (meridiem == 'PM' && hour != 12) hour += 12;
    }
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > DateTime(year, month + 1, 0).day ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      return null;
    }
    return DateTime(year, month, day, hour, minute, second);
  }
}
