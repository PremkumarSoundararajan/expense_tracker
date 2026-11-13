import 'package:googleapis/sheets/v4.dart' as sheets;

import '../models/statement_source.dart';
import 'worker_csv_sync_service.dart';

class GoogleStatementTab {
  const GoogleStatementTab({required this.id, required this.title});
  final int id;
  final String title;
}

class GoogleStatementWorkbook {
  const GoogleStatementWorkbook({
    required this.id,
    required this.title,
    required this.tabs,
  });
  final String id;
  final String title;
  final List<GoogleStatementTab> tabs;
}

class GoogleSheetImportException implements Exception {
  const GoogleSheetImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads only the source sheet explicitly chosen by the user. Its ID is never
/// used as the destination ledger, and no source cells or permissions are changed.
class GoogleSheetStatementService {
  const GoogleSheetStatementService(this.api);
  final sheets.SheetsApi api;

  Future<T> _request<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on sheets.DetailedApiRequestError catch (error) {
      throw GoogleSheetImportException(switch (error.status) {
        401 => 'Reconnect your Google account, then try again.',
        403 => 'This Google account cannot read the sheet. Check its sharing access and Google Sheets permission.',
        404 => 'Sheet not found. Check the link and that it is shared with your signed-in Google account.',
        429 => 'Google is busy. Please wait a moment and try again.',
        _ => 'Could not read the Google Sheet. Please try again.',
      });
    }
  }

  Future<GoogleStatementWorkbook> loadWorkbook(String link) async {
    final id = normalizeSpreadsheetId(link);
    if (id == null || id.length < 20) {
      throw const GoogleSheetImportException(
        'Enter a valid Google Sheets link or spreadsheet ID.',
      );
    }
    final workbook = await _request(
      () => api.spreadsheets.get(
        id,
        $fields: 'properties(title),sheets(properties(sheetId,title,index,sheetType))',
      ),
    );
    final sourceTabs =
        (workbook.sheets ?? [])
            .where(
              (sheet) =>
                  sheet.properties?.sheetType == null ||
                  sheet.properties?.sheetType == 'GRID',
            )
            .toList()
          ..sort(
            (a, b) =>
                (a.properties?.index ?? 0).compareTo(b.properties?.index ?? 0),
          );
    final tabs = [
      for (final sheet in sourceTabs)
        if (sheet.properties?.sheetId != null &&
            (sheet.properties?.title?.isNotEmpty ?? false))
          GoogleStatementTab(
            id: sheet.properties!.sheetId!,
            title: sheet.properties!.title!,
          ),
    ];
    if (tabs.isEmpty) {
      throw const GoogleSheetImportException(
        'This spreadsheet has no readable worksheets.',
      );
    }
    return GoogleStatementWorkbook(
      id: id,
      title: workbook.properties?.title ?? 'Google Sheet',
      tabs: List.unmodifiable(tabs),
    );
  }

  Future<PreparedStatement> readWorksheet(
    GoogleStatementWorkbook workbook,
    GoogleStatementTab tab,
  ) async {
    if (!workbook.tabs.any(
      (item) => item.id == tab.id && item.title == tab.title,
    )) {
      throw const GoogleSheetImportException(
        'Choose a worksheet from this spreadsheet.',
      );
    }
    // Quoting the whole sheet name avoids confusing names like A1 with a cell
    // reference, and doubling apostrophes preserves names such as Bank's CSV.
    final range = "'${tab.title.replaceAll("'", "''")}'";
    final result = await _request(
      () => api.spreadsheets.values.get(
        workbook.id,
        range,
        valueRenderOption: 'FORMATTED_VALUE',
        dateTimeRenderOption: 'FORMATTED_STRING',
        majorDimension: 'ROWS',
        $fields: 'values',
      ),
    );
    final rows = <List<String>>[];
    for (final source in result.values ?? <List<Object?>>[]) {
      final row = source.map((cell) => cell?.toString() ?? '').toList();
      while (row.isNotEmpty && row.last.trim().isEmpty) {
        row.removeLast();
      }
      if (row.any((cell) => cell.trim().isNotEmpty)) rows.add(row);
    }
    if (rows.length < 2) {
      throw const GoogleSheetImportException(
        'This worksheet needs a header and at least one transaction row. Choose another worksheet.',
      );
    }
    return PreparedStatement(
      name: '${workbook.title} — ${tab.title}',
      csv: buildCsvFromRows(rows),
    );
  }
}
