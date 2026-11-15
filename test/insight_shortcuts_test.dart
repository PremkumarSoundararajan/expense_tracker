import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pocket_ledger/main.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/financial_baseline_service.dart';
import 'package:pocket_ledger/services/local_transaction_store.dart';
import 'package:pocket_ledger/widgets/insight_shortcuts.dart';
import 'package:pocket_ledger/widgets/merchant_baseline_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Account implements GoogleSignInAccount {
  @override
  String get email => 'shortcut-test@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Transaction> rows(double classified) => [
  Transaction(
    id: 'classified',
    date: DateTime(2026, 10),
    amount: classified,
    description: 'Grocery store',
    category: 'Groceries',
    baselineGroup: 'Essential',
  ),
  Transaction(
    id: 'unknown',
    date: DateTime(2026, 10),
    amount: 100 - classified,
    description: 'Other shop',
    category: 'Shopping',
  ),
];

void main() {
  for (final coverage in [0.0, 49.0, 50.0, 79.0, 80.0, 100.0]) {
    testWidgets('locks use existing readiness at $coverage percent', (
      tester,
    ) async {
      var action = '';
      Future<void> show(double percent) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InsightShortcuts(
              summary: FinancialBaselineService().summarize(
                transactions: rows(percent),
                mappings: const [],
              ),
              onTrends: () => action = 'trends',
              onSpots: () => action = 'spots',
              onBudget: () => action = 'budget',
              onSavings: () => action = 'savings',
              onTargets: () => action = 'targets',
              onLocked: (label) => action = 'locked:$label',
            ),
          ),
        ),
      );
      await show(coverage);
      expect(
        find.byIcon(Icons.lock_outline),
        coverage < 50 ? findsNWidgets(2) : findsNothing,
      );
      for (final entry in {
        'Spending trends': 'trends',
        'Spending spots': 'spots',
        'Suggested budget': 'budget',
      }.entries) {
        await tester.tap(find.text(entry.key));
        expect(action, entry.value);
      }
      await tester.tap(find.text('Savings insights'));
      expect(action, coverage < 50 ? 'locked:Savings insights' : 'savings');
      await tester.tap(find.text('Spending targets'));
      expect(action, coverage < 50 ? 'locked:Spending targets' : 'targets');
      // Both unlock and relock when saved source data changes.
      await show(coverage < 50 ? 80 : 0);
      expect(
        find.byIcon(Icons.lock_outline),
        coverage < 50 ? findsNothing : findsNWidgets(2),
      );
    });
  }

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('two explicit rows at $width text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: width == 390 ? Brightness.dark : Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: InsightShortcuts(
                  summary: FinancialBaselineService().summarize(
                    transactions: rows(0),
                    mappings: const [],
                  ),
                  onTrends: () {},
                  onSpots: () {},
                  onBudget: () {},
                  onSavings: () {},
                  onTargets: () {},
                  onLocked: (_) {},
                ),
              ),
            ),
          ),
        );
        Rect button(String label) =>
            tester.getRect(find.byKey(ValueKey('insight-shortcut-$label')));
        expect(button('Spending trends').top, button('Spending spots').top);
        expect(button('Spending trends').top, button('Suggested budget').top);
        expect(button('Savings insights').top, button('Spending targets').top);
        expect(
          button('Savings insights').top,
          greaterThan(button('Suggested budget').bottom),
        );
        expect(
          button('Savings insights').width,
          button('Spending trends').width,
        );
        expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'Dashboard explains lock and takes user to remaining classification',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'currency_symbol': r'$'});
      await LocalTransactionStore(accountKey: 'shortcut-test@example.com')
          .saveCached(rows(0));
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
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
      await tester.tap(find.text('Savings insights'));
      await tester.pumpAndSettle();
      expect(find.text('Unlock Savings insights'), findsOneWidget);
      expect(find.textContaining('at least 50%'), findsOneWidget);
      await tester.tap(find.text('Classify expenses'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(MerchantBaselinePanel), findsOneWidget);
      expect(
        tester
            .widget<MerchantBaselinePanel>(find.byType(MerchantBaselinePanel))
            .showRemainingInitially,
        isTrue,
      );
      expect(find.text('Financial Baseline').hitTestable(), findsOneWidget);
      final panel = tester.widget<MerchantBaselinePanel>(
        find.byType(MerchantBaselinePanel),
      );
      final save = panel.onSaved([
        {
          'id': 'm:other shop',
          'kind': 'merchant',
          'name': 'Other shop',
          'aliases': ['Other shop'],
          'category': 'Shopping',
          'group': 'Potentially Flexible',
          'expenseType': 'Regular',
        },
      ]);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      await save;
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<InsightShortcuts>(find.byType(InsightShortcuts))
            .baselineReady,
        isTrue,
      );
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
