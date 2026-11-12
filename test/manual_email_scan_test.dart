import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocket_ledger/services/email_capture_service.dart';
import 'package:pocket_ledger/widgets/email_capture_screen.dart';

void main() {
  const mailbox = {'id': 'a', 'email': 'receipts@example.com', 'last_scan': 0};
  final end = DateTime.utc(2026, 11, 11, 12).millisecondsSinceEpoch;
  Map<String, dynamic> job(String status) => {
    'id': 'job1',
    'status': status,
    'from': end - 2 * 86400000,
    'through': end,
    'processed': status == 'complete' ? 30 : 5,
    'estimated': 30,
    'ready': 2,
    'review': 1,
  };
  Widget screen(MockClient client, {bool settings = false}) => MaterialApp(
    home: EmailCaptureScreen(
      service: EmailCaptureService(
        timezoneName: () async => 'America/Chicago',
        accessToken: () async => 'test',
        client: client,
      ),
      settingsMode: settings,
      reminderFrequency: () => 'off',
      changeReminderFrequency: (_) async {},
      reminderTime: () => const TimeOfDay(hour: 20, minute: 30),
      changeReminderTime: () async {},
      onReview: (_, __) async => 'Approved',
    ),
  );
  void size(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> tick(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> dispose(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  }

  testWidgets(
    'opening loads saved results and validates range without starting a job',
    (tester) async {
      size(tester);
      var starts = 0;
      final client = MockClient((r) async {
        if (r.method == 'POST') starts++;
        return http.Response(
          jsonEncode({
            'accounts': [mailbox],
            'items': [],
          }),
          200,
        );
      });
      await tester.pumpWidget(screen(client));
      await tester.pumpAndSettle();
      expect(starts, 0);
      await tester.enterText(
        find.widgetWithText(TextField, 'How many days back?'),
        '0',
      );
      await tester.tap(find.text('Start scan'));
      await tester.pumpAndSettle();
      expect(starts, 0);
      expect(find.textContaining('Choose 1–30 days'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'How many days back?'),
        '31',
      );
      await tester.tap(find.text('Start scan'));
      await tester.pumpAndSettle();
      expect(starts, 0);
      expect(find.textContaining('Choose 1–30 days'), findsOneWidget);
      expect(find.textContaining('Gmail only'), findsOneWidget);
      expect(find.text('Currency for email imports'), findsNothing);
    },
  );
  testWidgets(
    'start clears old rows, sends one job request, then polls progress to completion',
    (tester) async {
      size(tester);
      Map<String, dynamic>? active;
      final starts = <Map<String, dynamic>>[];
      var polls = 0;
      final client = MockClient((r) async {
        if (r.method == 'GET')
          return http.Response(
            jsonEncode({
              'accounts': [
                {...mailbox, if (active != null) 'job': active},
              ],
              'items': active == null
                  ? [
                      {
                        'id': 'old',
                        'merchant': 'Old merchant',
                        'amount': 12,
                        'date': '2026-10-01',
                        'currency': 'USD',
                      },
                    ]
                  : [],
            }),
            200,
          );
        if (r.url.path.endsWith('/start')) {
          starts.add(jsonDecode(r.body) as Map<String, dynamic>);
          active = job('running');
          return http.Response(jsonEncode({'job': active, 'reset': true}), 200);
        }
        polls++;
        active = job('complete');
        return http.Response(jsonEncode({'job': active}), 200);
      });
      await tester.pumpWidget(screen(client));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'How many days back?'),
        '2',
      );
      await tester.tap(find.text('Start scan'));
      await tick(tester);
      expect(starts.single['days'], 2);
      expect(starts.single['currency'], 'USD');
      expect(starts.single['timezone'], 'America/Chicago');
      expect(starts.single['requestId'], isNotEmpty);
      expect(find.textContaining('Old merchant'), findsNothing);
      expect(find.text('Scanning…'), findsOneWidget);
      expect(find.text('Continues in the background.'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      expect(starts.length, 1);
      expect(polls, 1);
      expect(find.text('Complete'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    },
  );
  testWidgets(
    'leaving stops polling without pausing the server and reopening reads completed job',
    (tester) async {
      size(tester);
      var active = job('running');
      var starts = 0, pauses = 0, polls = 0;
      final client = MockClient((r) async {
        if (r.method == 'GET')
          return http.Response(
            jsonEncode({
              'accounts': [
                {...mailbox, 'job': active},
              ],
              'items': [],
            }),
            200,
          );
        if (r.url.path.endsWith('/pause'))
          pauses++;
        else if (r.url.path.endsWith('/start'))
          starts++;
        else
          polls++;
        return http.Response(jsonEncode({'job': active}), 200);
      });
      await tester.pumpWidget(screen(client));
      await tick(tester);
      expect(find.text('Scanning…'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 2));
      active = job('complete');
      await tester.pump(const Duration(seconds: 5));
      expect(pauses, 0);
      expect(starts, 0);
      expect(polls, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Complete'), findsOneWidget);
      expect(starts, 0);
    },
  );
  testWidgets('only the explicit Pause button pauses a background job', (
    tester,
  ) async {
    size(tester);
    var active = job('running');
    var pauses = 0;
    final client = MockClient((r) async {
      if (r.method == 'GET')
        return http.Response(
          jsonEncode({
            'accounts': [
              {...mailbox, 'job': active},
            ],
            'items': [],
          }),
          200,
        );
      if (r.url.path.endsWith('/pause')) {
        pauses++;
        active = job('paused');
      }
      return http.Response(jsonEncode({'job': active}), 200);
    });
    await tester.pumpWidget(screen(client));
    await tick(tester);
    final pause = find.text('Pause scan');
    await tester.ensureVisible(pause);
    await tester.tap(pause);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(pauses, 1);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Resume scan'), findsOneWidget);
  });
  testWidgets('resume restarts a failed job without resetting the date range', (
    tester,
  ) async {
    size(tester);
    var active = job('failed');
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((r) async {
      if (r.method == 'GET')
        return http.Response(
          jsonEncode({
            'accounts': [
              {...mailbox, 'job': active},
            ],
            'items': [],
          }),
          200,
        );
      if (r.url.path.endsWith('/start')) {
        requests.add(jsonDecode(r.body) as Map<String, dynamic>);
        active = job('running');
      } else
        active = job('complete');
      return http.Response(jsonEncode({'job': active}), 200);
    });
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resume scan'));
    await tick(tester);
    expect(requests.single['resume'], true);
    expect(requests.single.containsKey('days'), false);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('Complete'), findsOneWidget);
  });
  testWidgets('settings never starts or polls scans', (tester) async {
    size(tester);
    var calls = 0;
    final client = MockClient((r) async {
      if (r.method != 'GET') calls++;
      return http.Response(
        jsonEncode({
          'accounts': [
            {...mailbox, 'job': job('running')},
          ],
          'items': [],
        }),
        200,
      );
    });
    await tester.pumpWidget(screen(client, settings: true));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(calls, 0);
    expect(find.text('Pause scan'), findsNothing);
  });
  testWidgets('disposing the page does not cancel or pause the job', (
    tester,
  ) async {
    size(tester);
    var calls = 0;
    final client = MockClient((r) async {
      if (r.method != 'GET') calls++;
      return http.Response(
        jsonEncode({
          'accounts': [
            {...mailbox, 'job': job('running')},
          ],
          'items': [],
        }),
        200,
      );
    });
    await tester.pumpWidget(screen(client));
    await tick(tester);
    await dispose(tester);
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });
}
