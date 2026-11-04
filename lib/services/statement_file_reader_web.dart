import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<Uint8List> readPickedStatementFile(PlatformFile file) =>
    cacheStatementByteStream(file.name, file.readAsByteStream());

Future<Uint8List> cacheStatementByteStream(
  String fileName,
  Stream<List<int>> stream,
) async {
  final builder = BytesBuilder(copy: false);
  try {
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      throw StateError('The selected file stream was empty.');
    }
    return bytes;
  } catch (error) {
    throw StateError(
      'Could not read "$fileName" from the selected file: $error',
    );
  }
}
