import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

class DailyReminderService {
  DailyReminderService({FlutterLocalNotificationsPlugin? notifications})
    : _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  static const notificationId = 830;
  static const title = 'Pocket Ledger';
  static const body = "Time to log today's expenses in Pocket Ledger!";
  static const channelId = 'daily_expense_reminder';
  static const channelName = 'Daily expense reminder';
  static const testNotificationId = 832;
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'A reminder to log daily expenses.',
      icon: 'ic_notification',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
    ),
  );

  final FlutterLocalNotificationsPlugin _notifications;
  Future<void>? _initialization;
  timezone.TZDateTime? _nextScheduledReminder;
  DateTime? get nextScheduledReminder => _nextScheduledReminder;

  Future<void> initialize() async {
    try {
      await (_initialization ??= _initialize());
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    timezone_data.initializeTimeZones();
    final localTimezone = await FlutterTimezone.getLocalTimezone();
    timezone.setLocalLocation(timezone.getLocation(localTimezone.identifier));

    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  Future<bool> requestPermission() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw UnsupportedError(
        'Daily reminders are supported only in the Android and iOS apps.',
      );
    }
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    throw UnsupportedError(
      'Daily reminders are supported only in the Android and iOS apps.',
    );
  }

  Future<timezone.TZDateTime> scheduleDaily(TimeOfDay time) async {
    await initialize();
    final problem = await _permissionProblem();
    if (problem != null) throw ReminderException(problem);
    final scheduledDate = nextDailyReminderDate(
      time,
      timezone.TZDateTime.now(timezone.local),
    );

    await _notifications.zonedSchedule(
      id: notificationId,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    if (!await _hasPendingReminder()) {
      throw const ReminderException(
        'The phone did not retain the reminder. Turn it off and on to retry.',
      );
    }
    _nextScheduledReminder = scheduledDate;
    return scheduledDate;
  }

  Future<bool> _hasPendingReminder() async =>
      (await _notifications.pendingNotificationRequests()).any(
        (request) => request.id == notificationId,
      );

  /// Checks actual phone permissions rather than relying on the saved switch.
  /// Reading this status never opens a system permission prompt.
  Future<String?> _permissionProblem() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final settings = await _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      if (settings == null) {
        return 'Could not check iPhone notification permission. Please try again.';
      }
      if (!settings.isEnabled || !settings.isAlertEnabled) {
        return 'Notifications or alerts are blocked. Enable Pocket Ledger notifications and banners in iPhone Settings.';
      }
      return null;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final enabled = await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
      if (enabled != true) {
        return 'Enable Pocket Ledger notifications in your phone Settings.';
      }
      return null;
    }
    return 'Reminders require the Android or iOS app.';
  }

  Future<String> reminderStatus({required bool enabled}) async {
    if (!enabled) return 'Reminder off.';
    await initialize();
    final problem = await _permissionProblem();
    if (problem != null) return problem;
    return await _hasPendingReminder()
        ? 'Scheduled on this phone.'
        : 'No reminder scheduled on this phone. Turn it off and on to retry.';
  }

  /// Tests notification display independently of the daily alarm. The separate
  /// ID cannot replace the real reminder or enable it when it was off.
  Future<void> sendTestNotification() async {
    if (!await requestPermission()) {
      throw const ReminderException(
        'Enable Pocket Ledger notifications in your phone Settings.',
      );
    }
    final problem = await _permissionProblem();
    if (problem != null) throw ReminderException(problem);
    await _notifications.show(
      id: testNotificationId,
      title: title,
      body: 'Test reminder from Pocket Ledger.',
      notificationDetails: _details,
    );
  }

  Future<void> cancelDaily() async {
    await initialize();
    await _notifications.cancel(id: notificationId);
    _nextScheduledReminder = null;
  }

  /// Cancels the legacy scan reminder on devices upgrading from the experiment.
  Future<void> cancelRetiredEmailReminder() async {
    await initialize();
    await _notifications.cancel(id: 831);
  }
}

/// Shared by the native schedule and confirmation; constructs tomorrow in the
/// same timezone rather than assuming every calendar day lasts 24 hours.
timezone.TZDateTime nextDailyReminderDate(
  TimeOfDay time,
  timezone.TZDateTime now,
) {
  final today = timezone.TZDateTime(
    now.location,
    now.year,
    now.month,
    now.day,
    time.hour,
    time.minute,
  );
  return today.isAfter(now)
      ? today
      : timezone.TZDateTime(
          now.location,
          now.year,
          now.month,
          now.day + 1,
          time.hour,
          time.minute,
        );
}

class ReminderException implements Exception {
  const ReminderException(this.message);
  final String message;
  @override
  String toString() => message;
}
