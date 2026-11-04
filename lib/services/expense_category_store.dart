import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/expense_category.dart';

class ExpenseCategoryStore {
  ExpenseCategoryStore({required String accountKey})
    : _key = 'expense_categories_v1_${accountKey.trim().toLowerCase()}';
  final String _key;

  Future<Map<String, Object?>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_key);
    if (encoded == null || encoded.isEmpty)
      return {
        'categories': <ExpenseCategory>[],
        'mappings': <ExpenseCategoryMapping>[],
      };
    final data = jsonDecode(encoded) as Map<String, dynamic>;
    return {
      'categories': (data['categories'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) => ExpenseCategory.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
      'mappings': (data['mappings'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) =>
                ExpenseCategoryMapping.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(),
    };
  }

  Future<void> save({
    required Iterable<ExpenseCategory> categories,
    required Iterable<ExpenseCategoryMapping> mappings,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(
      _key,
      jsonEncode({
        'version': 1,
        'categories': categories.map((c) => c.toJson()).toList(),
        'mappings': mappings.map((m) => m.toJson()).toList(),
      }),
    );
    if (!ok) throw StateError('Could not save your expense categories.');
  }
}
