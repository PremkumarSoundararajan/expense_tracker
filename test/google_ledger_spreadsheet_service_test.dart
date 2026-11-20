import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocket_ledger/services/google_ledger_spreadsheet_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const key = 'ledger_spreadsheet_id_owner@example.com';
  http.Response jsonResponse(String body, [int status = 200]) => http.Response(
    body,
    status,
    headers: {'content-type': 'application/json'},
  );

  test('uses the saved ID without listing or accessing other files', () async {
    SharedPreferences.setMockInitialValues({key: 'saved'});
    final client = MockClient(
      (_) async => throw StateError('Unexpected request'),
    );
    final service = GoogleLedgerSpreadsheetService(
      driveApi: drive.DriveApi(client),
      sheetsApi: sheets.SheetsApi(client),
      preferences: await SharedPreferences.getInstance(),
      accountEmail: 'owner@example.com',
    );
    expect(await service.resolve(), 'saved');
    client.close();
  });

  test('migrates only one matching app ledger and persists its ID', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <http.Request>[];
    final client = MockClient((request) async {
      calls.add(request);
      return jsonResponse(
        jsonEncode({
          'files': [
            {'id': 'existing'},
          ],
        }),
        200,
      );
    });
    final prefs = await SharedPreferences.getInstance();
    final service = GoogleLedgerSpreadsheetService(
      driveApi: drive.DriveApi(client),
      sheetsApi: sheets.SheetsApi(client),
      preferences: prefs,
      accountEmail: 'owner@example.com',
    );
    expect(await service.resolve(), 'existing');
    expect(await service.resolve(), 'existing');
    expect(prefs.getString(key), 'existing');
    expect(calls, hasLength(1));
    expect(
      calls.single.url.queryParameters['q'],
      contains("name = 'Expense Tracker DB'"),
    );
    expect(calls.single.url.queryParameters['q'], contains("'me' in owners"));
    client.close();
  });

  test('does not choose between multiple matching ledgers', () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient(
      (_) async => jsonResponse(
        jsonEncode({
          'files': [
            {'id': 'one'},
            {'id': 'two'},
          ],
        }),
        200,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    final service = GoogleLedgerSpreadsheetService(
      driveApi: drive.DriveApi(client),
      sheetsApi: sheets.SheetsApi(client),
      preferences: prefs,
      accountEmail: 'owner@example.com',
    );
    await expectLater(service.resolve(), throwsStateError);
    expect(prefs.getString(key), isNull);
    client.close();
  });

  test('retries initializing a newly created ledger by its saved ID', () async {
    SharedPreferences.setMockInitialValues({});
    var failInitialization = true;
    final calls = <http.Request>[];
    final client = MockClient((request) async {
      calls.add(request);
      if (request.url.host == 'www.googleapis.com' && request.method == 'GET') {
        return jsonResponse('{"files":[]}');
      }
      if (request.method == 'POST') {
        return jsonResponse('{"spreadsheetId":"new"}');
      }
      return failInitialization
          ? jsonResponse('{"error":{"message":"offline"}}', 503)
          : jsonResponse('{}');
    });
    final prefs = await SharedPreferences.getInstance();
    final service = GoogleLedgerSpreadsheetService(
      driveApi: drive.DriveApi(client),
      sheetsApi: sheets.SheetsApi(client),
      preferences: prefs,
      accountEmail: 'owner@example.com',
    );
    await expectLater(service.resolve(), throwsA(anything));
    expect(prefs.getString(key), 'new');
    failInitialization = false;
    expect(await service.resolve(), 'new');
    expect(calls.where((r) => r.method == 'POST'), hasLength(1));
    expect(calls.last.url.path, contains('/new/values/'));
    client.close();
  });
}
