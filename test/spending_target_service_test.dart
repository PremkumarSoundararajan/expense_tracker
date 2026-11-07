import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/spending_target.dart';
import 'package:pocket_ledger/models/financial_baseline.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/spending_target_service.dart';

final now = DateTime(2026, 11, 20);
final mappings = [
  const FinancialBaselineMapping(
    merchantFingerprint: 'Cafe',
    group: BaselineGroup.potentiallyFlexible,
  ),
];
const categories = [
  ExpenseCategory(id: 'dining', parentId: 'food-household', name: 'Dining'),
];
SpendingTarget cap(String id, {double amount = 100, DateTime? start}) =>
    SpendingTarget.activate(
      type: id == 'cafe'
          ? SpendingTargetType.merchant
          : SpendingTargetType.category,
      scopeId: id,
      name: id,
      average: amount,
      percentage: 0,
      effectiveDate: start ?? DateTime(2026, 11),
      now: now,
    );
Transaction expense(
  double amount, {
  String id = 'new',
  int month = 11,
  String merchant = 'Cafe',
  String? categoryId = 'dining',
}) => Transaction(
  id: id,
  date: DateTime(2026, month, 5),
  amount: amount,
  category: 'Dining',
  categoryId: categoryId,
  description: merchant,
);
void main() {
  final s = SpendingTargetService();
  List<TargetAwareness> preview(
    List<Transaction> ledger,
    Transaction proposed, {
    List<SpendingTarget>? targets,
  }) => s.preview(
    proposed: proposed,
    targets: targets ?? [cap('cafe')],
    transactions: ledger,
    mappings: mappings,
    categories: categories,
    now: now,
  );
  test(
    'merchant first, category and parent independently monitor same expense',
    () {
      final a = preview(
        [],
        expense(85),
        targets: [
          cap('food-household', amount: 300),
          cap('dining'),
          cap('cafe'),
        ],
      );
      expect(a, hasLength(3));
      expect(a.first.after.target.type, SpendingTargetType.merchant);
      expect(a.map((a) => a.after.actual), everyElement(85));
      expect(a.first.crossed80, isTrue);
      expect(a.first.crossed100, isFalse);
    },
  );
  test('80 and 100 thresholds and repeated prominent warning suppression', () {
    expect(preview([], expense(79)).single.prominent, isFalse);
    expect(
      preview([expense(70, id: 'old')], expense(10)).single.crossed80,
      isTrue,
    );
    final reached = preview([expense(85, id: 'old')], expense(15)).single;
    expect(reached.crossed100, isTrue);
    expect(reached.after.status, TargetStatus.reached);
    final over = preview([expense(100, id: 'old')], expense(15)).single;
    expect(over.prominent, isFalse);
    expect(over.after.remaining, -15);
    expect(over.after.status, TargetStatus.over);
    expect(over.after.progress, 1.15);
  });
  test('zero target safely reports any positive expense as over', () {
    final a = preview([], expense(1), targets: [cap('cafe', amount: 0)]).single;
    expect(a.crossed100, isTrue);
    expect(a.after.status, TargetStatus.over);
    expect(a.after.progress.isFinite, isTrue);
    final zero = s
        .usage(
          targets: [cap('cafe', amount: 0)],
          transactions: [],
          mappings: mappings,
          categories: categories,
          asOf: now,
        )
        .single;
    expect(zero.progress, 0);
    expect(zero.status, TargetStatus.within);
  });
  test('edit replaces proposed ID and delete/reclassification recalculate', () {
    final a = preview([expense(85)], expense(90)).single;
    expect(a.after.actual, 90);
    expect(a.prominent, isFalse);
    final usage = s.usage(
      targets: [cap('cafe')],
      transactions: [],
      mappings: mappings,
      categories: categories,
      asOf: now,
    );
    expect(usage.single.actual, 0);
    final essential = s
        .usage(
          targets: [cap('cafe')],
          transactions: [expense(90)],
          mappings: [
            const FinancialBaselineMapping(
              merchantFingerprint: 'Cafe',
              group: BaselineGroup.essential,
            ),
          ],
          categories: categories,
          asOf: now,
        )
        .single;
    expect(essential.actual, 0);
    expect(essential.needsReview, isTrue);
    expect(preview([], expense(90, merchant: 'Other')), isEmpty);
  });
  test('excluded transfers refunds payments reversals and nonpositive do not alert', () {
    for (final name in [
      'Cafe refund',
      'Cafe transfer',
      'Cafe credit card payment',
      'Cafe reversal',
    ]) {
      expect(preview([], expense(100, merchant: name)), isEmpty);
    }
    expect(preview([], expense(-1)), isEmpty);
    expect(preview([], expense(double.nan)), isEmpty);
  });
  test('immediate start includes earlier current-month spending and backdated entry', () {
    final t = cap('cafe', start: DateTime(2026, 11, 15));
    expect(
      preview(
        [expense(70, id: 'old')],
        expense(20),
        targets: [t],
      ).single.after.actual,
      90,
    );
    expect(preview([], expense(20, month: 10), targets: [t]), isEmpty);
    expect(
      preview(
        [],
        expense(20),
        targets: [cap('cafe', start: DateTime(2026, 12))],
      ),
      isEmpty,
    );
  });
  test(
    'deleted category needs review and explicit IDs never redirect by name',
    () {
      final u = s
          .usage(
            targets: [cap('deleted')],
            transactions: [expense(20, categoryId: 'deleted')],
            mappings: mappings,
            categories: categories,
            asOf: now,
          )
          .single;
      expect(u.needsReview, isTrue);
      expect(u.actual, 0);
      expect(
        preview(
          [],
          expense(20, categoryId: 'deleted'),
          targets: [cap('dining')],
        ),
        isEmpty,
      );
    },
  );
  test('import summary uses committed changes, correct months and suppresses duplicates', () {
    final old = expense(85, id: 'old');
    final added = expense(30);
    List<TargetAwareness> changes(
      List<Transaction> before,
      List<Transaction> after,
    ) => s.importChanges(
      targets: [cap('cafe', start: DateTime(2026, 10))],
      before: before,
      after: after,
      mappings: mappings,
      categories: categories,
      now: now,
    );
    expect(changes([old], [old]), isEmpty);
    final update = changes([old], [old, added]).single;
    expect(update.crossed100, isTrue);
    expect(update.after.actual, 115);
    final alreadyOver = changes(
      [old, added],
      [old, added, expense(10, id: 'extra')],
    ).single;
    expect(alreadyOver.crossed100, isFalse);
    final months = changes([], [
      expense(90, month: 10, id: 'oct'),
      expense(20),
    ]);
    expect(months, hasLength(2));
    expect(months.first.after.month, DateTime(2026, 10));
    expect(months.last.after.actual, 20);
    expect(changes([], [expense(100, merchant: 'Cafe refund')]), isEmpty);
  });
}
