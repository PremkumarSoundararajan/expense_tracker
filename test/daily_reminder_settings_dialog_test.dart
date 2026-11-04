import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/widgets/daily_reminder_settings_dialog.dart';

void main() {
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
