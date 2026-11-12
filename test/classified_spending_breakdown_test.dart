import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/classified_spending_breakdown_service.dart';
import 'package:pocket_ledger/services/favourite_spending_spots_service.dart';
import 'package:pocket_ledger/services/merchant_classification_service.dart';

Transaction expense(
  String id,
  double amount, {
  String merchant = 'Market',
  String category = 'Uncategorized',
  String? group,
  int? sheetRow,
}) => Transaction(
  id: id.isEmpty ? null : id,
  sheetRow: sheetRow,
  date: DateTime(2026, 10, 1),
  amount: amount,
  description: merchant,
  category: category,
  baselineGroup: group,
);
Map<String, dynamic> merchant({bool excluded = false}) => {
  'id': 'm:market',
  'kind': 'merchant',
  'name': 'Market',
  'aliases': ['Market'],
  'category': 'Groceries',
  'group': 'Essential',
  if (excluded) 'na': true,
};
ClassifiedSpendingBreakdown build(
  List<Transaction> rows, {
  List<Map<String, dynamic>> records = const [],
  Map<Transaction, String?> legacy = const {},
}) => const ClassifiedSpendingBreakdownService().build(
  groups: const FavouriteSpendingSpotsService()
      .calculate(
        transactions: rows,
        now: DateTime(2026, 11, 12),
        allHistory: true,
      )
      .actual,
  index: MerchantClassificationIndex(records),
  categories: const [
    ExpenseCategory(
      id: 'custom',
      parentId: 'lifestyle-misc',
      name: 'Pottery classes',
    ),
  ],
  legacyGroups: legacy,
);

