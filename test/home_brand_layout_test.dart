import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pocket_ledger/main.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/local_transaction_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Account implements GoogleSignInAccount {
  @override
  String get email => 'home-brand-test@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets(
      'Home branding and summary group remain separate from expense entry at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'currency_symbol': r'$',
          'email_scan_retirement_notice_v1': true,
        });
        await LocalTransactionStore(accountKey: 'home-brand-test@example.com')
            .saveCached([
              Transaction(
                id: 'expense',
                date: DateTime.now(),
                amount: 32068,
                category: 'Food / Household',
              ),
            ]);
        await tester.pumpWidget(
          MaterialApp(
            home: DashboardScreen(
              account: _Account(),
              isDarkMode: width == 390,
              onDarkModeChanged: (_) async {},
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 400));
        }
        await tester.pumpAndSettle();
        final group = find.byKey(const ValueKey('home-spending-summary'));
        expect(find.byKey(const ValueKey('home-brand-logo')), findsOneWidget);
        expect(
          find.descendant(
            of: group,
            matching: find.byKey(const ValueKey('home-month-summary')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: group, matching: find.text('TODAY')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: group, matching: find.text('THIS YEAR')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: group, matching: find.text('Add New Expense')),
          findsNothing,
        );
        expect(
          tester.getRect(group).bottom + 20,
          lessThanOrEqualTo(tester.getRect(find.text('Add New Expense')).top),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
