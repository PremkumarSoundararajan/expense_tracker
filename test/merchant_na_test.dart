import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/favourite_spending_spots_service.dart';
import 'package:pocket_ledger/services/merchant_classification_service.dart';
import 'package:pocket_ledger/services/merchant_classification_store.dart';
import 'package:pocket_ledger/services/merchant_na_service.dart';
import 'package:pocket_ledger/services/budget_comparison.dart';
import 'package:pocket_ledger/widgets/merchant_baseline_panel.dart';

Transaction expense(String merchant, double amount, String id) => Transaction(
  id: id,
  description: merchant,
  date: DateTime(2026, 10, 1),
  amount: amount,
  category: 'Food',
  categoryId: 'food',
  expenseType: ExpenseType.regular,
);
List<Transaction> ledger() => [
  expense('Alpha', 900, 'a'),
  expense('Beta', 20, 'b'),
  expense('Beta', 30, 'c'),
  expense('Gamma', 50, 'd'),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Home Maintenance is selectable without duplicating a custom choice',
    () {
      expect(withHomeMaintenance([]).single.name, 'Home Maintenance');
      expect(withHomeMaintenance([homeMaintenanceCategory]).length, 1);
      expect(homeMaintenanceCategory.parentId, 'housing-bills');
      expect(
        withHomeMaintenance([
          const ExpenseCategory(
            id: 'custom',
            parentId: 'housing-bills',
            name: 'Home Maintenance',
          ),
        ]).single.id,
        'custom',
      );
    },
  );
  test('threshold is finite positive and uses strict merchant totals', () {
    for (final value in [
      '',
      'bad',
      '0',
      '-1',
      'NaN',
      'Infinity',
      '.001',
      '1e308',
    ])
      expect(merchantNaThreshold(value), isNull);
    expect(merchantNaThreshold(' 50.00 '), 50);
    final groups = const FavouriteSpendingSpotsService()
        .calculate(transactions: ledger(), allHistory: true)
        .actual;
    expect(previewMerchantNa(groups, 50).groups, isEmpty);
    final preview = previewMerchantNa(groups, 51);
    expect(preview.groups.length, 2);
    expect(preview.amount, 100);
    expect(preview.spendingPercent, 10);
    expect(preview.transactionPercent, 75);
  });
  test('NA defaults persist, include actual spending, preserve overrides and restore original choices', () async {
    final rows = ledger();
    final group = const FavouriteSpendingSpotsService()
        .calculate(transactions: rows, allHistory: true)
        .actual
        .firstWhere((g) => g.name == 'Beta');
    final exception = {
      'id': 't:b',
      'kind': 'transaction',
      'transactionId': 'b',
      'expenseType': 'Unexpected Occasional',
      'category': 'Medical',
      'categoryId': 'medical',
    };
    final original = MerchantClassificationIndex([exception]);
    final record = merchantNaRecord(group, original);
    final store = MerchantClassificationStore('na');
    await store.save([record, exception]);
    final restored = MerchantClassificationStore('na');
    await restored.load();
    expect(restored.records[record['id']]?['na'], true);
    final na = restored.index.apply(rows[2]);
    expect(na.category, 'NA');
    expect(na.expenseType, ExpenseType.unknown);
    expect(na.baselineGroup, 'Unclassified');
    expect(
      restored.index.apply(rows[1]).expenseType,
      ExpenseType.unexpectedOccasional,
    );
    final amounts = BudgetSpending.fromTransactions(
      rows.map(restored.index.apply),
    );
    expect(amounts.total, 1000);
    expect(amounts.unknown, 30);
    expect(
      restored.index.apply(expense('Beta REF 100', 4, 'future')).category,
      'NA',
    );
    final changes = removeMerchantNa(record, restored.index);
    await restored.save(changes);
    final undone = restored.index.apply(na);
    expect(undone.category, 'Food');
    expect(undone.expenseType, ExpenseType.regular);
    expect(restored.index.apply(rows[1]).category, 'Medical');
  });

  for (final width in [1280.0, 390.0]) {
    testWidgets('threshold preview validation save and remove NA at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MerchantClassificationStore('na-widget');
      await store.save([
        {
          'id': 'm:alpha',
          'kind': 'merchant',
          'name': 'Alpha',
          'aliases': ['Alpha'],
          'category': 'Food',
          'categoryId': 'food',
          'group': 'Essential',
          'expenseType': 'Regular',
        },
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MerchantBaselinePanel(
                transactions: ledger(),
                categories: const [
                  ExpenseCategory(
                    id: 'food',
                    parentId: 'food-household',
                    name: 'Food',
                  ),
                ],
                legacyMappings: const [],
                store: store,
                currencySymbol: r'$',
                historyComplete: true,
                showRemainingInitially: true,
                onSaved: (changes) async {
                  await store.save(changes);
                  return 'Saved';
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bulk Exclude Small Merchants'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('na-threshold-toggle')))
            .height,
        greaterThanOrEqualTo(56),
      );
      await tester.tap(find.byKey(const ValueKey('na-threshold-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-na-threshold')));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a valid amount of at least 0.01.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('na-threshold')),
        '1001',
      );
      await tester.pumpAndSettle();
      expect(find.text('Exclude all merchants <'), findsOneWidget);
      expect(find.textContaining('would be excluded'), findsNothing);
      expect(find.textContaining('Saved rule for current'), findsNothing);
      expect(find.byKey(const ValueKey('na-impact-warning')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('save-na-threshold')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(r'total expenses are below $1,001'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('review-na')), findsOneWidget);
      expect(store.records.values.where((r) => r['na'] == true).length, 2);
      expect(store.records['m:alpha']?['na'], isNot(true));
      expect(
        store.index.apply(ledger().first).expenseType,
        ExpenseType.regular,
      );
      expect(find.byKey(const ValueKey('na-threshold-toggle')), findsNothing);
      expect(find.text('NA'), findsWidgets);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      // Return later to the same account: NA is reviewable and reversible.
      final menu = find.byTooltip('Merchant actions').first;
      await tester.ensureVisible(menu);
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove NA'));
      await tester.pumpAndSettle();
      final save = find.text('Save changes');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        store.records.values
            .where((r) => r['na'] == true && r['deleted'] != true)
            .length,
        1,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
