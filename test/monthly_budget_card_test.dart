import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/services/monthly_rollover_service.dart';
import 'package:pocket_ledger/widgets/monthly_budget_card.dart';

void main() {
  testWidgets('shows monthly total and target action when no target is set', (
    tester,
  ) async {
    var targetActionPressed = false;
    var breakdownPressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonthlyBudgetCard(
            currentSpent: 10468,
            currencySymbol: '\$',
            monthlyTarget: null,
            onCalendarPressed: () => breakdownPressed = true,
            onSetTargetPressed: () => targetActionPressed = true,
          ),
        ),
      ),
    );

    expect(find.text('THIS MONTH'), findsOneWidget);
    expect(find.text('\$10,468'), findsOneWidget);
    expect(find.text('Total actual spending'), findsOneWidget);
    expect(find.text('Monthly Budget'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget);
    expect(find.text('Daily Allowance Set a monthly budget'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.byTooltip('Set monthly budget'));
    await tester.pump();
    expect(targetActionPressed, isTrue);
    expect(breakdownPressed, isFalse);

    await tester.tap(find.text('\$10,468'));
    expect(breakdownPressed, isTrue);
  });

  testWidgets('shows remaining daily budget and progress under the target', (
    tester,
  ) async {
    var targetActionPressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonthlyBudgetCard(
            currentSpent: 50,
            regularSpent: 50,
            currencySymbol: '\$',
            monthlyTarget: 100,
            now: DateTime(2025, 3, 15),
            onCalendarPressed: () {},
            onSetTargetPressed: () => targetActionPressed = true,
          ),
        ),
      ),
    );

    expect(find.text('\$100'), findsOneWidget);
    expect(find.text('Daily Allowance \$3 · 17 days left'), findsOneWidget);
    expect(find.textContaining('<'), findsNothing);
    await tester.tap(find.byTooltip('Edit monthly budget'));
    await tester.pump();
    expect(targetActionPressed, isTrue);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.5,
    );
  });

  testWidgets('shows over-budget status and caps progress at the limit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonthlyBudgetCard(
            currentSpent: 125,
            regularSpent: 125,
            currencySymbol: '\$',
            monthlyTarget: 100,
            now: DateTime(2025, 3, 15),
            onCalendarPressed: () {},
            onSetTargetPressed: () {},
          ),
        ),
      ),
    );

    expect(find.text('Over budget by \$25'), findsOneWidget);
    expect(
      find.text('Daily Allowance Not available while over budget'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.0,
    );
  });

  testWidgets('shows actual current spend and rollover recap together', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonthlyBudgetCard(
            currentSpent: 0,
            currencySymbol: '\$',
            monthlyTarget: 100,
            now: DateTime(2025, 3, 1),
            rolloverRecap: const MonthlyRolloverRecap(
              previousMonthSpend: 75,
              monthlyBudget: 100,
            ),
            onCalendarPressed: () {},
            onSetTargetPressed: () {},
          ),
        ),
      ),
    );

    expect(
      find.text('🎉 Great job last month! You stayed under budget by \$25.'),
      findsOneWidget,
    );
    expect(find.text('\$0'), findsAtLeastNWidgets(1));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('\$100'), findsNWidgets(2));
  });

  testWidgets('shows over-budget rollover message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonthlyBudgetCard(
            currentSpent: 0,
            currencySymbol: '\$',
            monthlyTarget: 100,
            now: DateTime(2025, 3, 1),
            rolloverRecap: const MonthlyRolloverRecap(
              previousMonthSpend: 125,
              monthlyBudget: 100,
            ),
            onCalendarPressed: () {},
            onSetTargetPressed: () {},
          ),
        ),
      ),
    );

    expect(
      find.text(
        "⚠️ Last month finished over budget by \$25. Here's to a fresh start!",
      ),
      findsOneWidget,
    );
  });

  testWidgets('includes today in days left at month start and end', (
    tester,
  ) async {
    for (final dateAndSummary in [
      (DateTime(2025, 3, 1), 'Daily Allowance \$10 · 31 days left'),
      (DateTime(2025, 3, 31), 'Daily Allowance \$310 · 1 day left'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MonthlyBudgetCard(
              currentSpent: 0,
              regularSpent: 0,
              currencySymbol: '\$',
              monthlyTarget: 310,
              now: dateAndSummary.$1,
              onCalendarPressed: () {},
              onSetTargetPressed: () {},
            ),
          ),
        ),
      );
      expect(find.text(dateAndSummary.$2), findsOneWidget);
      expect(find.textContaining('including today'), findsNothing);
    }
  });

  testWidgets('shows zero allowance at exact and zero budgets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonthlyBudgetCard(
            currentSpent: 100,
            regularSpent: 100,
            currencySymbol: '\$',
            monthlyTarget: 100,
            now: DateTime(2025, 3, 31),
            onCalendarPressed: () {},
            onSetTargetPressed: () {},
          ),
        ),
      ),
    );
    expect(find.text('\$0'), findsOneWidget);
    expect(find.text('Daily Allowance \$0 · 1 day left'), findsOneWidget);
    expect(find.text('Over budget by'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MonthlyBudgetCard(
            currentSpent: 0,
            regularSpent: 0,
            currencySymbol: '\$',
            monthlyTarget: 0,
            now: DateTime(2025, 3, 31),
            onCalendarPressed: () {},
            onSetTargetPressed: () {},
          ),
        ),
      ),
    );
    expect(find.text('\$0'), findsAtLeastNWidgets(1));
    expect(find.text('Not set'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('keeps the month card within a narrow phone layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: MonthlyBudgetCard(
              currentSpent: 14000,
              regularSpent: 4500,
              plannedOccasionalSpent: 8000,
              unexpectedOccasionalSpent: 1500,
              currencySymbol: '\$',
              monthlyTarget: 6000,
              now: DateTime(2025, 3, 15),
              onCalendarPressed: () {},
              onSetTargetPressed: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Daily Allowance'), findsOneWidget);
    expect(find.text('Days left in month'), findsNothing);
    final allowance = find.text('Daily Allowance \$88 · 17 days left');
    expect(allowance, findsOneWidget);
    final allowanceText = tester.widget<Text>(allowance);
    expect(allowanceText.maxLines, 1);
    expect(allowanceText.softWrap, isFalse);
  });

  testWidgets(
    'places budget metrics, remaining progress and allowance neatly',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MonthlyBudgetCard(
              currentSpent: 240,
              regularSpent: 150,
              currencySymbol: '\$',
              monthlyTarget: 300,
              now: DateTime(2025, 3, 15),
              onCalendarPressed: () {},
              onSetTargetPressed: () {},
            ),
          ),
        ),
      );

      final budgetLabel = tester.getRect(find.text('Monthly Budget'));
      final budgetAmount = tester.getRect(find.text('\$300'));
      final progressBar = tester.getRect(find.byType(LinearProgressIndicator));
      final remainingLabel = tester.getRect(find.text('Budget remaining'));
      final card = tester.getRect(find.byType(Card));
      final allowancePill = tester.getRect(
        find.byKey(const ValueKey('daily-allowance-pill')),
      );
      final allowanceText = tester.getRect(
        find.text('Daily Allowance \$9 · 17 days left'),
      );
      expect(remainingLabel.center.dx, greaterThan(budgetLabel.center.dx));
      expect(remainingLabel.center.dy, closeTo(budgetLabel.center.dy, 24));
      expect(allowancePill.center.dx, closeTo(card.center.dx, 2));
      expect(allowanceText.center.dx, closeTo(allowancePill.center.dx, 2));
      expect(allowancePill.top, greaterThan(budgetLabel.top));
      expect(find.text('Days left in month'), findsNothing);
      expect(find.text('Daily Allowance \$9 · 17 days left'), findsOneWidget);
      expect(find.text('50% of budget left'), findsOneWidget);
      expect(find.byType(Divider), findsNothing);
      expect(budgetAmount.top - budgetLabel.bottom, lessThanOrEqualTo(24));
      expect(progressBar.top, greaterThan(budgetAmount.bottom));
      expect(progressBar.bottom, lessThan(allowancePill.top));
      final editButton = tester.getRect(find.byTooltip('Edit monthly budget'));
      expect(editButton.width, greaterThanOrEqualTo(44));
      expect(editButton.height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    },
  );
}
