import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pocket_ledger/main.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/local_transaction_store.dart';
import 'package:pocket_ledger/utils/currency_format.dart';
import 'package:pocket_ledger/utils/transaction_period_format.dart';
import 'package:pocket_ledger/widgets/month_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Account implements GoogleSignInAccount {
  @override
  String get email => 'home-test@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final previousYear in [false, true]) {
    testWidgets(
      'Today and This Year survive collapsing a ${previousYear ? 'previous-year' : 'past-month'} selection',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'currency_symbol': r'$',
          'monthly_target': 500.0,
        });
        final now = DateTime.now();
        final past = previousYear
            ? DateTime(now.year - 1, 10, 5)
            : DateTime(now.year, now.month - 1, 5);
        final ledger = [
          Transaction(
            id: 'today',
            date: now,
            amount: 17,
            category: 'Food / Household',
            description: 'Today shop',
          ),
          Transaction(
            id: 'past',
            date: past,
            amount: 44,
            category: 'Food / Household',
            description: 'Past shop',
          ),
        ];
        await LocalTransactionStore(accountKey: 'home-test@example.com')
            .saveCached(ledger);
        await tester.pumpWidget(
          MaterialApp(
            home: DashboardScreen(
              account: _Account(),
              isDarkMode: false,
              onDarkModeChanged: (_) async {},
            ),
          ),
        );
        // Allow local loading and the existing three short offline auth retries.
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 400));
        }
        await tester.pumpAndSettle();
        final summary = find.byKey(const ValueKey('home-month-summary'));
        await tester.tap(summary);
        await tester.pumpAndSettle();
        final selector = tester.widget<MonthSelector>(
          find.byType(MonthSelector),
        );
        selector.onSelected(DateTime(past.year, past.month));
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: summary,
                matching: find.text(formatMonthHeading(past, now: now)),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Within budget'), findsOneWidget);
        expect(find.textContaining('budget remaining'), findsNothing);
        expect(find.textContaining('0% used'), findsNothing);
        expect(find.text('TODAY'), findsOneWidget);
        expect(find.text('THIS YEAR'), findsOneWidget);
        expect(
          find.descendant(
            of: summary,
            matching: find.text(formatMonthHeading(past, now: now)),
          ),
          findsOneWidget,
        );
        final expectedYear = ledger
            .where((t) => t.date.year == now.year)
            .fold<double>(0, (sum, t) => sum + t.amount);
        final yearCard = find
            .ancestor(
              of: find.text('THIS YEAR'),
              matching: find.byType(GestureDetector),
            )
            .first;
        expect(
          find.descendant(
            of: yearCard,
            matching: find.text(formatWholeCurrency(expectedYear, r'$')),
          ),
          findsOneWidget,
        );
        await tester.tap(yearCard);
        await tester.pumpAndSettle();
        expect(find.text('This Year Spending Breakdown'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text(formatFullCurrency(expectedYear, r'$')),
          ),
          findsWidgets,
        );
        await tester.tap(find.byTooltip('Close breakdown'));
        await tester.pumpAndSettle();
        final todayCard = find
            .ancestor(
              of: find.text('TODAY'),
              matching: find.byType(GestureDetector),
            )
            .first;
        expect(
          find.descendant(
            of: todayCard,
            matching: find.text(formatWholeCurrency(17, r'$')),
          ),
          findsOneWidget,
        );
        await tester.tap(todayCard);
        await tester.pumpAndSettle();
        expect(find.text('Today Spending Breakdown'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text(formatFullCurrency(17, r'$')),
          ),
          findsWidgets,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
