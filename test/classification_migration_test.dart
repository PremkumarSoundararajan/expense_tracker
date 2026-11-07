import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_ledger/models/financial_baseline.dart';
import 'package:pocket_ledger/services/financial_baseline_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('legacy groups canonicalize and duplicate rows merge', () {
    expect(BaselineGroup.values, hasLength(2));
    expect(BaselineGroup.parse('Committed'), BaselineGroup.essential);
    expect(
      BaselineGroup.parse('Discretionary'),
      BaselineGroup.potentiallyFlexible,
    );
    final rows = FinancialBaselineMapping.migrateStoredRows([
      {'merchant': 'Rent', 'group': 'Committed'},
      {'merchant': 'Rent', 'group': 'Essential'},
      {'merchant': 'Cafe', 'group': 'Discretionary'},
      {'merchant': 'Other', 'group': 'Unclassified'},
    ]);
    expect(rows, hasLength(2));
    expect(rows.last.toJson()['group'], 'Potentially Flexible');
  });
  test(
    'draft base and unsaved assignments migrate without overwriting draft',
    () async {
      SharedPreferences.setMockInitialValues({
        'financial_baseline_draft_v1_test': '{"base":[{"merchant":"Cafe","group":"Committed"}],"draft":[{"merchant":"Cafe","group":"Discretionary"}]}',
      });
      final draft = await FinancialBaselineStore(accountKey: 'test')
          .loadDraft();
      expect(draft!.baseMappings.single.group, BaselineGroup.essential);
      expect(
        draft.draftMappings.single.group,
        BaselineGroup.potentiallyFlexible,
      );
    },
  );

  test(
    'separate offline classification saves preserve earlier pending changes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = FinancialBaselineStore(accountKey: 'test');
      await store.savePendingSync(
        const FinancialBaselineSyncBatch(
          upserts: [
            FinancialBaselineMapping(
              merchantFingerprint: 'Rent',
              group: BaselineGroup.essential,
            ),
          ],
          removals: [],
        ),
      );
      await store.savePendingSync(
        const FinancialBaselineSyncBatch(
          upserts: [
            FinancialBaselineMapping(
              merchantFingerprint: 'Cafe',
              group: BaselineGroup.potentiallyFlexible,
            ),
          ],
          removals: [],
        ),
      );
      expect((await store.loadPendingSync())!.upserts, hasLength(2));
      await store.savePendingSync(
        const FinancialBaselineSyncBatch(upserts: [], removals: ['Cafe']),
      );
      final pending = (await store.loadPendingSync())!;
      expect(pending.upserts.single.merchantFingerprint, 'Rent');
      expect(pending.removals, ['Cafe']);
    },
  );
}
