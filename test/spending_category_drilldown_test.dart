import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/main.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/expense_category_store.dart';
import 'package:pocket_ledger/services/local_transaction_store.dart';
import 'package:pocket_ledger/widgets/month_selector.dart';
import 'package:pocket_ledger/widgets/monthly_budget_card.dart';

class _Account implements GoogleSignInAccount {
  @override
  String get email => 'drilldown-test@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder inSheet(Finder child) =>
    find.descendant(of: find.byType(BottomSheet).last, matching: child);
Future<void> tapRow(WidgetTester tester, String text) async {
  final row = inSheet(find.text(text));
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<void> boot(
  WidgetTester tester, {
  required double width,
  required String period,
}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({'currency_symbol': r'$'});
  final now = DateTime.now();
  final date = period == 'month'
      ? DateTime(now.year, now.month - 1, 5)
      : DateTime(now.year, now.month, now.day);
  await ExpenseCategoryStore(accountKey: 'drilldown-test@example.com').save(
    categories: const [
      ExpenseCategory(
        id: 'groceries',
        parentId: 'food-household',
        name: 'Groceries',
      ),
      ExpenseCategory(
        id: 'supplies',
        parentId: 'food-household',
        name: 'Household Supplies',
      ),
      ExpenseCategory(
        id: 'custom',
        parentId: 'lifestyle-misc',
        name: 'My pottery class',
      ),
    ],
    mappings: const [],
  );
  await LocalTransactionStore(accountKey: 'drilldown-test@example.com')
      .saveCached([
        Transaction(
          id: 'g',
          date: date,
          amount: 23,
          category: 'Groceries',
          categoryId: 'groceries',
          description: 'Grocery receipt',
          expenseType: ExpenseType.regular,
        ),
        Transaction(
          id: 's',
          date: date,
          amount: 11,
          category: 'Household Supplies',
          categoryId: 'supplies',
          description: 'Supply receipt',
          expenseType: ExpenseType.plannedOccasional,
        ),
        Transaction(
          id: 'b',
          date: date,
          amount: 5,
          category: 'Food / Household',
          description: 'Legacy food receipt',
          expenseType: ExpenseType.unknown,
        ),
        Transaction(
          id: 'c',
          date: date,
          amount: 21,
          category: 'My pottery class',
          categoryId: 'custom',
          description: 'Custom class receipt',
          expenseType: ExpenseType.unexpectedOccasional,
        ),
        Transaction(
          id: 'l',
          date: date,
          amount: 7,
          category: 'Lifestyle / Misc',
          description: 'Legacy lifestyle receipt',
          expenseType: ExpenseType.regular,
        ),
        Transaction(
          id: 't',
          date: date,
          amount: 9,
          category: 'Transport',
          description: 'Transport receipt',
          expenseType: ExpenseType.regular,
        ),
        Transaction(
          id: 'x',
          date: DateTime(now.year - 2, 1),
          amount: 99,
          category: 'Groceries',
          description: 'Outside period receipt',
        ),
        Transaction(
          id: 'transfer',
          date: date,
          amount: 200,
          category: 'Transfers',
          description: 'Internal transfer receipt',
        ),
      ]);
  await tester.pumpWidget(
    MaterialApp(
      home: DashboardScreen(
        account: _Account(),
        isDarkMode: true,
        onDarkModeChanged: (_) async {},
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pumpAndSettle();
  if (period == 'month') {
    await tester.tap(find.byKey(const ValueKey('home-month-summary')));
    await tester.pumpAndSettle();
    tester
        .widget<MonthSelector>(find.byType(MonthSelector))
        .onSelected(DateTime(date.year, date.month));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(MonthlyBudgetCard),
        matching: find.text('Total actual spending'),
      ),
    );
    await tester.pumpAndSettle();
  } else {
    final card = find
        .ancestor(
          of: find.text(period == 'today' ? 'TODAY' : 'THIS YEAR'),
          matching: find.byType(GestureDetector),
        )
        .first;
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final (width, period) in [
    (390.0, 'month'),
    (1200.0, 'month'),
    (390.0, 'today'),
    (1200.0, 'year'),
  ]) {
    testWidgets(
      'default $period parent category opens all its transactions at $width',
      (tester) async {
        await boot(tester, width: width, period: period);
        await tapRow(tester, 'Food / Household');
        for (final note in [
          'Grocery receipt',
          'Supply receipt',
          'Legacy food receipt',
        ]) {
          expect(inSheet(find.text(note)), findsOneWidget);
        }
        for (final note in [
          'Custom class receipt',
          'Transport receipt',
          'Outside period receipt',
          'Internal transfer receipt',
        ]) {
          expect(inSheet(find.text(note)), findsNothing);
        }
        await tester.tap(find.byTooltip('Close transactions'));
        await tester.pumpAndSettle();
        await tapRow(tester, 'Lifestyle / Misc');
        expect(inSheet(find.text('Custom class receipt')), findsOneWidget);
        expect(inSheet(find.text('Legacy lifestyle receipt')), findsOneWidget);
        expect(inSheet(find.text('Grocery receipt')), findsNothing);
        await tester.tap(find.byTooltip('Close transactions'));
        await tester.pumpAndSettle();
        expect(inSheet(find.text('Food / Household')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'Actual Regular Unknown and Occasional retain exact category and type buckets',
    (tester) async {
      await boot(tester, width: 1200, period: 'month');
      for (final (filter, category, note) in [
        ('Actual', 'Groceries', 'Grocery receipt'),
        ('Regular', 'Groceries', 'Grocery receipt'),
        ('Unknown', 'Food / Household', 'Legacy food receipt'),
        ('Occasional', 'Household Supplies', 'Supply receipt'),
      ]) {
        final chip = find.ancestor(
          of: inSheet(find.text(filter)),
          matching: find.byType(ActionChip),
        );
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        await tapRow(tester, category);
        expect(inSheet(find.text(note)), findsOneWidget);
        for (final other in [
          'Grocery receipt',
          'Supply receipt',
          'Legacy food receipt',
          'Custom class receipt',
          'Transport receipt',
          'Outside period receipt',
          'Internal transfer receipt',
        ].where((item) => item != note)) {
          expect(inSheet(find.text(other)), findsNothing);
        }
        await tester.tap(find.byTooltip('Close transactions'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close breakdown').last);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
