import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/services/statement_file_reader.dart';

void main() {
  test('copies a picked file byte stream through a local cache', () async {
    final result = await cacheStatementByteStream(
      'drive statement.csv',
      Stream<List<int>>.fromIterable([
        [1, 2],
        [3, 4, 5],
      ]),
    );

    expect(result, isA<Uint8List>());
    expect(result, [1, 2, 3, 4, 5]);
  });

  test('surfaces a failed remote file stream', () async {
    await expectLater(
      cacheStatementByteStream(
        'cloud.xlsx',
        Stream<List<int>>.error(StateError('provider download failed')),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('provider download failed'),
        ),
      ),
    );
  });
}
