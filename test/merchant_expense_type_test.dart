import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/services/merchant_classification_store.dart';
import 'package:pocket_ledger/widgets/merchant_baseline_panel.dart';

void main() {
  testWidgets(
    'merchant type applies across a large lazy list and inherited choices are visible',
    (tester) async {
      tester.view.physicalSize = const Size(1450, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final store = MerchantClassificationStore('type-test');
      final rows = [
        for (var i = 0; i < 1000; i++)
          Transaction(
            id: 'tx-$i',
            date: DateTime(2026, 1, 1),
            amount: 10,
            category: 'Food',
            categoryId: 'food',
            description: 'Market REF $i',
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MerchantBaselinePanel(
              showRemainingInitially: true,
              transactions: rows,
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
              onSaved: (changes) async {
                await store.save(changes);
                return 'Saved';
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final type = find.byWidgetPredicate(
        (w) =>
            w is DropdownButton<String> &&
            w.key.toString().contains('merchant-type-'),
      );
      await tester.tap(type);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regular').last);
      await tester.pumpAndSettle();
      final watch = Stopwatch()..start();
      await tester.tap(find.byTooltip('View transactions'));
      await tester.pumpAndSettle();
      watch.stop();
      final built = find.byWidgetPredicate(
        (w) => w.key.toString().contains('merchant-transaction-'),
      );
      expect(built.evaluate().length, lessThan(30));
      expect(find.text('Merchant default'), findsNothing);
      final rowType = tester.widget<DropdownButton<String>>(
        find.byKey(const ValueKey('transaction-type-tx-0')),
      );
      expect(rowType.value, 'Regular');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(
        rows.every(
          (t) => store.index.apply(t).expenseType == ExpenseType.regular,
        ),
        true,
      );
      expect(find.textContaining('Expense Type → budgets'), findsOneWidget);
      print(
        'Expand 1000 transactions: ${watch.elapsedMilliseconds}ms; built ${built.evaluate().length} transaction widgets',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
