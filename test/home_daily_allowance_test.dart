import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pocket_ledger/app_theme.dart';
import 'package:pocket_ledger/main.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/budget_comparison.dart';
import 'package:pocket_ledger/services/local_transaction_store.dart';
import 'package:pocket_ledger/widgets/month_selector.dart';
import 'package:pocket_ledger/widgets/daily_allowance_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Account implements GoogleSignInAccount {
  @override
  String get email => 'daily-allowance@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('daily allowance includes Unknown, excludes Unexpected, and handles month end', () {
    final amounts = BudgetSpending.fromAmounts(
      total: 857,
      regular: 600,
      unexpected: 200,
    );
    expect(amounts.dailyAllowance(7093, now: DateTime(2026, 11, 15)), 402.25);
    expect(amounts.dailyAllowance(7093, now: DateTime(2026, 11, 30)), 6436);
    expect(amounts.dailyAllowance(7093, now: DateTime(2028, 2, 28)), 3218);
    expect(amounts.dailyAllowance(10, now: DateTime(2026, 11, 30)), 0);
    expect(amounts.dailyAllowance(null), isNull);
    expect(amounts.dailyAllowance(double.nan), isNull);
    expect(amounts.dailyAllowance(-1), isNull);
    expect(amounts.dailyAllowance(658, now: DateTime(2026, 11, 15)), .06);
  });

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets(
        'Today allowance stays current and readable at $width scale=$scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 1800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({
            'currency_symbol': r'$',
            'monthly_target': 10000.0,
          });
          final now = DateTime.now();
          final ledger = [
            Transaction(
              id: 'current',
              date: now,
              amount: 857,
              category: 'Food',
              expenseType: ExpenseType.regular,
            ),
            Transaction(
              id: 'unexpected',
              date: now,
              amount: 200,
              category: 'Repair',
              expenseType: ExpenseType.unexpectedOccasional,
            ),
            Transaction(
              id: 'past',
              date: DateTime(now.year, now.month - 1, 5),
              amount: 9000,
              category: 'Travel',
            ),
          ];
          await LocalTransactionStore(accountKey: 'daily-allowance@example.com')
              .saveCached(ledger);
          await tester.pumpWidget(
            MaterialApp(
              theme: width == 390 ? AppTheme.dark : AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
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
          final allowance = BudgetSpending.fromTransactions(
            ledger.where(
              (t) => t.date.month == now.month && t.date.year == now.year,
            ),
          ).dailyAllowance(10000, now: now)!.floor();
          final label = 'Safe to spend \$$allowance/day';
          final pill = find.byKey(const ValueKey('daily-allowance-pill'));
          final month = find.byKey(const ValueKey('home-month-summary'));
          expect(find.text(label), findsOneWidget);
          expect(tester.getSize(pill).height, greaterThanOrEqualTo(48));
          expect(find.descendant(of: month, matching: pill), findsNothing);
          final todayCard = find
              .ancestor(
                of: find.text('TODAY'),
                matching: find.byType(GestureDetector),
              )
              .first;
          final yearCard = find
              .ancestor(
                of: find.text('THIS YEAR'),
                matching: find.byType(GestureDetector),
              )
              .first;
          expect(
            find.descendant(of: todayCard, matching: pill),
            findsOneWidget,
          );
          expect(
            tester.getSize(todayCard).height,
            tester.getSize(yearCard).height,
          );
          // Test fonts have wide fixed-width glyphs. Allow wrapping rather than
          // truncation; the actual UI font is also checked in rendered previews.
          expect(
            tester.widget<Text>(find.text(label)).maxLines,
            width >= 360 && scale == 1 ? 1 : isNull,
          );
          expect(tester.widget<Text>(find.text(label)).style!.fontSize, 11.5);
          final selector = tester.widget<MonthSelector>(
            find.byType(MonthSelector),
          );
          selector.onSelected(DateTime(now.year, now.month - 1));
          await tester.pumpAndSettle();
          expect(find.text(label), findsOneWidget);
          await tester.ensureVisible(pill);
          await tester.tap(pill);
          await tester.pumpAndSettle();
          expect(find.byType(DailyAllowanceDialog), findsOneWidget);
          expect(find.byType(BottomSheet), findsNothing);
          expect(
            find.text(
              MaterialLocalizations.of(
                tester.element(find.byType(DailyAllowanceDialog)),
              ).formatMonthYear(now),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byType(DailyAllowanceDialog),
              matching: find.text(r'$857'),
            ),
            findsOneWidget,
          );
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
