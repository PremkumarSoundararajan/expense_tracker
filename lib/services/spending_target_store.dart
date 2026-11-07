import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;

import '../models/spending_target.dart';

typedef TargetExchange = Future<List<SpendingTarget>> Function(
  List<SpendingTarget> pending,
);

/// One atomic account-local envelope holds both definitions and their outbox.
/// All mutations and syncs are serialized, so a sync acknowledgement cannot
/// erase an edit made while a network request is in flight.
class SpendingTargetStore extends ChangeNotifier {
  SpendingTargetStore({required String accountKey})
    : _key = 'spending_targets_v1_${accountKey.trim().toLowerCase()}';
  final String _key;
  List<SpendingTarget> _targets = [];
  Set<String> _pending = {};
  Future<void> _tail = Future.value();
  List<SpendingTarget> get targets => List.unmodifiable(_targets);
  bool get hasPending => _pending.isNotEmpty;

  Future<void> _serial(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace stack) {});
    return next;
  }

  Future<void> load() => _serial(() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_key);
    if (encoded == null) return;
    final json = jsonDecode(encoded) as Map<String, dynamic>;
    _targets = (json['targets'] as List)
        .map((t) => SpendingTarget.fromJson(Map<String, dynamic>.from(t)))
        .toList();
    _pending = (json['pending'] as List).cast<String>().toSet();
    notifyListeners();
  });
  Future<void> _persist(
    List<SpendingTarget> targets,
    Set<String> pending,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      _key,
      jsonEncode({
        'targets': targets.map((t) => t.toJson()).toList(),
        'pending': pending.toList(),
      }),
    )) {
      throw StateError('Could not save spending targets locally.');
    }
    _targets = targets;
    _pending = pending;
    notifyListeners();
  }

  Future<void> save(Iterable<SpendingTarget> changes) => _serial(() async {
    final byId = {for (final t in _targets) t.id: t};
    final pending = {..._pending};
    for (final t in changes) {
      byId[t.id] = t;
      pending.add(t.id);
    }
    await _persist(byId.values.toList(), pending);
  });
  Future<void> synchronize(TargetExchange exchange) => _serial(() async {
    final remote = await exchange(
      _targets.where((t) => _pending.contains(t.id)).toList(),
    );
    final merged = {for (final t in _targets) t.id: t};
    for (final t in remote) {
      final old = merged[t.id];
      if (old == null || !old.updatedAt.isAfter(t.updatedAt)) merged[t.id] = t;
    }
    await _persist(merged.values.toList(), {});
  });
}

class SpendingTargetSheetsSyncService {
  static const tabTitle = 'Spending Targets';
  static const headers = [
    'Target ID',
    'Type',
    'Scope ID',
    'Display Name',
    'Historical Monthly Average',
    'Reduction Percentage',
    'Monthly Target',
    'Effective Date',
    'Active',
    'Last Updated',
  ];

