import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/transaction.dart';

class LocalTransactionStore {
  LocalTransactionStore({String accountKey = 'default'})
    : _cacheKey = 'transaction_cache_v1_$accountKey',
      _pendingKey = 'transaction_outbox_v1_$accountKey';

  final String _cacheKey;
  final String _pendingKey;

  Future<List<Transaction>> loadCached() async {
    final preferences = await SharedPreferences.getInstance();
    return _decode(preferences.getString(_cacheKey));
  }

  Future<List<Transaction>> loadPending() async {
    final preferences = await SharedPreferences.getInstance();
    return _decode(preferences.getString(_pendingKey));
  }

  Future<void> saveCached(List<Transaction> transactions) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _cacheKey,
      jsonEncode(
        transactions.map((transaction) => transaction.toJson()).toList(),
      ),
    );
    if (!saved) throw StateError('Could not save the local transaction cache.');
  }

  Future<void> savePending(List<Transaction> transactions) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _pendingKey,
      jsonEncode(
        transactions.map((transaction) => transaction.toJson()).toList(),
      ),
    );
    if (!saved) throw StateError('Could not save pending expense changes.');
  }

  Future<void> upsertPending(Transaction transaction) async {
    final pending = List<Transaction>.of(await loadPending());
    final index = pending.indexWhere(
      (candidate) =>
          transaction.id != null && candidate.id == transaction.id ||
          transaction.sheetRow != null &&
              candidate.sheetRow == transaction.sheetRow,
    );
    if (index < 0) {
      pending.add(transaction);
    } else {
      pending[index] = transaction;
    }
    await savePending(pending);
  }

  static List<Transaction> _decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return const [];
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const FormatException('Stored transaction data is invalid.');
    }
    return decoded
        .whereType<Map>()
        .map((row) => Transaction.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: true);
  }
}
