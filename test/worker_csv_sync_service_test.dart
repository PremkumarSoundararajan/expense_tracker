import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/worker_csv_sync_service.dart';

void main() {
  group('WorkerCsvSyncService', () {
    test(
      'preview returns replacement spreadsheet ID from Worker response',
      () async {
        final client = MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'status': 'ok',
                'reviewPreview': true,
                'reviewedCategoryUpdates': true,
                'expenseTypeReview': true,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'status': 'preview',
              'spreadsheetId': 'replacement-sheet-id',
              'spreadsheetCreated': true,
              'rows': [],
              'filtered': 0,
              'duplicates': 0,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        final service = WorkerCsvSyncService(client);

        final preview = await service.previewCsv(
          accessToken: 'active-user-token',
          spreadsheetId: 'deleted-sheet-id',
          csv: 'Date,Description,Amount',
        );

        expect(preview.spreadsheetId, 'replacement-sheet-id');
        expect(preview.spreadsheetCreated, isTrue);
        service.close();
      },
    );

    test(
      'posts raw CSV with the required authorization and target headers',
      () async {
        http.Request? request;
        const csv = 'Timestamp,Description\r\n2026-10-31,Café';
        final client = MockClient((incoming) async {
          request = incoming;
          return http.Response('Synced', 200);
        });
        final service = WorkerCsvSyncService(client);

        final response = await service.syncCsv(
          accessToken: 'active-user-token',
          spreadsheetId: 'target-sheet-id',
          csv: csv,
        );

        expect(response.statusCode, 200);
        expect(request!.method, 'POST');
        expect(request!.url, WorkerCsvSyncService.endpoint);
        expect(request!.headers['authorization'], 'Bearer active-user-token');
        expect(request!.headers['x-spreadsheet-id'], 'target-sheet-id');
        expect(request!.headers['content-type'], 'text/plain');
        expect(utf8.decode(request!.bodyBytes), csv);
        service.close();
      },
    );

    test('reports non-success responses', () async {
      final service = WorkerCsvSyncService(
        MockClient((_) async => http.Response('No access', 403)),
      );

      await expectLater(
        service.syncCsv(
          accessToken: 'active-user-token',
          spreadsheetId: 'target-sheet-id',
          csv: 'Timestamp,Amount',
        ),
        throwsA(
          isA<WorkerCsvSyncException>()
              .having((error) => error.statusCode, 'statusCode', 403)
              .having(
                (error) => error.toString(),
                'message',
                contains('No access'),
              ),
        ),
      );
      service.close();
    });
  });

  group('buildExpenseCsv', () {
    test('uses the ledger columns and safely escapes descriptions', () {
      final csv = buildExpenseCsv([
        Transaction(
          date: DateTime(2026, 10, 31),
          amount: 12.5,
          category: 'Food / Household',
          description: 'Market, "Downtown"\nreceipt',
          expenseType: ExpenseType.plannedOccasional,
          id: 'expense-1',
        ),
      ]);

      expect(
        csv,
        'Timestamp,Amount,Category,Description,Expense Type,Transaction ID,Category ID'
        '\r\n2026-10-31,12.5,Food / Household,'
        '"Market, ""Downtown""\nreceipt",Planned Occasional,expense-1,',
      );
    });

    test('exports an empty ledger as a header-only CSV', () {
      expect(
        buildExpenseCsv(const []),
        'Timestamp,Amount,Category,Description,Expense Type,Transaction ID,Category ID',
      );
    });

    test('preserves explicitly reviewed spending categories on transfer-like descriptions', () {
      final transactionCsv = buildExpenseCsv([
        Transaction(
          date: DateTime(2026, 10, 31),
          amount: 125,
          category: 'Financial Obligations',
          description: 'FID BKG SVC LLC DES:MONEYLINE',
          id: 'transfer-1',
        ),
      ]);
      final reviewedCsv = buildReviewedExpenseCsv([
        const WorkerExpensePreview(
          date: '2026-10-31',
          amount: 125,
          category: 'Housing / Bills',
          categoryMatched: true,
          description: 'FID BKG SVC LLC DES:MONEYLINE',
          expenseType: 'Regular',
          duplicate: false,
        ),
      ]);

      expect(transactionCsv, contains('125.0,Financial Obligations,'));
      expect(reviewedCsv, contains('125.00,Housing / Bills,'));
    });
  });

  test('transfer review category is available as a stable dropdown value', () {
    expect(reviewExpenseCategoryOptions, contains('Transfers'));
  });

  group('normalizeSpreadsheetId', () {
    test('accepts a pasted spreadsheet URL and a raw ID', () {
      expect(
        normalizeSpreadsheetId(
          'https://docs.google.com/spreadsheets/d/sheet_123-abc/edit#gid=0',
        ),
        'sheet_123-abc',
      );
      expect(normalizeSpreadsheetId('sheet_123-abc'), 'sheet_123-abc');
    });

    test('rejects empty or malformed targets', () {
      expect(normalizeSpreadsheetId('  '), isNull);
      expect(normalizeSpreadsheetId('https://example.com/not-a-sheet'), isNull);
      expect(normalizeSpreadsheetId('id with spaces'), isNull);
    });
  });
}
