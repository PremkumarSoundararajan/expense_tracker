import 'dart:convert';

import 'package:flutter/services.dart';

import 'worker_csv_sync_service.dart';

class StatementDocument {
  const StatementDocument({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

/// Android's system picker, including Drive virtual documents. Only the
/// explicitly selected document is read; no storage or Drive-wide scope needed.
class StatementDocumentPicker {
  const StatementDocumentPicker();
  static const channel = MethodChannel('pocket_ledger/statement_documents');

  Future<StatementDocument?> pick() async {
    final result = await channel.invokeMapMethod<String, dynamic>(
      'pickStatement',
    );
    if (result == null) return null;
    final name = result['name'];
    final bytes = result['bytes'];
    if (name is! String || bytes is! Uint8List || bytes.isEmpty) {
      throw StateError(
        'Could not read the selected document. Please choose it again.',
      );
    }
    return StatementDocument(name: name, bytes: bytes);
  }
}

/// Drive for desktop stores native Sheets as small JSON shortcuts, not Excel
/// files. Extract only a Sheets ID; never fetch an arbitrary URL from the file.
String spreadsheetIdFromShortcut(List<int> bytes) {
  if (bytes.length > 64 * 1024) {
    throw const FormatException('This is not a valid Google Sheets shortcut.');
  }
  try {
    final json = jsonDecode(utf8.decode(bytes).replaceFirst('\uFEFF', ''));
    if (json is Map && json['url'] is String) {
      final id = normalizeSpreadsheetId(json['url'] as String);
      if (id != null && id.length >= 20) return id;
    }
  } catch (_) {
    // Use the same actionable message for malformed and unsupported shortcuts.
  }
  throw const FormatException(
    'Could not read this Google Sheets shortcut. Choose the original sheet from Google Drive.',
  );
}
