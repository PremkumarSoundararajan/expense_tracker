import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<Uint8List> readPickedStatementFile(PlatformFile file) => Future.error(
  UnsupportedError('Statement file reading is not supported on this platform.'),
);

Future<Uint8List> cacheStatementByteStream(
  String fileName,
  Stream<List<int>> stream,
) => Future.error(
  UnsupportedError('Statement file caching is not supported on this platform.'),
);
