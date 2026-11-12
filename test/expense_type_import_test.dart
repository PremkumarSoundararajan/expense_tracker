import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/local_transaction_store.dart';
import 'package:pocket_ledger/services/suggested_budget_service.dart';
import 'package:pocket_ledger/services/worker_csv_sync_service.dart';
import 'package:pocket_ledger/widgets/statement_review_dialog.dart';

void main() {
  test('missing, invalid and legacy values are Unknown; all valid values round trip', () {
    for (final value in [null, '', 'Occasional', 'bad']) {
      final row = Transaction.fromSheetRow([
        '2026-01-05',
        100,
        'Other',
        'Merchant',
        value,
      ]);
      expect(row.expenseType, ExpenseType.unknown);
      expect(Transaction.fromJson(row.toJson()).originalExpenseType, value);
    }
    for (final type in ExpenseType.values) {
      final row = Transaction(
        date: DateTime(2026, 1, 5),
        amount: 100,
        category: 'Other',
        expenseType: type,
      );
      expect(Transaction.fromJson(row.toJson()).expenseType, type);
      expect(
        Transaction.fromSheetRow([
          '2026-01-05',
          100,
          'Other',
          'Merchant',
          type.sheetValue,
        ]).expenseType,
        type,
      );
    }
  });
  test('legacy raw value survives cache, outbox, category edit and CSV synchronization', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalTransactionStore();
    final row = Transaction.fromSheetRow([
      '2026-01-05',
      100,
      'Other',
      'Merchant',
      'Occasional',
      'stable',
    ]);
    await store.saveCached([row]);
    await store.upsertPending(row.copyWith(category: 'Transport'));
    expect((await store.loadCached()).single.expenseType, ExpenseType.unknown);
    final pending = (await store.loadPending()).single;
    expect(pending.expenseTypeStorageValue, 'Occasional');
    expect(buildExpenseCsv([pending]), contains('Occasional'));
    expect(
      pending
          .copyWith(expenseType: ExpenseType.plannedOccasional)
          .expenseTypeStorageValue,
      'Planned Occasional',
    );
  });
  test('Unknown excluded from suggested budget with explicit coverage', () {
    final regular = [
      for (var m = 1; m <= 4; m++)
        Transaction(
          date: DateTime(2026, m, 1),
          amount: 100,
          category: 'Other',
          description: 'Subscription',
          expenseType: ExpenseType.regular,
        ),
    ];
    final service = SuggestedBudgetService();
    final base = service.suggest(
      transactions: regular,
      now: DateTime(2026, 5, 1),
    )!;
    final result = service.suggest(
      transactions: [
        ...regular,
        Transaction.fromSheetRow([
          '2026-04-05',
          9000,
          'Other',
          'Tax',
          'Occasional',
        ]),
      ],
      now: DateTime(2026, 5, 1),
    )!;
    expect(result.amount, base.amount);
    expect(result.unknownCount, 1);
    expect(result.unknownAmount, 9000);
  });
  test(
    'confirmed type survives category, duplicate toggles, and reviewed CSV',
    () {
      final row =
          WorkerExpensePreview.fromJson({
                'date': '2026-04-05',
                'amount': 100,
                'category': 'Other',
                'description': 'Shop',
                'expenseType': 'Unknown',
                'duplicate': true,
                'existingCategory': 'Other',
              })
              .withExpenseType('Unexpected Occasional')
              .withCategory('Transport')
              .withImportAnyway(false);
      expect(row.expenseType, 'Unexpected Occasional');
      expect(row.expenseTypeSource, 'Confirmed');
      expect(row.willImport, true);
      expect(
        buildReviewedExpenseCsv([row]),
        contains('Unexpected Occasional,TRUE,FALSE'),
      );
    },
  );
  testWidgets(
    'bulk assignment changes only selected rows and survives import',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      List<WorkerExpensePreview>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await showDialog<List<WorkerExpensePreview>>(
                    context: context,
                    builder: (_) => StatementReviewDialog(
                      fileName: 'test.csv',
                      currencySymbol: r'$',
                      preview: WorkerCsvPreview(
                        spreadsheetId: 'test',
                        spreadsheetCreated: false,
                        filteredCount: 0,
                        duplicateCount: 0,
                        rows: [
                          for (var i = 0; i < 3; i++)
                            WorkerExpensePreview(
                              date: '2026-04-05',
                              amount: 100,
                              category: 'Transport',
                              categoryMatched: true,
                              description: 'Shop $i',
                              expenseType: i == 2 ? 'Regular' : 'Unknown',
                              duplicate: false,
                            ),
                        ],
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('statement-edit-classifications')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unknown (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Shop 2'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('statement-select-0')),
      );
      await tester.tap(find.byKey(const ValueKey('statement-select-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('statement-bulk-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Planned Occasional').last);
      await tester.pumpAndSettle();
      expect(find.text('Unknown (1)'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('statement-review-confirm-import')),
      );
      await tester.pumpAndSettle();
      expect(saved![0].expenseType, 'Planned Occasional');
      expect(saved![1].expenseType, 'Unknown');
      expect(saved![2].expenseType, 'Regular');
      expect(tester.takeException(), isNull);
    },
  );
}
