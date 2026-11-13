import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/statement_source.dart';
import 'package:pocket_ledger/services/google_sheet_statement_service.dart';
import 'package:pocket_ledger/widgets/google_sheet_import_dialog.dart';

const book = GoogleStatementWorkbook(
  id: '12345678901234567890abcdef',
  title: 'Private statement',
  tabs: [
    GoogleStatementTab(id: 0, title: 'Cover'),
    GoogleStatementTab(id: 1, title: 'Transactions'),
  ],
);
const statement = PreparedStatement(
  name: 'Private statement — Transactions',
  csv: 'Date,Amount\r\n2026-11-01,25',
);

Future<void> openDialog(
  WidgetTester tester, {
  required Future<GoogleStatementWorkbook> Function(String) load,
  required Future<PreparedStatement> Function(
    GoogleStatementWorkbook,
    GoogleStatementTab,
  )
  read,
  required void Function(PreparedStatement?) result,
  bool waitForLoad = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result(
                await showDialog<PreparedStatement>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => GoogleSheetImportDialog(
                    initialSource: book.id,
                    sourceName: 'Statement.gsheet',
                    loadWorkbook: load,
                    readWorksheet: read,
                  ),
                ),
              );
            },
            child: const Text('Import'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Import'));
  await tester.pump();
  if (waitForLoad) await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets(
      'selected shortcut loads worksheets without a link field at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var loads = 0, reads = 0;
        PreparedStatement? selected;
        await openDialog(
          tester,
          load: (input) async {
            loads++;
            expect(input, book.id);
            return book;
          },
          read: (workbook, tab) async {
            reads++;
            expect(workbook.id, book.id);
            expect(tab.title, 'Transactions');
            return statement;
          },
          result: (value) => selected = value,
        );
        expect(find.byType(TextField), findsNothing);
        expect(loads, 1);
        expect(reads, 0);
        expect(selected, isNull);
        await tester.tap(find.byKey(ValueKey(book.id)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Transactions').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(reads, 1);
        expect(selected?.csv, statement.csv);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('access errors can be retried for the selected shortcut', (
    tester,
  ) async {
    var loads = 0;
    PreparedStatement? selected;
    await openDialog(
      tester,
      load: (_) async {
        loads++;
        if (loads == 1) {
          throw const GoogleSheetImportException('Check access to this sheet.');
        }
        return book;
      },
      read: (_, _) async => statement,
      result: (value) => selected = value,
    );
    expect(find.text('Check access to this sheet.'), findsOneWidget);
    await tester.tap(find.text('Load worksheets'));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });
  for (final phase in ['metadata', 'rows']) {
    testWidgets(
      'cancel during $phase ignores late results without closing the app page',
      (tester) async {
        final metadata = Completer<GoogleStatementWorkbook>();
        final rows = Completer<PreparedStatement>();
        PreparedStatement? selected;
        var reads = 0, finished = 0;
        await openDialog(
          tester,
          load: (_) =>
              phase == 'metadata' ? metadata.future : Future.value(book),
          read: (_, _) {
            reads++;
            return rows.future;
          },
          result: (value) {
            selected = value;
            finished++;
          },
          waitForLoad: phase != 'metadata',
        );
        await tester.pump();
        if (phase == 'rows') {
          await tester.pumpAndSettle();
          await tester.tap(find.text('Continue'));
          await tester.pump();
        }
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        if (phase == 'metadata') {
          metadata.complete(book);
        } else {
          rows.complete(statement);
        }
        await tester.pumpAndSettle();
        expect(selected, isNull);
        expect(finished, 1);
        expect(reads, phase == 'rows' ? 1 : 0);
        expect(find.text('Import'), findsOneWidget);
        expect(find.byType(GoogleSheetImportDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
