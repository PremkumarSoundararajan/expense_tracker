import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:pocket_ledger/services/google_sheet_statement_service.dart';

const sourceId = 'source_sheet_12345678901234567890';
const link =
    'https://docs.google.com/spreadsheets/d/$sourceId/edit?usp=sharing#gid=7';
http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
Map<String, Object> metadata({List<Map<String, Object>>? tabs}) => {
  'properties': {'title': 'Native bank statement'},
  'sheets':
      tabs ??
      [
        {
          'properties': {
            'sheetId': 7,
            'title': "Bank's transactions! A1",
            'index': 1,
            'sheetType': 'GRID',
          },
        },
        {
          'properties': {
            'sheetId': 0,
            'title': 'Cover',
            'index': 0,
            'sheetType': 'GRID',
          },
        },
        {
          'properties': {
            'sheetId': 9,
            'title': 'Chart',
            'index': 2,
            'sheetType': 'OBJECT',
          },
        },
      ],
};

void main() {
  test('private source uses Sheets GET only and loads worksheet metadata before values', () async {
    final calls = <http.Request>[];
    final client = MockClient((request) async {
      calls.add(request);
      return jsonResponse(metadata());
    });
    final service = GoogleSheetStatementService(sheets.SheetsApi(client));
    final workbook = await service.loadWorkbook(link);
    expect(workbook.id, sourceId);
    expect(workbook.title, 'Native bank statement');
    expect(workbook.tabs.map((tab) => tab.title), [
      'Cover',
      "Bank's transactions! A1",
    ]);
    expect(calls.length, 1);
    expect(calls.single.method, 'GET');
    expect(calls.single.url.host, 'sheets.googleapis.com');
    expect(calls.single.url.path, '/v4/spreadsheets/$sourceId');
    expect(calls.single.url.queryParameters['fields'], contains('properties'));
    client.close();
  });
  test('chosen worksheet becomes escaped CSV with formatted dates and amounts, not a source write', () async {
    final calls = <http.Request>[];
    final client = MockClient((request) async {
      calls.add(request);
      if (!request.url.path.contains('/values/')) {
        return jsonResponse(metadata());
      }
      return jsonResponse({
        'values': [
          ['Date', 'Description', 'Amount', ''],
          ['11/02/2026', 'Shop, "Central"', '1,234.50', null],
          ['11/03/2026', 'Two\nlines', 0],
          ['', null, ''],
        ],
      });
    });
    final service = GoogleSheetStatementService(sheets.SheetsApi(client));
    final workbook = await service.loadWorkbook(link);
    final statement = await service.readWorksheet(workbook, workbook.tabs.last);
    expect(
      Uri.decodeComponent(calls.last.url.path),
      "/v4/spreadsheets/$sourceId/values/'Bank''s transactions! A1'",
    );
    expect(
      calls.last.url.queryParameters['valueRenderOption'],
      'FORMATTED_VALUE',
    );
    expect(
      calls.last.url.queryParameters['dateTimeRenderOption'],
      'FORMATTED_STRING',
    );
    expect(
      statement.csv,
      'Date,Description,Amount\r\n11/02/2026,"Shop, ""Central""","1,234.50"\r\n11/03/2026,"Two\nlines",0',
    );
    expect(statement.name, "Native bank statement — Bank's transactions! A1");
    expect(calls.every((call) => call.method == 'GET'), isTrue);
    client.close();
  });
  test('sheet named A1 is quoted and raw spreadsheet IDs work', () async {
    final calls = <http.Request>[];
    final client = MockClient((request) async {
      calls.add(request);
      return request.url.path.contains('/values/')
          ? jsonResponse({
              'values': [
                ['Date', 'Amount'],
                ['2026-11-01', '20'],
              ],
            })
          : jsonResponse(
              metadata(
                tabs: [
                  {
                    'properties': {'sheetId': 0, 'title': 'A1'},
                  },
                ],
              ),
            );
    });
    final service = GoogleSheetStatementService(sheets.SheetsApi(client));
    final workbook = await service.loadWorkbook(sourceId);
    await service.readWorksheet(workbook, workbook.tabs.single);
    expect(Uri.decodeComponent(calls.last.url.path), endsWith("/values/'A1'"));
    client.close();
  });
  test('invalid link fails locally without a network request', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return jsonResponse({});
    });
    final service = GoogleSheetStatementService(sheets.SheetsApi(client));
    for (final input in [
      '',
      'not a link',
      'https://example.com/statement',
      'https://docs.google.com/spreadsheets/d/x/edit',
    ]) {
      await expectLater(
        service.loadWorkbook(input),
        throwsA(isA<GoogleSheetImportException>()),
      );
    }
    expect(calls, 0);
    client.close();
  });
  for (final status in [401, 403, 404, 429, 500]) {
    test(
      'Google $status is actionable and never exposes response contents',
      () async {
        final client = MockClient(
          (_) async => jsonResponse({
            'error': {'code': status, 'message': 'private server detail'},
          }, status),
        );
        final service = GoogleSheetStatementService(sheets.SheetsApi(client));
        await expectLater(
          service.loadWorkbook(link),
          throwsA(
            isA<GoogleSheetImportException>().having(
              (e) => e.message,
              'message',
              isNot(contains('private server detail')),
            ),
          ),
        );
        client.close();
      },
    );
  }
  test('empty workbook and header-only worksheet are rejected', () async {
    for (final values in [
      <List<Object?>>[],
      [
        ['Date', 'Amount'],
      ],
      [
        [' '],
        [''],
      ],
    ]) {
      final client = MockClient(
        (request) async => request.url.path.contains('/values/')
            ? jsonResponse({'values': values})
            : jsonResponse(metadata()),
      );
      final service = GoogleSheetStatementService(sheets.SheetsApi(client));
      final book = await service.loadWorkbook(link);
      await expectLater(
        service.readWorksheet(book, book.tabs.first),
        throwsA(isA<GoogleSheetImportException>()),
      );
      client.close();
    }
    final client = MockClient((_) async => jsonResponse(metadata(tabs: [])));
    await expectLater(
      GoogleSheetStatementService(sheets.SheetsApi(client)).loadWorkbook(link),
      throwsA(isA<GoogleSheetImportException>()),
    );
    client.close();
  });
  test('rejects a tab from another workbook before fetching values', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return jsonResponse(metadata());
    });
    final service = GoogleSheetStatementService(sheets.SheetsApi(client));
    final book = await service.loadWorkbook(link);
    await expectLater(
      service.readWorksheet(
        book,
        const GoogleStatementTab(id: 123, title: 'Elsewhere'),
      ),
      throwsA(isA<GoogleSheetImportException>()),
    );
    expect(calls, 1);
    client.close();
  });
}
