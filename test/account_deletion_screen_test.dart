import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pocket_ledger/app_theme.dart';
import 'package:pocket_ledger/main.dart';
import 'package:pocket_ledger/services/account_deletion_service.dart';
import 'package:pocket_ledger/widgets/account_deletion_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DeletionAccount implements GoogleSignInAccount {
  @override
  String get email => 'recovery@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Normal account access must not run during deletion recovery.',
  );
}

void main() {
  testWidgets(
    'restart with pending deletion blocks normal ledger initialization',
    (tester) async {
      final key = AccountDeletionService.pendingKey('recovery@example.com');
      SharedPreferences.setMockInitialValues({
        key: '{}',
        'transaction_outbox_v1_recovery@example.com': 'do not synchronize',
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DashboardScreen(
            account: _DeletionAccount(),
            isDarkMode: false,
            onDarkModeChanged: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Resume deletion'), findsOneWidget);
      expect(find.text('Import Statements'), findsNothing);
      expect(find.text('Add New Expense'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('transaction_outbox_v1_recovery@example.com'),
        'do not synchronize',
      );
      expect(prefs.containsKey(key), true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('requires confirmation, shows progress, then clear completion', (
    tester,
  ) async {
    final finish = Completer<void>();
    var started = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountDeletionScreen(
          email: 'test@example.com',
          signOut: () async {},
          delete: (progress) async {
            started = true;
            progress('Deleting expenses');
            await finish.future;
          },
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Delete account and app data'),
      250,
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Delete account and app data'),
    );
    await tester.pumpAndSettle();
    expect(started, false);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(started, false);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Delete account and app data'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently'));
    await tester.pump();
    expect(started, true);
    expect(find.text('Deleting expenses'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Deletion complete'), findsNothing);
    finish.complete();
    await tester.pumpAndSettle();
    expect(find.text('Deletion complete'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('failed deletion stays incomplete and can be retried', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountDeletionScreen(
          email: 'test@example.com',
          pending: true,
          signOut: () async {},
          delete: (_) async {
            calls++;
            if (calls == 1) throw StateError('Network unavailable');
          },
        ),
      ),
    );
    await tester.ensureVisible(find.text('Resume deletion'));
    await tester.tap(find.text('Resume deletion'));
    await tester.pumpAndSettle();
    expect(find.text('Network unavailable'), findsOneWidget);
    expect(find.text('Deletion complete'), findsNothing);
    await tester.ensureVisible(find.text('Resume deletion'));
    await tester.tap(find.text('Resume deletion'));
    await tester.pumpAndSettle();
    expect(find.text('Deletion complete'), findsOneWidget);
  });
}
