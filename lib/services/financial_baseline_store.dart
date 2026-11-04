import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/financial_baseline.dart';

class FinancialBaselineStore {
  FinancialBaselineStore({String accountKey = 'default'})
    : _preferenceKey =
          'financial_baseline_mappings_v2_${accountKey.trim().toLowerCase()}',
      _legacyPreferenceKey =
          'financial_baseline_rules_v1_${accountKey.trim().toLowerCase()}';

  final String _preferenceKey;
  final String _legacyPreferenceKey;

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

  List<FinancialBaselineMapping> _decodeMappings(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const FormatException(
        'Stored financial baseline mappings are invalid.',
      );
    }
    return decoded
        .whereType<Map>()
        .map(
          (row) =>
              FinancialBaselineMapping.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }
}
