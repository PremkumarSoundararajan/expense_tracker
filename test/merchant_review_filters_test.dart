import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/merchant_classification_store.dart';
import 'package:pocket_ledger/widgets/merchant_baseline_panel.dart';

void main() {
  for (final width in [1280.0, 390.0]) {
    testWidgets(
      'classified filters combine effective fields and retain pending edits at $width',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = MerchantClassificationStore('filters');
        Map<String, dynamic> rule(
          String name,
          String category,
          String categoryId,
          String group,
          String type,
        ) => {
          'id': 'm:${name.toLowerCase()}',
          'kind': 'merchant',
          'name': name,
          'aliases': [name],
          'category': category,
          'categoryId': categoryId,
          'group': group,
          'expenseType': type,
        };
        await store.save([
          rule(
            'Alpha',
            'Household Supplies',
            'household',
            'Essential',
            'Regular',
          ),
          rule(
            'Beta',
            'Household Supplies',
            'household',
            'Potentially Flexible',
            'Planned Occasional',
          ),
          rule(
            'Gamma',
            'Home Maintenance',
            'maintenance',
            'Potentially Flexible',
            'Unexpected Occasional',
          ),
          {
            'id': 't:override',
            'kind': 'transaction',
            'transactionId': 'override',
            'category': 'Home Maintenance',
            'categoryId': 'maintenance',
            'group': 'Potentially Flexible',
            'expenseType': 'Unexpected Occasional',
          },
        ]);
        final rows = [
          for (final name in ['Alpha', 'Beta', 'Gamma'])
            Transaction(
              id: name,
              date: DateTime(2026, 10, 1),
              amount: 100,
              description: name,
              category: 'Other',
              expenseType: ExpenseType.unknown,
            ),
          Transaction(
            id: 'override',
            date: DateTime(2026, 10, 1),
            amount: 10,
            description: 'Alpha',
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
                      id: 'household',
                      parentId: 'food-household',
                      name: 'Household Supplies',
                    ),
                    ExpenseCategory(
                      id: 'maintenance',
                      parentId: 'housing-bills',
                      name: 'Home Maintenance',
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
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('baseline-classified')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('na-threshold-toggle')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('baseline-filter-toggle')));
        await tester.pumpAndSettle();
        Future<void> choose(String field, String value) async {
          final control = find.byKey(ValueKey('baseline-filter-$field'));
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          await tester.tap(control);
          await tester.pumpAndSettle();
          await tester.tap(find.text(value).last);
          await tester.pumpAndSettle();
        }

        await choose('group', 'Potentially Flexible');
        expect(
          find.text('Alpha · 2'),
          findsOneWidget,
        ); // Explicit transaction exception.
        expect(find.text('Beta · 1'), findsOneWidget);
        expect(find.textContaining('3 of 3 merchants match'), findsOneWidget);
        if (width >= 900) expect(find.text('Gamma · 1'), findsOneWidget);
        await choose('category', 'Household Supplies');
        expect(
          find.text('Alpha · 2'),
          findsNothing,
        ); // Conditions must match the same transaction.
        expect(find.text('Beta · 1'), findsOneWidget);
        expect(find.text('Gamma · 1'), findsNothing);
        await choose('type', 'Regular');
        expect(find.text('Beta · 1'), findsNothing);
        expect(
          find.textContaining('No merchants match these filters'),
          findsOneWidget,
        );
        final clear = find.byKey(const ValueKey('baseline-clear-filters'));
        await tester.ensureVisible(clear);
        await tester.pumpAndSettle();
        await tester.tap(clear);
        await tester.pumpAndSettle();
        await choose('category', 'Household Supplies');
        expect(find.text('Alpha · 2'), findsOneWidget);
        expect(find.text('Beta · 1'), findsOneWidget);
        final category = find.byKey(const ValueKey('merchant-category-alpha'));
        await tester.ensureVisible(category);
        await tester.pumpAndSettle();
        await tester.tap(category);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Home Maintenance').last);
        await tester.pumpAndSettle();
        expect(
          find.text('Alpha · 2'),
          findsOneWidget,
        ); // Remains visible until saved.
        final save = find.text('Save changes');
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('Alpha · 2'), findsNothing);
        expect(find.text('Beta · 1'), findsOneWidget);
        expect(store.index.apply(rows.first).category, 'Home Maintenance');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
