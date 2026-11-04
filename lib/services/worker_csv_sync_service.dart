import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/transaction.dart';
import 'transaction_filter.dart';

class WorkerCsvSyncService {
  WorkerCsvSyncService(this._client);

  static final Uri endpoint = Uri.parse(
    'https://pocket-ledger-api.ledgerapi.workers.dev',
  );

  final http.Client _client;

  Future<http.Response> syncCsv({
    required String accessToken,
    required String spreadsheetId,
    required String csv,
    bool allowDuplicates = false,
    Map<String, Object?>? categoryConfig,
  }) async {
    return _sendCsv(
      accessToken: accessToken,
      spreadsheetId: spreadsheetId,
      csv: csv,
      action: 'import',
      allowDuplicates: allowDuplicates,
      categoryConfig: categoryConfig,
    );
  }

  Future<WorkerCsvPreview> previewCsv({
    required String accessToken,
    required String spreadsheetId,
    required String csv,
    Map<String, Object?>? categoryConfig,
  }) async {
    final capabilityResponse = await _client.get(endpoint);
    if (capabilityResponse.statusCode < 200 ||
        capabilityResponse.statusCode >= 300) {
      throw StateError(
        'The Cloudflare Worker must be deployed with statement review support '
        'before importing. No statement was imported.',
      );
    }
    final capabilities =
        jsonDecode(capabilityResponse.body) as Map<String, dynamic>;
    if (capabilities['reviewPreview'] != true) {
      throw StateError(
        'The Cloudflare Worker does not support statement review yet. '
        'No statement was imported.',
      );
    }
    if (capabilities['reviewedCategoryUpdates'] != true) {
      throw StateError(
        'The Cloudflare Worker needs an update before reviewed category '
        'changes can be saved to existing transactions. Deploy the latest '
        'pocket-ledger-api Worker and try again. No statement was imported.',
      );
    }

    final response = await _sendCsv(
      accessToken: accessToken,
      spreadsheetId: spreadsheetId,
      csv: csv,
      action: 'preview',
      categoryConfig: categoryConfig,
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return WorkerCsvPreview(
      spreadsheetId: payload['spreadsheetId']?.toString() ?? spreadsheetId,
      spreadsheetCreated: payload['spreadsheetCreated'] == true,
      rows: (payload['rows'] as List<dynamic>? ?? const [])
          .map(
            (row) => WorkerExpensePreview.fromJson(row as Map<String, dynamic>),
          )
          .toList(),
      filteredCount: payload['filtered'] as int? ?? 0,
      duplicateCount: payload['duplicates'] as int? ?? 0,
    );
  }

  Future<http.Response> _sendCsv({
    required String accessToken,
    required String spreadsheetId,
    required String csv,
    required String action,
    bool allowDuplicates = false,
    Map<String, Object?>? categoryConfig,
  }) async {
    if (accessToken.trim().isEmpty) {
      throw ArgumentError.value(
        accessToken,
        'accessToken',
        'Must not be empty.',
      );
    }
    if (spreadsheetId.trim().isEmpty) {
      throw ArgumentError.value(
        spreadsheetId,
        'spreadsheetId',
        'Must not be empty.',
      );
    }

    final request = http.Request('POST', endpoint)
      ..headers.addAll({
        'Authorization': 'Bearer $accessToken',
        'X-Spreadsheet-ID': spreadsheetId,
        'X-Action': action,
        if (allowDuplicates) 'X-Allow-Duplicates': 'true',
        if (categoryConfig != null)
          'X-Category-Config': base64Url.encode(
            utf8.encode(jsonEncode(categoryConfig)),
          ),
        'Content-Type': 'text/plain',
      })
      ..bodyBytes = utf8.encode(csv);
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WorkerCsvSyncException(response.statusCode, response.body);
    }
    return response;
  }

  void close() => _client.close();
}

const reviewExpenseCategoryOptions = <String>[
  'Food / Household',
  'Housing / Bills',
  'Transport',
  'Health & Wellness',
  'Lifestyle / Misc',
  'Financial Obligations',
  'Transfers',
];

class WorkerCsvPreview {
  const WorkerCsvPreview({
    required this.spreadsheetId,
    required this.spreadsheetCreated,
    required this.rows,
    required this.filteredCount,
    required this.duplicateCount,
  });

  final String spreadsheetId;
  final bool spreadsheetCreated;
  final List<WorkerExpensePreview> rows;
  final int filteredCount;
  final int duplicateCount;
}

class WorkerExpensePreview {
  const WorkerExpensePreview({
    required this.date,
    required this.amount,
    required this.category,
    required this.categoryMatched,
    required this.description,
    required this.expenseType,
    required this.duplicate,
    this.duplicateRow,
    this.existingCategory,
    this.importAnyway = false,
    this.categoryId,
    this.userEdited = false,
    this.rememberMapping = false,
  });

