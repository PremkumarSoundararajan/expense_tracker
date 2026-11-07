import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_ledger/models/spending_target.dart';
import 'package:pocket_ledger/services/spending_target_store.dart';
import 'package:pocket_ledger/services/spending_target_service.dart';

SpendingTarget target({
  String scope = 'cafe',
  double percentage = 40,
  DateTime? date,
}) => SpendingTarget.activate(
  type: SpendingTargetType.merchant,
  scopeId: scope,
  name: 'Cafe',
  average: 200,
  percentage: percentage,
  effectiveDate: date ?? DateTime(2026, 12),
  now: DateTime(2026, 11, 6),
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'activation calculation, deterministic IDs, revision history and zero',
    () {
      final t = target();
      expect(t.monthlyAmount, 120);
      expect(target().id, t.id);
      expect(target(percentage: 100).monthlyAmount, 0);
      final revised = t.revise(effectiveDate: DateTime(2027, 1), amount: 90);
      expect(revised.scopeId, t.scopeId);
      final increased = t.revise(effectiveDate: DateTime(2027, 1), amount: 250);
      expect(
        increased
            .revise(effectiveDate: DateTime(2027, 2), active: false)
            .active,
        isFalse,
      );
      expect(revised.id, isNot(t.id));
      final s = SpendingTargetService();
      expect(
        s.effective([t, revised], DateTime(2026, 12, 15)).single.monthlyAmount,
        120,
      );
      expect(
        s.effective([t, revised], DateTime(2027, 1, 1)).single.monthlyAmount,
        90,
      );
      final inactive = revised.revise(
        effectiveDate: DateTime(2027, 2),
        active: false,
      );
      expect(s.effective([t, revised, inactive], DateTime(2027, 2)), isEmpty);
      expect(SpendingTarget.fromJson(t.toJson()).toJson(), t.toJson());
    },
  );
  test(
    'account isolation, offline outbox, retry and no duplicate IDs',
    () async {
      final store = SpendingTargetStore(accountKey: 'A');
      await store.save([target(), target()]);
      expect(store.targets, hasLength(1));
      expect(store.hasPending, isTrue);
      final restored = SpendingTargetStore(accountKey: 'a');
      await restored.load();
      expect(restored.targets.single.id, target().id);
      expect(restored.hasPending, isTrue);
      await expectLater(
        restored.synchronize((_) async => throw StateError('offline')),
        throwsStateError,
      );
      expect(restored.hasPending, isTrue);
      await restored.synchronize((pending) async => pending);
      expect(restored.hasPending, isFalse);
      final other = SpendingTargetStore(accountKey: 'other');
      await other.load();
      expect(other.targets, isEmpty);
    },
  );
  test('edit during sync remains pending after acknowledgement', () async {
    final store = SpendingTargetStore(accountKey: 'a');
    await store.save([target()]);
    final response = Completer<List<SpendingTarget>>();
    final sync = store.synchronize((_) => response.future);
    final edit = store.save([target(scope: 'other')]);
    response.complete([target()]);
    await sync;
    await edit;
    expect(store.targets, hasLength(2));
    expect(store.hasPending, isTrue);
  });
}
