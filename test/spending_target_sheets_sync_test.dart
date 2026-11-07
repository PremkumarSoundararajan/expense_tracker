import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:pocket_ledger/models/spending_target.dart';
import 'package:pocket_ledger/services/spending_target_store.dart';

SpendingTarget target(String id, {double amount = 100}) =>
    SpendingTarget.activate(
      type: SpendingTargetType.category,
      scopeId: id,
      name: id,
      average: amount,
      percentage: 25,
      effectiveDate: DateTime(2026, 12),
      now: DateTime(2026, 11, 6),
    );
List<Object?> row(SpendingTarget t) => [
  t.id,
  t.type.name,
  t.scopeId,
  t.name,
  t.historicalMonthlyAverage,
  t.reductionPercentage,
  t.monthlyAmount,
  t.effectiveDate.toIso8601String().split('T').first,
  t.active,
  t.updatedAt.toIso8601String(),
];
void main() {
  test('one batched append for activation, retry upserts IDs without duplicate records', () async {
    final rows = <List<Object?>>[SpendingTargetSheetsSyncService.headers];
    var appends = 0;
    var updates = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/book')) {
        return http.Response(
          jsonEncode({
            'sheets': [
              {
                'properties': {'title': 'Spending Targets'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({'values': rows}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (request.url.path.endsWith(':append')) {
        appends++;
        rows.addAll((body['values'] as List).map((r) => List<Object?>.from(r)));
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('values:batchUpdate')) {
        updates++;
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      fail('Unexpected ${request.method} ${request.url}');
    });
    final service = SpendingTargetSheetsSyncService();
    final api = sheets.SheetsApi(client);
    final first = await service.exchange(
      api: api,
      spreadsheetId: 'book',
      pending: [target('dining'), target('shopping')],
    );
    expect(first, hasLength(2));
    expect(appends, 1);
    expect(rows, hasLength(3));
    await service.exchange(
      api: api,
      spreadsheetId: 'book',
      pending: [target('dining')],
    );
    expect(appends, 1);
    expect(updates, 1);
    expect(rows, hasLength(3));
  });
  test(
    'duplicate healing keeps newest timestamp; malformed schema blocks writes',
    () async {
      final t = target('dining');
      final newer = t.revise(
        effectiveDate: t.effectiveDate,
        amount: 50,
        now: DateTime(2026, 11, 7),
      );
      final rows = [
        SpendingTargetSheetsSyncService.headers,
        row(t),
        row(newer),
      ];
      Map<String, dynamic>? written;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/book')) {
          return http.Response(
            jsonEncode({
              'sheets': [
                {
                  'properties': {'title': 'Spending Targets'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({'values': rows}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        written = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final result = await SpendingTargetSheetsSyncService().exchange(
        api: sheets.SheetsApi(client),
        spreadsheetId: 'book',
        pending: [],
      );
      expect(result.single.monthlyAmount, 50);
      expect(written!['data'], hasLength(2));
      rows[0] = ['Unexpected'];
      written = null;
      await expectLater(
        SpendingTargetSheetsSyncService().exchange(
          api: sheets.SheetsApi(client),
          spreadsheetId: 'book',
          pending: [t],
        ),
        throwsStateError,
      );
      expect(written, isNull);
    },
  );
}
