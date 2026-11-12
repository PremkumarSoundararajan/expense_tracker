import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/services/daily_reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezones = MethodChannel('flutter_timezone');
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezones, (_) async => 'America/Chicago');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (call) async {
          calls.add(call);
          if (call.method == 'initialize') return true;
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezones, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, null);
  });
  test('hourly reminder is a local notification with an Expenses navigation payload', () async {
    await DailyReminderService().scheduleEmail(
      'hourly',
      const TimeOfDay(hour: 20, minute: 30),
    );
    final request = calls.singleWhere((c) => c.method == 'periodicallyShow');
    expect(request.arguments['id'], DailyReminderService.emailNotificationId);
    expect(request.arguments['payload'], 'email-review');
    expect(
      request.arguments['body'],
      contains('Open Expenses to start a scan'),
    );
    expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
  });
  test(
    'daily reminder and off do not replace the ordinary expense reminder',
    () async {
      final service = DailyReminderService();
      await service.scheduleEmail(
        'daily',
        const TimeOfDay(hour: 8, minute: 15),
      );
      final request = calls.singleWhere((c) => c.method == 'zonedSchedule');
      expect(request.arguments['id'], DailyReminderService.emailNotificationId);
      expect(request.arguments['payload'], 'email-review');
      calls.clear();
      await service.scheduleEmail('off', const TimeOfDay(hour: 8, minute: 15));
      expect(calls.length, 1);
      expect(calls.single.method, 'cancel');
      expect(
        calls.single.arguments['id'],
        DailyReminderService.emailNotificationId,
      );
    },
  );
}
