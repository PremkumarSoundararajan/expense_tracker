import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/models/financial_baseline.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/spending_reduction_planner_service.dart';

Transaction tx(
  String description,
  double amount, {
  String category = 'Food / Household',
  String? categoryId = 'food-household',
  int day = 5,
}) => Transaction(
  date: DateTime(2026, 10, day),
  amount: amount,
  category: category,
  categoryId: categoryId,
  description: description,
);

const food = ExpenseCategory(
  id: 'food-household',
  parentId: 'food-household',
  name: 'Food / Household',
);
const dining = ExpenseCategory(
  id: 'food-household:dining',
  parentId: 'food-household',
  name: 'Restaurants / Eating Out',
);
const groceries = ExpenseCategory(
  id: 'food-household:groceries',
  parentId: 'food-household',
  name: 'Groceries',
);

void main() {
  final service = SpendingReductionPlannerService();

  test('only adjustable transactions feed category and merchant options', () {
    final data = service.analyze(
      categories: const [food, dining, groceries],
      lifestyleMappings: const [
        FinancialBaselineMapping(
          merchantFingerprint: 'DINING PLACE',
          group: BaselineGroup.potentiallyFlexible,
        ),
        FinancialBaselineMapping(
          merchantFingerprint: 'GROCERY MARKET',
          group: BaselineGroup.potentiallyFlexible,
        ),
        FinancialBaselineMapping(
          merchantFingerprint: 'PHARMACY',
          group: BaselineGroup.essential,
        ),
      ],
      transactions: [
        tx('DINING PLACE', 100, category: dining.name, categoryId: dining.id),
        tx(
          'GROCERY MARKET',
          50,
          category: groceries.name,
          categoryId: groceries.id,
        ),
        tx('PHARMACY', 300),
        tx('CARD TRANSFER', 400),
        tx(
          'DINING PLACE REFUND',
          90,
          category: dining.name,
          categoryId: dining.id,
        ),
      ],
    );
    expect(data.merchants.map((merchant) => merchant.monthlySpending), [
      100,
      50,
    ]);
    expect(data.merchants.first.transactionCount, 1);
    expect(
      data.categories
          .firstWhere((category) => category.id == food.id)
          .monthlySpending,
      150,
    );
    expect(
      data.categories
          .firstWhere((category) => category.id == dining.id)
          .monthlySpending,
      100,
    );
  });

  test(
    'merchant targets override category targets without double counting',
    () {
      final data = service.analyze(
        categories: const [food, dining],
        lifestyleMappings: const [
          FinancialBaselineMapping(
            merchantFingerprint: 'RESTAURANT A',
            group: BaselineGroup.potentiallyFlexible,
          ),
          FinancialBaselineMapping(
            merchantFingerprint: 'RESTAURANT B',
            group: BaselineGroup.potentiallyFlexible,
          ),
        ],
        transactions: [
          tx('RESTAURANT A', 100, category: dining.name, categoryId: dining.id),
          tx('RESTAURANT B', 200, category: dining.name, categoryId: dining.id),
        ],
      );
      final plan = data.calculate({
        'category:${dining.id}': 20,
        'merchant:restaurant a': 50,
      });
      expect(plan.monthlyReduction, 90);
      expect(plan.annualizedPotential, 1080);
      expect(
        plan.impacts.firstWhere((impact) => impact.isMerchant).monthlyReduction,
        50,
      );
      expect(
        plan.impacts
            .firstWhere((impact) => !impact.isMerchant)
            .monthlyReduction,
        40,
      );
      expect(
        plan.impacts.fold<double>(
          0,
          (sum, impact) => sum + impact.monthlyReduction,
        ),
        plan.monthlyReduction,
      );
    },
  );

  test(
    'subcategory target overrides parent and parent covers remaining spending',
    () {
      final data = service.analyze(
        categories: const [food, dining, groceries],
        lifestyleMappings: const [
          FinancialBaselineMapping(
            merchantFingerprint: 'DINER',
            group: BaselineGroup.potentiallyFlexible,
          ),
          FinancialBaselineMapping(
            merchantFingerprint: 'MARKET',
            group: BaselineGroup.potentiallyFlexible,
          ),
        ],
        transactions: [
          tx('DINER', 100, category: dining.name, categoryId: dining.id),
          tx('MARKET', 200, category: groceries.name, categoryId: groceries.id),
        ],
      );
      final plan = data.calculate({
        'category:${food.id}': 20,
        'category:${dining.id}': 50,
      });
      expect(plan.monthlyReduction, 90);
      expect(
        plan.impacts
            .firstWhere((impact) => impact.name == food.name)
            .monthlyReduction,
        40,
      );
      expect(
        plan.impacts
            .firstWhere((impact) => impact.name.contains(dining.name))
            .monthlyReduction,
        50,
      );
    },
  );

  test('multiple merchant overrides leave unmatched spending to the category target', () {
    final data = service.analyze(
      categories: const [food, dining],
      lifestyleMappings: const [
        FinancialBaselineMapping(
          merchantFingerprint: 'DINER A',
          group: BaselineGroup.potentiallyFlexible,
        ),
        FinancialBaselineMapping(
          merchantFingerprint: 'DINER B',
          group: BaselineGroup.potentiallyFlexible,
        ),
        FinancialBaselineMapping(
          merchantFingerprint: 'DINER C',
          group: BaselineGroup.potentiallyFlexible,
        ),
      ],
      transactions: [
        tx('DINER A', 100, category: dining.name, categoryId: dining.id),
        tx('DINER B', 200, category: dining.name, categoryId: dining.id),
        tx('DINER C', 300, category: dining.name, categoryId: dining.id),
      ],
    );
    final plan = data.calculate({
      'category:${dining.id}': 20,
      'merchant:diner a': 50,
      'merchant:diner b': 25,
    });
    expect(plan.monthlyReduction, 160);
    expect(
      plan.impacts.firstWhere((impact) => !impact.isMerchant).monthlyReduction,
      60,
    );
  });

  test('merchant override spans eligible transactions across categories', () {
    final data = service.analyze(
      categories: const [food, dining, groceries],
      lifestyleMappings: const [
        FinancialBaselineMapping(
          merchantFingerprint: 'ONLINE SHOP',
          group: BaselineGroup.potentiallyFlexible,
        ),
      ],
      transactions: [
        tx('ONLINE SHOP', 60, category: dining.name, categoryId: dining.id),
        tx(
          'ONLINE SHOP',
          40,
          category: groceries.name,
          categoryId: groceries.id,
          day: 12,
        ),
      ],
    );
    final plan = data.calculate({
      'category:${dining.id}': 20,
      'category:${groceries.id}': 10,
      'merchant:shop': 50,
    });
    expect(plan.monthlyReduction, 50);
    expect(
      plan.impacts
          .where((impact) => !impact.isMerchant)
          .every((impact) => impact.monthlyReduction == 0),
      isTrue,
    );
  });

  test(
    'unknown expense category remains uncategorized but merchant target works',
    () {
      final data = service.analyze(
        categories: const [],
        lifestyleMappings: const [
          FinancialBaselineMapping(
            merchantFingerprint: 'LOCAL SHOP',
            group: BaselineGroup.potentiallyFlexible,
          ),
        ],
        transactions: [
          tx(
            'LOCAL SHOP',
            80,
            category: 'Not mapped',
            categoryId: 'missing:id',
          ),
        ],
      );
      expect(data.hasUncategorizedSpending, isTrue);
      expect(data.uncategorizedMonthlySpending, 80);
      expect(
        data.categories.any((category) => category.id == '__uncategorized__'),
        isFalse,
      );
      expect(data.calculate({'merchant:local shop': 25}).monthlyReduction, 20);
    },
  );

  test('removing a merchant target restores the category target', () {
    final data = service.analyze(
      categories: const [food, dining],
      lifestyleMappings: const [
        FinancialBaselineMapping(
          merchantFingerprint: 'RESTAURANT A',
          group: BaselineGroup.potentiallyFlexible,
        ),
      ],
      transactions: [
        tx('RESTAURANT A', 100, category: dining.name, categoryId: dining.id),
      ],
    );
    final categoryTarget = 'category:${dining.id}';
    final merchantTarget = 'merchant:restaurant a';
    expect(
      data.calculate({categoryTarget: 20, merchantTarget: 50}).monthlyReduction,
      50,
    );
    expect(data.calculate({categoryTarget: 20}).monthlyReduction, 20);
  });

  test('missing category IDs fall back to configured category names', () {
    final data = service.analyze(
      categories: const [food, dining],
      lifestyleMappings: const [
        FinancialBaselineMapping(
          merchantFingerprint: 'DINER',
          group: BaselineGroup.potentiallyFlexible,
        ),
      ],
      transactions: [tx('DINER', 100, category: dining.name, categoryId: null)],
    );
    expect(data.categories.any((category) => category.id == dining.id), isTrue);
    expect(data.hasUncategorizedSpending, isFalse);
  });

  test('zero eligible adjustable spending produces an empty zero plan', () {
    final data = service.analyze(
      categories: const [food],
      lifestyleMappings: const [
        FinancialBaselineMapping(
          merchantFingerprint: 'PHARMACY',
          group: BaselineGroup.essential,
        ),
      ],
      transactions: [tx('PHARMACY', 100)],
    );
    expect(data.merchants, isEmpty);
    expect(data.categories, isEmpty);
    expect(data.calculate(const {}).monthlyReduction, 0);
    expect(data.calculate(const {}).annualizedPotential, 0);
  });
}
