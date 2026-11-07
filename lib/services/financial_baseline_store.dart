import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/financial_baseline.dart';

class FinancialBaselineStore {
  FinancialBaselineStore({String accountKey = 'default'})
    : _preferenceKey =
          'financial_baseline_mappings_v2_${accountKey.trim().toLowerCase()}',
      _legacyPreferenceKey =
          'financial_baseline_rules_v1_${accountKey.trim().toLowerCase()}',
      _draftPreferenceKey =
          'financial_baseline_draft_v1_${accountKey.trim().toLowerCase()}',
      _pendingPreferenceKey =
          'financial_baseline_pending_v1_${accountKey.trim().toLowerCase()}';

  final String _preferenceKey;
  final String _legacyPreferenceKey;
  final String _draftPreferenceKey;
  final String _pendingPreferenceKey;

  Future<List<FinancialBaselineMapping>> loadMappings() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_preferenceKey);
    if (encoded != null && encoded.isNotEmpty) {
      return _decodeMappings(encoded);
    }

    final legacyEncoded = preferences.getString(_legacyPreferenceKey);
    if (legacyEncoded == null || legacyEncoded.isEmpty) return const [];
    final decoded = jsonDecode(legacyEncoded);
    if (decoded is! List) {
      throw const FormatException(
        'Stored financial baseline mappings are invalid.',
      );
    }
    final mappings = FinancialBaselineMapping.migrateStoredRows(decoded);
    await saveMappings(mappings);
    return mappings;
  }

  Future<void> saveMappings(Iterable<FinancialBaselineMapping> mappings) async {
    final preferences = await SharedPreferences.getInstance();
    final unique = <String, FinancialBaselineMapping>{};
    for (final mapping in mappings) {
      unique[mapping.id] = mapping;
    }
    final saved = await preferences.setString(
      _preferenceKey,
      jsonEncode(unique.values.map((mapping) => mapping.toJson()).toList()),
    );
    if (!saved) throw StateError('Could not save financial baseline mappings.');
  }

  Future<void> saveDraft(FinancialBaselineDraft draft) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _draftPreferenceKey,
      jsonEncode({
        'base': draft.baseMappings.map((mapping) => mapping.toJson()).toList(),
        'draft': draft.draftMappings
            .map((mapping) => mapping.toJson())
            .toList(),
      }),
    );
    if (!saved) {
      throw StateError('Could not save the financial baseline draft.');
    }
  }

  Future<FinancialBaselineDraft?> loadDraft() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_draftPreferenceKey);
    if (encoded == null || encoded.isEmpty) return null;
    final value = jsonDecode(encoded);
    if (value is! Map) {
      throw const FormatException('Stored baseline draft is invalid.');
    }
    return FinancialBaselineDraft(
      baseMappings: _decodeMappings(jsonEncode(value['base'] ?? const [])),
      draftMappings: _decodeMappings(jsonEncode(value['draft'] ?? const [])),
    );
  }

  Future<void> clearDraft() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_draftPreferenceKey);
  }

  Future<void> savePendingSync(FinancialBaselineSyncBatch batch) async {
    final preferences = await SharedPreferences.getInstance();
    final previous = await loadPendingSync();
    final upserts = <String, FinancialBaselineMapping>{
      for (final m in previous?.upserts ?? const <FinancialBaselineMapping>[])
        m.merchantFingerprint.trim().toLowerCase(): m,
    };
    final removals = <String, String>{
      for (final merchant in previous?.removals ?? const <String>[])
        merchant.trim().toLowerCase(): merchant,
    };
    for (final merchant in batch.removals) {
      final key = merchant.trim().toLowerCase();
      upserts.remove(key);
      removals[key] = merchant;
    }
    for (final m in batch.upserts) {
      final key = m.merchantFingerprint.trim().toLowerCase();
      removals.remove(key);
      upserts[key] = m;
    }
    final saved = await preferences.setString(
      _pendingPreferenceKey,
      jsonEncode({
        'upserts': upserts.values.map((mapping) => mapping.toJson()).toList(),
        'removals': removals.values.toList(),
      }),
    );
    if (!saved) throw StateError('Could not queue baseline changes for sync.');
  }

  Future<FinancialBaselineSyncBatch?> loadPendingSync() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_pendingPreferenceKey);
    if (encoded == null || encoded.isEmpty) return null;
    final decoded = jsonDecode(encoded);
    if (decoded is List) {
      return FinancialBaselineSyncBatch(
        upserts: _decodeMappings(encoded),
        removals: const [],
      );
    }
    if (decoded is! Map) {
      throw const FormatException('Stored baseline sync batch is invalid.');
    }
    return FinancialBaselineSyncBatch(
      upserts: _decodeMappings(jsonEncode(decoded['upserts'] ?? const [])),
      removals: (decoded['removals'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }

  Future<void> clearPendingSync() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_pendingPreferenceKey);
  }

  List<FinancialBaselineMapping> _decodeMappings(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const FormatException(
        'Stored financial baseline mappings are invalid.',
      );
    }
    return FinancialBaselineMapping.migrateStoredRows(decoded);
  }
}
