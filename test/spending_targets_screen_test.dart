import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/models/spending_target.dart';
import 'package:pocket_ledger/models/financial_baseline.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/services/spending_target_store.dart';
import 'package:pocket_ledger/widgets/spending_reduction_planner_screen.dart';
import 'package:pocket_ledger/widgets/spending_targets_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'what-if does not persist; activation needs review and explicit confirmation',
    (tester) async {
      final store = SpendingTargetStore(accountKey: 'test');
      var writes = 0;
      final now = DateTime.now();
      final ledger = [
        Transaction(
          id: 'one',
          date: DateTime(now.year, now.month, 1),
          amount: 200,
          category: 'Dining',
          categoryId: 'dining',
          description: 'Cafe',
        ),
      ];
      const mappings = [
        FinancialBaselineMapping(
          merchantFingerprint: 'Cafe',
          group: BaselineGroup.potentiallyFlexible,
        ),
      ];
      const categories = [
        ExpenseCategory(
          id: 'dining',
          parentId: 'food-household',
          name: 'Dining',
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: SpendingReductionPlannerScreen(
            transactions: ledger,
            lifestyleMappings: mappings,
            categories: categories,
            currencySymbol: r'$',
            targetStore: store,
            onTargetsSaved: () async {
              writes++;
              return 'Synced';
            },
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('target-selector-category:dining')),
      );
      await tester.pumpAndSettle();
      expect(store.targets, isEmpty);
      expect(writes, 0);
      await tester.tap(find.text('Activate Spending Targets'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm activation'), findsOneWidget);
      expect(store.targets, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.targets, isEmpty);
      await tester.tap(find.text('Activate Spending Targets'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm activation'));
      await tester.pumpAndSettle();
      expect(store.targets.single.monthlyAmount, 150);
      expect(
        store.targets.single.effectiveDate,
        DateTime(now.year, now.month + 1),
      );
      expect(writes, 1);
      await tester.tap(find.byTooltip('Spending Targets'));
      await tester.pumpAndSettle();
      expect(find.byType(SpendingTargetsScreen), findsOneWidget);
      expect(find.textContaining('starts'), findsOneWidget);
    },
  );

  testWidgets(
    'current usage, dated edit and deactivation preserve earlier definitions',
    (tester) async {
      final store = SpendingTargetStore(accountKey: 'test');
      final now = DateTime.now();
      final original = SpendingTarget.activate(
        type: SpendingTargetType.merchant,
        scopeId: 'cafe',
        name: 'Cafe',
        average: 200,
        percentage: 50,
        effectiveDate: DateTime(now.year, now.month),
        now: now,
      );
      await store.save([original]);
      await tester.pumpWidget(
        MaterialApp(
          home: SpendingTargetsScreen(
            store: store,
            transactions: [
              Transaction(
                id: 'one',
                date: now,
                amount: 135,
                category: 'Dining',
                description: 'Cafe',
              ),
            ],
            mappings: const [
              FinancialBaselineMapping(
                merchantFingerprint: 'Cafe',
                group: BaselineGroup.potentiallyFlexible,
              ),
            ],
            categories: const [],
            currencySymbol: r'$',
          ),
        ),
      );
      expect(find.textContaining('Over target'), findsOneWidget);
      expect(find.textContaining(RegExp(r'35.*over target')), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '80');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.targets, hasLength(2));
      expect(store.targets.first.monthlyAmount, 100);
      expect(store.targets.last.monthlyAmount, 80);
      expect(
        store.targets.last.effectiveDate,
        DateTime(now.year, now.month + 1),
      );
      await tester.tap(find.text('Deactivate').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deactivate').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('No active spending targets'), findsOneWidget);
    },
  );
}
