import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/widgets/monthly_budget_target_dialog.dart';

void main() {
  testWidgets('validates input and returns a saved target', (tester) async {
    double? savedTarget;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                savedTarget = await showDialog<double>(
                  context: context,
                  builder: (_) => const MonthlyBudgetTargetDialog(
                    currencySymbol: '\$',
                    initialTarget: null,
                  ),
                );
              },
              child: const Text('Open target dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open target dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Target'));
    await tester.pump();
    expect(find.text('Enter a target greater than zero.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '250');
    await tester.tap(find.text('Save Target'));
    await tester.pumpAndSettle();

    expect(savedTarget, 250);
    expect(tester.takeException(), isNull);
  });
}
