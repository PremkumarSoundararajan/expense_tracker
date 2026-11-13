import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/main.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/local_transaction_store.dart';
import 'package:pocket_ledger/services/statement_document_picker.dart';

class _Account implements GoogleSignInAccount {
  @override
  String get email => 'expenses-panel@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> openExpenses(
  WidgetTester tester, {
  required double width,
  bool dark = false,
  bool empty = false,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({'currency_symbol': r'$'});
  await LocalTransactionStore(accountKey: 'expenses-panel@example.com')
      .saveCached([
        if (!empty)
          for (var i = 0; i < 3; i++)
            Transaction(
              id: 'expense-$i',
              date: DateTime.now().subtract(Duration(days: i)),
              amount: 10 + i.toDouble(),
              category: 'Food / Household',
              description: 'Recorded expense $i',
            ),
      ]);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B4D3E),
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
      ),
      home: DashboardScreen(
        account: _Account(),
        isDarkMode: dark,
        onDarkModeChanged: (_) async {},
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.tap(find.text('Expenses').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Import Statements directly opens the device picker without source options or a link',
    (tester) async {
      var picks = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(StatementDocumentPicker.channel, (
        call,
      ) async {
        expect(call.method, 'pickStatement');
        picks++;
        return null; // User cancels in the device/Drive picker.
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          StatementDocumentPicker.channel,
          null,
        ),
      );
      await openExpenses(tester, width: 390);
      final button = find.byKey(
        const ValueKey('import_reconcile_statements_button'),
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(picks, 1);
      expect(find.text('CSV / Excel file'), findsNothing);
      expect(find.text('Google Sheets'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      expect(find.text('3 transactions'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  for (final width in [320.0, 390.0, 1200.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'Expenses import panel and lazy ledger at $width (dark=$dark)',
        (tester) async {
          await openExpenses(tester, width: width, dark: dark);
          final panel = find.byKey(const ValueKey('expenses-import-panel'));
          final button = find.byKey(
            const ValueKey('import_reconcile_statements_button'),
          );
          final note = find.text(
            'CSV, Excel & Google Sheets · Duplicates checked\nYou can review/edit before import.',
          );
          expect(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.text('Expenses'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: panel, matching: find.text('Expenses')),
            findsNothing,
          );
          expect(
            find.descendant(of: panel, matching: find.text('3 transactions')),
            findsNothing,
          );
          expect(find.descendant(of: panel, matching: button), findsOneWidget);
          expect(find.text('Import Statements'), findsOneWidget);
          expect(
            tester.getSize(button).width,
            closeTo(tester.getSize(panel).width - 34, .1),
          );
          expect(tester.getSize(button).height, greaterThanOrEqualTo(50));
          expect(
            tester.getRect(find.text('3 transactions')).top,
            greaterThanOrEqualTo(tester.getRect(panel).bottom),
          );
          expect(
            tester.getRect(button).bottom,
            lessThan(tester.getRect(note).top),
          );
          for (var i = 0; i < 3; i++) {
            expect(find.text('Recorded expense $i'), findsOneWidget);
          }
          expect(
            tester.getTopLeft(find.text('Recorded expense 0')).dy,
            lessThan(tester.getTopLeft(find.text('Recorded expense 2')).dy),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
  testWidgets('empty Expenses still offers import with one empty state', (
    tester,
  ) async {
    await openExpenses(tester, width: 390, empty: true);
    expect(find.text('0 transactions'), findsOneWidget);
    expect(find.text('No expenses recorded yet.'), findsOneWidget);
    expect(find.text('Import Statements'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
