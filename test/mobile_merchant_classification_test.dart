import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/merchant_classification_store.dart';
import 'package:pocket_ledger/widgets/merchant_baseline_panel.dart';

void main() {
  for (final size in [
    const Size(320, 720),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    testWidgets(
      'phone can classify all fields, save, and edit an exception at $size',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = MerchantClassificationStore('phone');
        final rows = [
          for (final id in ['a', 'b'])
            Transaction(
              id: id,
              description: 'Market',
              date: DateTime(2026, 10, 1),
              amount: 50,
              category: 'Other',
              expenseType: ExpenseType.unknown,
            ),
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MerchantBaselinePanel(
                  transactions: rows,
                  categories: const [
                    ExpenseCategory(
                      id: 'food',
                      parentId: 'food-household',
                      name: 'Food',
                    ),
                    homeMaintenanceCategory,
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
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('baseline-unclassified')));
        await tester.pumpAndSettle();
        final list = find.byKey(const ValueKey('mobile-merchant-list'));
        expect(list, findsOneWidget);
        expect(
          find.byKey(const ValueKey('desktop-merchant-list')),
          findsNothing,
        );
        Future<void> choose(String key, String value) async {
          final control = find.byKey(ValueKey(key));
          await tester.ensureVisible(list);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            control,
            150,
            scrollable: find
                .descendant(of: list, matching: find.byType(Scrollable))
                .first,
          );
          await tester.pumpAndSettle();
          final bounds = tester.getRect(control);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(size.width));
          expect(bounds.height, greaterThanOrEqualTo(40));
          await tester.tap(control);
          await tester.pumpAndSettle();
          await tester.tap(find.text(value).last);
          await tester.pumpAndSettle();
        }

        await choose('merchant-category-market', 'Home Maintenance');
        await choose('merchant-group-market', 'Potentially Flexible');
        await choose('merchant-type-market', 'Regular');
        expect(find.text('Ready to save'), findsOneWidget);
        Future<void> save() async {
          final button = find.text('Save changes');
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          await tester.tap(button);
          await tester.pumpAndSettle();
        }

        await save();
        for (final row in rows) {
          final effective = store.index.apply(row);
          expect(effective.category, 'Home Maintenance');
          expect(effective.baselineGroup, 'Potentially Flexible');
          expect(effective.expenseType, ExpenseType.regular);
        }
        final classified = find.byKey(const ValueKey('baseline-classified'));
        await tester.ensureVisible(classified);
        await tester.pumpAndSettle();
        await tester.tap(classified);
        await tester.pumpAndSettle();
        final expand = find.byKey(const ValueKey('merchant-expand-market'));
        await tester.ensureVisible(expand);
        await tester.pumpAndSettle();
        await tester.tap(expand);
        await tester.pumpAndSettle();
        await choose('transaction-category-a', 'Food');
        await choose('transaction-group-a', 'Essential');
        await choose('transaction-type-a', 'Unexpected Occasional');
        await save();
        final exception = store.index.apply(rows.first);
        expect(exception.category, 'Food');
        expect(exception.baselineGroup, 'Essential');
        expect(exception.expenseType, ExpenseType.unexpectedOccasional);
        expect(store.index.apply(rows.last).expenseType, ExpenseType.regular);
      },
    );
  }
}
