import 'package:flutter_test/flutter_test.dart';

// Relative imports so the file works without knowing the package name.
// Swap for `package:<your_app>/...` if your lints prefer it.
import '../lib/models/transaction.dart';
import '../lib/services/suggested_budget_service.dart';

// -----------------------------------------------------------------------------
// Test fixtures
// -----------------------------------------------------------------------------

/// "Today" for every test. Current month = Oct 2026, so completed months run
/// up to Sep 2026 and the 6-month lookback window is Apr–Sep.
final now = DateTime(2026, 10, 15);

/// A date [monthsAgo] months before the current month (1 = Sep, 6 = Apr).
DateTime ago(int monthsAgo, [int day = 10]) =>
    DateTime(2026, 10 - monthsAgo, day);

/// ONE place to adapt if the Transaction constructor differs.
Transaction tx({
  required DateTime date,
  required double amount,
  String category = 'Other',
  String description = '',
  ExpenseType type = ExpenseType.regular,
}) {
  return Transaction(
    date: date,
    amount: amount,
    category: category,
    description: description,
    expenseType: type,
  );
}

/// $1,000 rent on the 1st of each month, from [from] to [to] months ago.
/// Gives tests a stable baseline and a full 6-month history.
List<Transaction> rent({int from = 6, int to = 1}) => [
  for (var m = from; m >= to; m--)
    tx(
      date: ago(m, 1),
      amount: 1000,
      category: 'Housing',
      description: 'Rent',
    ),
];

SuggestedBudgetItem? find(List<SuggestedBudgetItem> items, String label) {
  for (final item in items) {
    if (item.label == label) return item;
  }
  return null;
}

List<SuggestedBudgetItem> allItems(SuggestedBudget b) => [
  ...b.recurringItems,
  ...b.miscItems,
  ...b.excludedItems,
];

