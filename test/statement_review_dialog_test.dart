import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/services/worker_csv_sync_service.dart';
import 'package:pocket_ledger/widgets/statement_review_dialog.dart';

void main() {
  testWidgets('mobile review keeps actions pinned and categories editable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    List<WorkerExpensePreview>? importedRows;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                key: const ValueKey('open-statement-review'),
                onPressed: () async {
                  importedRows = await showDialog<List<WorkerExpensePreview>>(
                    context: context,
                    builder: (_) => StatementReviewDialog(
                      fileName: 'statement.csv',
                      preview: WorkerCsvPreview(
                        spreadsheetId: 'target-sheet-id',
                        spreadsheetCreated: false,
                        rows: [
                          for (var index = 0; index < 8; index++)
                            WorkerExpensePreview(
                              date: '2025-01-${index + 1}',
                              amount: 25 + index.toDouble(),
                              category: 'Food / Household',
                              categoryMatched: false,
                              description: 'GROCERY STORE $index',
                              expenseType: 'Regular',
                              duplicate: false,
                            ),
                        ],
                        filteredCount: 2,
                        duplicateCount: 0,
                      ),
                      currencySymbol: r'$',
                    ),
                  );
                },
                child: const Text('Review'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-statement-review')));
    await tester.pumpAndSettle();

    final confirm = find.byKey(
      const ValueKey('statement-review-confirm-import'),
    );
    expect(find.text('Review statement before import'), findsOneWidget);
    expect(find.textContaining('2 non-expense or unreadable'), findsOneWidget);
    expect(confirm, findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(
      tester.getRect(confirm).bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height),
    );

    final category = find.byType(DropdownButtonFormField<String>).first;
    await tester.tap(category);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transport').last);
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(find.text('Review statement before import'), findsOneWidget);
    expect(confirm, findsOneWidget);
    expect(
      tester.getRect(confirm).bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height),
    );

    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(importedRows, hasLength(8));
    expect(importedRows!.first.category, 'Transport');
  });
}
