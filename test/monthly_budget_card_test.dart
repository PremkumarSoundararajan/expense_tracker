import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/app_theme.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/budget_comparison.dart';
import 'package:pocket_ledger/widgets/monthly_budget_card.dart';
import 'package:pocket_ledger/widgets/month_selector.dart';
import 'package:pocket_ledger/utils/transaction_period_format.dart';

void main() {
  Future<void> show(
    WidgetTester tester, {
    double width = 390,
    bool dark = false,
    bool hero = false,
    double total = 3357.29,
    double regular = 3000,
    double unexpected = 10.47,
    double? budget = 4349.35,
    DateTime? month,
    VoidCallback? edit,
    VoidCallback? category,
    VoidCallback? review,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MonthlyBudgetCard(
              hero: hero,
              currentSpent: total,
              regularSpent: regular,
              unexpectedOccasionalSpent: unexpected,
              currencySymbol: r'$',
              monthlyTarget: budget,
              now: DateTime(2026, 11, 15),
              selectedMonth: month,
              onCalendarPressed: category ?? () {},
              onSetTargetPressed: edit ?? () {},
              onReviewUnclassified: review,
              onMonthSelected: (_) {},
              availableMonths: [DateTime(2024, 1), DateTime(2026, 11)],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('This month label follows the selected month', (tester) async {
    await show(tester);
    expect(find.text('THIS MONTH'), findsOneWidget);
    expect(find.text('November 2026'), findsOneWidget);

    await show(tester, month: DateTime(2026, 10));
    expect(find.text('THIS MONTH'), findsNothing);
    expect(find.text('October 2026'), findsOneWidget);

    await show(tester, month: DateTime(2026, 11));
    expect(find.text('THIS MONTH'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('hero month label uses onHeader in dark=$dark', (tester) async {
      await show(tester, dark: dark, hero: true);
      final semantic = (dark ? AppTheme.dark : AppTheme.light)
          .extension<AppSemanticColors>()!;
      expect(
        tester.widget<Text>(find.text('November 2026')).style?.color,
        semantic.onHeader,
      );
    });
  }

  testWidgets(
    'budget progress uses semantic status colors and neutral totals',
    (tester) async {
      await show(tester, total: 79, regular: 79, unexpected: 0, budget: 100);
      final actual = tester.widget<Text>(find.text(r'$79'));
      expect(actual.style?.color, AppTheme.light.colorScheme.onSurface);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .color,
        AppTheme.light.extension<AppSemanticColors>()!.success,
      );

      await show(tester, total: 80, regular: 80, unexpected: 0, budget: 100);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .color,
        AppTheme.light.extension<AppSemanticColors>()!.warning,
      );

      await show(tester, total: 101, regular: 101, unexpected: 0, budget: 100);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .color,
        AppTheme.light.colorScheme.error,
      );
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets('budget amount and info open details at $width', (
      tester,
    ) async {
      await show(
        tester,
        width: width,
        total: 857,
        regular: 657,
        unexpected: 200,
        budget: 20000,
      );
      expect(find.byKey(const ValueKey('daily-allowance-pill')), findsNothing);
      expect(find.text('Budget details'), findsNothing);
      await tester.tap(find.text(r'Budget: $20,000'));
      await tester.pumpAndSettle();
      expect(find.text('Budget details — November 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Close budget details'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      expect(find.text('Budget details — November 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets('compact Home and details popup at $width dark=$dark', (
        tester,
      ) async {
        var edited = false;
        var drilled = false;
        await show(
          tester,
          width: width,
          dark: dark,
          edit: () => edited = true,
          category: () => drilled = true,
        );
        expect(find.text(r'$3,357'), findsOneWidget);
        expect(find.text('Within budget'), findsOneWidget);
        expect(find.text(r'$1,003 left'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('daily-allowance-pill')),
          findsNothing,
        );
        expect(find.text('ACTUAL EXPENSE'), findsOneWidget);
        expect(find.text(r'Budget: $4,349'), findsOneWidget);
        expect(
          find.text('Progress uses \$3,346.82 counted toward budget'),
          findsOneWidget,
        );
        final kpis = tester.widget<Row>(
          find.byKey(const ValueKey('budget-kpi-row')),
        );
        expect(kpis.crossAxisAlignment, CrossAxisAlignment.end);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('hero-month-selector')))
              .bottom,
          lessThan(
            tester.getRect(find.byKey(const ValueKey('budget-kpi-row'))).top,
          ),
        );
        final progress = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(progress.value, closeTo(3346.82 / 4349.35, .000001));
        expect(
          tester.getSize(find.byTooltip('Previous month')),
          const Size(48, 48),
        );
        expect(find.text('By Category'), findsNothing);
        expect(find.text('Total actual spending'), findsNothing);
        expect(
          tester.getSize(find.byType(MonthlyBudgetCard)).height,
          lessThan(360),
        );
        await tester.tap(find.text('ACTUAL EXPENSE'));
        expect(drilled, isTrue);
        drilled = false;
        await tester.tap(find.text(r'$3,357'));
        expect(drilled, isTrue);
        await tester.tap(find.byKey(const ValueKey('monthly-budget-details')));
        await tester.pumpAndSettle();
        final sheet = find.byType(BottomSheet);
        expect(
          find.descendant(
            of: sheet,
            matching: find.text('Budget details — November 2026'),
          ),
          findsOneWidget,
        );
        for (final amount in [
          r'$3,357.29',
          r'-$10.47',
          r'$3,346.82',
          r'$4,349.35',
          r'$1,002.53',
        ]) {
          expect(
            find.descendant(of: sheet, matching: find.text(amount)),
            findsOneWidget,
          );
        }
        await tester.ensureVisible(find.text('Edit budget'));
        await tester.tap(find.text('Edit budget'));
        await tester.pumpAndSettle();
        expect(edited, isTrue);
        expect(sheet, findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'unknown stays included without a range and review closes details',
    (tester) async {
      var reviewed = false;
      await show(
        tester,
        total: 120,
        regular: 90,
        unexpected: 0,
        budget: 100,
        review: () => reviewed = true,
      );
      expect(find.text('Over budget'), findsOneWidget);
      expect(find.text(r'$20 over'), findsOneWidget);
      expect(find.textContaining('uncertain'), findsNothing);
      expect(find.byKey(const ValueKey('daily-allowance-pill')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('monthly-budget-details')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('monthly-budget-coverage')));
      await tester.pumpAndSettle();
      expect(reviewed, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    },
  );
  testWidgets(
    'past months show their budget and congratulations without daily allowance',
    (tester) async {
      await show(tester, month: DateTime(2026, 10));
      expect(find.text('Within budget'), findsOneWidget);
      expect(find.text(r'Budget: $4,349'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('past-budget-congratulations')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('daily-allowance-pill')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('monthly-budget-details')));
      await tester.pumpAndSettle();
      expect(find.text('Budget details — October 2026'), findsOneWidget);
      expect(find.text(r'$4,349.35'), findsOneWidget);
    },
  );
  testWidgets('no budget can be set in details and zero budget is valid', (
    tester,
  ) async {
    var edited = false;
    await show(tester, budget: null, edit: () => edited = true);
    expect(find.text('No budget set'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.byKey(const ValueKey('monthly-budget-details')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set budget'));
    await tester.pumpAndSettle();
    expect(edited, isTrue);
    await show(tester, total: 0, regular: 0, unexpected: 0, budget: 0);
    expect(find.text('Exactly on budget'), findsOneWidget);
    expect(find.byKey(const ValueKey('daily-allowance-pill')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'month arrows include gaps, calendar reaches old history and blocks future',
    (tester) async {
      DateTime? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MonthSelector(
              now: DateTime(2026, 11),
              selectedMonth: DateTime(2026, 11),
              months: [DateTime(2024, 1), DateTime(2026, 11)],
              onSelected: (v) => chosen = v,
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_right),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Previous month'));
      expect(chosen, DateTime(2026, 10));
      await tester.tap(find.byTooltip('Choose month'));
      await tester.pumpAndSettle();
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.firstDate, DateTime(2024, 1));
      expect(picker.lastDate, DateTime(2026, 11, 30));
    },
  );
  test('recorded comparison uses actual minus unexpected with signed Unknown refunds', () {
    final data = BudgetSpending.fromTransactions([
      Transaction(
        id: 'a',
        date: DateTime(2026, 11),
        amount: 80,
        category: 'Food',
        expenseType: ExpenseType.regular,
      ),
      Transaction(
        id: 'b',
        date: DateTime(2026, 11),
        amount: 30,
        category: 'Food',
      ),
      Transaction(
        id: 'c',
        date: DateTime(2026, 11),
        amount: -10,
        category: 'Food',
      ),
      Transaction(
        id: 'd',
        date: DateTime(2026, 11),
        amount: 50,
        category: 'Food',
        expenseType: ExpenseType.unexpectedOccasional,
      ),
    ]);
    expect(data.total, 150);
    expect(data.budgetRelevant, 100);
    expect(data.recordedOutcome(100), BudgetOutcome.exact);
    expect(data.recordedRemaining(120), 20);
    expect(data.unknown, 20);
    expect(data.regular, 80);
    final history = [
      for (var m = 1; m <= 18; m++)
        Transaction(date: DateTime(2024, m), amount: 10, category: 'Food'),
    ];
    expect(
      availableLedgerMonths(
        history,
        now: DateTime(2026, 11),
        limit: null,
      ).length,
      19,
    );
  });
}
