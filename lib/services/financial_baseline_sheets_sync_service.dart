import 'package:googleapis/sheets/v4.dart' as sheets;

import '../models/financial_baseline.dart';
import 'google_sheets_service.dart';

class FinancialBaselineSheetsSyncService {
  static const tabTitle = 'Financial Baseline';
  final GoogleSheetsService _googleSheetsService = GoogleSheetsService();

  Future<List<FinancialBaselineMapping>> loadMappings({
    required sheets.SheetsApi sheetsApi,
    required String spreadsheetId,
  }) async {
    await _ensureTab(sheetsApi, spreadsheetId);
    final response = await sheetsApi.spreadsheets.values.get(
      spreadsheetId,
      "'$tabTitle'!A2:B",
    );
    return [
      for (final row in response.values ?? const <List<Object?>>[])
        if (row.length >= 2 && row[0].toString().trim().isNotEmpty)
          FinancialBaselineMapping(
            merchantFingerprint: row[0].toString().trim(),
            group: BaselineGroup.parse(row[1]),
          ),
    ];
  }

  /// Ensures the tab exists and applies local mappings as idempotent upserts.
  /// Existing sheet rows not represented locally are preserved.
  Future<void> sync({
    required sheets.SheetsApi sheetsApi,
    required String spreadsheetId,
    required Iterable<FinancialBaselineMapping> mappings,
  }) async {
    await _ensureTab(sheetsApi, spreadsheetId);
    await _applyChanges(
      sheetsApi: sheetsApi,
      spreadsheetId: spreadsheetId,
      mappings: mappings,
    );
  }

  /// One values.batchUpdate call for the entire set of changed mappings.
  Future<void> syncChanges({
    required sheets.SheetsApi sheetsApi,
    required String spreadsheetId,
    required Iterable<FinancialBaselineMapping> mappings,
    Iterable<String> removedMerchants = const [],
  }) async {
    await _ensureTab(sheetsApi, spreadsheetId);
    await _applyChanges(
      sheetsApi: sheetsApi,
      spreadsheetId: spreadsheetId,
      mappings: mappings,
      removedMerchants: removedMerchants,
    );
  }

  Future<void> _ensureTab(sheets.SheetsApi api, String spreadsheetId) async {
    final spreadsheet = await api.spreadsheets.get(
      spreadsheetId,
      $fields: 'sheets.properties.title',
    );
    final hasTab =
        spreadsheet.sheets?.any(
          (sheet) => sheet.properties?.title == tabTitle,
        ) ??
        false;
    if (!hasTab) {
      await api.spreadsheets.batchUpdate(
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
      await api.spreadsheets.values.update(
        sheets.ValueRange(values: [GoogleSheetsService.baselineHeaders]),
        spreadsheetId,
        "'$tabTitle'!A1:B1",
        valueInputOption: 'RAW',
      );
    } else {
      await _googleSheetsService.validateSheetHeaders(
        sheetsApi: api,
        spreadsheetId: spreadsheetId,
        range: "'$tabTitle'!A1:B1",
        expected: GoogleSheetsService.baselineHeaders,
      );
    }
  }

  Future<void> _applyChanges({
    required sheets.SheetsApi sheetsApi,
    required String spreadsheetId,
    required Iterable<FinancialBaselineMapping> mappings,
    Iterable<String> removedMerchants = const [],
  }) async {
    final response = await sheetsApi.spreadsheets.values.get(
      spreadsheetId,
      "'$tabTitle'!A2:B",
    );
    final rows = response.values ?? const <List<Object?>>[];
    final rowByMerchant = <String, int>{};
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].isEmpty) continue;
      final name = rows[i][0].toString().trim();
      if (name.isNotEmpty) rowByMerchant[_key(name)] = i + 2;
    }

    final data = <sheets.ValueRange>[];
    var nextRow = rows.length + 2;
    final seen = <String>{};
    for (final mapping in mappings) {
      final merchant = mapping.merchantFingerprint.trim();
      if (merchant.isEmpty) continue;
      final key = _key(merchant);
      if (!seen.add(key)) continue;
      final row = rowByMerchant[key] ?? nextRow++;
      data.add(
        sheets.ValueRange(
          range: "'$tabTitle'!A$row:B$row",
          values: [
            [merchant, mapping.group.label],
          ],
        ),
      );
    }
    for (final merchant in removedMerchants) {
      final row = rowByMerchant[_key(merchant)];
      if (row != null) {
        data.add(
          sheets.ValueRange(
            range: "'$tabTitle'!A$row:B$row",
            values: [
              ['', ''],
            ],
          ),
        );
      }
    }
    if (data.isEmpty) return;
    await sheetsApi.spreadsheets.values.batchUpdate(
      sheets.BatchUpdateValuesRequest(valueInputOption: 'RAW', data: data),
      spreadsheetId,
    );
  }

  String _key(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
