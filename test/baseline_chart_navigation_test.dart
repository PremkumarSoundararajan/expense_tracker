import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/services/merchant_classification_store.dart';
import 'package:pocket_ledger/widgets/merchant_baseline_panel.dart';
import 'package:pocket_ledger/widgets/spending_breakdown.dart';

void main() {
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets(
      'Classified charts replace table and preserve drafts at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final store = MerchantClassificationStore('chart-navigation');
        await store.save([
          {
            'id': 'm:market',
            'kind': 'merchant',
            'name': 'Market',
            'aliases': ['Market'],
            'category': 'Food',
            'categoryId': 'food',
            'group': 'Essential',
            'expenseType': 'Regular',
          },
          {
            'id': 'm:excluded',
            'kind': 'merchant',
            'name': 'Excluded shop',
            'aliases': ['Excluded shop'],
            'category': 'NA',
            'group': 'Unclassified',
            'expenseType': 'NA',
            'na': true,
          },
        ]);
        var saves = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: width == 390 ? Brightness.dark : Brightness.light,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: MerchantBaselinePanel(
                  transactions: [
                    for (final (id, name, amount) in [
                      ('1', 'Market', 100.0),
                      ('2', 'New shop', 50.0),
                      ('3', 'Excluded shop', 25.0),
                    ])
                      Transaction(
                        id: id,
                        description: name,
                        date: DateTime(2026, 10, 1),
                        amount: amount,
                        category: 'Uncategorized',
                      ),
                  ],
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
                    saves++;
                    await store.save(changes);
                    return 'Saved';
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SpendingBreakdown), findsNothing);
        await tester.tap(find.byKey(const ValueKey('baseline-classified')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('essentiality-donut')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('baseline-search-classified')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('review-na')), findsNothing);
        expect(find.byKey(const ValueKey('na-threshold-toggle')), findsNothing);
        final donut = find.byKey(const ValueKey('essentiality-donut'));
        await tester.ensureVisible(donut);
        await tester.tap(donut);
        await tester.pumpAndSettle();
        expect(find.byType(SpendingBreakdown), findsNothing);
        expect(
          find.byKey(const ValueKey('baseline-search-classified')),
          findsOneWidget,
        );
        final group = find.byKey(const ValueKey('merchant-group-market'));
        await tester.ensureVisible(group);
        await tester.tap(group);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Potentially Flexible').last);
        await tester.pumpAndSettle();
        final back = find.byKey(const ValueKey('baseline-back-to-chart'));
        await tester.ensureVisible(back);
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(find.text('Preview includes unsaved choices.'), findsOneWidget);
        expect(find.byType(SpendingBreakdown), findsOneWidget);
        expect(saves, 0);
        expect(store.records['m:market']?['group'], 'Essential');
        final category = find.text('Category');
        await tester.ensureVisible(category);
        await tester.tap(category);
        await tester.pumpAndSettle();
        final bar = find.descendant(
          of: find.byType(SpendingBreakdown),
          matching: find.text('Food'),
        );
        await tester.ensureVisible(bar);
        await tester.tap(bar);
        await tester.pumpAndSettle();
        expect(find.byType(SpendingBreakdown), findsNothing);
        await tester.ensureVisible(back);
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(
          find.text('Categories classified: 57.1% of spending'),
          findsOneWidget,
        );
        await tester.ensureVisible(bar);
        await tester.tap(bar);
        await tester.pumpAndSettle();
        final save = find.text('Save changes');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(saves, 1);
        expect(store.records['m:market']?['group'], 'Potentially Flexible');
        final unclassified = find.byKey(
          const ValueKey('baseline-unclassified'),
        );
        await tester.ensureVisible(unclassified);
        await tester.tap(unclassified);
        await tester.pumpAndSettle();
        expect(find.byType(SpendingBreakdown), findsNothing);
        expect(find.byKey(const ValueKey('review-na')), findsOneWidget);
        final box = find.byKey(const ValueKey('bulk-exclusion-box'));
        final toggle = find.byKey(const ValueKey('na-threshold-toggle'));
        expect(find.descendant(of: box, matching: toggle), findsOneWidget);
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: box,
            matching: find.byKey(const ValueKey('na-threshold')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: box,
            matching: find.byKey(const ValueKey('save-na-threshold')),
          ),
          findsOneWidget,
        );
        expect(
          tester.getRect(box).bottom + 16,
          lessThan(
            tester
                .getRect(
                  find.byKey(const ValueKey('baseline-search-remaining')),
                )
                .top,
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
