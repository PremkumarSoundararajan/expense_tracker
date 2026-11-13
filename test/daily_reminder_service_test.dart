import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/services/daily_reminder_service.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezones = MethodChannel('flutter_timezone');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var allowed = true;
  var alerts = true;
  var retained = true;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    allowed = alerts = retained = true;
    calls.clear();
    messenger.setMockMethodCallHandler(
      timezones,
      (_) async => 'America/Chicago',
    );
    messenger.setMockMethodCallHandler(notifications, (call) async {
      calls.add(call);
      return switch (call.method) {
        'initialize' => true,
        'requestPermissions' || 'requestNotificationsPermission' => allowed,
        'areNotificationsEnabled' => allowed,
        'checkPermissions' => {
          'isEnabled': allowed,
          'isAlertEnabled': alerts,
          'isSoundEnabled': true,
        },
        'pendingNotificationRequests' => [
          if (retained)
            {
              'id': DailyReminderService.notificationId,
              'title': DailyReminderService.title,
              'body': DailyReminderService.body,
              'payload': null,
            },
        ],
        _ => null,
      };
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(timezones, null);
    messenger.setMockMethodCallHandler(notifications, null);
  });

  test(
    'iOS five-minutes-ahead reminder retains the upcoming local time',
    () async {
      final service = DailyReminderService();
      await service.initialize();
      final expected = tz.TZDateTime.now(tz.local)
          .add(const Duration(minutes: 5));
      final result = await service.scheduleDaily(
        TimeOfDay(hour: expected.hour, minute: expected.minute),
      );
      final scheduled =
          calls.singleWhere((call) => call.method == 'zonedSchedule').arguments
              as Map;
      final date = DateTime.parse(scheduled['scheduledDateTime'] as String);
      expect(
        [date.year, date.month, date.day, date.hour, date.minute],
        [
          expected.year,
          expected.month,
          expected.day,
          expected.hour,
          expected.minute,
        ],
      );
      expect(scheduled['timeZoneName'], 'America/Chicago');
      expect(
        scheduled['matchDateTimeComponents'],
        DateTimeComponents.time.index,
      );
      final specifics = scheduled['platformSpecifics'] as Map;
      expect(specifics['presentBanner'], isTrue);
      expect(specifics['presentList'], isTrue);
      expect(specifics['presentSound'], isTrue);
      expect(calls.last.method, 'pendingNotificationRequests');
      expect(service.nextScheduledReminder, result);
      await service.cancelDaily();
      expect(service.nextScheduledReminder, isNull);
    },
  );
  for (final entry in [
    (
      now: tz.TZDateTime(tz.UTC, 2026, 11, 13, 13),
      time: const TimeOfDay(hour: 13, minute: 2),
      expected: tz.TZDateTime(tz.UTC, 2026, 11, 13, 13, 2),
    ),
    (
      now: tz.TZDateTime(tz.UTC, 2026, 11, 13, 13, 3),
      time: const TimeOfDay(hour: 13, minute: 2),
      expected: tz.TZDateTime(tz.UTC, 2026, 11, 14, 13, 2),
    ),
    (
      now: tz.TZDateTime(tz.UTC, 2026, 11, 13, 13, 2),
      time: const TimeOfDay(hour: 13, minute: 2),
      expected: tz.TZDateTime(tz.UTC, 2026, 11, 14, 13, 2),
    ),
    (
      now: tz.TZDateTime(tz.UTC, 2026, 12, 31, 23, 59),
      time: const TimeOfDay(hour: 0, minute: 1),
      expected: tz.TZDateTime(tz.UTC, 2027, 1, 1, 0, 1),
    ),
  ]) {
    test('next reminder follows the upcoming local date from ${entry.now}', () {
      expect(nextDailyReminderDate(entry.time, entry.now), entry.expected);
    });
  }
  test(
    'iOS permissions revoked after enabling cannot silently save a schedule',
    () async {
      allowed = false;
      await expectLater(
        DailyReminderService().scheduleDaily(
          const TimeOfDay(hour: 13, minute: 5),
        ),
        throwsA(isA<ReminderException>()),
      );
      expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
    },
  );
  test(
    'iOS badge-only permission explains that alerts need enabling',
    () async {
      alerts = false;
      expect(
        await DailyReminderService().reminderStatus(enabled: true),
        contains('banners'),
      );
    },
  );
  test('an unretained schedule surfaces an error instead of success', () async {
    retained = false;
    await expectLater(
      DailyReminderService().scheduleDaily(
        const TimeOfDay(hour: 13, minute: 5),
      ),
      throwsA(
        isA<ReminderException>().having(
          (e) => e.message,
          'message',
          contains('did not retain'),
        ),
      ),
    );
  });
  test(
    'status checks the phone queue without prompting for permission',
    () async {
      final service = DailyReminderService();
      expect(
        await service.reminderStatus(enabled: true),
        'Scheduled on this phone.',
      );
      retained = false;
      expect(
        await service.reminderStatus(enabled: true),
        contains('No reminder scheduled'),
      );
      expect(
        calls.where((call) => call.method == 'requestPermissions'),
        isEmpty,
      );
    },
  );
  test('off status does not initialize or schedule notifications', () async {
    expect(
      await DailyReminderService().reminderStatus(enabled: false),
      'Reminder off.',
    );
    expect(calls, isEmpty);
  });
  test('test notification requests permission and never replaces the daily reminder', () async {
    await DailyReminderService().sendTestNotification();
    final shown =
        calls.singleWhere((call) => call.method == 'show').arguments as Map;
    expect(shown['id'], DailyReminderService.testNotificationId);
    expect(shown['id'], isNot(DailyReminderService.notificationId));
    expect((shown['platformSpecifics'] as Map)['presentBanner'], isTrue);
    expect(calls.any((call) => call.method == 'requestPermissions'), isTrue);
    expect(
      calls.where(
        (call) => call.method == 'zonedSchedule' || call.method == 'cancel',
      ),
      isEmpty,
    );
  });
  test('denied test permission sends nothing', () async {
    allowed = false;
    await expectLater(
      DailyReminderService().sendTestNotification(),
      throwsA(isA<ReminderException>()),
    );
    expect(calls.where((call) => call.method == 'show'), isEmpty);
  });
  test(
    'Android also verifies permission and retains the named small icon',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      await DailyReminderService().scheduleDaily(
        const TimeOfDay(hour: 13, minute: 5),
      );
      final scheduled =
          calls.singleWhere((call) => call.method == 'zonedSchedule').arguments
              as Map;
      final specifics = scheduled['platformSpecifics'] as Map;
      expect(specifics['icon'], 'ic_notification');
      expect(
        specifics['scheduleMode'],
        AndroidScheduleMode.inexactAllowWhileIdle.name,
      );
      expect(calls.last.method, 'pendingNotificationRequests');
    },
  );
}
