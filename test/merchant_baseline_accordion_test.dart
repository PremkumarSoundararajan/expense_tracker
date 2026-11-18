import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/app_theme.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/merchant_classification_store.dart';
import 'package:pocket_ledger/widgets/merchant_baseline_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final width in [320.0, 1280.0]) {
    testWidgets('baseline sections show spending and guard edits at $width', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MerchantClassificationStore('accordion-$width');
      await store.save([
        {
          'id': 'm:alpha',
          'kind': 'merchant',
          'name': 'Alpha',
          'aliases': ['Alpha'],
          'category': 'Food',
          'categoryId': 'food',
          'group': 'Essential',
          'expenseType': 'Regular',
        },
        {
          'id': 'm:excluded',
          'kind': 'merchant',
          'name': 'Excluded',
          'aliases': ['Excluded'],
          'na': true,
        },
      ]);
      var failSave = false;
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: width == 320 ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MerchantBaselinePanel(
                transactions: [
                  for (final (id, name, amount) in [
                    ('a', 'Alpha', 60.0),
                    ('b', 'Beta', 30.0),
                    ('c', 'Excluded', 10.0),
                  ])
                    Transaction(
                      id: id,
                      description: name,
                      amount: amount,
                      date: DateTime(2025, 1, 1),
                      category: 'Unknown',
                    ),
                ],
                categories: const [
                  ExpenseCategory(
                    id: 'food',
                    parentId: 'food-household',
                    name: 'Food',
                  ),
                ],
                legacyMappings: const [],
                store: store,
                currencySymbol: r'$',
                historyComplete: true,
                onSaved: (changes) async {
                  saves++;
                  if (failSave) throw StateError('offline');
                  await store.save(changes);
                  return 'Saved';
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('60.0%'), findsOneWidget);
      expect(find.textContaining(r'1 merchant · $60'), findsOneWidget);
      expect(find.textContaining(r'1 merchant · $30'), findsOneWidget);
      expect(find.textContaining(r'1 merchant · $10'), findsOneWidget);
      expect(find.byTooltip('Classified: 60.0%'), findsNWidgets(2));
      expect(find.byTooltip('Unclassified: 30.0%'), findsNWidgets(2));
      expect(find.byTooltip('Excluded: 10.0%'), findsNWidgets(2));
      final bar = tester
          .getSize(find.byKey(const ValueKey('baseline-spending-bar')))
          .width;
      expect(
        tester
            .getSize(find.byKey(const ValueKey('baseline-bar-classified')))
            .width,
        closeTo(bar * .6, .01),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('baseline-bar-remaining')))
            .width,
        closeTo(bar * .3, .01),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('baseline-bar-na'))).width,
        closeTo(bar * .1, .01),
      );
      await tester.tap(find.byTooltip('How coverage is calculated'));
      await tester.pumpAndSettle();
      final rows = [
        ('classified', r'60.0% · $60'),
        ('remaining', r'30.0% · $30'),
        ('na', r'10.0% · $10'),
      ];
      for (final (key, value) in rows) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('baseline-coverage-$key')),
            matching: find.text(value),
          ),
          findsOneWidget,
        );
      }
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('baseline-coverage-classified')),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('baseline-coverage-remaining')),
              )
              .dy,
        ),
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('baseline-coverage-remaining')),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('baseline-coverage-na')))
              .dy,
        ),
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      Future<void> tapKey(String key) async {
        final target = find.byKey(ValueKey(key));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tapKey('baseline-classified');
      expect(find.text('Alpha · 1'), findsOneWidget);
      await tapKey('merchant-group-alpha');
      await tester.tap(find.text('Potentially Flexible').last);
      await tester.pumpAndSettle();
      await tapKey('merchant-expand-alpha');
      await tapKey('transaction-type-a');
      await tester.tap(find.text('Planned Occasional').last);
      await tester.pumpAndSettle();

      await tapKey('baseline-unclassified');
      expect(find.textContaining('1 merchant has changes'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha · 1'), findsOneWidget);
      failSave = true;
      await tapKey('baseline-unclassified');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not save:'), findsWidgets);
      expect(find.text('Alpha · 1'), findsOneWidget);
      expect(store.draft, isNotEmpty);
      failSave = false;
      await tapKey('baseline-unclassified');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.records['m:alpha']?['group'], 'Potentially Flexible');
      expect(store.records['t:a']?['expenseType'], 'Planned Occasional');
      expect(store.draft, isEmpty);
      expect(saves, 2);
      expect(find.text('Beta · 1'), findsOneWidget);

      await tapKey('merchant-category-beta');
      await tester.tap(find.text('Food').last);
      await tester.pumpAndSettle();
      await tapKey('baseline-unclassified');
      expect(find.textContaining('1 merchant has changes'), findsOneWidget);
      await tester.tap(find.text('Ignore'));
      await tester.pumpAndSettle();
      expect(find.text('Beta · 1'), findsNothing);
      expect(store.draft, isEmpty);
      await tapKey('baseline-unclassified');
      await tapKey('merchant-category-beta');
      await tester.tap(find.text('Food').last);
      await tester.pumpAndSettle();
      await tapKey('review-na');
      expect(find.textContaining('1 merchant has changes'), findsOneWidget);
      await tester.tap(find.text('Ignore'));
      await tester.pumpAndSettle();
      expect(find.text('Excluded · 1'), findsOneWidget);
      expect(store.records['m:beta'], isNull);
      await tapKey('baseline-unclassified');
      await tapKey('merchant-category-beta');
      await tester.tap(find.text('Food').last);
      await tester.pumpAndSettle();
      await tapKey('baseline-unclassified');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.records['m:beta']?['categoryId'], 'food');
      expect(find.text('Beta · 1'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty baseline shows zero percentages', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: Scaffold(
          body: MerchantBaselinePanel(
            transactions: const [],
            categories: const [],
            legacyMappings: const [],
            store: MerchantClassificationStore('empty-accordion'),
            currencySymbol: r'$',
            historyComplete: true,
            onSaved: (_) async => 'Saved',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0.0%'), findsOneWidget);
    for (final section in ['Classified', 'Unclassified', 'Excluded']) {
      expect(find.byTooltip('$section: 0.0%'), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('baseline-bar-classified')), findsNothing);
    await tester.tap(find.byTooltip('How coverage is calculated'));
    await tester.pumpAndSettle();
    for (final key in ['classified', 'remaining', 'na']) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('baseline-coverage-$key')),
          matching: find.text(r'0.0% · $0'),
        ),
        findsOneWidget,
      );
    }
    final usage = find.text('Expense Type → budgets');
    await tester.ensureVisible(usage);
    await tester.pumpAndSettle();
    expect(usage.hitTestable(), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
