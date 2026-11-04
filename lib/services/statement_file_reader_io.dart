import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<Uint8List> readPickedStatementFile(PlatformFile file) =>
    cacheStatementByteStream(file.name, file.readAsByteStream());

Future<Uint8List> cacheStatementByteStream(
  String fileName,
  Stream<List<int>> stream,
) async {
  final cacheDirectory = await Directory.systemTemp.createTemp(
    'pocket-ledger-statement-',
  );
  final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final cachedFile = File(
    '${cacheDirectory.path}${Platform.pathSeparator}'
    '${safeName.isEmpty ? 'statement' : safeName}',
  );

  try {
    final sink = cachedFile.openWrite();
    try {
      await for (final chunk in stream) {
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    final bytes = await cachedFile.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('The selected file stream was empty.');
    }
    return bytes;
  } catch (error) {
    throw StateError(
      'Could not copy the selected file into local cache: $error',
    );
  } finally {
    await cacheDirectory.delete(recursive: true);
  }
}
