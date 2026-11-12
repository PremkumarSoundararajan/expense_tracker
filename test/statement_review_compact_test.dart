import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/services/worker_csv_sync_service.dart';
import 'package:pocket_ledger/widgets/statement_review_dialog.dart';

void main() {
  for (final width in [1280.0, 800.0]) {
    testWidgets('desktop review is a single aligned row at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      List<WorkerExpensePreview>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open'),
                onPressed: () async {
                  saved = await showDialog<List<WorkerExpensePreview>>(
                    context: context,
                    builder: (_) => StatementReviewDialog(
                      fileName: 'Chase.csv',
                      currencySymbol: r'$',
                      preview: WorkerCsvPreview(
                        spreadsheetId: 'test',
                        spreadsheetCreated: false,
                        filteredCount: 64,
                        duplicateCount: 0,
                        rows: [
                          for (var i = 0; i < 10; i++)
                            WorkerExpensePreview(
                              date: '2026-10-27',
                              amount: 25,
                              category: 'Lifestyle / Misc',
                              categoryMatched: true,
                              description: 'Merchant $i',
                              expenseType: 'Unknown',
                              duplicate: false,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('statement-review-row-0'));
      final category = find.byKey(
        const ValueKey('statement-review-category-0-Lifestyle / Misc'),
      );
      final type = find.byKey(const ValueKey('statement-type-0-Unknown'));
      expect(tester.getSize(row).height, lessThanOrEqualTo(52));
      expect(
        (tester.getCenter(category).dy - tester.getCenter(type).dy).abs(),
        lessThan(1),
      );
      expect(
        (tester.getCenter(find.text('Merchant 0')).dy -
                tester.getCenter(type).dy)
            .abs(),
        lessThan(1),
      );
      expect(find.text('Expense Type'), findsOneWidget);
      if (width == 1280) {
        await tester.tap(type);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Planned Occasional').last);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('statement-review-confirm-import')),
        );
        await tester.pumpAndSettle();
        expect(saved!.first.expenseType, 'Planned Occasional');
        expect(saved![1].expenseType, 'Unknown');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
