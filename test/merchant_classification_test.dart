import 'support/baseline_navigation.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/models/financial_baseline.dart';
import 'package:pocket_ledger/services/merchant_classification_service.dart';
import 'package:pocket_ledger/services/worker_csv_sync_service.dart';
import 'package:pocket_ledger/services/merchant_classification_store.dart';
import 'package:pocket_ledger/services/financial_baseline_service.dart';
import 'package:pocket_ledger/services/favourite_spending_spots_service.dart';
import 'package:pocket_ledger/widgets/merchant_baseline_panel.dart';

Map<String, dynamic> rule({
  String category = 'Food',
  String group = 'Essential',
}) => {
  'id': 'm:market',
  'kind': 'merchant',
  'name': 'Market',
  'aliases': ['MARKET REF 100'],
  'category': category,
  'categoryId': category.toLowerCase(),
  'group': group,
};
Transaction transaction({
  String id = 'tx',
  int row = 7,
  String description = 'MARKET REF 200',
  double amount = 100,
}) => Transaction(
  id: id,
  sheetRow: row,
  date: DateTime(2026, 10, 5),
  amount: amount,
  category: 'Other',
  categoryId: 'other',
  description: description,
  expenseType: ExpenseType.plannedOccasional,
);
const categories = [
  ExpenseCategory(id: 'food', parentId: 'food-household', name: 'Food'),
  ExpenseCategory(id: 'shopping', parentId: 'lifestyle-misc', name: 'Shopping'),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('merchant aliases match new references; explicit exceptions win and Expense Type is preserved', () {
    final records = [
      rule(),
      {
        'id': 't:tx',
        'kind': 'transaction',
        'transactionId': 'tx',
        'category': 'Shopping',
        'categoryId': 'shopping',
        'group': 'Potentially Flexible',
      },
    ];
    final effective = MerchantClassificationIndex(records).apply(transaction());
    expect(effective.category, 'Shopping');
    expect(effective.baselineGroup, 'Potentially Flexible');
    expect(effective.expenseType, ExpenseType.plannedOccasional);
    expect(effective.description, 'MARKET REF 200');
    final newRule = rule(category: 'Food', group: 'Essential');
    expect(
      MerchantClassificationIndex([newRule, records.last])
          .apply(transaction())
          .category,
      'Shopping',
    );
    expect(
      MerchantClassificationIndex([
        newRule,
        {...records.last, 'deleted': true},
      ]).apply(transaction()).category,
      'Food',
    );
    expect(
      MerchantClassificationIndex([newRule])
          .apply(transaction(id: 'new'))
          .category,
      'Food',
    );
    expect(
      MerchantClassificationIndex([newRule])
          .apply(transaction(description: 'UNKNOWN SHOP'))
          .category,
      'Other',
    );
  });
  test('master essentiality and explicit Unclassified outrank overlapping legacy rules', () {
    final raw = transaction();
    final service = FinancialBaselineService();
    const legacy = [
      FinancialBaselineMapping(
        merchantFingerprint: 'Market',
        group: BaselineGroup.potentiallyFlexible,
      ),
    ];
    final essential = MerchantClassificationIndex([rule()]).apply(raw);
    expect(
      service
          .classify(transactions: [essential], mappings: legacy)
          .single
          .assignedGroup,
      BaselineGroup.essential,
    );
    final unknown = MerchantClassificationIndex([rule(group: 'Unclassified')])
        .apply(raw);
    expect(
      service
          .classify(transactions: [unknown], mappings: legacy)
          .single
          .assignedGroup,
      isNull,
    );
    expect(Transaction.fromJson(essential.toJson()).baselineGroup, 'Essential');
  });
  test('alias collisions remain unresolved instead of guessing', () {
    final index = MerchantClassificationIndex([
      rule(),
      {...rule(), 'id': 'm:another', 'group': 'Potentially Flexible'},
    ]);
    expect(index.merchantFor('MARKET REF 999'), isNull);
    expect(index.apply(transaction()).category, 'Other');
  });
  test(
    'coverage picks the minimum ranked merchant count crossing the target',
    () {
      final groups = const FavouriteSpendingSpotsService()
          .calculate(
            allHistory: true,
            now: DateTime(2026, 11, 10),
            transactions: [
              transaction(id: 'a', description: 'Alpha', amount: 500),
              transaction(id: 'b', description: 'Beta', amount: 200),
              transaction(id: 'c', description: 'Gamma', amount: 200),
              transaction(id: 'd', description: 'Delta', amount: 100),
            ],
          )
          .actual;
      expect(merchantsForCoverage(groups, .75).length, 3);
      expect(merchantsForCoverage(groups, .9).length, 3);
      expect(merchantsForCoverage(groups, 1).length, 4);
    },
  );
  test(
    'offline defaults and exceptions survive reload and are account-local',
    () async {
      final store = MerchantClassificationStore('one');
      await store.save([
        rule(),
        {
          'id': 't:tx',
          'kind': 'transaction',
          'transactionId': 'tx',
          'group': 'Unclassified',
        },
      ]);
      final restored = MerchantClassificationStore('one');
      await restored.load();
      expect(restored.pending.length, 2);
      expect(restored.index.apply(transaction()).baselineGroup, 'Unclassified');
      final other = MerchantClassificationStore('two');
      await other.load();
      expect(other.records, isEmpty);
    },
  );
  test('sheet sync resolves fresh rows by ID, updates category cells only, and preserves unrelated remote records', () async {
    final store = MerchantClassificationStore('one');
    await store.save([rule()]);
    final remote = {
      'id': 'm:remote',
      'kind': 'merchant',
      'aliases': ['REMOTE'],
      'category': 'Shopping',
      'categoryId': 'shopping',
      'group': 'Essential',
    };
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final path = Uri.decodeComponent(request.url.path);
      if (request.method == 'POST') {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('Sheet1!F2:F')) {
        return http.Response(
          jsonEncode({
            'values': [
              for (var i = 0; i < 18; i++) [i == 17 ? 'tx' : ''],
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.contains('/values/'))
        return http.Response(
          jsonEncode({
            'values': [
              ['Record ID', 'Classification'],
              [remote['id'], jsonEncode(remote)],
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
      transaction(row: 7),
    ]);
    expect(store.records.containsKey('m:remote'), true);
    expect(store.pending, isEmpty);
    final cells = [for (final req in requests) ...req['data'] as List];
    expect(cells.any((c) => c['range'] == 'Sheet1!C19'), true);
    expect(cells.any((c) => c['range'] == 'Sheet1!G19'), true);
    expect(cells.any((c) => c['range'] == 'Sheet1!C7'), false);
    expect(
      cells
          .where((c) => (c['range'] as String).startsWith('Sheet1!'))
          .every(
            (c) =>
                (c['range'] as String).contains('!C') ||
                (c['range'] as String).contains('!G'),
          ),
      true,
    );
  });
  test('failed network leaves the durable merchant outbox queued', () async {
    final store = MerchantClassificationStore('one');
    await store.save([rule()]);
    final client = MockClient((_) async => http.Response('offline', 503));
    await expectLater(
      store.synchronize(sheets.SheetsApi(client), 'sheet', [transaction()]),
      throwsA(anything),
    );
    final restored = MerchantClassificationStore('one');
    await restored.load();
    expect(restored.pending, contains('m:market'));
    expect(restored.index.apply(transaction()).category, 'Food');
  });

  test(
    'unfinished merchant choices restore without entering the sync outbox',
    () async {
      final store = MerchantClassificationStore('draft');
      await store.saveDraft([rule()]);
      final restored = MerchantClassificationStore('draft');
      await restored.load();
      expect(restored.draft['m:market']?['group'], 'Essential');
      expect(restored.pending, isEmpty);
      expect(restored.records, isEmpty);
      await restored.clearDraft();
      final cleared = MerchantClassificationStore('draft');
      await cleared.load();
      expect(cleared.draft, isEmpty);
    },
  );
  test('numeric-only and check aliases stay exact, never classifying another check', () {
    final index = MerchantClassificationIndex([
      {
        ...rule(),
        'aliases': ['Check #147'],
      },
    ]);
    expect(
      index.apply(transaction(description: 'Check #147')).category,
      'Food',
    );
    expect(
      index.apply(transaction(description: 'Check #148')).category,
      'Other',
    );
  });
  test('malformed exception without a transaction ID is rejected', () {
    expect(
      () => MerchantClassificationIndex([
        {'id': 't:bad', 'kind': 'transaction', 'category': 'Food'},
      ]),
      throwsFormatException,
    );
  });

  testWidgets(
    'merchant edits preserve exceptions until apply-to-all is explicitly confirmed',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MerchantClassificationStore('reset');
      await store.save([
        rule(),
        {
          'id': 't:tx',
          'kind': 'transaction',
          'transactionId': 'tx',
          'category': 'Shopping',
          'categoryId': 'shopping',
          'group': 'Potentially Flexible',
        },
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MerchantBaselinePanel(
              showRemainingInitially: true,
              transactions: [
                transaction(),
                transaction(id: 'other'),
              ],
              categories: categories,
              legacyMappings: const [],
              store: store,
              currencySymbol: r'$',
              historyComplete: true,
              onSaved: (changes) async {
                await store.save(changes);
                return 'Saved';
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('baseline-classified')));
      await tester.pumpAndSettle();
      await openClassifiedTable(tester);
      final category = find.byWidgetPredicate(
        (w) =>
            w is DropdownButton<String> &&
            w.key.toString().contains('merchant-category-'),
      );
      await tester.ensureVisible(category);
      await tester.tap(category);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shopping').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(
        store.index.apply(transaction()).baselineGroup,
        'Potentially Flexible',
      );
      expect(store.index.apply(transaction(id: 'other')).category, 'Shopping');
      await tester.tap(find.byTooltip('Merchant actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply to all, including exceptions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        store.index.apply(transaction()).baselineGroup,
        'Potentially Flexible',
      );
      await tester.tap(find.byTooltip('Merchant actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply to all, including exceptions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply to all'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(store.index.apply(transaction()).baselineGroup, 'Essential');
      expect(store.records['t:tx']?['deleted'], true);
    },
  );
  testWidgets('unfinished edits restore after leaving and can be discarded', (
    tester,
  ) async {
    final store = MerchantClassificationStore('restore-widget');
    Widget panel(MerchantClassificationStore state) => MaterialApp(
      home: Scaffold(
        body: MerchantBaselinePanel(
          showRemainingInitially: true,
          transactions: [transaction()],
          categories: categories,
          legacyMappings: const [],
          store: state,
          currencySymbol: r'$',
          historyComplete: true,
          onSaved: (changes) async {
            await state.save(changes);
            return 'Saved';
          },
        ),
      ),
    );
    await tester.pumpWidget(panel(store));
    await tester.pumpAndSettle();
    final category = find.byWidgetPredicate(
      (w) =>
          w is DropdownButton<String> &&
          w.key.toString().contains('merchant-category-'),
    );
    await tester.ensureVisible(category);
    await tester.tap(category);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food').last);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    final restored = MerchantClassificationStore('restore-widget');
    await restored.load();
    expect(restored.draft, isNotEmpty);
    expect(restored.pending, isEmpty);
    await tester.pumpWidget(panel(restored));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 unsaved changes'), findsOneWidget);
    await tester.ensureVisible(find.text('Discard'));
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(restored.draft, isEmpty);
    expect(restored.records, isEmpty);
  });

  test('automatic merchant projection preserves review flags and stable duplicate identity', () {
    final row = WorkerExpensePreview.fromJson({
      'date': '2026-10-05',
      'amount': 100,
      'category': 'Other',
      'description': 'MARKET REF 200',
      'expenseType': 'Unexpected Occasional',
      'duplicate': true,
      'transactionId': 'tx',
    });
    final projected = row
        .withMerchantCategory('Food', 'food')
        .withImportAnyway(false);
    expect(projected.transactionId, 'tx');
    expect(projected.userEdited, false);
    expect(projected.expenseType, 'Unexpected Occasional');
    final edited = projected.withCategory('Shopping', categoryId: 'shopping');
    expect(edited.transactionId, 'tx');
    expect(edited.userEdited, true);
    expect(buildReviewedExpenseCsv([edited]), contains('Category Reviewed'));
  });
  test('import requires a Worker supporting merchant classifications before posting', () async {
    var posted = false;
    final service = WorkerCsvSyncService(
      MockClient((request) async {
        if (request.method == 'POST') posted = true;
        return http.Response(
          jsonEncode({
            'expenseTypeReview': true,
            'reviewPreview': true,
            'reviewedCategoryUpdates': true,
          }),
          200,
        );
      }),
    );
    await expectLater(
      service.previewCsv(
        accessToken: 'token',
        spreadsheetId: 'sheet',
        csv: 'Date,Amount,Description',
        requireMerchantReview: true,
      ),
      throwsStateError,
    );
    expect(posted, false);
    service.close();
  });
  for (final ids in [
    <String>[],
    ['tx', 'tx'],
  ]) {
    test(
      'deleted or ambiguous IDs never receive category writes: $ids',
      () async {
        final store = MerchantClassificationStore('ids-${ids.length}');
        await store.save([rule()]);
        final writes = <Map<String, dynamic>>[];
        final client = MockClient((request) async {
          final path = Uri.decodeComponent(request.url.path);
          if (request.method == 'POST') {
            writes.add(jsonDecode(request.body) as Map<String, dynamic>);
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
                  for (final id in ids) [id],
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
        final status = await store.synchronize(
          sheets.SheetsApi(client),
          'sheet',
          [transaction()],
        );
        final cells = [
          for (final request in writes) ...request['data'] as List,
        ];
        expect(
          cells.any((cell) => (cell['range'] as String).startsWith('Sheet1!')),
          false,
        );
        if (ids.isNotEmpty)
          expect(status, contains('Duplicate transaction IDs'));
      },
    );
  }
  test('category projection retries after metadata succeeded but cell writing failed', () async {
    final store = MerchantClassificationStore('retry-category');
    await store.save([rule()]);
    var categoryWrites = 0;
    final client = MockClient((request) async {
      final path = Uri.decodeComponent(request.url.path);
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if ((body['data'] as List).any(
          (cell) => (cell['range'] as String).startsWith('Sheet1!'),
        )) {
          categoryWrites++;
          if (categoryWrites == 1)
            return http.Response(
              jsonEncode({
                'error': {'message': 'offline'},
              }),
              503,
              headers: {'content-type': 'application/json'},
            );
        }
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
              ['tx'],
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
              ['m:market', jsonEncode(rule())],
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
    await expectLater(
      store.synchronize(sheets.SheetsApi(client), 'sheet', [transaction()]),
      throwsA(anything),
    );
    final restored = MerchantClassificationStore('retry-category');
    await restored.load();
    expect(restored.index.apply(transaction()).category, 'Food');
    await restored.synchronize(sheets.SheetsApi(client), 'sheet', [
      transaction(),
    ]);
    expect(categoryWrites, 2);
  });
  for (final width in [1200.0, 390.0]) {
    testWidgets(
      'merchant table saves defaults and transaction exception at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = MerchantClassificationStore('widget');
        await store.save([rule()]);
        List<Map<String, dynamic>>? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 620,
                child: MerchantBaselinePanel(
                  showRemainingInitially: true,
                  transactions: [transaction()],
                  categories: categories,
                  legacyMappings: const [],
                  store: store,
                  currencySymbol: r'$',
                  historyComplete: true,
                  onSaved: (changes) async {
                    saved = changes;
                    await store.save(changes);
                    return 'Saved locally';
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Financial Baseline'), findsOneWidget);
        expect(find.text('80%'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('baseline-classified')));
        await tester.pumpAndSettle();
        await openClassifiedTable(tester);
        final expand = find.byTooltip('View transactions').first;
        await tester.tap(expand);
        await tester.pumpAndSettle();
        final dropdown = find.byKey(const ValueKey('transaction-category-tx'));
        if (width < 900) {
          await tester.scrollUntilVisible(
            dropdown,
            100,
            scrollable: find
                .descendant(
                  of: find.byKey(const ValueKey('mobile-merchant-list')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
        } else {
          await tester.ensureVisible(dropdown);
        }
        await tester.pumpAndSettle();
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Shopping').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save changes'));
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();
        expect(saved!.single['transactionId'], 'tx');
        expect(saved!.single['categoryId'], 'shopping');
        expect(store.index.apply(transaction()).category, 'Shopping');
        // Let the test binding report rendering errors with full context.
      },
    );
  }
}
