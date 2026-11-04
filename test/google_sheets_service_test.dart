import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocket_ledger/services/google_sheets_service.dart';

void main() {
  group('GoogleSheetsService header validation', () {
    test('accepts expected transaction headers with trailing whitespace', () {
      GoogleSheetsService.validateHeaders(
        actual: [
          'Timestamp ',
          'Amount',
          'Category',
          'Description',
          'Expense Type',
          'Transaction ID',
          'Category ID',
        ],
        expected: GoogleSheetsService.transactionHeaders,
        range: 'Sheet1!A1:G1',
      );
    });
    test('reports missing headers and asks the user to verify the layout', () {
      expect(
        () => GoogleSheetsService.validateHeaders(
          actual: ['Timestamp', 'Amount', 'Category'],
          expected: GoogleSheetsService.transactionHeaders,
          range: 'Sheet1!A1:G1',
        ),
        throwsA(
          isA<GoogleSheetHeaderException>()
              .having((error) => error.range, 'range', 'Sheet1!A1:G1')
              .having(
                (error) => error.toString(),
                'message',
                allOf(
                  contains('Expected row 1 headers'),
                  contains('Transaction ID'),
                  contains('Verify that the connected sheet'),
                  contains('no data was read or written'),
                ),
              ),
        ),
      );
    });
    test('rejects modified baseline headers', () {
      expect(
        () => GoogleSheetsService.validateHeaders(
          actual: ['Merchant', 'Expense Type'],
          expected: GoogleSheetsService.baselineHeaders,
          range: "'Financial Baseline'!A1:B1",
        ),
        throwsA(isA<GoogleSheetHeaderException>()),
      );
    });
    test('accepts the legacy Type transaction header alias', () {
      GoogleSheetsService.validateHeaders(
        actual: [
          'Timestamp',
          'Amount',
          'Type',
          'Description',
          'Expense Type',
          'Transaction ID',
          'Category ID',
        ],
        expected: GoogleSheetsService.transactionHeaders,
        range: 'Sheet1!A1:G1',
        acceptedAlternatives: const {
          2: {'Type'},
        },
      );
    });
    test('rewrites the legacy Type header to Category', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'values': [
                [
                  'Timestamp',
                  'Amount',
                  'Type',
                  'Description',
                  'Expense Type',
                  'Transaction ID',
                  'Category ID',
                ],
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          '{"updatedCells":1}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await GoogleSheetsService().validateSheetHeaders(
        sheetsApi: sheets.SheetsApi(client),
        spreadsheetId: 'test-sheet',
        range: 'Sheet1!A1:G1',
        expected: GoogleSheetsService.transactionHeaders,
        acceptedAlternatives: const {
          2: {'Type'},
        },
        canonicalizationRanges: const {2: 'Sheet1!C1'},
      );
      client.close();
      expect(requests, hasLength(2));
      expect(requests[1].method, 'PUT');
      expect(Uri.decodeComponent(requests[1].url.path), contains('Sheet1!C1'));
      expect(jsonDecode(requests[1].body), {
        'values': [
          ['Category'],
        ],
      });
    });
    test('completes recognized missing trailing transaction headers', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'values': [
                ['Timestamp', 'Amount', 'Type', 'Description'],
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          '{"updatedCells":2}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await GoogleSheetsService().validateSheetHeaders(
        sheetsApi: sheets.SheetsApi(client),
        spreadsheetId: 'test-sheet',
        range: 'Sheet1!A1:G1',
        expected: GoogleSheetsService.transactionHeaders,
        acceptedAlternatives: const {
          2: {'Type'},
        },
        canonicalizationRanges: const {2: 'Sheet1!C1'},
        allowMissingTrailingHeaders: true,
        trailingHeaderCellRanges: const {
          4: 'Sheet1!E1',
          5: 'Sheet1!F1',
          6: 'Sheet1!G1',
        },
      );
      client.close();
      expect(requests, hasLength(3));
      expect(Uri.decodeComponent(requests[1].url.path), contains('Sheet1!C1'));
      expect(jsonDecode(requests[1].body)['values'], [
        ['Category'],
      ]);
      expect(Uri.decodeComponent(requests[2].url.path), contains('Sheet1!E1'));
      expect(jsonDecode(requests[2].body)['values'], [
        ['Expense Type', 'Transaction ID', 'Category ID'],
      ]);
    });
    test('sends multiple rows in a single append request', () async {
      var requestCount = 0;
      Map<String, dynamic>? payload;
      final client = MockClient((request) async {
        requestCount++;
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{"spreadsheetId":"test-sheet"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await GoogleSheetsService().appendRows(
        sheetsApi: sheets.SheetsApi(client),
        spreadsheetId: 'test-sheet',
        range: 'Sheet1!A1',
        valueInputOption: 'USER_ENTERED',
        rows: [
          [
            '2025-01-01',
            '20',
            'Transfers',
            'A2A',
            'Regular',
            'tx-1',
            'transfers',
          ],
          ['2025-01-02', '45', 'Food', 'Market', 'Regular', 'tx-2', 'food'],
        ],
      );
      client.close();
      expect(requestCount, 1);
      expect(payload?['values'], hasLength(2));
      expect(payload?['values'][0], [
        '2025-01-01',
        '20',
        'Transfers',
        'A2A',
        'Regular',
        'tx-1',
        'transfers',
      ]);
    });
  });
}
