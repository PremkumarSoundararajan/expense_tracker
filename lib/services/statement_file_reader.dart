import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'statement_file_reader_stub.dart'
    if (dart.library.io) 'statement_file_reader_io.dart'
    if (dart.library.js_interop) 'statement_file_reader_web.dart'
    as implementation;

Future<Uint8List> readPickedStatementFile(PlatformFile file) =>
    implementation.readPickedStatementFile(file);

Future<Uint8List> cacheStatementByteStream(
  String fileName,
  Stream<List<int>> stream,
) => implementation.cacheStatementByteStream(fileName, stream);
