import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocket_ledger/services/email_capture_service.dart';
import 'package:pocket_ledger/widgets/email_capture_screen.dart';

void main() {
  testWidgets(
    'a readable review amount is visible and prefilled but still requires confirmation',
    (tester) async {
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
              'items': [],
              'needsReview': [
                {
                  'id': 'suggestion',
                  'accountId': 'a',
                  'merchant': 'Shop',
                  'amount': 25.75,
                  'currency': 'USD',
                  'date': '2026-11-10',
                  'needsReview': true,
                  'reviewReason': 'no_completion_phrase',
                  'amountIsSuggestion': true,
                  'amountCandidates': [
                    {
                      'label': 'Total',
                      'amount': 25.75,
                      'currency': 'USD',
                      'amountText': 'USD 25.75',
                    },
                  ],
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
      expect(find.text('Shop · Possible USD 25.75 — verify'), findsOneWidget);
      expect(find.text('Review email & enter expense'), findsNothing);
      final summary = tester.widget<ExpansionTile>(
        find.byKey(const ValueKey('email-suggestion')),
      );
      expect((summary.title as Text).maxLines, 1);
      expect((summary.subtitle as Text).maxLines, 1);
      await tester.tap(find.text('Shop · Possible USD 25.75 — verify'));
      await tester.pumpAndSettle();
      expect(find.text('Total: USD 25.75'), findsNothing);
      await tester.tap(find.text('View email evidence'));
      await tester.pumpAndSettle();
      expect(find.text('Total: USD 25.75'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Total: USD 25.75'), findsNothing);
      final edit = find.text('Review email & enter expense');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, '25.75');
      await tester.tap(find.text('Keep changes'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(approved, false);
    },
  );
  testWidgets('unresolved review emails can be bulk-selected for exclusion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<dynamic>? excluded;
    var removed = false;
    final service = EmailCaptureService(
      timezoneName: () async => 'America/Chicago',
      accessToken: () async => 'test',
      client: MockClient((r) async {
        if (r.method == 'POST') {
          expect(r.url.path, '/email/exclude');
          excluded = jsonDecode(r.body)['ids'] as List;
          removed = true;
          return http.Response('{"excluded":true}', 200);
        }
        return http.Response(
          jsonEncode({
            'accounts': [],
            'items': [],
            'needsReview': removed
                ? []
                : [
                    {
                      'id': 'review1',
                      'accountId': 'a',
                      'merchant': 'Shop',
                      'amount': null,
                      'currency': 'USD',
                      'date': '2026-11-10',
                      'needsReview': true,
                      'reviewReason': 'no_amount',
                    },
                  ],
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EmailCaptureScreen(
          service: service,
          reminderTime: () => const TimeOfDay(hour: 20, minute: 30),
          changeReminderTime: () async {},
          reminderFrequency: () => 'off',
          changeReminderFrequency: (_) async {},
          onReview: (_, __) async => throw StateError('Must not approve'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final select = find.text('Select review emails (up to 50)');
    await tester.ensureVisible(select);
    await tester.tap(select);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exclude selected'));
    await tester.pumpAndSettle();
    expect(excluded, ['review1']);
  });
  for (final width in [1280.0, 390.0]) {
    testWidgets(
      'needs-review email requires details and confirmation before approval at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1800);
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
                'items': [],
                'pendingTotal': 0,
                'needsReviewTotal': 1,
                'needsReview': [
                  {
                    'id': 'review1',
                    'accountId': 'a',
                    'merchant': 'Shop',
                    'amount': null,
                    'currency': 'USD',
                    'date': '2026-11-10',
                    'needsReview': true,
                    'reviewReason': 'amount_conflict',
                    'excerpt':
                        'Amount paid USD 20. Current Amount Paid USD 30.',
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
              onReview: (items, _) async {
                approved = items;
                return 'Approved';
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Needs review (1)'), findsOneWidget);
        await tester.tap(find.text('Shop · conflicting amounts'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Needs review · amount_conflict'),
          findsNothing,
        );
        expect(find.text('Shop · conflicting amounts'), findsOneWidget);
        expect(find.text('Shop · USD 0.00'), findsNothing);
        final edit = find.text('Review email & enter expense');
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        final dialog = find.byType(AlertDialog);
        final fields = find.descendant(
          of: dialog,
          matching: find.byType(TextField),
        );
        expect(tester.widget<TextField>(fields.at(1)).controller!.text, '');
        await tester.enterText(fields.at(1), '20.00');
        await tester.tap(find.text('Keep changes'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(approved, isNull);
        final confirmation = find.text(
          'I checked the original email. This is a completed expense, not an unpaid bill, refund, hold or transfer.',
        );
        await tester.ensureVisible(confirmation);
        await tester.tap(confirmation);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keep changes'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        final select = find
            .descendant(
              of: find.widgetWithText(ExpansionTile, 'Shop · USD 20.00'),
              matching: find.byType(Checkbox),
            )
            .first;
        await tester.ensureVisible(select);
        await tester.tap(select);
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
        expect(approved!.single.amount, 20);
        expect(approved!.single.manualReviewConfirmed, true);
        expect(approved!.single.needsReview, true);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
