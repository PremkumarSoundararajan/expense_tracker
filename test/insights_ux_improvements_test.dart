import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/app_theme.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/merchant_classification_store.dart';
import 'package:pocket_ledger/services/favourite_spending_spots_service.dart';
import 'package:pocket_ledger/widgets/expense_category_management_screen.dart';
import 'package:pocket_ledger/widgets/expense_category_selector.dart';
import 'package:pocket_ledger/widgets/financial_baseline_screen.dart';
import 'package:pocket_ledger/widgets/merchant_baseline_panel.dart';

Transaction expense(
  String name,
  double amount, {
  String? group,
  String category = 'Groceries',
  String? id,
}) => Transaction(
  id: id ?? name,
  date: DateTime(2026, 10, 1),
  amount: amount,
  category: category,
  description: name,
  baselineGroup: group,
);
void main() {
  test('coverage handles empty scope, dominant and tied merchants without adding arbitrary rows', () {
    expect(merchantsForCoverage([], .8), isEmpty);
    final groups = const FavouriteSpendingSpotsService()
        .calculate(
          transactions: [
            expense('Alpha', 850),
            expense('Beta', 75),
            expense('Gamma', 75),
          ],
          allHistory: true,
        )
        .actual;
    expect(
      merchantsForCoverage(groups, .75).map((g) => g.key),
      merchantsForCoverage(groups, .8).map((g) => g.key),
    );
    expect(merchantsForCoverage(groups, .9).length, 2);
    expect(merchantsForCoverage(groups, 1).length, 3);
    expect(
      merchantsForCoverage(groups, 1).fold<double>(0, (s, g) => s + g.total),
      1000,
    );
  });
  testWidgets(
    'bulk preview protects exclusions and opt-outs; confirmation preserves pending-sync status',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = MerchantClassificationStore('preview-protection');
      await store.save([
        {
          'id': 'm:beta',
          'kind': 'merchant',
          'aliases': ['Beta'],
          'naOptOut': true,
        },
        {
          'id': 'm:gamma',
          'kind': 'merchant',
          'aliases': ['Gamma'],
          'na': true,
          'category': 'NA',
          'group': 'Unclassified',
          'expenseType': 'Unknown',
        },
        {
          'id': 't:delta',
          'kind': 'transaction',
          'transactionId': 'Delta',
          'group': 'Essential',
        },
      ]);
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MerchantBaselinePanel(
                transactions: [
                  expense('Alpha', 900),
                  expense('Beta', 20),
                  expense('Gamma', 50),
                  expense('Delta', 30),
                ],
                categories: const [],
                legacyMappings: const [],
                store: store,
                historyComplete: true,
                currencySymbol: r'$',
                showRemainingInitially: true,
                onSaved: (changes) async {
                  saves++;
                  await store.save(changes);
                  return 'Saved on this device. Google Sheets sync is pending.';
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('na-threshold-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('na-threshold')), '100');
      await tester.pumpAndSettle();
      expect(
        find.text(r'1 merchants · $30 · 3.0% of spending'),
        findsOneWidget,
      );
      expect(find.text('Already excluded: 1 merchants.'), findsOneWidget);
      expect(saves, 0);
      expect(store.records['m:delta'], isNull);
      await tester.tap(find.byKey(const ValueKey('save-na-threshold')));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(
        find.textContaining('1 additional merchants excluded'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'newly excluded. Saved on this device. Google Sheets sync is pending.',
        ),
        findsOneWidget,
      );
      expect(store.records['t:delta']?['group'], 'Essential');
      expect(store.records['m:beta']?['na'], isNot(true));
      expect(store.records['m:delta']?['na'], isTrue);
    },
  );
  testWidgets(
    'category bulk controls preserve custom IDs, mappings and partial states after reopen',
    (tester) async {
      var saved = <ExpenseCategory>[
        const ExpenseCategory(
          id: 'custom',
          parentId: 'food-household',
          name: 'My groceries',
        ),
      ];
      var writes = 0;
      Widget screen() => MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: ExpenseCategoryManagementScreen(
          categories: saved,
          mappings: const [
            ExpenseCategoryMapping(keyword: 'SHOP', categoryId: 'custom'),
          ],
          onMappingsChanged: (_) => fail('Selection must not rewrite rules'),
          onChanged: (value) {
            saved = value;
            writes++;
          },
        ),
      );
      await tester.pumpWidget(screen());
      Checkbox global() => tester.widget<Checkbox>(
        find.descendant(
          of: find.byKey(const ValueKey('category-select-all')),
          matching: find.byType(Checkbox),
        ),
      );
      expect(global().value, isNull);
      final section = find.byKey(
        const ValueKey('category-section-food-household'),
      );
      expect(tester.widget<Checkbox>(section).value, isNull);
      await tester.tap(section);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(section).value, isTrue);
      expect(writes, 1);
      await tester.tap(find.text('Select All Categories'));
      await tester.pumpAndSettle();
      expect(global().value, isTrue);
      expect(writes, 2);
      expect(saved.singleWhere((c) => c.id == 'custom').name, 'My groceries');
      expect(
        saved.singleWhere((c) => c.id == lifeTermInsuranceCategory.id).active,
        isTrue,
      );
      await tester.tap(find.text('Deselect All'));
      await tester.pumpAndSettle();
      expect(global().value, isFalse);
      expect(writes, 3);
      expect(saved.any((c) => c.id == 'custom'), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen());
      expect(global().value, isFalse);
      await tester.tap(find.text('Select All Categories'));
      await tester.pumpAndSettle();
      expect(global().value, isTrue);
      expect(saved.map((c) => c.id).toSet().length, saved.length);
      expect(tester.takeException(), isNull);
    },
  );
  test('Life Insurance is distinct and explicitly disabled categories stay disabled', () {
    final categories = withRequiredExpenseCategories([
      const ExpenseCategory(
        id: 'housing-bills:home-insurance',
        parentId: 'housing-bills',
        name: 'Home Insurance',
      ),
      lifeTermInsuranceCategory.copyWith(active: false, archived: true),
    ]);
    expect(
      categories
          .singleWhere((c) => c.id == lifeTermInsuranceCategory.id)
          .archived,
      isTrue,
    );
    expect(
      categories.singleWhere((c) => c.name == 'Home Insurance').parentId,
      'housing-bills',
    );
    expect(
      suggestedExpenseSubcategories['financial-obligations'],
      contains('Life / Term Insurance'),
    );
    expect(defaultExpenseParents.length, 6);
  });
  testWidgets(
    'Life Insurance available in shared manual/import category picker',
    (tester) async {
      String? chosen;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: Scaffold(
            body: ExpenseCategorySelector(
              selectedCategory: '',
              categories: withRequiredExpenseCategories([]),
              onCategorySelected: (v) => chosen = v,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('expense-category-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Life / Term Insurance'));
      await tester.pumpAndSettle();
      expect(chosen, 'Life / Term Insurance');
    },
  );
  for (final width in [320.0, 1280.0]) {
    for (final mode in ['empty', 'unknown', 'partial', 'full', 'excluded']) {
      testWidgets('savings $mode at $width', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var classify = false;
        final rows = switch (mode) {
          'empty' => <Transaction>[],
          'unknown' => [expense('Shop', 100)],
          'excluded' => [
            expense('Shop', 100, category: 'NA', group: 'Unclassified'),
          ],
          'partial' => [
            expense('Home', 60, group: 'Essential'),
            expense('Shop', 40),
          ],
          _ => [
            expense('Home', 60, group: 'Essential'),
            expense('Shop', 40, group: 'Potentially Flexible'),
          ],
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            home: FinancialBaselineScreen(
              insightsOnly: true,
              transactions: rows,
              initialMappings: const [],
              currencySymbol: r'$',
              onMappingsSaved: (_) async => null,
              onClassifyExpenses: () => classify = true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (mode == 'empty') {
          expect(find.text('No spending data yet'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('essential-monthly-average')),
            findsNothing,
          );
        } else if (mode == 'unknown' || mode == 'excluded') {
          expect(
            find.text("Savings insights aren't ready yet"),
            findsOneWidget,
          );
          expect(find.text('Potentially Flexible'), findsNothing);
          await tester.tap(find.text('Classify Expenses'));
          expect(classify, isTrue);
        } else {
          expect(
            find.byKey(const ValueKey('essential-monthly-average')),
            findsOneWidget,
          );
          expect(
            find.textContaining(mode == 'partial' ? '60.0%' : '100.0%'),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('potentially-adjustable-plan-launch')),
            findsOneWidget,
          );
        }
      });
    }
  }
  testWidgets(
    'coverage shows actual spending scope and equivalent targets; search expands scope',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MerchantBaselinePanel(
                transactions: [
                  expense('Alpha', 850),
                  expense('Beta', 100),
                  expense('Gamma', 50),
                ],
                categories: const [],
                legacyMappings: const [],
                store: MerchantClassificationStore('coverage-ux'),
                currencySymbol: r'$',
                showRemainingInitially: true,
                onSaved: (_) async => 'Saved',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('80%'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(r'80% target · 1 merchants · $850 · 85.0%'),
        findsOneWidget,
      );
      expect(
        find.text('Same 1 merchants as the 75% selection.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Top 15'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(r'Top 15 · 3 merchants · $1,000 · 100.0%'),
        findsOneWidget,
      );
      await tester.tap(find.text('75%'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Gamma');
      await tester.pumpAndSettle();
      expect(
        find.textContaining(r'Unclassified · 1 merchants · $50 · 5.0%'),
        findsOneWidget,
      );
      expect(find.textContaining('Search includes all'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
