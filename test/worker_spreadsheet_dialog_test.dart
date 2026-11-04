import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/widgets/worker_spreadsheet_dialog.dart';

void main() {
  testWidgets('saves a spreadsheet ID pasted as a Google Sheets URL', (
    tester,
  ) async {
    String? savedTarget;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                savedTarget = await showDialog<String>(
                  context: context,
                  builder: (_) => WorkerSpreadsheetDialog(
                    initialSpreadsheetId: null,
                    onCreateSpreadsheet: () async => 'created-sheet',
                  ),
                );
              },
              child: const Text('Open settings'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://docs.google.com/spreadsheets/d/sheet_456/edit',
    );
    await tester.tap(find.text('Save target'));
    await tester.pumpAndSettle();

    expect(savedTarget, 'sheet_456');
  });

  testWidgets('populates a newly created sheet ID', (tester) async {
    String? savedTarget;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                savedTarget = await showDialog<String>(
                  context: context,
                  builder: (_) => WorkerSpreadsheetDialog(
                    initialSpreadsheetId: null,
                    onCreateSpreadsheet: () async => 'created-sheet',
                  ),
                );
              },
              child: const Text('Open settings'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create sheet'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'created-sheet',
    );

    await tester.tap(find.text('Save target'));
    await tester.pumpAndSettle();
    expect(savedTarget, 'created-sheet');
  });
}
