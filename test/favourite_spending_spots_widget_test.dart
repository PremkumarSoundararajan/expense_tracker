import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/widgets/favourite_spending_spots_widget.dart';

void main() {
  testWidgets('shows only the five highest actual spending spots', (
    tester,
  ) async {
    final transactions = [
      for (var index = 1; index <= 6; index++)
        Transaction(
          date: DateTime(2025, 5, 1),
          amount: index * 10,
          category: 'Food / Household',
          description: 'Merchant ${String.fromCharCode(64 + index)}',
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FavouriteSpendingSpotsWidget(
            transactions: transactions,
            currencySymbol: '\$',
            now: DateTime(2025, 8, 15),
          ),
        ),
      ),
    );

    expect(find.text('Merchant F'), findsOneWidget);
    expect(find.text('Merchant B'), findsOneWidget);
    expect(find.text('Merchant A'), findsNothing);
  });

  testWidgets('opens a spot detail with the original transaction and returns', (
    tester,
  ) async {
    final transaction = Transaction(
      date: DateTime(2025, 6, 12),
      amount: 45,
      category: 'Food / Household',
      description: 'Tokyo Cafe #123 WEB ID: 987654',
      expenseType: ExpenseType.plannedOccasional,
      id: 'spot-detail-1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FavouriteSpendingSpotsWidget(
            transactions: [
              transaction,
              Transaction(
                date: DateTime(2025, 5, 1),
                amount: 1,
                category: 'Food / Household',
                description: 'History start',
              ),
            ],
            currencySymbol: '\$',
            now: DateTime(2025, 8, 15),
          ),
        ),
      ),
    );

    expect(find.text('Your Favourite Spending Spots'), findsOneWidget);
    await tester.tap(find.text('Tokyo Cafe'));
    await tester.pumpAndSettle();

    expect(find.text('Tokyo Cafe'), findsOneWidget);
    expect(find.text('Tokyo Cafe #123 WEB ID: 987654'), findsOneWidget);
    expect(
      find.text('2025-06-12 · Food / Household · Planned Occasional'),
      findsOneWidget,
    );
    expect(find.text('\$45'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Your Favourite Spending Spots'), findsOneWidget);
  });
}
