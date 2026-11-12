import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/merchant_na_service.dart';
import 'package:pocket_ledger/services/merchant_classification_service.dart';
import 'package:pocket_ledger/services/merchant_classification_store.dart';
import 'package:pocket_ledger/services/worker_csv_sync_service.dart';
import 'package:pocket_ledger/widgets/statement_import_complete_dialog.dart';
import 'package:pocket_ledger/widgets/statement_review_dialog.dart';

Transaction tx(
  String id,
  double amount, {
  String description = 'Corner Shop #100',
}) => Transaction(
  id: id,
  date: DateTime(2026, 10, 1),
  amount: amount,
  description: description,
  category: 'Other',
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('ambiguous merchant aliases stay unresolved instead of being bulk excluded', () {
    final rules = [
      merchantNaPolicyRecord(100),
      for (final id in ['m:a','m:b']) {'id': id, 'kind': 'merchant', 'aliases': ['Corner Shop #100']},
    ];
    expect(reconcileMerchantNaPolicy(rules, [tx('one', 20)]), isEmpty);
  });
  test('saved exclusion policy applies to future merchants and expiry uses cumulative unique spending', () {
    final policy = merchantNaPolicyRecord(100);
    final first = reconcileMerchantNaPolicy([policy], [tx('one', 70)]);
    expect(first.single['na'], true);
    expect(first.single['naThreshold'], 100);
    final records = [policy, ...first];
    expect(
      reconcileMerchantNaPolicy(records, [tx('one', 70), tx('one', 70)]),
      isEmpty,
    );
    expect(
      reconcileMerchantNaPolicy(records, [tx('one', 70), tx('two', 29.99)]),
      isEmpty,
    );
    final expired = reconcileMerchantNaPolicy(records, [
      tx('one', 70),
      tx('two', 30, description: 'Corner Shop #200'),
    ]).single;
    expect(expired['na'], false);
    expect(expired['category'], 'Uncategorized');
    expect(expired['expenseType'], 'Unknown');
    expect(expired['group'], 'Unclassified');
    expect(expired['naReviewRequired'], true);
    expect(
      reconcileMerchantNaPolicy([policy, expired], [tx('one', 70)]),
      isEmpty,
    );
    final next = reconcileMerchantNaPolicy(records, [
      tx('one', 70),
      tx('new', 15, description: 'New Merchant'),
    ]);
    expect(next.single['na'], true);
  });
  test('classified merchants, manual opt-outs and transaction exceptions are preserved', () {
    final policy = merchantNaPolicyRecord(100);
    final classified = {
      'id': 'm:corner',
      'kind': 'merchant',
      'name': 'Corner Shop',
      'aliases': ['Corner Shop #100'],
      'category': 'Groceries',
      'categoryId': 'groceries',
      'expenseType': 'Regular',
      'group': 'Essential',
    };
    expect(
      reconcileMerchantNaPolicy([policy, classified], [tx('one', 70)]),
      isEmpty,
    );
    final excluded = reconcileMerchantNaPolicy(
      [policy],
      [tx('one', 70)],
    ).single;
    final exception = {
      'id': 't:one',
      'kind': 'transaction',
      'transactionId': 'one',
      'category': 'Medical',
      'expenseType': 'Unexpected Occasional',
      'group': 'Essential',
    };
    final expired = reconcileMerchantNaPolicy(
      [policy, excluded, exception],
      [tx('one', 70), tx('two', 40)],
    ).single;
    final index = MerchantClassificationIndex([policy, expired, exception]);
    expect(index.apply(tx('one', 70)).category, 'Medical');
    expect(index.apply(tx('two', 40)).category, 'Uncategorized');
    final removed = removeMerchantNa(
      excluded,
      MerchantClassificationIndex([excluded]),
    );
    expect(
      reconcileMerchantNaPolicy([policy, ...removed], [tx('one', 70)]),
      isEmpty,
    );
  });
  test('legacy unknown limits are not guessed; saving a policy adopts and enforces it', () {
    final legacy = reconcileMerchantNaPolicy(
      [merchantNaPolicyRecord(100)],
      [tx('one', 70)],
    ).single..remove('naThreshold');
    expect(reconcileMerchantNaPolicy([legacy], [tx('one', 120)]), isEmpty);
    expect(
      reconcileMerchantNaPolicy(
        [legacy, merchantNaPolicyRecord(100)],
        [tx('one', 120)],
      ).single['na'],
      false,
    );
  });
  test('full-sheet synchronization persists expiry and updates classification cells without overwriting exceptions', () async {
    final policy = merchantNaPolicyRecord(100);
    final excluded = reconcileMerchantNaPolicy(
      [policy],
      [tx('one', 70)],
    ).single;
    final store = MerchantClassificationStore('policy-test');
    await store.save([policy, excluded]);
    final writes = <dynamic>[];
    final client = MockClient((r) async {
      final path = Uri.decodeComponent(r.url.path);
      if (r.method == 'POST') {
        final body = jsonDecode(r.body);
        if (body['data'] is List) writes.addAll(body['data']);
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('Sheet1!F2:F'))
        return http.Response(
          jsonEncode({
            'values': [
              ['one'],
              ['two'],
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      if (path.contains('/values/'))
        return http.Response(
          jsonEncode({
            'values': [
              ['Record ID', 'Classification'],
              [policy['id'], jsonEncode(policy)],
              [excluded['id'], jsonEncode(excluded)],
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      return http.Response(
        jsonEncode({
          'sheets': [
            {
              'properties': {'title': MerchantClassificationStore.tab},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    await store.synchronize(sheets.SheetsApi(client), 'sheet', [
      tx('one', 70).copyWith(category: 'NA'),
      tx('two', 40).copyWith(category: 'NA'),
    ]);
    expect(store.records[excluded['id']]!['na'], false);
    expect(
      writes.any(
        (w) =>
            w['range'] == 'Sheet1!C2' && w['values'][0][0] == 'Uncategorized',
      ),
      true,
    );
    expect(store.index.apply(tx('two', 40)).expenseType, ExpenseType.unknown);
    expect(store.pending, isEmpty);
  });
  testWidgets(
    'confirmation starts without dropdowns and successful import offers optional merchant classification',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatementReviewDialog(
              fileName: 'test.csv',
              currencySymbol: r'$',
              preview: WorkerCsvPreview(
                spreadsheetId: 'sheet',
                spreadsheetCreated: false,
                filteredCount: 0,
                duplicateCount: 0,
                rows: [
                  WorkerExpensePreview(
                    date: '2026-10-01',
                    amount: 10,
                    category: 'Other',
                    categoryMatched: false,
                    description: 'Shop',
                    expenseType: 'Unknown',
                    duplicate: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Confirm statement import'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('Confirm & Import'), findsOneWidget);
      bool? classify;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  classify = await showDialog<bool>(
                    context: context,
                    builder: (_) => const StatementImportCompleteDialog(
                      summary: 'Imported 10 transactions.',
                    ),
                  );
                },
                child: const Text('Complete'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Complete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Classify merchants'));
      await tester.pumpAndSettle();
      expect(classify, true);
    },
  );
  test(
    'inherited category changes never make an unedited duplicate importable',
    () {
      const row = WorkerExpensePreview(
        date: '2026-10-01',
        amount: 10,
        category: 'Groceries',
        existingCategory: 'Other',
        categoryMatched: true,
        description: 'Shop',
        expenseType: 'Regular',
        duplicate: true,
      );
      expect(row.willImport, false);
      expect(row.withCategory('Medical').willImport, true);
    },
  );
}
