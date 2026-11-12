import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/main.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/local_transaction_store.dart';
import 'package:pocket_ledger/services/merchant_classification_store.dart';
import 'package:pocket_ledger/widgets/merchant_baseline_panel.dart';
import 'package:pocket_ledger/widgets/spending_summary_widget.dart';
import 'package:pocket_ledger/widgets/favourite_spending_spots_widget.dart';
import 'package:pocket_ledger/widgets/monthly_budget_card.dart';
import 'package:pocket_ledger/widgets/monthly_budget_target_dialog.dart';
import 'package:pocket_ledger/widgets/suggested_budget_sheet.dart';

class _Account implements GoogleSignInAccount {
  @override
  String get email => 'merchant-insights@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'budget drilldown closes nested dialogs and opens all remaining merchants',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'currency_symbol': r'$',
        'monthly_target': 5000.0,
      });
      final now = DateTime.now();
      await MerchantClassificationStore('merchant-insights@example.com').save([
        {
          'id': 'm:alpha',
          'kind': 'merchant',
          'name': 'Alpha',
          'aliases': ['Alpha'],
          'category': 'Food / Household',
          'categoryId': 'food-household',
          'group': 'Essential',
          'expenseType': 'Regular',
        },
      ]);
      await LocalTransactionStore(accountKey: 'merchant-insights@example.com')
          .saveCached([
            for (final offset in [1, 2])
              Transaction(
                id: 'alpha-$offset',
                date: DateTime(now.year, now.month - offset, 1),
                amount: 400,
                description: 'Alpha',
                category: 'Food / Household',
                categoryId: 'food-household',
                baselineGroup: 'Essential',
                expenseType: ExpenseType.regular,
              ),
            Transaction(
              id: 'beta',
              date: DateTime(now.year, now.month - 1, 5),
              amount: 150,
              description: 'Beta',
              category: 'Food / Household',
              categoryId: 'food-household',
              expenseType: ExpenseType.unknown,
            ),
            Transaction(
              id: 'gamma',
              date: DateTime(now.year, now.month - 2, 5),
              amount: 50,
              description: 'Gamma',
              category: 'Food / Household',
              categoryId: 'food-household',
              expenseType: ExpenseType.unknown,
            ),
          ]);
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            account: _Account(),
            isDarkMode: false,
            onDarkModeChanged: (_) async {},
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-month-summary')));
      await tester.pumpAndSettle();
      // Open the same target dialog used by the Home budget action.
      tester
          .widget<MonthlyBudgetCard>(find.byType(MonthlyBudgetCard))
          .onSetTargetPressed();
      await tester.pumpAndSettle();
      expect(find.byType(MonthlyBudgetTargetDialog), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('suggested-budget-dialog-card')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SuggestedBudgetBreakdown), findsOneWidget);
      await tester.tap(find.text('Classify remaining expenses').last);
      await tester.pumpAndSettle();
      expect(find.byType(MonthlyBudgetTargetDialog), findsNothing);
      expect(find.byType(SuggestedBudgetBreakdown), findsNothing);
      expect(find.byType(MerchantBaselinePanel), findsOneWidget);
      expect(find.text('Beta · 1'), findsOneWidget);
      expect(find.text('Gamma · 1'), findsOneWidget);
      expect(find.text('Alpha · 2'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insights').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('You can stop here'), findsOneWidget);
      expect(find.text('Beta · 1'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [1280.0, 390.0]) {
    testWidgets(
      'Insights prioritizes merchant review and opens other insights on demand at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'currency_symbol': r'$',
          'monthly_target': 5000.0,
        });
        await LocalTransactionStore(accountKey: 'merchant-insights@example.com')
            .saveCached([
              for (var i = 0; i < 20; i++)
                Transaction(
                  id: 'merchant-$i',
                  date: DateTime(2026, 10, 5),
                  amount: 100 + i.toDouble(),
                  category: 'Food / Household',
                  categoryId: 'food-household',
                  description: 'Merchant ${String.fromCharCode(65 + i)}',
                  expenseType: ExpenseType.regular,
                ),
            ]);
        await tester.pumpWidget(
          MaterialApp(
            home: DashboardScreen(
              account: _Account(),
              isDarkMode: false,
              onDarkModeChanged: (_) async {},
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 400));
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('Insights').last);
        await tester.pumpAndSettle();
        expect(find.byType(MerchantBaselinePanel), findsOneWidget);
        expect(find.byType(SpendingSummaryWidget), findsNothing);
        expect(find.byType(FavouriteSpendingSpotsWidget), findsNothing);
        expect(
          find.byKey(const ValueKey('baseline-unclassified')),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsNothing);
        expect(
          tester.getSize(find.byType(MerchantBaselinePanel)).height,
          lessThan(350),
        );
        expect(find.text('Merchant'), findsNothing);
        // Only the app bar and bottom navigation carry the Insights label.
        expect(find.text('Insights'), findsNWidgets(2));
        final baselineTop = tester
            .getTopLeft(find.byType(MerchantBaselinePanel))
            .dy;
        for (final label in [
          'Spending trends',
          'Spending spots',
          'Savings insights',
          'Suggested budget',
          'Spending targets',
        ]) {
          final shortcut = find.text(label);
          expect(shortcut.hitTestable(), findsOneWidget);
          expect(tester.getTopLeft(shortcut).dy, lessThan(baselineTop));
        }
        final trends = find.text('Spending trends');
        await tester.ensureVisible(trends);
        await tester.pumpAndSettle();
        await tester.tap(trends);
        await tester.pumpAndSettle();
        expect(find.byType(SpendingSummaryWidget), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings').last);
        await tester.pumpAndSettle();
        final webLink = find.byKey(
          const ValueKey('pocket-ledger-web-settings'),
        );
        await tester.ensureVisible(webLink);
        await tester.pumpAndSettle();
        expect(webLink.hitTestable(), findsOneWidget);
      },
    );
  }
}
