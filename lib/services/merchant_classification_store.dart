import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;

import '../models/transaction.dart';
import 'merchant_classification_service.dart';

/// Account-local durable outbox; sheet records are merged by stable record ID.
class MerchantClassificationStore {
  MerchantClassificationStore(String account)
    : _key = 'merchant_classifications_v1_${account.toLowerCase()}';
  static const tab = 'Merchant Classifications';
  final String _key;
  Map<String, Map<String, dynamic>> records = {};
  Set<String> pending = {};
  Map<String, Map<String, dynamic>> draft = {};
  Future<void> _draftWrites = Future<void>.value();
  Future<String>? _syncFlight;
  MerchantClassificationIndex get index =>
      MerchantClassificationIndex(records.values);

  Future<bool> desktopSuggestionDismissed() async =>
      (await SharedPreferences.getInstance()).getBool(
        '${_key}_desktop_suggestion_dismissed',
      ) ??
      false;

  Future<void> dismissDesktopSuggestion() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool('${_key}_desktop_suggestion_dismissed', true)) {
      throw StateError('Could not save desktop suggestion preference.');
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final draftRaw = prefs.getString('${_key}_draft');
    if (draftRaw != null) {
      final list = jsonDecode(draftRaw) as List;
      draft = {
        for (final value in list)
          value['id'] as String: Map<String, dynamic>.from(value as Map),
      };
    }
    final raw = prefs.getString(_key);
    if (raw == null) return;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    records = {
      for (final r in data['records'] as List)
        r['id'] as String: Map<String, dynamic>.from(r as Map),
    };
    pending = (data['pending'] as List).cast<String>().toSet();
  }

  Future<void> saveDraft(List<Map<String, dynamic>> changes) {
    draft = {
      for (final change in changes)
        change['id'] as String: Map<String, dynamic>.from(change),
    };
    final snapshot = jsonEncode(draft.values.toList());
    return _draftWrites = _draftWrites.catchError((Object _) {}).then((
      _,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString('${_key}_draft', snapshot))
        throw StateError('Could not save the merchant review draft.');
    });
  }

  Future<void> clearDraft() {
    draft = {};
    return _draftWrites = _draftWrites.catchError((Object _) {}).then((
      _,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${_key}_draft');
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      _key,
      jsonEncode({
        'records': records.values.toList(),
        'pending': pending.toList(),
      }),
    )) {
      throw StateError(
        'Could not save merchant classifications on this device.',
      );
    }
  }

  Future<void> save(Iterable<Map<String, dynamic>> changes) async {
    final previousRecords = Map<String, Map<String, dynamic>>.of(records);
    final previousPending = Set<String>.of(pending);
    for (final change in changes) {
      final id = change['id'] as String;
      records[id] = Map<String, dynamic>.from(change);
      pending.add(id);
    }
    try {
      MerchantClassificationIndex(records.values);
      await _persist();
    } catch (_) {
      records = previousRecords;
      pending = previousPending;
      rethrow;
    }
  }

  Future<String> synchronize(
    sheets.SheetsApi api,
    String spreadsheetId,
    List<Transaction> rawTransactions,
  ) async {
    final inFlight = _syncFlight;
    if (inFlight != null) {
      final status = await inFlight;
      if (pending.isNotEmpty)
        return synchronize(api, spreadsheetId, rawTransactions);
      return status;
    }
    return _syncFlight = _exchange(
      api,
      spreadsheetId,
      rawTransactions,
    ).whenComplete(() => _syncFlight = null);
  }

  Future<String> _exchange(
    sheets.SheetsApi api,
    String spreadsheetId,
    List<Transaction> rawTransactions,
  ) async {
    final metadata = await api.spreadsheets.get(
      spreadsheetId,
      $fields: 'sheets.properties.title',
    );
    if (!(metadata.sheets?.any((s) => s.properties?.title == tab) ?? false)) {
      if (records.isEmpty && pending.isEmpty) {
        return 'No merchant changes to sync.';
      }
      pending.addAll(records.keys);
      await _persist();
      await api.spreadsheets.batchUpdate(
        sheets.BatchUpdateSpreadsheetRequest(
          requests: [
            sheets.Request(
              addSheet: sheets.AddSheetRequest(
                properties: sheets.SheetProperties(title: tab),
              ),
            ),
          ],
        ),
        spreadsheetId,
      );
      await api.spreadsheets.values.update(
        sheets.ValueRange(
          values: [
            ['Record ID', 'Classification'],
          ],
        ),
        spreadsheetId,
        "'$tab'!A1:B1",
        valueInputOption: 'RAW',
      );
    }
    final response = await api.spreadsheets.values.get(
      spreadsheetId,
      "'$tab'!A1:B",
    );
    final rows = response.values ?? [];
    if (rows.isEmpty ||
        rows.first.length < 2 ||
        rows.first[0] != 'Record ID' ||
        rows.first[1] != 'Classification') {
      throw StateError(
        'The Merchant Classifications sheet headers are invalid. No classifications were overwritten.',
      );
    }
    final remote = <String, Map<String, dynamic>>{};
    final positions = <String, int>{};
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].length < 2 || rows[i][0].toString().isEmpty) continue;
      final record = Map<String, dynamic>.from(
        jsonDecode(rows[i][1].toString()) as Map,
      );
      final id = rows[i][0].toString();
      if (record['id'] != id)
        throw StateError('A merchant classification record has an invalid ID.');
      remote[id] = record;
      positions[id] = i + 1;
    }
    MerchantClassificationIndex(
      remote.values,
    ); // Validate before replacing the local cache.
    // Unrelated remote records survive; only locally edited record IDs win.
    final sent = {for (final id in pending) id: jsonEncode(records[id])};
    final merged = {...remote, for (final id in pending) id: records[id]!};
    var next = rows.length + 1;
    final updates = <sheets.ValueRange>[];
    for (final id in sent.keys) {
      final row = positions[id] ?? next++;
      updates.add(
        sheets.ValueRange(
          range: "'$tab'!A$row:B$row",
          values: [
            [id, sent[id]],
          ],
        ),
      );
    }
    if (updates.isNotEmpty) {
      await api.spreadsheets.values.batchUpdate(
        sheets.BatchUpdateValuesRequest(valueInputOption: 'RAW', data: updates),
        spreadsheetId,
      );
    }
    // Keep any edits made while the network operation was in flight queued.
    final latest = {for (final id in pending) id: records[id]!};
    records = {...merged, ...latest};
    for (final id in sent.keys) {
      if (jsonEncode(records[id]) == sent[id]) pending.remove(id);
    }
    await _persist();

    // Write category cells only, never stale dates, amounts, descriptions or IDs.
    // The caller supplies a fresh full-sheet read with stable IDs and current rows.
    final classifier = index;
    final candidates = <(Transaction, Transaction)>[];
    for (final raw in rawTransactions) {
      if (raw.id == null) continue;
      final effective = classifier.apply(raw);
      if (raw.category != effective.category ||
          raw.categoryId != effective.categoryId ||
          raw.expenseType != effective.expenseType)
        candidates.add((raw, effective));
    }
    if (candidates.isEmpty) return 'Merchant classifications saved and synced.';
    // Row numbers can shift while metadata is syncing. Resolve IDs again
    // immediately before writing, and skip deleted or duplicated IDs.
    final ids = await api.spreadsheets.values.get(spreadsheetId, 'Sheet1!F2:F');
    final currentRows = <String, int>{};
    final duplicates = <String>{};
    final idRows = ids.values ?? [];
    for (var i = 0; i < idRows.length; i++) {
      final id = idRows[i].firstOrNull?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      if (currentRows.containsKey(id)) duplicates.add(id);
      currentRows[id] = i + 2;
    }
    final categoryUpdates = <sheets.ValueRange>[];
    for (final (raw, effective) in candidates) {
      final row = currentRows[raw.id];
      if (row == null || duplicates.contains(raw.id)) continue;
      categoryUpdates.add(
        sheets.ValueRange(
          range: 'Sheet1!C$row',
          values: [
            [effective.category],
          ],
        ),
      );
      if (raw.expenseType != effective.expenseType)
        categoryUpdates.add(
          sheets.ValueRange(
            range: 'Sheet1!E$row',
            values: [
              [effective.expenseType.sheetValue],
            ],
          ),
        );
      categoryUpdates.add(
        sheets.ValueRange(
          range: 'Sheet1!G$row',
          values: [
            [effective.categoryId ?? ''],
          ],
        ),
      );
    }
    for (var i = 0; i < categoryUpdates.length; i += 400) {
      await api.spreadsheets.values.batchUpdate(
        sheets.BatchUpdateValuesRequest(
          valueInputOption: 'RAW',
          data: categoryUpdates.skip(i).take(400).toList(),
        ),
        spreadsheetId,
      );
    }
    if (candidates.any((entry) => duplicates.contains(entry.$1.id)))
      return 'Merchant choices synced. Duplicate transaction IDs were left unchanged in Sheets; fix the IDs and refresh.';
    return 'Merchant classifications saved and synced.';
  }
}
