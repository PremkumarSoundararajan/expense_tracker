import 'dart:convert';

import 'package:googleapis/sheets/v4.dart' as sheets;

import '../models/expense_category.dart';

class ExpenseCategorySheetsSyncService {
  static const tabTitle = 'Expense Categories';
  static const headers = ['Configuration'];

  Future<Map<String, Object?>> sync({
    required sheets.SheetsApi sheetsApi,
    required String spreadsheetId,
    required List<ExpenseCategory> categories,
    required List<ExpenseCategoryMapping> mappings,
    bool preferLocal = false,
  }) async {
    final spreadsheet = await sheetsApi.spreadsheets.get(
      spreadsheetId,
      $fields: 'sheets.properties.title',
    );
    final exists =
        spreadsheet.sheets?.any((s) => s.properties?.title == tabTitle) ??
        false;
    if (!exists) {
      await sheetsApi.spreadsheets.batchUpdate(
        sheets.BatchUpdateSpreadsheetRequest(
          requests: [
            sheets.Request(
              addSheet: sheets.AddSheetRequest(
                properties: sheets.SheetProperties(title: tabTitle),
              ),
            ),
          ],
        ),
        spreadsheetId,
      );
      await sheetsApi.spreadsheets.values.update(
        sheets.ValueRange(values: [headers]),
        spreadsheetId,
        "'$tabTitle'!A1",
        valueInputOption: 'RAW',
      );
    }
    final read = await sheetsApi.spreadsheets.values.get(
      spreadsheetId,
      "'$tabTitle'!A1:A2",
    );
    final remote = read.values != null && read.values!.length > 1
        ? read.values![1].firstOrNull?.toString()
        : null;
    if (!preferLocal && remote != null && remote.trim().isNotEmpty) {
      final decoded = jsonDecode(remote) as Map<String, dynamic>;
      return {
        'categories': (decoded['categories'] as List? ?? const [])
            .whereType<Map>()
            .map((r) => ExpenseCategory.fromJson(Map<String, dynamic>.from(r)))
            .toList(),
        'mappings': (decoded['mappings'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (r) =>
                  ExpenseCategoryMapping.fromJson(Map<String, dynamic>.from(r)),
            )
            .toList(),
      };
    }
    final config = jsonEncode({
      'version': 1,
      'categories': categories.map((c) => c.toJson()).toList(),
      'mappings': mappings.map((m) => m.toJson()).toList(),
    });
    await sheetsApi.spreadsheets.values.update(
      sheets.ValueRange(
        values: [
          [config],
        ],
      ),
      spreadsheetId,
      "'$tabTitle'!A2",
      valueInputOption: 'RAW',
    );
    return {'categories': categories, 'mappings': mappings};
  }
}