void main() {
  test(
    'explicit unknown category never revives a stale merchant category ID',
    () {
      final data = build(
        [expense('1', 100)],
        records: [
          {...merchant(), 'categoryId': 'custom'},
          {
            'id': 't:1',
            'kind': 'transaction',
            'transactionId': '1',
            'category': 'Unknown',
          },
        ],
      );
      expect(data.categories.items, isEmpty);
      expect(data.essentiality.classifiedTotal, 100);
    },
  );
  test('dimension totals and coverage are independent and include unknowns in denominator', () {
    final rows = [
      expense('1', 100),
      expense('2', 50, merchant: 'Cafe', category: 'Dining'),
      expense('3', 50, merchant: 'Unidentified'),
    ];
    final data = build(
      rows,
      records: [
        merchant(),
        {
          'id': 'm:unknown',
          'kind': 'merchant',
          'name': 'Unidentified',
          'aliases': ['Unidentified'],
          'group': 'Potentially Flexible',
        },
      ],
    );
    expect(data.essentiality.classifiedTotal, 150);
    expect(data.essentiality.coverage, 75);
    expect(data.categories.classifiedTotal, 150);
    expect(data.categories.coverage, 75);
    expect(data.essentiality.items.map((i) => i.name), [
      'Essential',
      'Potentially Flexible',
    ]);
    expect(
      data.essentiality.percent(data.essentiality.items.first),
      closeTo(66.6667, .001),
    );
    final onlyCategory = build([
      expense('1', 60, category: 'Dining'),
      expense('2', 40),
    ]);
    expect(onlyCategory.categories.coverage, 60);
    expect(onlyCategory.essentiality.coverage, 0);
  });
  test('transaction overrides beat merchant choices for each dimension', () {
    final data = build(
      [expense('1', 100), expense('2', 40)],
      records: [
        merchant(),
        {
          'id': 't:2',
          'kind': 'transaction',
          'transactionId': '2',
          'category': 'Pottery classes',
          'categoryId': 'custom',
          'group': 'Potentially Flexible',
        },
      ],
    );
    expect(data.essentiality.items.last.name, 'Potentially Flexible');
    expect(data.essentiality.items.last.amount, 40);
    expect(data.categories.items.last.name, 'Pottery classes');
    expect(data.categories.classifiedTotal, 140);
  });
  test(
    'excluded merchants count only explicit valid dimensional exceptions',
    () {
      final data = build(
        [
          expense('1', 100, category: 'Stale sheet category'),
          expense('2', 40),
          expense('3', 20),
        ],
        records: [
          merchant(excluded: true),
          {
            'id': 't:2',
            'kind': 'transaction',
            'transactionId': '2',
            'category': 'Pottery classes',
            'categoryId': 'custom',
          },
          {
            'id': 't:3',
            'kind': 'transaction',
            'transactionId': '3',
            'group': 'Potentially Flexible',
          },
        ],
      );
      expect(data.categories.classifiedTotal, 40);
      expect(data.essentiality.classifiedTotal, 20);
      expect(data.categories.eligibleTotal, 160);
      expect(data.essentiality.coverage, 12.5);
    },
  );
  test('unknown and NA never become Other or a known Essentiality', () {
    final data = build([
      for (final name in ['Unknown', 'NA', 'Unclassified', 'Uncategorized', ''])
        expense(name, 20, merchant: name, category: name),
    ], records: []);
    expect(data.categories.items, isEmpty);
    expect(data.essentiality.items, isEmpty);
  });
  test('top five plus Other preserve full custom category details', () {
    final data = build([
      for (var i = 1; i <= 8; i++)
        expense('$i', i * 10, merchant: 'Merchant $i', category: 'Custom $i'),
    ]).categories;
    expect(data.items.length, 8);
    expect(data.topCategories.length, 6);
    expect(data.topCategories.first.name, 'Custom 8');
    expect(data.topCategories.last.name, 'Other');
    expect(data.topCategories.last.amount, 60);
    expect(
      data.topCategories.fold<double>(0, (sum, i) => sum + data.percent(i)),
      closeTo(100, .00001),
    );
  });
  test('same inventory deduplicates IDs and sheet rows, nets refunds and drops transfers/future/nonfinite', () {
    final purchase = expense('1', 100, category: 'Groceries');
    final data = build(
      [
        purchase,
        purchase,
        expense('1', 100, category: 'Groceries'),
        expense(
          'refund',
          20,
          merchant: 'Refund from Market',
          category: 'Groceries',
        ),
        expense('', 10, merchant: 'Cafe', category: 'Dining', sheetRow: 5),
        expense('', 10, merchant: 'Cafe', category: 'Dining', sheetRow: 5),
        expense(
          'transfer',
          200,
          merchant: 'Internal Transfer',
          category: 'Transfers',
        ),
        expense('zero', 0),
        expense('nan', double.nan),
        Transaction(
          id: 'future',
          date: DateTime(2027),
          amount: 50,
          category: 'Groceries',
        ),
      ],
      records: [merchant()],
    );
    expect(data.categories.eligibleTotal, 90);
    expect(data.categories.classifiedTotal, 90);
    expect(data.categories.items.first.amount, 80);
    expect(data.essentiality.classifiedTotal, 80);
  });
  test('empty and zero spending are safe', () {
    for (final rows in [
      <Transaction>[],
      [expense('zero', 0)],
    ]) {
      final data = build(rows);
      expect(data.categories.items, isEmpty);
      expect(data.categories.coverage, 0);
      expect(data.essentiality.coverage, 0);
    }
  });
  test(
    'legacy essentiality is respected, explicit unknown does not fall back',
    () {
      final row = expense('1', 50);
      expect(
        build([row], legacy: {row: 'Essential'}).essentiality.classifiedTotal,
        50,
      );
      expect(
        build(
          [row],
          legacy: {row: 'Essential'},
          records: [
            {...merchant(), 'group': 'Unclassified'},
          ],
        ).essentiality.items,
        isEmpty,
      );
    },
  );
  test('refund-only negative bucket is retained as a net adjustment', () {
    final data = build([
      expense('1', 100, category: 'Food'),
      expense('2', 30, merchant: 'Refund from Market', category: 'Adjustment'),
    ]).categories;
    expect(data.classifiedTotal, 70);
    expect(data.items.last.amount, -30);
    expect(
      data.items.fold<double>(0, (sum, item) => sum + data.percent(item)),
      closeTo(100, .00001),
    );
  });
}