void main() {
  late SuggestedBudgetService service;

  setUp(() => service = SuggestedBudgetService());

  SuggestedBudget run(List<Transaction> transactions) {
    final result = service.suggest(transactions: transactions, now: now);
    expect(result, isNotNull, reason: 'expected a suggestion');
    return result!;
  }

  // ---------------------------------------------------------------------------
  // Scenario 1: recently started recurring expense
  // ---------------------------------------------------------------------------
  group('recently started recurring expense', () {
    test('averages over active life, not total history', () {
      final result = run([
        // Establishes ~9 months of history (Jan 1), outside the 6-mo window.
        tx(date: ago(9, 1), amount: 25, description: 'Seed one-off'),
        // 4 consecutive months: Jun–Sep.
        tx(date: ago(4), amount: 320, category: 'Education', description: 'Gideon Reading'),
        tx(date: ago(3), amount: 350, category: 'Education', description: 'Gideon Reading'),
        tx(date: ago(2), amount: 320, category: 'Education', description: 'Gideon Reading'),
        tx(date: ago(1), amount: 320, category: 'Education', description: 'Gideon Reading'),
      ]);

      final gideon = find(result.recurringItems, 'Gideon Reading');
      expect(gideon, isNotNull);
      expect(gideon!.monthlyAverage, closeTo(327.50, 0.001));
      expect(gideon.monthsSeen, 4);
      expect(gideon.rationale, contains('327.50'));
      expect(result.completedMonths, 9);
      // Old (diluted) behaviour would have produced 1310 / 9 = 145.56.
      expect(gideon.monthlyAverage, isNot(closeTo(145.56, 0.5)));
      expect(result.amount, closeTo(327.50 * 1.1, 0.01));
    });

    test('a new bill seen in the two most recent months is recurring', () {
      final result = run([
        ...rent(),
        tx(date: ago(2), amount: 50, category: 'Subscriptions', description: 'New Sub'),
        tx(date: ago(1), amount: 50, category: 'Subscriptions', description: 'New Sub'),
      ]);

      final item = find(result.recurringItems, 'New Sub');
      expect(item, isNotNull);
      expect(item!.monthlyAverage, closeTo(50, 0.001));
    });

    test('bi-monthly bill is not overstated', () {
      final result = run([
        ...rent(),
        tx(date: ago(6), amount: 90, category: 'Utilities', description: 'Water'),
        tx(date: ago(4), amount: 90, category: 'Utilities', description: 'Water'),
        tx(date: ago(2), amount: 90, category: 'Utilities', description: 'Water'),
      ]);

      final water = find(result.recurringItems, 'Water');
      expect(water, isNotNull);
      // 270 spread over the 6 months since the first charge.
      expect(water!.monthlyAverage, closeTo(45, 0.001));
      expect(water.monthsSeen, 3);
    });
  });

  // ---------------------------------------------------------------------------
  // Scenario 2: cancelled / defunct expense
  // ---------------------------------------------------------------------------
  group('cancelled expense', () {
    test('subscription that stopped inside the window is excluded', () {
      final result = run([
        ...rent(),
        // Apr–Jun, then nothing for Jul–Sep.
        tx(date: ago(6), amount: 15, category: 'Subscriptions', description: 'Old Streaming'),
        tx(date: ago(5), amount: 15, category: 'Subscriptions', description: 'Old Streaming'),
        tx(date: ago(4), amount: 15, category: 'Subscriptions', description: 'Old Streaming'),
      ]);

      expect(find(result.recurringItems, 'Old Streaming'), isNull);
      expect(result.recurringTotal, closeTo(1000, 0.001));

      final excluded = find(result.excludedItems, 'Old Streaming');
      expect(excluded, isNotNull);
      expect(excluded!.rationale, contains('cancelled'));
    });

    test('subscription older than the window never appears in the budget', () {
      final result = run([
        ...rent(),
        tx(date: ago(9), amount: 40, category: 'Fitness', description: 'Old Gym'),
        tx(date: ago(8), amount: 40, category: 'Fitness', description: 'Old Gym'),
        tx(date: ago(7), amount: 40, category: 'Fitness', description: 'Old Gym'),
      ]);

      expect(find(result.recurringItems, 'Old Gym'), isNull);
      expect(find(result.miscItems, 'Old Gym'), isNull);
      expect(result.recurringTotal, closeTo(1000, 0.001));
    });

    test('one missed month does not cancel a recurring bill', () {
      final result = run([
        ...rent(),
        // Apr, May, Jun, Aug — skipped Jul and Sep? No: last charge Aug,
        // so it is still within the allowed gap.
        tx(date: ago(6), amount: 30, category: 'Subscriptions', description: 'Cloud Storage'),
        tx(date: ago(5), amount: 30, category: 'Subscriptions', description: 'Cloud Storage'),
        tx(date: ago(4), amount: 30, category: 'Subscriptions', description: 'Cloud Storage'),
        tx(date: ago(2), amount: 30, category: 'Subscriptions', description: 'Cloud Storage'),
      ]);

      expect(find(result.recurringItems, 'Cloud Storage'), isNotNull);
      expect(find(result.excludedItems, 'Cloud Storage'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Scenario 3: isolated one-off expense
  // ---------------------------------------------------------------------------
  group('isolated one-off expense', () {
    test('two non-consecutive months is variable spending, not a bill', () {
      final result = run([
        ...rent(),
        tx(date: ago(6), amount: 450, category: 'Auto', description: 'Texas Car Care'),
        tx(date: ago(3), amount: 450, category: 'Auto', description: 'Texas Car Care'),
      ]);

      expect(find(result.recurringItems, 'Texas Car Care'), isNull);

      final auto = find(result.miscItems, 'Auto');
      expect(auto, isNotNull);
      expect(auto!.monthsSeen, 2);
      // Trimmed mean of [450, 0, 0, 450, 0, 0] = [0, 0, 0, 450] -> 112.50.
      expect(auto.monthlyAverage, closeTo(112.50, 0.001));
      expect(result.amount, closeTo((1000 + 112.50) * 1.1, 0.01));
    });

    test('a single spike month is dropped from the baseline', () {
      final result = run([
        ...rent(),
        tx(date: ago(3), amount: 900, category: 'Travel', description: 'Weekend Trip'),
      ]);

      expect(find(result.miscItems, 'Travel'), isNull);
      final excluded = find(result.excludedItems, 'Travel');
      expect(excluded, isNotNull);
      expect(result.miscAverage, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Scenario 4: variable spending category
  // ---------------------------------------------------------------------------
  group('variable spending category', () {
    test('smooths groceries without double-counting recurring stores', () {
      final amounts = [400.0, 450.0, 550.0, 500.0, 420.0, 480.0];
      final result = run([
        // Recurring grocery-category bill (membership) — must not leak into
        // the variable pool.
        for (var m = 6; m >= 1; m--)
          tx(date: ago(m, 1), amount: 60, category: 'Groceries', description: 'Costco'),
        // Different store each month -> each is one-off at merchant level.
        for (var i = 0; i < 6; i++)
          tx(
            date: ago(6 - i),
            amount: amounts[i],
            category: 'Groceries',
            description: 'Store ${String.fromCharCode(65 + i)}',
          ),
      ]);

      final costco = find(result.recurringItems, 'Costco');
      expect(costco, isNotNull);
      expect(costco!.monthlyAverage, closeTo(60, 0.001));

      final groceries = find(result.miscItems, 'Groceries');
      expect(groceries, isNotNull);
      // Sorted: 400 420 450 480 500 550 -> trim ends -> mean(420..500) = 462.5.
      expect(groceries!.monthlyAverage, closeTo(462.50, 0.001));
      expect(
        groceries.sourceTransactions.any((t) => t.description == 'Costco'),
        isFalse,
      );
      expect(result.recurringTotal + result.miscAverage, closeTo(522.50, 0.001));
    });
  });

  // ---------------------------------------------------------------------------
  // Scenario 5: partial months & incomplete history
  // ---------------------------------------------------------------------------
  group('partial months and incomplete history', () {
    test('empty list returns null', () {
      expect(service.suggest(transactions: const [], now: now), isNull);
    });

    test('about 1.5 months of history returns null without throwing', () {
      final result = service.suggest(
        transactions: [
          tx(date: DateTime(2026, 9, 10), amount: 50, description: 'Coffee'),
          tx(date: DateTime(2026, 10, 5), amount: 20, description: 'Coffee'),
        ],
        now: now,
      );
      expect(result, isNull);
    });

    test('current-month-only history returns null', () {
      final result = service.suggest(
        transactions: [
          tx(date: ago(0, 2), amount: 100, description: 'Groceries'),
          tx(date: ago(0, 5), amount: 80, description: 'Gas'),
        ],
        now: now,
      );
      expect(result, isNull);
    });

    test('exactly two completed months is enough', () {
      final result = run(rent(from: 2, to: 1));
      expect(result.completedMonths, 2);
      expect(result.recurringItems, hasLength(1));
      expect(result.amount, closeTo(1100, 0.01));
    });

    test('current partial month is ignored', () {
      final result = run([
        ...rent(),
        tx(date: ago(0, 5), amount: 9999, category: 'Other', description: 'Current Month Splurge'),
      ]);
      expect(find(allItems(result), 'Current Month Splurge'), isNull);
      expect(result.amount, closeTo(1100, 0.01));
    });
  });

  // ---------------------------------------------------------------------------
  // Scenario 6: refunds & overlapping imports
  // ---------------------------------------------------------------------------
  group('refunds and overlapping imports', () {
    test('same-month charge and refund net to zero', () {
      final result = run([
        ...rent(),
        tx(date: ago(2, 10), amount: 100, category: 'Shopping', description: 'Amazon'),
        tx(date: ago(2, 12), amount: -100, category: 'Shopping', description: 'Amazon'),
      ]);

      expect(find(allItems(result), 'Shopping'), isNull);
      expect(result.miscAverage, 0);
      expect(result.amount, closeTo(1100, 0.01));
    });

    test('refund in a later month offsets the earlier charge', () {
      final result = run([
        ...rent(),
        tx(date: ago(3), amount: 100, category: 'Shopping', description: 'Amazon'),
        tx(date: ago(2), amount: -100, category: 'Shopping', description: 'Amazon'),
      ]);

      expect(find(allItems(result), 'Shopping'), isNull);
      expect(result.amount, closeTo(1100, 0.01));
    });

    test('exact duplicate rows from overlapping imports are counted once', () {
      final duplicated = [
        ...rent(),
        tx(date: ago(1, 1), amount: 1000, category: 'Housing', description: 'Rent'),
      ];
      final result = run(duplicated);

      final rentItem = find(result.recurringItems, 'Rent');
      expect(rentItem, isNotNull);
      expect(rentItem!.monthlyAverage, closeTo(1000, 0.001));
    });
  });

  // ---------------------------------------------------------------------------
  // Scope: occasional expenses and buffer math
  // ---------------------------------------------------------------------------
  group('scope and totals', () {
    test('occasional expense types are excluded', () {
      final result = run([
        ...rent(),
        tx(date: ago(2), amount: 2000, category: 'Home', description: 'New Roof', type: ExpenseType.plannedOccasional),
        tx(date: ago(3), amount: 800, category: 'Auto', description: 'Transmission', type: ExpenseType.unexpectedOccasional),
      ]);

      expect(find(allItems(result), 'New Roof'), isNull);
      expect(find(allItems(result), 'Transmission'), isNull);
      expect(result.amount, closeTo(1100, 0.01));
    });

    test('amount = (recurring + misc) plus 10% buffer, rounded to cents', () {
      final result = run(rent());
      expect(result.recurringTotal, closeTo(1000, 0.001));
      expect(result.buffer, closeTo(100, 0.001));
      expect(result.amount, 1100.00);
    });
  });

  // ---------------------------------------------------------------------------
  // normalizeMerchant
  // ---------------------------------------------------------------------------
  group('normalizeMerchant', () {
    test('strips processor prefixes and reference suffixes', () {
      expect(normalizeMerchant('SQ *Blue Bottle'), 'blue bottle');
      expect(normalizeMerchant('Starbucks #12345'), 'starbucks');
      expect(normalizeMerchant('AMZN Mktp US*2K4HG'), 'amzn mktp us');
      expect(normalizeMerchant('Netflix 01/15'), 'netflix');
    });

    test('keeps short meaningful numbers and handles blanks', () {
      expect(normalizeMerchant('Gym 24'), 'gym 24');
      expect(normalizeMerchant('   '), '');
    });
  });
}
