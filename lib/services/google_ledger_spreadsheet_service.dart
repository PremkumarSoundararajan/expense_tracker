import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:shared_preferences/shared_preferences.dart';

import 'google_sheets_service.dart';

class GoogleLedgerSpreadsheetService {
  const GoogleLedgerSpreadsheetService({
    required this.driveApi,
    required this.sheetsApi,
    required this.preferences,
    required this.accountEmail,
  });

  final drive.DriveApi driveApi;
  final sheets.SheetsApi sheetsApi;
  final SharedPreferences preferences;
  final String accountEmail;

  Future<String> resolve() async {
    final account = accountEmail.trim().toLowerCase();
    final key = 'ledger_spreadsheet_id_$account';
    final pendingKey = 'ledger_spreadsheet_initializing_$account';
    final pending = preferences.getString(pendingKey);
    if (pending != null && pending.isNotEmpty) {
      await _save(key, pending);
      await _initialize(pending);
      if (!await preferences.remove(pendingKey)) {
        throw StateError('Could not save spreadsheet setup progress.');
      }
      return pending;
    }

    final saved = preferences.getString(key);
    if (saved != null && saved.isNotEmpty) return saved;

    // Older versions did not persist the ledger ID. Restrict migration to
    // app-accessible, owned sheets with the exact legacy database name.
    final matches = await driveApi.files.list(
      q: "name = 'Expense Tracker DB' and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false and 'me' in owners",
      $fields: 'nextPageToken,files(id)',
      pageSize: 2,
    );
    final files = matches.files ?? [];
    if (files.length > 1 || matches.nextPageToken != null) {
      throw StateError(
        'Multiple Expense Tracker DB spreadsheets were found. '
        'Resolve the duplicate databases in Google Drive before syncing.',
      );
    }
    if (files.isNotEmpty) {
      final id = files.single.id;
      if (id == null || id.isEmpty) {
        throw StateError('Google did not return a spreadsheet ID.');
      }
      await _save(key, id);
      return id;
    }

    final created = await sheetsApi.spreadsheets.create(
      sheets.Spreadsheet(
        properties: sheets.SpreadsheetProperties(title: 'Expense Tracker DB'),
      ),
    );
    final id = created.spreadsheetId;
    if (id == null || id.isEmpty) {
      throw StateError('Google did not return a spreadsheet ID.');
    }
    await _save(pendingKey, id);
    await _save(key, id);
    await _initialize(id);
    if (!await preferences.remove(pendingKey)) {
      throw StateError('Could not save spreadsheet setup progress.');
    }
    return id;
  }

  Future<void> _save(String key, String value) async {
    if (!await preferences.setString(key, value)) {
      throw StateError('Could not save the spreadsheet ID.');
    }
  }

  Future<void> _initialize(String id) async {
    await sheetsApi.spreadsheets.values.update(
      sheets.ValueRange(values: [GoogleSheetsService.transactionHeaders]),
      id,
      'Sheet1!A1:G1',
      valueInputOption: 'RAW',
    );
  }
}
