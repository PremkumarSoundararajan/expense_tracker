import 'dart:math';

const defaultExpenseParents = <String, String>{
  'housing-bills': 'Housing / Bills',
  'food-household': 'Food / Household',
  'transport': 'Transport',
  'financial-obligations': 'Financial Obligations',
  'health-wellness': 'Health & Wellness',
  'lifestyle-misc': 'Lifestyle / Misc',
};

const suggestedExpenseSubcategories = <String, List<String>>{
  'housing-bills': [
    'Mortgage / Rent',
    'Electricity',
    'Natural Gas',
    'Water',
    'Phone',
    'Internet',
    'Home Maintenance',
    'Home Furnishings',
    'Home Insurance',
  ],
  'food-household': [
    'Groceries',
    'Restaurants / Eating Out',
    'Food Delivery',
    'Household Supplies',
  ],
  'transport': [
    'Fuel',
    'Car Maintenance',
    'Auto Insurance',
    'Parking',
    'Public Transport',
    'Rideshare',
  ],
  'financial-obligations': [
    'Loan Payments',
    'Taxes',
    'Credit Card Fees',
    'Bank Fees',
  ],
  'health-wellness': ['Medical', 'Pharmacy', 'Dental', 'Vision', 'Fitness'],
  'lifestyle-misc': [
    'Personal Care',
    'Shopping',
    'Clothing',
    'Entertainment',
    'Travel',
    'Education',
    'Professional Services',
    'Gifts & Donations',
    'Hobbies',
    'Pets',
  ],
};

String stableCategoryId(String parentId, String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return '$parentId:$slug';
}

String createCustomCategoryId(String parentId) =>
    '$parentId:custom-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random.secure().nextInt(1 << 20).toRadixString(36)}';

const homeMaintenanceCategory = ExpenseCategory(
  id: 'housing-bills:home-maintenance',
  parentId: 'housing-bills',
  name: 'Home Maintenance',
  isSuggested: true,
);

List<ExpenseCategory> withHomeMaintenance(
  Iterable<ExpenseCategory> categories,
) {
  final result = categories.toList();
  if (!result.any(
    (c) =>
        c.id == homeMaintenanceCategory.id ||
        c.name.toLowerCase() == 'home maintenance',
  ))
    result.add(homeMaintenanceCategory);
  return result;
}

class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.parentId,
    required this.name,
    this.active = true,
    this.archived = false,
    this.sortOrder = 0,
    this.isSuggested = false,
  });
  final String id;
  final String parentId;
  final String name;
  final bool active;
  final bool archived;
  final int sortOrder;
  final bool isSuggested;
  String get parentName => defaultExpenseParents[parentId] ?? 'Other';

  ExpenseCategory copyWith({
    String? name,
    bool? active,
    bool? archived,
    int? sortOrder,
  }) => ExpenseCategory(
    id: id,
    parentId: parentId,
    name: name ?? this.name,
    active: active ?? this.active,
    archived: archived ?? this.archived,
    sortOrder: sortOrder ?? this.sortOrder,
    isSuggested: isSuggested,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'parentId': parentId,
    'name': name,
    'active': active,
    'archived': archived,
    'sortOrder': sortOrder,
    'isSuggested': isSuggested,
  };
  factory ExpenseCategory.fromJson(Map<String, dynamic> json) =>
      ExpenseCategory(
        id: json['id']?.toString() ?? '',
        parentId: json['parentId']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        active: json['active'] != false,
        archived: json['archived'] == true,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        isSuggested: json['isSuggested'] == true,
      );
}

class ExpenseCategoryMapping {
  const ExpenseCategoryMapping({
    required this.keyword,
    required this.categoryId,
    this.matchType = 'keyword',
  });
  final String keyword;
  final String categoryId;
  final String matchType;
  Map<String, Object?> toJson() => {
    'keyword': keyword,
    'categoryId': categoryId,
    'matchType': matchType,
  };
  factory ExpenseCategoryMapping.fromJson(Map<String, dynamic> json) =>
      ExpenseCategoryMapping(
        keyword: json['keyword']?.toString() ?? '',
        categoryId: json['categoryId']?.toString() ?? '',
        matchType: json['matchType']?.toString() ?? 'keyword',
      );
}
