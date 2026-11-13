import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/widgets/daily_reminder_settings_dialog.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'successful enable shows confirmed date and time on $platform',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final now = DateTime.now();
        final next = DateTime(now.year, now.month, now.day, 13, 2);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DailyReminderSettingsDialog(
                enabled: false,
                time: const TimeOfDay(hour: 13, minute: 2),
                onEnabledChanged: (_) async => true,
                onTimeChanged: (_) async {},
                nextReminder: () => next,
              ),
            ),
          ),
        );
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(find.text('Reminder set successfully.'), findsOneWidget);
        expect(find.textContaining('Next reminder: Today,'), findsOneWidget);
        expect(
          find.textContaining('at 1:02 PM (${next.timeZoneName})'),
          findsOneWidget,
        );
        expect(
          find.text('Android may deliver later.'),
          platform == TargetPlatform.android ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(find.text('Reminder turned off.'), findsOneWidget);
        expect(find.textContaining('Next reminder:'), findsNothing);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
  for (final enabled in [true, false]) {
    testWidgets(
      'saving time confirms next reminder only when enabled=$enabled',
      (tester) async {
        final now = DateTime.now();
        final next = DateTime(now.year, now.month, now.day + 1, 13, 5);
        var saved = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DailyReminderSettingsDialog(
                enabled: enabled,
                time: const TimeOfDay(hour: 13, minute: 5),
                onEnabledChanged: (_) async => true,
                onTimeChanged: (_) async {
                  saved++;
                },
                nextReminder: () => next,
              ),
            ),
          ),
        );
        await tester.tap(find.text('Reminder time'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(saved, 1);
        if (enabled) {
          expect(find.text('Reminder set successfully.'), findsOneWidget);
          expect(
            find.textContaining('Next reminder: Tomorrow,'),
            findsOneWidget,
          );
        } else {
          expect(
            find.text('Time saved. Turn on the reminder to schedule it.'),
            findsOneWidget,
          );
          expect(find.textContaining('Next reminder:'), findsNothing);
        }
      },
    );
  }
  testWidgets('failed scheduling never shows a success confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyReminderSettingsDialog(
            enabled: false,
            time: const TimeOfDay(hour: 13, minute: 5),
            onEnabledChanged: (_) async =>
                throw Exception('Phone rejected schedule'),
            onTimeChanged: (_) async {},
            nextReminder: () => DateTime.now(),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('Phone rejected schedule'), findsOneWidget);
    expect(find.text('Reminder set successfully.'), findsNothing);
    expect(find.textContaining('Next reminder:'), findsNothing);
  });
  testWidgets(
    'shows phone queue status and test does not enable the daily reminder',
    (tester) async {
      var tests = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyReminderSettingsDialog(
              enabled: false,
              time: const TimeOfDay(hour: 13, minute: 5),
              onEnabledChanged: (_) async => true,
              onTimeChanged: (_) async {},
              onCheckStatus: () async => 'Reminder off.',
              onSendTest: () async {
                tests++;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reminder off.'), findsOneWidget);
      await tester.tap(find.text('Send test notification'));
      await tester.pumpAndSettle();
      expect(tests, 1);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(find.textContaining('Test sent to your phone.'), findsOneWidget);
    },
  );
  testWidgets('test failure is visible and leaves controls usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyReminderSettingsDialog(
            enabled: true,
            time: const TimeOfDay(hour: 13, minute: 5),
            onEnabledChanged: (_) async => true,
            onTimeChanged: (_) async {},
            onCheckStatus: () async => 'No reminder scheduled on this phone.',
            onSendTest: () async {
              throw Exception('Notifications blocked');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No reminder scheduled on this phone.'), findsOneWidget);
    await tester.tap(find.text('Send test notification'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Notifications blocked'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNotNull,
    );
  });
  testWidgets('defaults to disabled at 8:30 PM', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyReminderSettingsDialog(
            enabled: false,
            time: const TimeOfDay(hour: 20, minute: 30),
            onEnabledChanged: (_) async => true,
            onTimeChanged: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('Daily Expense Reminder'), findsOneWidget);
    expect(find.text('Get a reminder to log daily expenses.'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    expect(find.text('Enable daily reminder'), findsOneWidget);
    expect(find.text('8:30 PM'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
  });

  testWidgets(
    'keeps reminder disabled when notification permission is denied',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyReminderSettingsDialog(
              enabled: false,
              time: const TimeOfDay(hour: 20, minute: 30),
              onEnabledChanged: (_) async => false,
              onTimeChanged: (_) async {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(
        find.text('Notification permission is required to enable reminders.'),
        findsOneWidget,
      );
      expect(find.text('Reminder set successfully.'), findsNothing);
    },
  );

  testWidgets('enables reminder when permission is granted', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyReminderSettingsDialog(
            enabled: false,
            time: const TimeOfDay(hour: 20, minute: 30),
            onEnabledChanged: (_) async => true,
            onTimeChanged: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(
      find.text('Notification permission is required to enable reminders.'),
      findsNothing,
    );
  });
}
