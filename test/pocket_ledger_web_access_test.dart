import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pocket_ledger/models/expense_category.dart';
import 'package:pocket_ledger/models/transaction.dart';
import 'package:pocket_ledger/services/merchant_classification_store.dart';
import 'package:pocket_ledger/services/pocket_ledger_web_access.dart';
import 'package:pocket_ledger/widgets/pocket_ledger_web_access.dart';
import 'package:pocket_ledger/widgets/merchant_baseline_panel.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  Widget screen(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
  testWidgets(
    'desktop suggestion leaves phone classification controls usable with a long queue',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MerchantClassificationStore('phone-queue');
      final rows = [
        for (var i = 0; i < 21; i++)
          Transaction(
            id: 'row$i',
            description: 'Market ${String.fromCharCode(65 + i)}',
            date: DateTime(2026, 10, 1),
            amount: 10,
            category: 'Food',
            categoryId: 'food',
            expenseType: ExpenseType.unknown,
          ),
      ];
      await tester.pumpWidget(
        screen(
          MerchantBaselinePanel(
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
            currencySymbol: r'$',
            historyComplete: true,
            showRemainingInitially: true,
            onSaved: (_) async => 'Saved',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Organizing many merchants?'), findsOneWidget);
      final list = find.byKey(const ValueKey('mobile-merchant-list'));
      final field = find
          .byWidgetPredicate(
            (w) =>
                w is DropdownButton<String> &&
                w.key.toString().contains('merchant-type-'),
          )
          .first;
      await tester.ensureVisible(list);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        field,
        100,
        scrollable: find
            .descendant(of: list, matching: find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
      expect(field.hitTestable(), findsOneWidget);
      final bounds = tester.getRect(field);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(320));
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regular').last);
      await tester.pumpAndSettle();
      expect(store.draft, isNotEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  test('desktop suggestion is native-mobile only and requires more than 20 merchants', () {
    for (final count in [0, 20, 21, 100])
      expect(
        shouldSuggestPocketLedgerDesktop(
          merchantsNeedingReview: count,
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        count > 20,
      );
    expect(
      shouldSuggestPocketLedgerDesktop(
        merchantsNeedingReview: 21,
        isWeb: false,
        platform: TargetPlatform.iOS,
      ),
      true,
    );
    expect(
      shouldSuggestPocketLedgerDesktop(
        merchantsNeedingReview: 100,
        isWeb: true,
        platform: TargetPlatform.android,
      ),
      false,
    );
    expect(
      shouldSuggestPocketLedgerDesktop(
        merchantsNeedingReview: 100,
        isWeb: true,
        platform: TargetPlatform.windows,
      ),
      false,
    );
    expect(
      shouldSuggestPocketLedgerDesktop(
        merchantsNeedingReview: 100,
        isWeb: false,
        platform: TargetPlatform.windows,
      ),
      false,
    );
  });
  testWidgets(
    'dismissal persists across group changes and local restarts, scoped to account',
    (tester) async {
      Widget suggestion(MerchantClassificationStore store, int count) => screen(
        MerchantDesktopSuggestion(store: store, merchantsNeedingReview: count),
      );
      final store = MerchantClassificationStore('one');
      await tester.pumpWidget(suggestion(store, 20));
      await tester.pumpAndSettle();
      expect(find.text('Organizing many merchants?'), findsNothing);
      await tester.pumpWidget(suggestion(store, 21));
      await tester.pumpAndSettle();
      expect(find.text('Organizing many merchants?'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('dismiss-desktop-suggestion')),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(suggestion(store, 40));
      await tester.pumpAndSettle();
      expect(find.text('Organizing many merchants?'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      final restarted = MerchantClassificationStore('one');
      await tester.pumpWidget(suggestion(restarted, 40));
      await tester.pumpAndSettle();
      expect(find.text('Organizing many merchants?'), findsNothing);
      expect(await restarted.desktopSuggestionDismissed(), true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        suggestion(MerchantClassificationStore('two'), 40),
      );
      await tester.pumpAndSettle();
      expect(find.text('Organizing many merchants?'), findsOneWidget);
    },
  );
  testWidgets(
    'both entry points request the configured production URL in the external browser',
    (tester) async {
      final calls = <({Uri uri, LaunchMode mode})>[];
      Future<bool> launch(Uri uri, LaunchMode mode) async {
        calls.add((uri: uri, mode: mode));
        return true;
      }

      final store = MerchantClassificationStore('links');
      await tester.pumpWidget(
        screen(
          MerchantDesktopSuggestion(
            store: store,
            merchantsNeedingReview: 21,
            launcher: launch,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Pocket Ledger Web'));
      await tester.pumpAndSettle();
      await store.dismissDesktopSuggestion();
      await tester.pumpWidget(
        screen(PocketLedgerWebSettingsTile(store: store, launcher: launch)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pocket Ledger Web'));
      await tester.pumpAndSettle();
      expect(calls.length, 2);
      for (final call in calls) {
        expect(call.uri.toString(), pocketLedgerWebUrl);
        expect(call.uri.toString(), 'https://pocket-ledger-cdn.pages.dev/');
        expect(call.mode, LaunchMode.externalApplication);
      }
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'unsaved draft offers stay or continue and never discards or synchronizes',
    (tester) async {
      final store = MerchantClassificationStore('draft');
      final draft = {
        'id': 'm:market',
        'kind': 'merchant',
        'name': 'Market',
        'aliases': ['Market'],
        'expenseType': 'Regular',
      };
      await store.saveDraft([draft]);
      store.pending.add('saved-pending');
      var launches = 0;
      await tester.pumpWidget(
        screen(
          PocketLedgerWebSettingsTile(
            store: store,
            launcher: (uri, mode) async {
              launches++;
              return true;
            },
          ),
        ),
      );
      await tester.tap(find.text('Pocket Ledger Web'));
      await tester.pumpAndSettle();
      expect(find.textContaining('waiting to sync.'), findsWidgets);
      expect(find.text('Open web app with unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Stay and save first'));
      await tester.pumpAndSettle();
      expect(launches, 0);
      await tester.tap(find.text('Pocket Ledger Web'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open web app'));
      await tester.pumpAndSettle();
      expect(launches, 1);
      expect(store.draft['m:market'], draft);
      expect(store.records, isEmpty);
      expect(store.pending, {'saved-pending'});
      final restarted = MerchantClassificationStore('draft');
      await restarted.load();
      expect(restarted.draft['m:market'], draft);
    },
  );
  testWidgets(
    'pending saved changes are explained without blocking browser access',
    (tester) async {
      final store = MerchantClassificationStore('pending');
      store.pending.add('pending');
      var opened = false;
      await tester.pumpWidget(
        screen(
          PocketLedgerWebSettingsTile(
            store: store,
            launcher: (uri, mode) async {
              opened = true;
              return true;
            },
          ),
        ),
      );
      expect(find.textContaining('waiting to sync'), findsOneWidget);
      await tester.tap(find.text('Pocket Ledger Web'));
      await tester.pumpAndSettle();
      expect(opened, true);
      expect(find.byType(AlertDialog), findsNothing);
      expect(store.pending, {'pending'});
    },
  );
  for (final throws in [false, true]) {
    testWidgets(
      'browser launch ${throws ? 'exception' : 'false result'} is handled gracefully',
      (tester) async {
        await tester.pumpWidget(
          screen(
            PocketLedgerWebSettingsTile(
              store: MerchantClassificationStore('failure'),
              launcher: (uri, mode) async {
                if (throws) throw StateError('No browser');
                return false;
              },
            ),
          ),
        );
        await tester.tap(find.text('Pocket Ledger Web'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Could not open the browser.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'NA merchants do not trigger the suggestion; genuine unfinished merchants do',
    (tester) async {
      final store = MerchantClassificationStore('counts');
      final naRows = [
        for (var i = 0; i < 25; i++)
          Transaction(
            id: 'na$i',
            description: 'Shop ${String.fromCharCode(65 + i)}',
            date: DateTime(2026, 10, 1),
            amount: 10,
            category: 'Food',
            categoryId: 'food',
            expenseType: ExpenseType.unknown,
          ),
      ];
      await store.save([
        for (final t in naRows)
          {
            'id': 'm:${t.id}',
            'kind': 'merchant',
            'name': t.description,
            'aliases': [t.description],
            'category': 'NA',
            'categoryId': 'na',
            'group': 'Unclassified',
            'expenseType': 'Unknown',
            'na': true,
          },
      ]);
      Widget panel(List<Transaction> rows) => screen(
        MerchantBaselinePanel(
          transactions: rows.toList(),
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
          onSaved: (_) async => 'Saved',
        ),
      );
      await tester.pumpWidget(panel(naRows));
      await tester.pumpAndSettle();
      expect(find.text('Organizing many merchants?'), findsNothing);
      final unfinished = [
        for (var i = 0; i < 21; i++)
          Transaction(
            id: 'review$i',
            description: 'Review ${String.fromCharCode(65 + i)}',
            date: DateTime(2026, 10, 1),
            amount: 10,
            category: 'Food',
            categoryId: 'food',
            expenseType: ExpenseType.unknown,
          ),
      ];
      await tester.pumpWidget(panel([...naRows, ...unfinished]));
      await tester.pumpAndSettle();
      expect(find.text('Organizing many merchants?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('baseline-classified')));
      await tester.pumpAndSettle();
      expect(find.text('Organizing many merchants?'), findsOneWidget);
      final t = unfinished.first;
      await store.save([
        {
          'id': 'm:review',
          'kind': 'merchant',
          'name': t.description,
          'aliases': [t.description],
          'category': 'Food',
          'categoryId': 'food',
          'group': 'Essential',
          'expenseType': 'Regular',
        },
      ]);
      await tester.pumpWidget(panel([...naRows, ...unfinished]));
      await tester.pumpAndSettle();
      expect(find.text('Organizing many merchants?'), findsNothing);
    },
  );
}
