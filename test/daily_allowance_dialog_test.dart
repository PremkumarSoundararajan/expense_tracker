import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/services/budget_comparison.dart';
import 'package:pocket_ledger/widgets/daily_allowance_dialog.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    double total = 105,
    double unexpected = 0,
    double budget = 1000,
    DateTime? date,
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => DailyAllowanceDialog(
                  spending: BudgetSpending.fromAmounts(
                    total: total,
                    regular: 0,
                    unexpected: unexpected,
                  ),
                  budget: budget,
                  currencySymbol: r'$',
                  date: date ?? DateTime(2026, 11, 15),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the subtraction, inclusive days and rounded allowance', (
    tester,
  ) async {
    await open(tester);
    expect(find.text(r'$1,000 − $105 = $895'), findsOneWidget);
    expect(find.text(r'$895 ÷ 16 ≈ $55.93/day'), findsOneWidget);
    expect(find.text('Days left (including today)'), findsOneWidget);
    expect(
      find.text(r'Shown on Home: $55/day (rounded down).'),
      findsOneWidget,
    );
    expect(find.text('Unexpected expenses excluded'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(DailyAllowanceDialog), findsNothing);
  });

  testWidgets('explains Unexpected exclusion and includes Unknown spending', (
    tester,
  ) async {
    await open(tester, total: 1057, unexpected: 200);
    expect(find.text('Unexpected expenses excluded'), findsOneWidget);
    expect(find.text(r'-$200'), findsOneWidget);
    expect(find.text(r'$1,000 − $857 = $143'), findsOneWidget);
    expect(find.text(r'$143 ÷ 16 ≈ $8.93/day'), findsOneWidget);
  });

  testWidgets('over budget clamps allowance to zero', (tester) async {
    await open(tester, total: 1100);
    expect(find.text('Over budget'), findsOneWidget);
    expect(find.text(r'$1,000 − $1,100 = -$100'), findsOneWidget);
    expect(find.text(r'$0 ÷ 16 ≈ $0/day'), findsOneWidget);
  });

  testWidgets('month end has one day, including leap day', (tester) async {
    await open(tester, date: DateTime(2028, 2, 29));
    expect(find.text(r'$895 ÷ 1 ≈ $895/day'), findsOneWidget);
  });

  testWidgets('zero budget and no expenses show zero allowance', (
    tester,
  ) async {
    await open(tester, budget: 0, total: 0);
    expect(find.text(r'$0 ÷ 16 ≈ $0/day'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('readable on narrow screen with large text: $brightness', (
      tester,
    ) async {
      await open(tester, scale: 1.6, brightness: brightness);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('daily-allowance-math')),
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
