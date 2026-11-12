import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pocket_ledger/main.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/local_transaction_store.dart';
import 'package:pocket_ledger/widgets/help_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Account implements GoogleSignInAccount {
  @override
  String get email => 'help-test@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'Help is searchable and readable on a narrow phone (dark=$dark)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: const HelpScreen(),
          ),
        );
        await tester.enterText(find.byType(TextField), 'currency');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings, currency and reminders'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('does not convert recorded amounts'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byType(TextField), 'zznomatch');
        await tester.pumpAndSettle();
        expect(find.textContaining('No matching topics.'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Insights help'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'suggested budget');
        await tester.pumpAndSettle();
        await tester.tap(find.text('How is the suggested budget calculated?'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Regular spending only'), findsOneWidget);
        expect(find.textContaining('10% buffer'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Help & how it works'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'Settings and Insights open the appropriate Help without a retirement notice',
    (tester) async {
      SharedPreferences.setMockInitialValues({'currency_symbol': r'$'});
      await LocalTransactionStore(accountKey: 'help-test@example.com')
          .saveCached([
            Transaction(
              id: 'help-expense',
              date: DateTime.now(),
              amount: 25,
              category: 'Food / Household',
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
      expect(find.text('Privacy update'), findsNothing);
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expect(find.text('Privacy update'), findsNothing);
      await tester.tap(find.text('Help & how it works'));
      await tester.pumpAndSettle();
      expect(find.byType(HelpScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insights').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Insights help'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<HelpScreen>(find.byType(HelpScreen)).insightsOnly,
        isTrue,
      );
      expect(
        find.text('Financial Baseline: start with the biggest merchants'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