  final String date;
  final double amount;
  final String category;
  final bool categoryMatched;
  final String description;
  final String expenseType;
  final bool duplicate;
  final int? duplicateRow;
  final String? existingCategory;
  final bool importAnyway;
  final String? categoryId;
  final bool userEdited;
  final bool rememberMapping;

  bool get categoryChanged =>
      duplicate &&
      existingCategory != null &&
      category.trim().toLowerCase() != existingCategory!.trim().toLowerCase();
  bool get willImport => !duplicate || importAnyway || categoryChanged;

  factory WorkerExpensePreview.fromJson(Map<String, dynamic> json) {
    final description = json['description']?.toString() ?? '';
    final workerCategory = json['category']?.toString().trim() ?? '';
    return WorkerExpensePreview(
      date: json['date']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      category: workerCategory.isNotEmpty
          ? workerCategory
          : isInternalTransfer(description)
          ? 'Transfers'
          : 'Lifestyle / Misc',
      categoryMatched: json['categoryMatched'] == true,
      description: description,
      expenseType: json['expenseType']?.toString() ?? 'Regular',
      duplicate: json['duplicate'] == true,
      duplicateRow: (json['duplicateRow'] as num?)?.toInt(),
      existingCategory: json['existingCategory']?.toString(),
      categoryId: json['categoryId']?.toString(),
    );
  }

  WorkerExpensePreview withCategory(String value, {String? categoryId}) =>
      WorkerExpensePreview(
        date: date,
        amount: amount,
        category: value,
        categoryMatched: true,
        description: description,
        expenseType: expenseType,
        duplicate: duplicate,
        duplicateRow: duplicateRow,
        existingCategory: existingCategory,
        importAnyway: importAnyway,
        categoryId: categoryId ?? this.categoryId,
        userEdited: true,
      );

  WorkerExpensePreview withRememberMapping(bool value) => WorkerExpensePreview(
    date: date,
    amount: amount,
    category: category,
    categoryMatched: categoryMatched,
    description: description,
    expenseType: expenseType,
    duplicate: duplicate,
    duplicateRow: duplicateRow,
    existingCategory: existingCategory,
    importAnyway: importAnyway,
    categoryId: categoryId,
    userEdited: userEdited,
    rememberMapping: value,
  );

  WorkerExpensePreview withImportAnyway(bool value) => WorkerExpensePreview(
    date: date,
    amount: amount,
    category: category,
    categoryMatched: categoryMatched,
    description: description,
    expenseType: expenseType,
    duplicate: duplicate,
    duplicateRow: duplicateRow,
    existingCategory: existingCategory,
    importAnyway: value,
    categoryId: categoryId,
    userEdited: userEdited,
    rememberMapping: rememberMapping,
  );
}

String buildReviewedExpenseCsv(Iterable<WorkerExpensePreview> rows) {
  return buildCsvFromRows([
    [
      'Timestamp',
      'Amount',
      'Category',
      'Description',
      'Expense Type',
      'Import Anyway',
      'Category ID',
    ],
    for (final row in rows)
      [
        row.date,
        row.amount.toStringAsFixed(2),
        row.category,
        row.description,
        row.expenseType,
        row.importAnyway ? 'TRUE' : 'FALSE',
        row.categoryId ?? '',
      ],
  ]);
}

String buildExpenseCsv(Iterable<Transaction> transactions) {
  final rows = <List<String>>[
    [
      'Timestamp',
      'Amount',
      'Category',
      'Description',
      'Expense Type',
      'Transaction ID',
      'Category ID',
    ],
    for (final transaction in transactions)
      [
        transaction.dateOnlyIsoString,
        transaction.amount.toString(),
        transaction.category,
        transaction.description,
        transaction.expenseType.sheetValue,
        transaction.id ?? '',
        transaction.categoryId ?? '',
      ],
  ];

  return buildCsvFromRows(rows);
}

String buildCsvFromRows(Iterable<Iterable<String>> rows) =>
    rows.map((row) => row.map(_escapeCsvField).join(',')).join('\r\n');

String _escapeCsvField(String value) {
  if (!value.contains(',') &&
      !value.contains('"') &&
      !value.contains('\r') &&
      !value.contains('\n')) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}

String? normalizeSpreadsheetId(String input) {
  final value = input.trim();
  if (value.isEmpty) return null;

  final linkMatch = RegExp(
    r'https?://docs\.google\.com/spreadsheets/d/([^/?#]+)',
    caseSensitive: false,
  ).firstMatch(value);
  final id = linkMatch?.group(1) ?? value;
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) return null;
  return id;
}

class WorkerCsvSyncException implements Exception {
  const WorkerCsvSyncException(this.statusCode, this.responseBody);

  final int statusCode;
  final String responseBody;

  @override
  String toString() {
    final detail = responseBody.trim();
    if (detail.isEmpty) return 'Worker returned HTTP $statusCode.';
    final shortDetail = detail.length > 240
        ? '${detail.substring(0, 240)}…'
        : detail;
    return 'Worker returned HTTP $statusCode: $shortDetail';
  }
}