  Future<List<SpendingTarget>> exchange({
    required sheets.SheetsApi api,
    required String spreadsheetId,
    required List<SpendingTarget> pending,
  }) async {
    final book = await api.spreadsheets.get(
      spreadsheetId,
      $fields: 'sheets.properties.title',
    );
    if (!(book.sheets ?? []).any((s) => s.properties?.title == tabTitle)) {
      if (pending.isEmpty) return [];
      await api.spreadsheets.batchUpdate(
        sheets.BatchUpdateSpreadsheetRequest(
          requests: [
            sheets.Request(
              addSheet: sheets.AddSheetRequest(
                properties: sheets.SheetProperties(title: tabTitle),
              ),
            ),
          ],
        ),
        spreadsheetId,
      );
      await api.spreadsheets.values.update(
        sheets.ValueRange(values: [headers]),
        spreadsheetId,
        "'$tabTitle'!A1:J1",
        valueInputOption: 'RAW',
      );
    }
    final response = await api.spreadsheets.values.get(
      spreadsheetId,
      "'$tabTitle'!A1:J",
    );
    final rows = response.values ?? <List<Object?>>[];
    if (rows.isEmpty) {
      if (pending.isEmpty) return [];
      await api.spreadsheets.values.update(
        sheets.ValueRange(values: [headers]),
        spreadsheetId,
        "'$tabTitle'!A1:J1",
        valueInputOption: 'RAW',
      );
      rows.add(headers);
    }
    if (rows.isEmpty ||
        !listEquals(rows.first.map((v) => v.toString()).toList(), headers)) {
      throw StateError(
        'Spending Targets headers differ; no targets were overwritten.',
      );
    }
    final remote = <String, SpendingTarget>{};
    final rowById = <String, int>{};
    final duplicates = <int>[];
    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      if (r.isEmpty || r[0].toString().isEmpty) continue;
      if (r.length < 10) {
        throw const FormatException('Incomplete spending target row.');
      }
      final t = SpendingTarget.fromJson({
        'id': r[0].toString(),
        'type': r[1].toString(),
        'scopeId': r[2].toString(),
        'name': r[3].toString(),
        'average': double.parse(r[4].toString()),
        'percentage': double.parse(r[5].toString()),
        'amount': double.parse(r[6].toString()),
        'effectiveDate': r[7].toString(),
        'active': r[8].toString().toLowerCase() == 'true',
        'updatedAt': r[9].toString(),
      });
      if (rowById.containsKey(t.id)) duplicates.add(i + 1);
      rowById.putIfAbsent(t.id, () => i + 1);
      if (remote[t.id] == null ||
          t.updatedAt.isAfter(remote[t.id]!.updatedAt)) {
        remote[t.id] = t;
      }
    }
    final data = <sheets.ValueRange>[];
    final additions = <List<Object?>>[];
    // Heal duplicate rows left by concurrent appends without dropping the
    // newest definition. Sheets append avoids overwriting another device’s row.
    for (final row in duplicates) {
      data.add(
        sheets.ValueRange(
          range: "'$tabTitle'!A$row:J$row",
          values: [List.filled(10, '')],
        ),
      );
    }
    final changes = {for (final row in pending) row.id: row};
    if (duplicates.isNotEmpty) {
      for (final t in remote.values) {
        final local = changes[t.id];
        if (local == null || t.updatedAt.isAfter(local.updatedAt)) {
          changes[t.id] = t;
        }
      }
    }
    for (final t in changes.values) {
      final old = remote[t.id];
      if (old != null && old.updatedAt.isAfter(t.updatedAt)) continue;
      final row = rowById[t.id];
      final values = <Object?>[
        t.id,
        t.type.name,
        t.scopeId,
        t.name,
        t.historicalMonthlyAverage,
        t.reductionPercentage,
        t.monthlyAmount,
        t.effectiveDate.toIso8601String().split('T').first,
        t.active,
        t.updatedAt.toUtc().toIso8601String(),
      ];
      if (row == null) {
        additions.add(values);
      } else {
        data.add(
          sheets.ValueRange(
            range: "'$tabTitle'!A$row:J$row",
            values: [
              [
                t.id,
                t.type.name,
                t.scopeId,
                t.name,
                t.historicalMonthlyAverage,
                t.reductionPercentage,
                t.monthlyAmount,
                t.effectiveDate.toIso8601String().split('T').first,
                t.active,
                t.updatedAt.toUtc().toIso8601String(),
              ],
            ],
          ),
        );
      }
      remote[t.id] = t;
    }
    if (data.isNotEmpty) {
      await api.spreadsheets.values.batchUpdate(
        sheets.BatchUpdateValuesRequest(valueInputOption: 'RAW', data: data),
        spreadsheetId,
      );
    }
    if (additions.isNotEmpty) {
      await api.spreadsheets.values.append(
        sheets.ValueRange(values: additions),
        spreadsheetId,
        "'$tabTitle'!A1:J",
        valueInputOption: 'RAW',
        insertDataOption: 'INSERT_ROWS',
      );
    }
    return remote.values.toList();
  }
}
