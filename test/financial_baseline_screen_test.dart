import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/financial_baseline.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/widgets/financial_baseline_screen.dart';

void main() {
  testWidgets('shows merchant pool above three direct group cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialBaselineScreen(
          transactions: [_transaction(DateTime(2025, 1), 60, 'LOCAL MARKET')],
          initialMappings: const [],
          currencySymbol: r'$',
          onMappingsSaved: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pool = find.byKey(const ValueKey('all-merchants-pool'));
    expect(pool, findsOneWidget);
    expect(find.text('Unassigned Merchants'), findsOneWidget);
    expect(find.text('LOCAL MARKET'), findsOneWidget);
    expect(
      tester.getTopLeft(pool).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('baseline-dashboard'))).dy,
      ),
    );
    final groups = find.byKey(const ValueKey('baseline-groups-heading'));
    await _scrollTo(tester, groups);
    for (final group in BaselineGroup.values) {
      final groupCard = find.byKey(ValueKey('baseline-group-${group.name}'));
      await _scrollTo(tester, groupCard);
      expect(groupCard, findsOneWidget);
    }
    expect(find.text('Expense type canvas'), findsNothing);
  });

  testWidgets('tapping a merchant assigns it directly to a lifestyle group', (
    tester,
  ) async {
    List<FinancialBaselineMapping>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialBaselineScreen(
          transactions: [
            _transaction(DateTime(2025, 1), 80, 'ATMOS ENERGY WEB ID 812'),
            _transaction(DateTime(2025, 2), 100, 'ATMOS ENERGY PYMT 9002'),
          ],
          initialMappings: const [],
          currencySymbol: r'$',
          onMappingsSaved: (mappings) async {
            saved = mappings;
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final merchant = find.byKey(
      const ValueKey('unmapped-merchant-atmos energy'),
    );
    await _scrollTo(tester, merchant);
    await tester.tap(merchant);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('assign-to-group-essential')),
      findsOneWidget,
    );
    expect(find.text('Electricity'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('assign-to-group-essential')));
    await tester.pumpAndSettle();

    expect(saved, [
      const FinancialBaselineMapping(
        merchantFingerprint: 'ATMOS ENERGY',
        group: BaselineGroup.essential,
      ),
    ]);
    final mappedMerchant = find.byKey(
      const ValueKey('mapped-essential-atmos energy'),
    );
    await _scrollTo(tester, mappedMerchant);
    expect(mappedMerchant, findsOneWidget);
    final essentialAverage = find.byKey(
      const ValueKey('baseline-group-average-essential'),
    );
    await _scrollTo(tester, essentialAverage);
    expect(tester.widget<Text>(essentialAverage).data, r'$90 / mo');
    expect(
      find.byKey(const ValueKey('unmapped-merchant-atmos energy')),
      findsNothing,
    );
  });

  testWidgets('search filters merchant pool case-insensitively and clears', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialBaselineScreen(
          transactions: [
            _transaction(DateTime(2025, 1), 40, 'KROGER #8'),
            _transaction(DateTime(2025, 1), 20, 'HEB #42'),
          ],
          initialMappings: const [],
          currencySymbol: r'$',
          onMappingsSaved: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final search = find.byKey(const ValueKey('all-merchants-search'));
    await _scrollTo(tester, search);
    await tester.enterText(search, 'kRo');
    await tester.pumpAndSettle();
    expect(find.text('KROGER'), findsOneWidget);
    expect(find.text('HEB'), findsNothing);
    expect(find.text('1 of 2 merchants'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clear-merchant-search')));
    await tester.pumpAndSettle();
    expect(find.text('KROGER'), findsOneWidget);
    expect(find.text('HEB'), findsOneWidget);
    expect(find.text('2 unassigned merchants'), findsOneWidget);
  });

  testWidgets('batch selection assigns merchants directly to a group', (
    tester,
  ) async {
    List<FinancialBaselineMapping>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialBaselineScreen(
          transactions: [
            _transaction(DateTime(2025, 1), 40, 'HEB #42'),
            _transaction(DateTime(2025, 1), 50, 'KROGER #8'),
            _transaction(DateTime(2025, 1), 60, 'WALGREENS #11'),
          ],
          initialMappings: const [],
          currencySymbol: r'$',
          onMappingsSaved: (mappings) async {
            saved = mappings;
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('toggle-merchant-multi-select'));
    await _scrollTo(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final heb = find.byKey(const ValueKey('unmapped-merchant-heb'));
    await _scrollTo(tester, heb);
    await tester.longPress(heb);
    final kroger = find.byKey(const ValueKey('unmapped-merchant-kroger'));
    await _scrollTo(tester, kroger);
    await tester.tap(kroger);
    final walgreens = find.byKey(const ValueKey('unmapped-merchant-walgreens'));
    await _scrollTo(tester, walgreens);
    await tester.tap(walgreens);
    await tester.pumpAndSettle();
    expect(find.text('Assign 3 selected merchants'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assign-selected-merchants')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assign-to-group-committed')));
    await tester.pumpAndSettle();

    expect(saved, [
      const FinancialBaselineMapping(
        merchantFingerprint: 'HEB',
        group: BaselineGroup.committed,
      ),
      const FinancialBaselineMapping(
        merchantFingerprint: 'KROGER',
        group: BaselineGroup.committed,
      ),
      const FinancialBaselineMapping(
        merchantFingerprint: 'WALGREENS',
        group: BaselineGroup.committed,
      ),
    ]);
    expect(find.text('Assign 3 selected merchants'), findsNothing);
    for (final merchant in ['heb', 'kroger', 'walgreens']) {
      expect(find.byKey(ValueKey('unmapped-merchant-$merchant')), findsNothing);
    }
  });

  testWidgets('unassigned spending remains unclassified until mapped', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialBaselineScreen(
          transactions: [
            _transaction(DateTime(2025, 1), 50, 'UNKNOWN LOCAL SHOP'),
          ],
          initialMappings: const [],
          currencySymbol: r'$',
          onMappingsSaved: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final unclassified = find.byKey(
      const ValueKey('baseline-metric-unclassified'),
    );
    await _scrollTo(tester, unclassified);
    expect(
      find.descendant(
        of: unclassified,
        matching: find.textContaining(r'$50 / mo'),
      ),
      findsOneWidget,
    );
  });
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Transaction _transaction(DateTime date, double amount, String description) =>
    Transaction(
      date: date,
      amount: amount,
      category: 'Other',
      description: description,
    );
