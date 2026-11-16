import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pocket_ledger/app_theme.dart';
import 'package:pocket_ledger/main.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/local_transaction_store.dart';
import 'package:pocket_ledger/services/suggested_budget_service.dart';
import 'package:pocket_ledger/widgets/merchant_baseline_panel.dart';
import 'package:pocket_ledger/widgets/suggested_budget_unavailable_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Account implements GoogleSignInAccount {
  @override
  String get email => 'budget-availability@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime(2026, 11, 15);
  final service = SuggestedBudgetService();
  Transaction expense(
    DateTime date, {
    ExpenseType type = ExpenseType.regular,
    double amount = 100,
  }) => Transaction(
    date: date,
    amount: amount,
    category: 'Groceries',
    description: 'Shop',
    expenseType: type,
  );
  SuggestedBudgetAssessment assess(List<Transaction> rows) =>
      service.assess(transactions: rows, now: now);

  test(
    '265 Unknown imports explain missing classification rather than no-op',
    () {
      final result = assess(
        List.generate(
          265,
          (i) =>
              expense(DateTime(2026, 7 + i % 4, 1), type: ExpenseType.unknown),
        ),
      );
      expect(result.suggestion, isNull);
      expect(
        result.reason,
        SuggestedBudgetUnavailableReason.needsClassification,
      );
      expect(result.unknownCount, 265);
    },
  );

  test(
    'empty and current-month-only history explain completed-month requirement',
    () {
      for (final rows in [
        <Transaction>[],
        [expense(now)],
      ]) {
        expect(
          assess(rows).reason,
          SuggestedBudgetUnavailableReason.noCompletedSpending,
        );
      }
    },
  );

  test(
    'planned-only spending does not tell users to classify it as Regular',
    () {
      expect(
        assess([
          expense(DateTime(2026, 8, 1), type: ExpenseType.plannedOccasional),
        ]).reason,
        SuggestedBudgetUnavailableReason.noRegularSpending,
      );
    },
  );

  test('partial first month is excluded from required history', () {
    final result = assess([expense(DateTime(2026, 9, 10))]);
    expect(result.reason, SuggestedBudgetUnavailableReason.insufficientHistory);
    expect(result.completedMonths, 1);
    expect(assess([expense(DateTime(2026, 9, 1))]).suggestion, isNotNull);
  });

  test(
    'stale history and fully refunded spending have distinct explanations',
    () {
      expect(
        assess([expense(DateTime(2025, 1, 1))]).reason,
        SuggestedBudgetUnavailableReason.noRecentRegularSpending,
      );
      expect(
        assess([
          expense(DateTime(2026, 9, 1)),
          expense(DateTime(2026, 9, 2), amount: -100),
        ]).reason,
        SuggestedBudgetUnavailableReason.noUsableSpending,
      );
    },
  );

  testWidgets('unavailable dialog is readable at 320px with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SuggestedBudgetNextStep? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  selected = await showDialog<SuggestedBudgetNextStep>(
                    context: context,
                    builder: (_) => SuggestedBudgetUnavailableDialog(
                      assessment: assess([
                        expense(
                          DateTime(2026, 8, 1),
                          type: ExpenseType.unknown,
                        ),
                      ]),
                    ),
                  ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'No expenses from completed months are marked Regular',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Set budget manually'));
    await tester.tap(find.text('Set budget manually'));
    await tester.pumpAndSettle();
    expect(selected, SuggestedBudgetNextStep.manual);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Dashboard Suggested budget opens explanation and classification action',
    (tester) async {
      SharedPreferences.setMockInitialValues({'currency_symbol': r'$'});
      final date = DateTime.now();
      await LocalTransactionStore(accountKey: 'budget-availability@example.com')
          .saveCached([
            for (var i = 0; i < 265; i++)
              Transaction(
                id: 'row-$i',
                date: DateTime(date.year, date.month - 1, 1),
                amount: 10,
                category: 'Groceries',
                description: 'Shop',
              ),
          ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
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
      await tester.tap(find.text('Suggested budget'));
      await tester.pumpAndSettle();
      expect(find.byType(SuggestedBudgetUnavailableDialog), findsOneWidget);
      expect(
        find.textContaining('265 completed-month expenses'),
        findsOneWidget,
      );
      await tester.tap(find.text('Classify expenses'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester
            .widget<MerchantBaselinePanel>(find.byType(MerchantBaselinePanel))
            .showRemainingInitially,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
