import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/services/email_capture_service.dart';
import 'package:pocket_ledger/widgets/email_capture_screen.dart';

void main() {
  testWidgets('unsafe legacy drafts show a warning and cannot reach approval', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var approved = false;
    final service = EmailCaptureService(
      timezoneName: () async => 'America/Chicago',
      accessToken: () async => 'test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'accounts': [],
            'items': [
              {
                'id': 'old',
                'accountId': 'a',
                'merchant': 'Shop',
                'amount': 1999,
                'currency': 'USD',
                'date': '2026-11-08',
                'reviewBlocked': true,
                'currencyNeedsReview': true,
              },
            ],
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EmailCaptureScreen(
          service: service,
          reminderTime: () => const TimeOfDay(hour: 20, minute: 30),
          changeReminderTime: () async {},
          reminderFrequency: () => 'off',
          changeReminderFrequency: (_) async {},
          onReview: (_, __) async {
            approved = true;
            return 'Approved';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shop · USD 1999.00'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Do not use this draft amount'), findsNothing);
    await tester.tap(find.text('View email evidence'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Do not use this draft amount'), findsOneWidget);
    expect(
      find.textContaining('Currency assumed from mailbox settings'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.widgetWithText(ExpansionTile, 'Shop · USD 1999.00'),
            matching: find.byType(Checkbox),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final currency = find.text(
      'Amounts use USD from Settings. No currency conversion.',
    );
    await tester.ensureVisible(currency);
    await tester.pumpAndSettle();
    final approve = find.text('Approve & add to Sheets');
    await tester.ensureVisible(approve);
    await tester.tap(approve);
    await tester.pumpAndSettle();
    expect(approved, false);
    expect(
      find.textContaining('Exclude drafts that could not be safely re-read'),
      findsOneWidget,
    );
  });
  for (final width in [1280.0, 390.0]) {
    testWidgets(
      'inline classifications reach approval at $width without a second review dialog',
      (tester) async {
        tester.view.physicalSize = Size(width, 1700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        List<EmailExpenseCandidate>? approved;
        final service = EmailCaptureService(
          timezoneName: () async => 'America/Chicago',
          accessToken: () async => 'test',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'accounts': [],
                'items': [
                  {
                    'id': 'email:1',
                    'accountId': 'a',
                    'merchant': 'CVS',
                    'amount': 19.22,
                    'currency': 'USD',
                    'date': '2026-11-08',
                  },
                ],
              }),
              200,
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: EmailCaptureScreen(
              service: service,
              reminderTime: () => const TimeOfDay(hour: 20, minute: 30),
              changeReminderTime: () async {},
              reminderFrequency: () => 'off',
              changeReminderFrequency: (_) async {},
              categories: const [
                ExpenseCategory(
                  id: 'pharmacy',
                  parentId: 'health-wellness',
                  name: 'Pharmacy',
                ),
              ],
              prepareCandidate: (item) => item.classified(
                expenseType: 'Regular',
                essentiality: 'Essential',
                edited: false,
              ),
              onReview: (items, _) async {
                approved = items;
                return 'Approved';
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Category'), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String> &&
                w.key.toString().contains('email-email:1-'),
            skipOffstage: false,
          ),
          findsNothing,
        );
        await tester.tap(find.text('CVS · USD 19.22'));
        await tester.pumpAndSettle();
        Finder field(String name) => find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.key.toString().contains('email-email:1-$name-'),
        );
        final category = field('Category'),
            essentiality = field('Essentiality'),
            type = field('Expense Type');
        if (width > 1000) {
          expect(
            (tester.getTopLeft(category).dy -
                    tester.getTopLeft(essentiality).dy)
                .abs(),
            lessThan(2),
          );
          expect(
            (tester.getTopLeft(type).dy - tester.getTopLeft(essentiality).dy)
                .abs(),
            lessThan(2),
          );
        }
        await tester.ensureVisible(category);
        await tester.tap(category);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pharmacy').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(essentiality);
        await tester.tap(essentiality);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Potentially Flexible').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(type);
        await tester.tap(type);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Planned Occasional').last);
        await tester.pumpAndSettle();
        final checkbox = find
            .descendant(
              of: find.widgetWithText(ExpansionTile, 'CVS · USD 19.22'),
              matching: find.byType(Checkbox),
            )
            .first;
        await tester.ensureVisible(checkbox);
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
        final currency = find.text(
          'Amounts use USD from Settings. No currency conversion.',
        );
        await tester.ensureVisible(currency);
            await tester.pumpAndSettle();
        final approve = find.text('Approve & add to Sheets');
        await tester.ensureVisible(approve);
        await tester.tap(approve);
        await tester.pumpAndSettle();
        expect(approved!.single.category, 'Pharmacy');
        expect(approved!.single.categoryId, 'pharmacy');
        expect(approved!.single.essentiality, 'Potentially Flexible');
        expect(approved!.single.expenseType, 'Planned Occasional');
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('editing receipt details preserves explicit classifications and resets duplicate approval', () {
    final source =
        const EmailExpenseCandidate(
          id: 'x',
          accountId: 'a',
          merchant: 'Shop',
          amount: 12,
          currency: 'USD',
          date: '2026-11-08',
        ).classified(
          category: 'Pharmacy',
          categoryId: 'pharmacy',
          expenseType: 'Regular',
          essentiality: 'Essential',
          importAnyway: true,
        );
    final edited = source.edited(
      merchant: 'CVS',
      amount: 19.22,
      date: '2026-11-08',
      currency: 'USD',
    );
    expect(edited.categoryId, 'pharmacy');
    expect(edited.expenseType, 'Regular');
    expect(edited.essentiality, 'Essential');
    expect(edited.classificationEdited, isTrue);
    expect(edited.importAnyway, isFalse);
  });
}
