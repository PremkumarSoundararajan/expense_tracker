import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/services/statement_document_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const picker = StatementDocumentPicker();
  tearDown(
    () => messenger.setMockMethodCallHandler(
      StatementDocumentPicker.channel,
      null,
    ),
  );

  test('selected provider export uses its actual name and bytes', () async {
    final bytes = Uint8List.fromList(utf8.encode('Date,Amount\n2026-11-01,25'));
    messenger.setMockMethodCallHandler(StatementDocumentPicker.channel, (
      call,
    ) async {
      expect(call.method, 'pickStatement');
      expect(call.arguments, isNull);
      return {'name': 'Bank statement.csv', 'bytes': bytes};
    });
    final document = await picker.pick();
    expect(document!.name, 'Bank statement.csv');
    expect(document.bytes, bytes);
  });
  test('cancelling the native picker returns no document', () async {
    messenger.setMockMethodCallHandler(
      StatementDocumentPicker.channel,
      (_) async => null,
    );
    expect(await picker.pick(), isNull);
  });
  test(
    'provider failures are surfaced without substituting an old document',
    () async {
      messenger.setMockMethodCallHandler(StatementDocumentPicker.channel, (
        _,
      ) async {
        throw PlatformException(
          code: 'statement_read_failed',
          message: 'Could not download this sheet.',
        );
      });
      await expectLater(picker.pick(), throwsA(isA<PlatformException>()));
    },
  );
  for (final response in [
    {'name': 'empty.csv', 'bytes': Uint8List(0)},
    {'name': 'broken.csv', 'bytes': 'not bytes'},
    {
      'bytes': Uint8List.fromList([1]),
    },
  ]) {
    test(
      'malformed provider response is rejected: ${response['name']}',
      () async {
        messenger.setMockMethodCallHandler(
          StatementDocumentPicker.channel,
          (_) async => response,
        );
        await expectLater(picker.pick(), throwsStateError);
      },
    );
  }
  const id = 'source_sheet_12345678901234567890';
  test(
    'local Drive shortcut resolves a private sheet ID without pasted text',
    () {
      for (final url in [
        'https://docs.google.com/spreadsheets/d/$id/edit?usp=drivesdk',
        'https://docs.google.com/spreadsheets/d/$id/edit#gid=123',
      ]) {
        final bytes = utf8.encode(
          '\uFEFF${jsonEncode({'url': url, 'resource_id': 'ignored'})}',
        );
        expect(spreadsheetIdFromShortcut(bytes), id);
      }
    },
  );
  test(
    'invalid, non-Sheets and oversized shortcuts never become network URLs',
    () {
      for (final input in [
        utf8.encode('not JSON'),
        utf8.encode('{"url":"https://example.com/private.csv"}'),
        utf8.encode('{"url":"https://docs.google.com/document/d/$id/edit"}'),
        utf8.encode('{"doc_id":"$id"}'),
        List.filled(65537, 32),
      ]) {
        expect(() => spreadsheetIdFromShortcut(input), throwsFormatException);
      }
    },
  );
}
