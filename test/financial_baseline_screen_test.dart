import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/financial_baseline.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/widgets/financial_baseline_screen.dart';

void main() {
  testWidgets('organizer is primary and removes long analysis sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialBaselineScreen(
          transactions: [_transaction(DateTime(2025, 1), 60, 'LOCAL MARKET')],
          initialMappings: const [],
          currencySymbol: r'$',
          onMappingsSaved: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollTo(
      tester,
      find.byKey(const ValueKey('classification-progress')),
    );
    expect(
      find.byKey(const ValueKey('classification-progress')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('view-baseline-insights')),
      findsOneWidget,
    );
    await _scrollTo(
      tester,
      find.byKey(const ValueKey('organize-your-spending')),
    );
    expect(find.text('Organize Your Spending'), findsOneWidget);
    expect(find.text('Understanding Your Spending'), findsNothing);
    expect(find.text('Where You Can Make Changes'), findsNothing);
    expect(find.text('Your Spending Insights'), findsNothing);
    for (final group in BaselineGroup.values) {
      expect(
        find.byKey(ValueKey('baseline-group-${group.name}')),
        findsOneWidget,
      );
    }
  });

  testWidgets(
    'autocomplete clears and retains focus for consecutive assignments',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var sheetWrites = 0;
      final drafts = <FinancialBaselineDraft>[];
      List<FinancialBaselineMapping>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: FinancialBaselineScreen(
            transactions: [
              _transaction(DateTime(2025, 1), 40, 'KROGER #8'),
              _transaction(DateTime(2025, 2), 25, 'KROGER #22'),
              _transaction(DateTime(2025, 3), 55, 'COSTCO #11'),
            ],
            initialMappings: const [],
            currencySymbol: r'$',
            onDraftChanged: (draft) async {
              drafts.add(draft);
            },
            onMappingsSaved: (mappings) async {
              sheetWrites++;
              saved = mappings;
              return 'Synced';
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('group-search-essential'));
      await _scrollTo(tester, input);
      for (final (query, key) in [('Kro', 'kroger'), ('Cost', 'costco')]) {
        await tester.enterText(input, query);
        await tester.pumpAndSettle();
        final option = find.byKey(ValueKey('autocomplete-option-$key'));
        await tester.tap(option);
        await tester.pumpAndSettle();
        final field = tester.widget<TextField>(input);
        expect(field.controller!.text, isEmpty);
        expect(field.focusNode!.hasFocus, isTrue);
        expect(find.byKey(ValueKey('mapped-essential-$key')), findsNothing);
        expect(find.byKey(ValueKey('unassigned-$key')), findsNothing);
        expect(sheetWrites, 0);
      }
      expect(drafts, hasLength(2));
      await tester.tap(find.byKey(const ValueKey('save-baseline-changes')));
      await tester.pumpAndSettle();
      expect(sheetWrites, 1);
      expect(saved, hasLength(2));
      expect(
        find.byKey(const ValueKey('baseline-save-status')),
        findsOneWidget,
      );
    },
  );

  testWidgets('group panels stay compact with fifty assigned merchants', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String letters(int value) {
      final first = String.fromCharCode(65 + value ~/ 26);
      final second = String.fromCharCode(65 + value % 26);
      return '$first$second';
    }

    final mappings = [
      for (var index = 0; index < 50; index++)
        FinancialBaselineMapping(
          merchantFingerprint: 'MERCHANT ${letters(index)} GROUP',
          group: BaselineGroup.essential,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialBaselineScreen(
          transactions: const [],
          initialMappings: mappings,
          currencySymbol: r'$',
          onMappingsSaved: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final essential = find.byKey(const ValueKey('baseline-group-essential'));
    expect(tester.getSize(essential).height, lessThan(100));
    expect(find.text('50 assigned'), findsOneWidget);
    expect(
      find.descendant(of: essential, matching: find.byType(InputChip)),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('organized-merchant-list')), findsNothing);
    expect(find.text('Organized Merchants (50)'), findsOneWidget);
  });

  testWidgets('organized merchants is collapsed and supports move and remove', (
    tester,
  ) async {
    const mapping = FinancialBaselineMapping(
      merchantFingerprint: 'NETFLIX',
      group: BaselineGroup.discretionary,
    );
    var writes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialBaselineScreen(
          transactions: [
            _transaction(DateTime(2025, 1), 15, 'NETFLIX MONTHLY'),
          ],
          initialMappings: const [mapping],
          currencySymbol: r'$',
          onMappingsSaved: (_) async {
            writes++;
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('organized-netflix')), findsNothing);
    final groupCard = find.byKey(
      const ValueKey('baseline-group-discretionary'),
    );
    final before = tester.getSize(groupCard).height;
    await _scrollTo(
      tester,
      find.byKey(const ValueKey('organized-merchants-title')),
    );
    await tester.tap(find.byKey(const ValueKey('organized-merchants-title')));
    await tester.pumpAndSettle();
    final merchant = find.byKey(
      const ValueKey('organized-discretionary-netflix'),
    );
    expect(merchant, findsOneWidget);
    final assignedSearch = find.byKey(
      const ValueKey('organized-merchant-search'),
    );
    await tester.enterText(assignedSearch, 'netflix');
    await tester.pumpAndSettle();
    expect(merchant, findsOneWidget);
    await tester.enterText(assignedSearch, 'missing');
    await tester.pumpAndSettle();
    expect(merchant, findsNothing);
    await tester.enterText(assignedSearch, 'netflix');
    await tester.pumpAndSettle();
    await tester.ensureVisible(merchant);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('organized-actions-netflix')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Essential'));
    await tester.pumpAndSettle();
    final moved = find.byKey(const ValueKey('organized-essential-netflix'));
    expect(moved, findsOneWidget);
    await tester.ensureVisible(moved);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('organized-actions-netflix')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove assignment'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('organized-essential-netflix')),
      findsNothing,
    );
    await _scrollTo(
      tester,
      find.byKey(const ValueKey('unassigned-netflix monthly')),
    );
    expect(
      find.byKey(const ValueKey('unassigned-netflix monthly')),
      findsOneWidget,
    );
    expect(writes, 0);
    expect(tester.getSize(groupCard).height, before);
  });

  testWidgets(
    'unassigned list searches all merchants and replenishes its 20 rows',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
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
        find.byKey(const ValueKey('unassigned-merchants-panel')),
      );
      final list = find.byKey(const ValueKey('unassigned-merchant-list'));
      expect(find.text('21 left · 20 shown'), findsOneWidget);
      expect(
        find
            .descendant(
              of: list,
              matching: find.byKey(
                const ValueKey('assign-merchant-merchant alpha'),
              ),
            )
            .evaluate(),
        hasLength(1),
      );
      expect(
        find.byKey(const ValueKey('assign-merchant-merchant uniform')),
        findsNothing,
      );

      final search = find.byKey(const ValueKey('unassigned-merchant-search'));
      await tester.enterText(search, 'uniform');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('assign-merchant-merchant uniform')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('clear-unassigned-search')));
      await tester.pumpAndSettle();
      final alphaAssign = find.byKey(
        const ValueKey('assign-merchant-merchant alpha'),
      );
      await tester.tap(alphaAssign);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('assign-to-group-essential')));
      await tester.pumpAndSettle();
      expect(find.text('20 left · 20 shown'), findsOneWidget);
      await tester.enterText(search, 'uniform');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('assign-merchant-merchant uniform')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'uses stacked layout on narrow screens and columns on wide screens',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FinancialBaselineScreen(
            transactions: [_transaction(DateTime(2025, 1), 25, 'COFFEE')],
            initialMappings: const [],
            currencySymbol: r'$',
            onMappingsSaved: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _scrollTo(
        tester,
        find.byKey(const ValueKey('baseline-narrow-layout')),
      );
      expect(
        find.byKey(const ValueKey('baseline-narrow-layout')),
        findsOneWidget,
      );
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      await _scrollTo(
        tester,
        find.byKey(const ValueKey('baseline-wide-layout')),
      );
      expect(
        find.byKey(const ValueKey('baseline-wide-layout')),
        findsOneWidget,
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );

  testWidgets(
    'insights explain classification completeness at each threshold',
    (tester) async {
      for (final percentage in [0, 49, 50, 79, 80, 100]) {
        final transactions = <Transaction>[];
        final mappings = <FinancialBaselineMapping>[];
        if (percentage > 0) {
          transactions.add(
            _transaction(
              DateTime(2025, 1),
              percentage.toDouble(),
              'KNOWN MERCHANT',
            ),
          );
          mappings.add(
            const FinancialBaselineMapping(
              merchantFingerprint: 'KNOWN MERCHANT',
              group: BaselineGroup.essential,
            ),
          );
        }
        if (percentage < 100) {
          transactions.add(
            _transaction(
              DateTime(2025, 1),
              (100 - percentage).toDouble(),
              'OTHER VENDOR',
            ),
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            home: FinancialBaselineScreen(
              key: ValueKey('insight-screen-$percentage'),
              transactions: transactions,
              initialMappings: mappings,
              currencySymbol: r'$',
              onMappingsSaved: (_) async => null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('view-baseline-insights')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('insights-classification-status')),
          findsOneWidget,
        );
        final status = tester
            .widget<Text>(
              find.byKey(const ValueKey('insights-classification-status')),
            )
            .data!;
        expect(status, startsWith('$percentage% classified'));
        if (percentage < 50) {
          expect(
            find.byKey(const ValueKey('insights-insufficient-data')),
            findsOneWidget,
          );
          expect(find.text('Identified Baseline'), findsNothing);
        } else {
          expect(
            find.byKey(const ValueKey('insights-insufficient-data')),
            findsNothing,
          );
          expect(find.text('Identified Baseline'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('insights-incomplete-warning')),
            percentage < 80 ? findsOneWidget : findsNothing,
          );
        }
        await tester.tap(find.byTooltip('Close insights'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('restores draft and supports discard without a Sheets write', (
    tester,
  ) async {
    var writes = 0;
    var cleared = false;
    const committed = FinancialBaselineMapping(
      merchantFingerprint: 'RENT',
      group: BaselineGroup.committed,
    );
    const draft = FinancialBaselineMapping(
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
            draftMappings: [draft],
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
    expect(
      find.byKey(const ValueKey('organized-essential-rent')),
      findsNothing,
    );
    await tester.tap(find.text('Discard Changes'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(cleared, isTrue);
  });

  testWidgets('save reminder appears once at twenty changed assignments', (
    tester,
  ) async {
    const vendorNames = [
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
      for (var index = 0; index < vendorNames.length; index++)
        _transaction(
          DateTime(2025, 1),
          index + 1,
          'VENDOR ${vendorNames[index]} STORE',
        ),
    ];
    final starterMappings = [
      for (var index = 0; index < 19; index++)
        FinancialBaselineMapping(
          merchantFingerprint: 'VENDOR ${vendorNames[index]} STORE',
          group: BaselineGroup.essential,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: FinancialBaselineScreen(
          transactions: transactions,
          initialMappings: const [],
          initialDraft: FinancialBaselineDraft(
            baseMappings: const [],
            draftMappings: starterMappings,
          ),
          currencySymbol: r'$',
          onMappingsSaved: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('unassigned-merchants-panel'));
    await _scrollTo(tester, panel);
    await tester.tap(
      find.descendant(of: panel, matching: find.byType(TextButton)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('assign-to-group-essential')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('baseline-save-reminder')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('baseline-reminder-continue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('baseline-save-reminder')), findsNothing);
    expect(find.text('Preview – Unsaved Changes (20)'), findsOneWidget);
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
      (state.position.pixels + 260).clamp(0, state.position.maxScrollExtent),
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Transaction _transaction(DateTime date, double amount, String description) =>
    Transaction(
      date: date,
      amount: amount,
      category: 'Other',
      description: description,
    );
