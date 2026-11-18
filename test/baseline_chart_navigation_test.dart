import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/app_theme.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/merchant_classification_store.dart';
import 'package:pocket_ledger/widgets/financial_baseline_screen.dart';
import 'package:pocket_ledger/widgets/merchant_baseline_panel.dart';
import 'package:pocket_ledger/widgets/spending_breakdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets('spending charts appear in insights at $width', (tester) async {
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
          'id': 'm:cafe',
          'kind': 'merchant',
          'name': 'Cafe',
          'aliases': ['Cafe'],
          'category': 'Food',
          'categoryId': 'food',
          'group': 'Potentially Flexible',
          'expenseType': 'Regular',
        },
        {
          'id': 'm:excluded',
          'kind': 'merchant',
          'name': 'Excluded',
          'aliases': ['Excluded'],
          'category': 'NA',
          'group': 'Unclassified',
          'na': true,
        },
        {
          'id': 't:exception',
          'kind': 'transaction',
          'transactionId': 'exception',
          'category': 'Food',
          'categoryId': 'food',
          'group': 'Potentially Flexible',
        },
      ]);
      final rows = [
        for (final (id, name, amount) in [
          ('1', 'Market', 100.0),
          ('2', 'Cafe', 50.0),
          ('3', 'Excluded', 20.0),
          ('exception', 'Excluded', 10.0),
        ])
          Transaction(
            id: id,
            description: name,
            date: DateTime(2025, 1, 1),
            amount: amount,
            category: 'Unknown',
          ),
      ];
      const categories = [
        ExpenseCategory(id: 'food', parentId: 'food-household', name: 'Food'),
      ];
      final effective = rows.map(store.index.apply).toList();
      var reviewed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: width == 390 ? AppTheme.dark : AppTheme.light,
          home: FinancialBaselineScreen(
            insightsOnly: true,
            transactions: effective,
            initialMappings: const [],
            categories: categories,
            merchantClassificationIndex: store.index,
            onReviewClassifiedMerchants: () => reviewed = true,
            currencySymbol: r'$',
            onMappingsSaved: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final average = find.byKey(const ValueKey('baseline-average-period'));
      final breakdown = find.byKey(
        const ValueKey('insights-spending-breakdown'),
      );
      final trend = find.byKey(const ValueKey('open-full-spending-trend'));
      expect(
        tester.getTopLeft(average).dy,
        lessThan(tester.getTopLeft(breakdown).dy),
      );
      expect(
        tester.getTopLeft(breakdown).dy,
        lessThan(tester.getTopLeft(trend).dy),
      );
      expect(
        find.text(
          'All recorded eligible history · totals, not monthly averages',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Essentiality classified: 88.9% of spending'),
        findsOneWidget,
      );
      expect(find.textContaining('62.5%'), findsOneWidget);
      expect(find.textContaining('37.5%'), findsOneWidget);
      final category = find.descendant(
        of: breakdown,
        matching: find.text('Category'),
      );
      await tester.ensureVisible(category);
      await tester.tap(category);
      await tester.pumpAndSettle();
      expect(
        find.text('Categories classified: 88.9% of spending'),
        findsOneWidget,
      );
      expect(find.text('Food'), findsOneWidget);
      final review = find.byKey(const ValueKey('review-classified-merchants'));
      await tester.ensureVisible(review);
      await tester.tap(review);
      expect(reviewed, isTrue);
      await tester.tap(find.byTooltip('Close insights'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MerchantBaselinePanel(
              showClassifiedInitially: true,
              transactions: effective,
              categories: categories,
              legacyMappings: const [],
              store: store,
              currencySymbol: r'$',
              onSaved: (_) async => 'Saved',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SpendingBreakdown), findsNothing);
      expect(find.text('View spending charts'), findsNothing);
      expect(
        find.byKey(const ValueKey('baseline-search-classified')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
