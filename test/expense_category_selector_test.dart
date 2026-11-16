import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/app_theme.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/widgets/expense_category_selector.dart';
import 'package:pocket_ledger/widgets/expense_category_management_screen.dart';

void main() {
  const categories = [
    ExpenseCategory(
      id: 'food-household:groceries',
      parentId: 'food-household',
      name: 'Groceries',
    ),
    ExpenseCategory(
      id: 'housing-bills:electricity',
      parentId: 'housing-bills',
      name: 'Electricity',
    ),
    ExpenseCategory(
      id: 'lifestyle-misc:entertainment',
      parentId: 'lifestyle-misc',
      name: 'Entertainment',
    ),
  ];

  test('retains the six broad categories as legacy defaults', () {
    expect(expenseCategoryOptions.map((category) => category.name).toList(), [
      'Housing / Bills',
      'Food / Household',
      'Transport',
      'Financial Obligations',
      'Health & Wellness',
      'Lifestyle / Misc',
    ]);
  });

  testWidgets(
    'add link remains available on a small phone with keyboard and larger text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(1.6),
              viewInsets: const EdgeInsets.only(bottom: 280),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: ExpenseCategorySelector(
              selectedCategory: 'Groceries',
              categories: categories,
              onCategorySelected: (_) {},
              onManageCategories: () async => categories,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('expense-category-selector')));
      await tester.pumpAndSettle();
      expect(find.text('Add a new category'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'add action returns from settings with new category and expense draft intact',
    (tester) async {
      var saved = [...categories];
      String? chosen;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  const TextField(
                    decoration: InputDecoration(labelText: 'Amount'),
                  ),
                  ExpenseCategorySelector(
                    selectedCategory: 'Groceries',
                    categories: saved,
                    onCategorySelected: (value) => chosen = value,
                    onManageCategories: () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => ExpenseCategoryManagementScreen(
                            categories: saved,
                            onChanged: (value) => saved = value,
                          ),
                        ),
                      );
                      return saved;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '42.50');
      await tester.tap(find.byKey(const ValueKey('expense-category-selector')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'not in the list');
      await tester.pumpAndSettle();
      expect(
        find.text('No categories match. Try another search.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Add a new category'));
      await tester.pumpAndSettle();
      expect(find.text('Expense categories'), findsOneWidget);
      await tester.tap(find.text('Food / Household').last);
      await tester.pumpAndSettle();
      final add = find.text('Add custom').first;
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Pet food');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Choose a category'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Pet food');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('Pet food'),
        ),
      );
      await tester.pumpAndSettle();
      expect(chosen, 'Pet food');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text ??
            tester
                .widget<EditableText>(find.byType(EditableText))
                .controller
                .text,
        '42.50',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('returning without edits preserves the category selection', (
    tester,
  ) async {
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: Scaffold(
          body: ExpenseCategorySelector(
            selectedCategory: 'Groceries',
            categories: categories,
            onCategorySelected: (value) => chosen = value,
            onManageCategories: () async => categories,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('expense-category-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a new category'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(chosen, isNull);
    await tester.tap(find.text('Electricity'));
    await tester.pumpAndSettle();
    expect(chosen, 'Electricity');
  });

  testWidgets('opens a compact searchable picker instead of a category grid', (
    tester,
  ) async {
    String selected = '';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: Scaffold(
          body: ExpenseCategorySelector(
            selectedCategory: 'Groceries',
            categories: categories,
            onCategorySelected: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.byType(ChoiceChip), findsNothing);
    await tester.tap(find.byKey(const ValueKey('expense-category-selector')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a category'), findsOneWidget);
    expect(find.text('Electricity'), findsOneWidget);
    expect(find.text('Housing / Bills'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ELEC');
    await tester.pumpAndSettle();
    expect(find.text('Electricity'), findsOneWidget);
    expect(
      find.text('Groceries'),
      findsOneWidget,
    ); // The closed selector retains its current value.
    await tester.tap(find.text('Electricity'));
    await tester.pumpAndSettle();
    expect(selected, 'Electricity');
  });

  testWidgets('shows recent and frequently used categories when available', (
    tester,
  ) async {
    final now = DateTime.now();
    final transactions = [
      Transaction(
        date: now,
        amount: 9,
        category: 'Groceries',
        categoryId: 'food-household:groceries',
      ),
      Transaction(
        date: now.subtract(const Duration(days: 2)),
        amount: 12,
        category: 'Groceries',
        categoryId: 'food-household:groceries',
      ),
      Transaction(
        date: now.subtract(const Duration(days: 1)),
        amount: 4,
        category: 'Electricity',
        categoryId: 'housing-bills:electricity',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: Scaffold(
          body: ExpenseCategorySelector(
            selectedCategory: 'Groceries',
            categories: categories,
            transactions: transactions,
            onCategorySelected: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('expense-category-selector')));
    await tester.pumpAndSettle();
    expect(find.text('Recently used'), findsOneWidget);
    expect(find.text('Frequently used'), findsOneWidget);
    expect(find.text('All categories'), findsOneWidget);
  });

  testWidgets('offers parent categories when no subcategories are configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: Scaffold(
          body: ExpenseCategorySelector(
            selectedCategory: 'Food / Household',
            onCategorySelected: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('expense-category-selector')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'transport');
    await tester.pumpAndSettle();
    expect(find.text('Transport'), findsWidgets);
    expect(find.text('Food / Household'), findsWidgets);
  });
}
