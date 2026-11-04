import 'package:googleapis/sheets/v4.dart' as sheets;

import '../models/financial_baseline.dart';
import 'google_sheets_service.dart';

class FinancialBaselineSheetsSyncService {
  static const tabTitle = 'Financial Baseline';
  final GoogleSheetsService _googleSheetsService = GoogleSheetsService();

  Future<void> sync({
    required sheets.SheetsApi sheetsApi,
    required String spreadsheetId,
    required Iterable<FinancialBaselineMapping> mappings,
  }) async {
    final spreadsheet = await sheetsApi.spreadsheets.get(
      spreadsheetId,
      $fields: 'sheets.properties.title',
    );
    final hasTab =
        spreadsheet.sheets?.any(
          (sheet) => sheet.properties?.title == tabTitle,
        ) ??
        false;
    if (!hasTab) {
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
    } else {
      await _googleSheetsService.validateSheetHeaders(
        sheetsApi: sheetsApi,
        spreadsheetId: spreadsheetId,
        range: "'$tabTitle'!A1:B1",
        expected: GoogleSheetsService.baselineHeaders,
      );
    }

    final tabRange = "'$tabTitle'!A:Z";
    await sheetsApi.spreadsheets.values.clear(
      sheets.ClearValuesRequest(),
      spreadsheetId,
      tabRange,
    );
    final rows = <List<Object?>>[
      GoogleSheetsService.baselineHeaders,
      for (final mapping in mappings)
        [mapping.merchantFingerprint.trim(), mapping.group.label],
    ];
    await _googleSheetsService.appendRows(
      sheetsApi: sheetsApi,
      spreadsheetId: spreadsheetId,
      range: "'$tabTitle'!A1",
      rows: rows,
      valueInputOption: 'RAW',
    );
  }
}
