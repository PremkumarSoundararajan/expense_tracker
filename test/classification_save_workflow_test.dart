import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/merchant_classification_store.dart';
import 'package:pocket_ledger/widgets/merchant_baseline_panel.dart';

void main() {
  for (final fails in [false, true]) {
    testWidgets(
      'unfinished merchant stays until save ${fails ? 'fails and retries' : 'succeeds'}',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = MerchantClassificationStore('save-workflow');
        var completion = Completer<String>();
        final rows = [
          Transaction(
            id: 'alpha',
            date: DateTime(2026, 10, 1),
            amount: 100,
            description: 'Alpha',
            category: 'Unknown',
            expenseType: ExpenseType.unknown,
          ),
        ];
        Widget screen() => MaterialApp(
          home: Scaffold(
            body: MerchantBaselinePanel(
              showRemainingInitially: true,
              transactions: rows,
              categories: const [
                ExpenseCategory(
                  id: 'food',
                  parentId: 'food-household',
                  name: 'Food',
                ),
              ],
              legacyMappings: const [],
              store: store,
              historyComplete: true,
              currencySymbol: r'$',
              onSaved: (changes) async {
                final result = await completion.future;
                await store.save(changes);
                return result;
              },
            ),
          ),
        );
        await tester.pumpWidget(screen());
        await tester.pumpAndSettle();
        Future<void> choose(String field, String value) async {
          final dropdown = find.byWidgetPredicate(
            (w) =>
                w is DropdownButton<String> &&
                w.key.toString().contains('merchant-$field-'),
          );
          await tester.tap(dropdown);
          await tester.pumpAndSettle();
          await tester.tap(find.text(value).last);
          await tester.pumpAndSettle();
        }

        await choose('category', 'Food');
        await choose('group', 'Essential');
        await choose('type', 'Regular');
        expect(find.text('Alpha · 1'), findsOneWidget);
        expect(find.text('Ready to save'), findsOneWidget);
        expect(
          find.text('0.0% classified · 100.0% unclassified'),
          findsOneWidget,
        );
        expect(find.textContaining('Top 80% done'), findsNothing);
        // Restoring the unsaved draft must also retain its original work-list membership.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(screen());
        await tester.pumpAndSettle();
        expect(find.text('Alpha · 1'), findsOneWidget);
        expect(find.text('Ready to save'), findsOneWidget);
        await tester.tap(find.text('Save changes'));
        await tester.pump();
        expect(find.text('Alpha · 1'), findsOneWidget);
        if (fails) {
          completion.completeError(StateError('Save failed'));
          await tester.pumpAndSettle();
          expect(find.textContaining('Could not save:'), findsOneWidget);
          expect(find.text('Alpha · 1'), findsOneWidget);
          expect(find.text('Ready to save'), findsOneWidget);
          expect(store.records, isEmpty);
          completion = Completer<String>();
          await tester.tap(find.text('Save changes'));
          await tester.pump();
        }
        completion.complete('Saved');
        await tester.pumpAndSettle();
        expect(find.text('Alpha · 1'), findsNothing);
        expect(
          find.text('100.0% classified · 0.0% unclassified'),
          findsOneWidget,
        );
        expect(store.index.apply(rows.single).expenseType, ExpenseType.regular);
        await tester.tap(find.byKey(const ValueKey('baseline-classified')));
        await tester.pumpAndSettle();
        expect(find.text('Alpha · 1'), findsOneWidget);
        expect(find.text('Ready to save'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
