import 'package:googleapis/sheets/v4.dart' as sheets;

class GoogleSheetHeaderException implements Exception {
  const GoogleSheetHeaderException({
    required this.range,
    required this.expected,
    required this.actual,
  });

  final String range;
  final List<String> expected;
  final List<Object?> actual;

  @override
  String toString() =>
      'Google Sheet layout is invalid for $range. Expected row 1 headers: '
      '${expected.join(', ')}. Found: ${actual.join(', ')}. '
      'Verify that the connected sheet uses the Pocket Ledger layout; '
      'no data was read or written.';
}

class GoogleSheetsService {
  static const transactionHeaders = [
    'Timestamp',
    'Amount',
    'Category',
    'Description',
    'Expense Type',
    'Transaction ID',
    'Category ID',
  ];

  static const baselineHeaders = ['Merchant', 'Lifestyle Group'];

  static void validateHeaders({
    required List<Object?>? actual,
    required List<String> expected,
    required String range,
    Map<int, Set<String>> acceptedAlternatives = const {},
    Map<int, String> canonicalizationRanges = const {},
  }) {
    final headers = actual ?? const <Object?>[];
    final matches =
        headers.length >= expected.length &&
        List.generate(expected.length, (index) {
          final value = headers[index]?.toString().trim();
          return value == expected[index] ||
              (acceptedAlternatives[index]?.contains(value) ?? false);
        }).every((match) => match);
    if (!matches) {
      throw GoogleSheetHeaderException(
        range: range,
        expected: expected,
        actual: headers,
      );
    }
  }

  Future<void> validateSheetHeaders({
    required sheets.SheetsApi sheetsApi,
    required String spreadsheetId,
    required String range,
    required List<String> expected,
    Map<int, Set<String>> acceptedAlternatives = const {},
    Map<int, String> canonicalizationRanges = const {},
    bool allowMissingTrailingHeaders = false,
    Map<int, String> trailingHeaderCellRanges = const {},
  }) async {
    final response = await sheetsApi.spreadsheets.values.get(
      spreadsheetId,
      range,
    );
    final values = response.values;
    final actualHeaders = values == null || values.isEmpty
        ? null
        : values.first;
    final hasOnlyRecognizedMissingTrailingHeaders =
        allowMissingTrailingHeaders &&
        actualHeaders != null &&
        actualHeaders.length >= expected.length - 3 &&
        actualHeaders.length < expected.length;
    validateHeaders(
      actual: actualHeaders,
      expected: hasOnlyRecognizedMissingTrailingHeaders
          ? expected.take(actualHeaders.length).toList(growable: false)
          : expected,
      range: range,
      acceptedAlternatives: acceptedAlternatives,
      canonicalizationRanges: canonicalizationRanges,
    );
    final headers = actualHeaders;
    if (headers == null) return;
    for (final entry in acceptedAlternatives.entries) {
      if (entry.key >= headers.length ||
          headers[entry.key]?.toString().trim() == expected[entry.key] ||
          !(entry.value.contains(headers[entry.key]?.toString().trim()))) {
        continue;
      }
      final canonicalRange = canonicalizationRanges[entry.key];
      if (canonicalRange == null) continue;
      await sheetsApi.spreadsheets.values.update(
        sheets.ValueRange(
          values: [
            [expected[entry.key]],
          ],
        ),
        spreadsheetId,
        canonicalRange,
        valueInputOption: 'RAW',
      );
    }
    if (hasOnlyRecognizedMissingTrailingHeaders) {
      final trailingRange = trailingHeaderCellRanges[headers.length];
      if (trailingRange == null) {
        throw GoogleSheetHeaderException(
          range: range,
          expected: expected,
          actual: headers,
        );
      }
      await sheetsApi.spreadsheets.values.update(
        sheets.ValueRange(
          values: [expected.skip(headers.length).toList(growable: false)],
        ),
        spreadsheetId,
        trailingRange,
        valueInputOption: 'RAW',
      );
    }
  }

  Future<void> appendRows({
    required sheets.SheetsApi sheetsApi,
    required String spreadsheetId,
    required String range,
    required Iterable<List<Object?>> rows,
    required String valueInputOption,
  }) async {
    final values = rows.toList(growable: false);
    if (values.isEmpty) return;
    await sheetsApi.spreadsheets.values.append(
      sheets.ValueRange(values: values),
      spreadsheetId,
      range,
      valueInputOption: valueInputOption,
      insertDataOption: 'INSERT_ROWS',
    );
  }
}
