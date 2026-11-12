import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/favourite_spending_spots_service.dart';

Transaction _transaction({
  required String description,
  required double amount,
  DateTime? date,
  ExpenseType expenseType = ExpenseType.regular,
  String? id,
  int? sheetRow,
  String category = 'Food / Household',
}) {
  return Transaction(
    date: date ?? DateTime(2025, 5, 1),
    amount: amount,
    category: category,
    description: description,
    expenseType: expenseType,
    id: id,
    sheetRow: sheetRow,
  );
}

void main() {
  const service = FavouriteSpendingSpotsService();
  final now = DateTime(2025, 11, 15);

  test(
    'groups identical merchant descriptions and averages over six months',
    () {
      final result = service.calculate(
        transactions: [
          _transaction(
            description: 'Harbor Cafe',
            amount: 100,
            date: DateTime(2025, 5, 1),
          ),
          _transaction(
            description: 'Harbor Cafe',
            amount: 150,
            date: DateTime(2025, 9, 8),
          ),
        ],
        now: now,
      );

      expect(result.completedMonths, 6);
      expect(result.actual, hasLength(1));
      expect(result.actual.single.total, 250);
      expect(result.actual.single.averageMonthly, closeTo(250 / 6, 0.001));
      expect(result.actual.single.transactionCount, 2);
    },
  );

  test('matches case, punctuation, store numbers and trailing references', () {
    final result = service.calculate(
      transactions: [
        _transaction(
          description: '  Harbor—Cafe #123 837492 WEB ID: ABC123  ',
          amount: 20,
        ),
        _transaction(
          description: 'harbor cafe #987 993847 WEB ID: XYZ987',
          amount: 30,
        ),
      ],
      now: now,
    );

    expect(result.actual, hasLength(1));
    expect(result.actual.single.total, 50);
    expect(
      result.actual.single.transactions.first.transaction.description,
      '  Harbor—Cafe #123 837492 WEB ID: ABC123  ',
    );
    expect(
      result.actual.single.transactions.last.transaction.description,
      'harbor cafe #987 993847 WEB ID: XYZ987',
    );
  });

  test('does not merge similar but distinct merchant names', () {
    final result = service.calculate(
      transactions: [
        _transaction(description: 'Acme Market', amount: 100),
        _transaction(description: 'Acme Markets', amount: 80),
      ],
      now: now,
    );

    expect(result.actual, hasLength(2));
    expect(result.actual.map((spot) => spot.name), [
      'Acme Market',
      'Acme Markets',
    ]);
  });

  test(
    'normalizes international descriptions without replacing the original',
    () {
      final result = service.calculate(
        transactions: [
          _transaction(description: '東京・食堂', amount: 20),
          _transaction(description: '東京 食堂', amount: 30),
          _transaction(description: 'दुकान — पुणे', amount: 40),
          _transaction(description: 'दुकान, पुणे', amount: 10),
        ],
        now: now,
      );

      expect(result.actual, hasLength(2));
      expect(result.actual.first.total, 50);
      expect(result.actual.last.total, 50);
      expect(
        result.actual
            .expand((spot) => spot.transactions)
            .any((item) => item.transaction.description == '東京・食堂'),
        isTrue,
      );
    },
  );

  test('filters regular and both occasional classifications', () {
    final result = service.calculate(
      transactions: [
        _transaction(
          description: 'Local Shop',
          amount: 40,
          expenseType: ExpenseType.regular,
        ),
        _transaction(
          description: 'Local Shop',
          amount: 30,
          expenseType: ExpenseType.plannedOccasional,
        ),
        _transaction(
          description: 'Local Shop',
          amount: 20,
          expenseType: ExpenseType.unexpectedOccasional,
        ),
      ],
      now: now,
    );

    expect(result.spotsFor(SpendingSpotFilter.actual).single.total, 90);
    expect(result.spotsFor(SpendingSpotFilter.regular).single.total, 40);
    expect(result.spotsFor(SpendingSpotFilter.occasional).single.total, 50);
  });

  test('excludes internal transfers from favourite spending spots', () {
    final result = service.calculate(
      transactions: [
        _transaction(
          description: 'FID BKG SVC LLC DES:MONEYLINE',
          amount: 800,
          category: 'Transfers',
        ),
        _transaction(description: 'Local Cafe', amount: 40),
      ],
      now: now,
    );

    expect(result.actual, hasLength(1));
    expect(result.actual.single.name, 'Local Cafe');
    expect(result.actual.single.total, 40);
  });

  test(
    'nets explicitly identified refunds and reversals against a merchant',
    () {
      final result = service.calculate(
        transactions: [
          _transaction(description: 'Kedai Makan', amount: 100),
          _transaction(description: 'Refund from Kedai Makan', amount: 25),
          _transaction(description: 'Kedai Makan reversal 123456', amount: 5),
        ],
        now: now,
      );

      expect(result.actual, hasLength(1));
      expect(result.actual.single.total, 70);
      expect(result.actual.single.transactionCount, 3);
      expect(result.actual.single.transactions[1].netAmount, -25);
      expect(result.actual.single.transactions[2].netAmount, -5);
    },
  );

  test('leaves empty descriptions as separate unspecified spots', () {
    final result = service.calculate(
      transactions: [
        _transaction(description: '', amount: 20),
        _transaction(description: '   ', amount: 10),
      ],
      now: now,
    );

    expect(result.actual, hasLength(2));
    expect(
      result.actual.map((spot) => spot.name),
      everyElement('Unspecified spending spot'),
    );
  });

  test('ranks by net total and applies the top five limit at presentation', () {
    final transactions = [
      for (var index = 1; index <= 7; index++)
        _transaction(
          description: 'Merchant ${String.fromCharCode(64 + index)}',
          amount: index * 10,
        ),
    ];
    final result = service.calculate(transactions: transactions, now: now);

    expect(result.actual.map((spot) => spot.total), [
      70,
      60,
      50,
      40,
      30,
      20,
      10,
    ]);
  });

  test(
    'uses the first fully eligible month and excludes the current month',
    () {
      final result = service.calculate(
        transactions: [
          _transaction(
            description: 'Early incomplete month',
            amount: 1000,
            date: DateTime(2025, 7, 10),
          ),
          _transaction(
            description: 'Included',
            amount: 90,
            date: DateTime(2025, 10, 4),
          ),
          _transaction(
            description: 'Current month',
            amount: 500,
            date: DateTime(2025, 11, 2),
          ),
        ],
        now: now,
      );

      expect(result.periodStart, DateTime(2025, 8));
      expect(result.periodEnd, DateTime(2025, 11));
      expect(result.completedMonths, 3);
      expect(result.actual.single.name, 'Included');
      expect(result.actual.single.averageMonthly, 30);
    },
  );

  test('does not include a first month that starts after day one', () {
    final result = service.calculate(
      transactions: [
        _transaction(
          description: 'Mid-month start',
          amount: 80,
          date: DateTime(2025, 10, 2),
        ),
      ],
      now: now,
    );

    expect(result.completedMonths, 0);
    expect(result.actual, isEmpty);
  });

  test(
    'does not double-count duplicated IDs, sheet rows, or object instances',
    () {
      final identified = _transaction(
        description: 'Identified Shop',
        amount: 100,
        id: 'transaction-1',
      );
      final rowIdentified = _transaction(
        description: 'Sheet Row Shop',
        amount: 50,
        sheetRow: 8,
      );
      final sameObject = _transaction(description: 'Object Shop', amount: 25);
      final result = service.calculate(
        transactions: [
          identified,
          _transaction(
            description: 'Identified Shop',
            amount: 100,
            id: 'transaction-1',
          ),
          rowIdentified,
          _transaction(description: 'Sheet Row Shop', amount: 50, sheetRow: 8),
          sameObject,
          sameObject,
        ],
        now: now,
      );

      expect(result.actual.map((spot) => spot.total), [100, 50, 25]);
    },
  );

  test('retains the original source transactions for drill-down', () {
    final original = _transaction(
      description: 'Original Store #91 WEB ID: 12345',
      amount: 40,
      date: DateTime(2025, 5, 1),
      category: 'Housing / Bills',
      expenseType: ExpenseType.plannedOccasional,
      id: 'detail-transaction',
    );
    final result = service.calculate(transactions: [original], now: now);
    final detail = result.actual.single.transactions.single.transaction;

    expect(identical(detail, original), isTrue);
    expect(detail.description, 'Original Store #91 WEB ID: 12345');
    expect(detail.date, DateTime(2025, 5, 1));
    expect(detail.amount, 40);
    expect(detail.category, 'Housing / Bills');
    expect(detail.expenseType, ExpenseType.plannedOccasional);
  });
}
