import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocket_ledger/services/email_capture_service.dart';
import 'package:pocket_ledger/widgets/email_capture_screen.dart';

void main() {
  test('transient status failures retry without exposing a raw Failed to fetch error', () async {
    var calls = 0;
    final service = EmailCaptureService(
      accessToken: () async => 'test',
      client: MockClient((_) async {
        calls++;
        if (calls < 3) throw http.ClientException('Failed to fetch');
        return http.Response('{"accounts":[],"items":[]}', 200);
      }),
    );
    final result = await service.status();
    expect(calls, 3);
    expect(result['items'], isEmpty);
    service.close();
  });
  test('lost approval response is never automatically retried', () async {
    var calls = 0;
    final service = EmailCaptureService(
      accessToken: () async => 'test',
      client: MockClient((_) async {
        calls++;
        throw http.ClientException('Failed to fetch');
      }),
    );
    await expectLater(
      service.request('approve', data: {}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Check your Sheet'),
        ),
      ),
    );
    expect(calls, 1);
    service.close();
  });
  test('service sends app authorization for explicit scans', () async {
    final calls = <http.Request>[];
    final service = EmailCaptureService(
      timezoneName: () async => 'America/Chicago',
      accessToken: () async => 'public-test-token',
      client: MockClient((r) async {
        calls.add(r);
        return http.Response('{"added":0,"more":false}', 200);
      }),
    );
    await service.request('scan', data: {'accountId': 'a', 'days': 7});
    expect(calls.single.url.path, '/email/scan');
    expect(calls.single.headers['Authorization'], 'Bearer public-test-token');
    expect(jsonDecode(calls.single.body)['days'], 7);
    expect(jsonDecode(calls.single.body)['timezone'], 'America/Chicago');
    service.close();
  });
  test('old or unconfigured Worker produces actionable error', () async {
    for (final response in [
      http.Response('legacy response', 200),
      http.Response('{"error":"Configure email capture first"}', 503),
    ]) {
      final service = EmailCaptureService(
        timezoneName: () async => 'America/Chicago',
        accessToken: () async => 'test',
        client: MockClient((_) async => response),
      );
      await expectLater(service.status(), throwsStateError);
      service.close();
    }
  });
  test('old statement API error identifies the deployment mismatch', () async {
    final service = EmailCaptureService(
      timezoneName: () async => 'America/Chicago',
      accessToken: () async => 'test',
      client: MockClient(
        (_) async =>
            http.Response('{"error":"Missing X-Spreadsheet-ID header"}', 400),
      ),
    );
    await expectLater(
      service.request('connect', data: {'currency': 'USD'}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Deploy the updated Worker'),
        ),
      ),
    );
    service.close();
  });

  Widget screen(
    EmailCaptureService service, {
    Future<bool> Function(Uri)? launch,
    Future<String> Function(List<EmailExpenseCandidate>, String)? review,
  }) => MaterialApp(
    home: EmailCaptureScreen(
      service: service,
      reminderTime: () => const TimeOfDay(hour: 20, minute: 30),
      changeReminderTime: () async {},
      reminderFrequency: () => 'off',
      changeReminderFrequency: (_) async {},
      settingsMode: launch != null,
      openAuthorization: launch,
      onReview: review ?? (_, __) async => 'Reviewed',
    ),
  );

  testWidgets('connection refuses an authorization URL outside Google', (
    tester,
  ) async {
    var launched = false;
    final service = EmailCaptureService(
      timezoneName: () async => 'America/Chicago',
      accessToken: () async => 'test',

      client: MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path.endsWith('status')
                ? {'accounts': [], 'items': []}
                : {'url': 'https://evil.example/oauth'},
          ),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      screen(
        service,
        launch: (_) async {
          launched = true;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect Gmail'));
    await tester.pumpAndSettle();
    expect(launched, false);
    expect(find.textContaining('Bad state:'), findsNothing);
    expect(
      find.textContaining('Unexpected authorization destination'),
      findsOneWidget,
    );
  });

  testWidgets('review requires explicit selection and currency confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var reviewed = false;
    final service = EmailCaptureService(
      timezoneName: () async => 'America/Chicago',
      accessToken: () async => 'test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'accounts': [],
            'items': [
              {
                'id': 'email:a',
                'accountId': 'a',
                'merchant': 'Test Shop',
                'amount': 12.5,
                'currency': 'USD',
                'date': '2026-11-09',
              },
            ],
          }),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      screen(
        service,
        review: (items, currency) async {
          reviewed = true;
          expect(items.single.merchant, 'Test Shop');
          expect(currency, 'USD');
          return 'Reviewed';
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(reviewed, false);
    await tester.tap(
      find
          .descendant(
            of: find.widgetWithText(ExpansionTile, 'Test Shop · USD 12.50'),
            matching: find.byType(Checkbox),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Amounts use USD from Settings. No currency conversion.'), findsOneWidget);
    await tester.pumpAndSettle();
    final button = find.text('Approve & add to Sheets');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(reviewed, true);
  });

  test('HTML server errors report interruption without claiming a Worker upgrade is required', () async {
    var calls = 0;
    final service = EmailCaptureService(
      timezoneName: () async => 'America/Chicago',
      accessToken: () async => 'test',
      client: MockClient((_) async {
        calls++;
        return http.Response('<html>Bad gateway</html>', 502);
      }),
    );
    await expectLater(
      service.request('scan', data: {'accountId': 'a', 'days': 45}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('HTTP 502'),
        ),
      ),
    );
    expect(calls, 1);
    service.close();
  });
}
