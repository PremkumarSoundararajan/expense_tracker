import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/financial_baseline.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/widgets/financial_baseline_screen.dart';

void main() {
  testWidgets('organizer shows four groups and stages changes until Save', (
    tester,
  ) async {
    var writes = 0;
    List<FinancialBaselineMapping>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialBaselineScreen(
          transactions: [_transaction(DateTime(2025, 1), 60, 'LOCAL MARKET')],
          initialMappings: const [],
          currencySymbol: r'$',
          onMappingsSaved: (mappings) async {
            writes++;
            saved = mappings;
            return 'synced';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollTo(
      tester,
      find.byKey(const ValueKey('organize-your-spending')),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Organize Your Spending'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('unassigned-local market')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('save-baseline-changes')), findsOneWidget);
    expect(writes, 0);
    for (final group in BaselineGroup.values) {
      expect(
        find.byKey(ValueKey('baseline-group-${group.name}')),
        findsOneWidget,
      );
    }
  });

  testWidgets('autocomplete classifies merchant and Save commits once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var writes = 0;
    List<FinancialBaselineMapping>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialBaselineScreen(
          transactions: [
            _transaction(DateTime(2025, 1), 40, 'KROGER #8'),
            _transaction(DateTime(2025, 2), 25, 'KROGER #22'),
          ],
          initialMappings: const [],
          currencySymbol: r'$',
          onMappingsSaved: (mappings) async {
            writes++;
            saved = mappings;
            return 'synced';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollTo(
      tester,
      find.byKey(const ValueKey('group-search-essential')),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('group-search-essential')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('group-search-essential')),
      'Kro',
    );
    await tester.pumpAndSettle();
    final option = find.byKey(const ValueKey('autocomplete-option-kroger'));
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(writes, 0, reason: 'editing must only update the local draft');
    expect(find.byKey(const ValueKey('unassigned-kroger')), findsNothing);
    expect(
      find.byKey(const ValueKey('mapped-essential-kroger')),
      findsOneWidget,
    );
    expect(find.textContaining('Preview – Unsaved Changes'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('save-baseline-changes')));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(saved, const [
      FinancialBaselineMapping(
        merchantFingerprint: 'KROGER',
        group: BaselineGroup.essential,
      ),
    ]);
  });

  testWidgets('restores a draft and supports discard without a sheet write', (
    tester,
  ) async {
    var writes = 0;
    var cleared = false;
    const committed = FinancialBaselineMapping(
      merchantFingerprint: 'RENT',
      group: BaselineGroup.committed,
    );
    const moved = FinancialBaselineMapping(
      merchantFingerprint: 'RENT',
      group: BaselineGroup.essential,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialBaselineScreen(
          transactions: [_transaction(DateTime(2025, 1), 100, 'RENT')],
          initialMappings: const [committed],
          initialDraft: const FinancialBaselineDraft(
            baseMappings: [committed],
            draftMappings: [moved],
          ),
          currencySymbol: r'$',
          onMappingsSaved: (_) async {
            writes++;
            return null;
          },
          onDraftCleared: () async {
            cleared = true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollTo(
      tester,
      find.byKey(const ValueKey('organize-your-spending')),
    );
    expect(find.text('Restored unfinished changes'), findsOneWidget);
    expect(find.byKey(const ValueKey('mapped-essential-rent')), findsOneWidget);
    await tester.tap(find.text('Discard Changes'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(cleared, isTrue);
    expect(find.byKey(const ValueKey('mapped-committed-rent')), findsOneWidget);
  });

  testWidgets('shows at most 20 merchants and replenishes after assignment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const names = [
      'ALPHA',
      'BRAVO',
      'CHARLIE',
      'DELTA',
      'ECHO',
      'FOXTROT',
      'GOLF',
      'HOTEL',
      'INDIA',
      'JULIET',
      'KILO',
      'LIMA',
      'MIKE',
      'NOVEMBER',
      'OSCAR',
      'PAPA',
      'QUEBEC',
      'ROMEO',
      'SIERRA',
      'TANGO',
      'UNIFORM',
    ];
    final transactions = [
      for (var i = 0; i < names.length; i++)
        _transaction(
          DateTime(2025, 1),
          (100 - i).toDouble(),
          'MERCHANT ${names[i]} STORE',
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialBaselineScreen(
          transactions: transactions,
          initialMappings: const [],
          currencySymbol: r'$',
          onMappingsSaved: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollTo(
      tester,
      find.byKey(const ValueKey('unassigned-merchant-list')),
    );
    expect(
      find.byKey(const ValueKey('unassigned-merchant-list')),
      findsOneWidget,
    );
    final visible = find.descendant(
      of: find.byKey(const ValueKey('unassigned-merchant-list')),
      matching: find.byType(ListTile),
    );
    expect(visible.evaluate().length, 20);
    await tester.tap(find.byKey(const ValueKey('unassigned-merchant alpha')));
    await tester.pumpAndSettle();
    await _scrollTo(
      tester,
      find.byKey(const ValueKey('assign-to-group-essential')),
    );
    await tester.tap(find.byKey(const ValueKey('assign-to-group-essential')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('unassigned-merchant uniform')),
      findsOneWidget,
    );
  });

  testWidgets('keeps existing confirmed assignments and preview intact', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialBaselineScreen(
          transactions: [_transaction(DateTime(2025, 1), 50, 'RENT PAYMENT')],
          initialMappings: const [
            FinancialBaselineMapping(
              merchantFingerprint: 'RENT',
              group: BaselineGroup.essential,
            ),
          ],
          currencySymbol: r'$',
          onMappingsSaved: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Preview – Unsaved Changes'), findsNothing);
    expect(find.text('Understanding Your Spending'), findsOneWidget);
    expect(find.text('Expense type canvas'), findsNothing);
  });
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  final scrollable = find
      .descendant(
        of: find.byKey(const ValueKey('financial-baseline-screen-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  final state = tester.state<ScrollableState>(scrollable);
  for (var i = 0; target.evaluate().isEmpty && i < 60; i++) {
    state.position.jumpTo(
      (state.position.pixels + 250).clamp(0, state.position.maxScrollExtent),
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  final rect = tester.getRect(target);
  if (rect.top > 130) {
    final state = tester.state<ScrollableState>(scrollable);
    state.position.jumpTo(
      (state.position.pixels + rect.top - 110).clamp(
        0,
        state.position.maxScrollExtent,
      ),
    );
    await tester.pumpAndSettle();
  }
}

Transaction _transaction(DateTime date, double amount, String description) =>
    Transaction(
      date: date,
      amount: amount,
      category: 'Other',
      description: description,
    );
