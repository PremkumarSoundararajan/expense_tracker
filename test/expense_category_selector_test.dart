import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/widgets/expense_category_selector.dart';

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

  testWidgets('opens a compact searchable picker instead of a category grid', (
    tester,
  ) async {
    String selected = '';
    await tester.pumpWidget(
      MaterialApp(
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
