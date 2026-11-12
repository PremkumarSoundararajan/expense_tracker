import 'package:flutter/foundation.dart';
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
  test('retirement cancels only the old scan reminder and never schedules mail access', () async {
    await DailyReminderService().cancelRetiredEmailReminder();
    final canceled = calls.where((c) => c.method == 'cancel').toList();
    expect(canceled, hasLength(1));
    expect(canceled.single.arguments['id'], 831);
    expect(
      calls.where(
        (c) => c.method == 'periodicallyShow' || c.method == 'zonedSchedule',
      ),
      isEmpty,
    );
  });
}
