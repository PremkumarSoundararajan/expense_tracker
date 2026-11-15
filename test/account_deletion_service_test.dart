import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocket_ledger/services/account_deletion_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const email = 'owner@example.com';
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'transaction_cache_v1_$email': 'private',
      'transaction_outbox_v1_$email': 'pending expense',
      'merchant_classifications_v1_${email}_draft': 'draft',
      'financial_baseline_mappings_v2_$email': 'baseline',
      'expense_categories_v1_$email': 'categories',
      'worker_spreadsheet_id_$email': 'db',
      'monthly_target': 100.0,
      'budget_snapshot_2026_11': 100.0,
      'transaction_cache_v1_someone@example.com': 'other user',
    }),
  );

  http.Response json(Object data, [int status = 200]) =>
      http.Response(jsonEncode(data), status);
  http.Response respond(http.Request r) {
    if (r.url.path == '') return json({'accountDeletion': true});
    if (r.url.path == '/drive/v3/files') {
      return json({
        'files': [
          {'id': 'db'},
        ],
      });
    }
    if (r.method == 'DELETE') return http.Response('', 204);
    if (r.url.host == 'sheets.googleapis.com') {
      return json({
        'values': [
          ['Timestamp', 'Amount', 'Category', 'Description'],
        ],
      });
    }
    if (r.url.path == '/account/delete') return json({'deleted': true});
    if (r.url.path == '/revoke') return http.Response('', 200);
    return json({
      'name': 'Expense Tracker DB',
      'ownedByMe': true,
      'mimeType': 'application/vnd.google-apps.spreadsheet',
    });
  }

  test(
    'deletes only verified app files, clears own data and revokes last',
    () async {
      final calls = <String>[];
      final progress = <String>[];
      final service = AccountDeletionService(
        accountEmail: email,
        client: MockClient((r) async {
          calls.add('${r.method} ${r.url.path}');
          return respond(r);
        }),
        accessToken: () async => 'secret',
        cancelReminders: () async {
          calls.add('cancel');
        },
        signOut: () async {
          calls.add('signOut');
        },
      );
      await service.delete(spreadsheetIds: {'db'}, onProgress: progress.add);
      expect(
        calls.indexOf('DELETE /drive/v3/files/db'),
        lessThan(calls.indexOf('POST /account/delete')),
      );
      expect(
        calls.indexOf('POST /account/delete'),
        lessThan(calls.indexOf('POST /revoke')),
      );
      expect(calls.last, 'signOut');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'transaction_cache_v1_someone@example.com'});
      expect(
        progress,
        contains(
          'Deleting expenses, categories, financial baseline and targets',
        ),
      );
      expect(await AccountDeletionService.isPending(email), false);
    },
  );

  test('old service deployment is rejected before deleting anything', () async {
    final calls = <String>[];
    final service = AccountDeletionService(
      accountEmail: email,
      client: MockClient((r) async {
        calls.add(r.method);
        return json({'status': 'ok'});
      }),
      accessToken: () async => 'secret',
      cancelReminders: () async {},
      signOut: () async {},
    );
    await expectLater(
      service.delete(spreadsheetIds: {}, onProgress: (_) {}),
      throwsStateError,
    );
    expect(calls, ['GET']);
    expect(await AccountDeletionService.isPending(email), false);
  });

  for (final unsafe in ['foreign-owner', 'wrong-name', 'wrong-header']) {
    test('refuses $unsafe without deleting files or revoking grants', () async {
      final calls = <String>[];
      final service = AccountDeletionService(
        accountEmail: email,
        client: MockClient((r) async {
          calls.add(r.method);
          if (r.url.path == '/drive/v3/files/db') {
            return json({
              'name': unsafe == 'wrong-name'
                  ? 'Personal budget'
                  : 'Expense Tracker DB',
              'ownedByMe': unsafe != 'foreign-owner',
              'mimeType': 'application/vnd.google-apps.spreadsheet',
            });
          }
          if (unsafe == 'wrong-header' && r.url.host == 'sheets.googleapis.com') {
            return json({
              'values': [
                ['Personal notes'],
              ],
            });
          }
          return respond(r);
        }),
        accessToken: () async => 'secret',
        cancelReminders: () async {},
        signOut: () async {},
      );
      await expectLater(
        service.delete(spreadsheetIds: {'db'}, onProgress: (_) {}),
        throwsStateError,
      );
      expect(calls, isNot(contains('DELETE')));
      expect(calls, isNot(contains('POST')));
      expect(await AccountDeletionService.isPending(email), true);
    });
  }

  test(
    'server failure retains retry journal; retry skips deleted spreadsheet',
    () async {
      var fail = true;
      var deletes = 0;
      var revoked = false;
      var signedOut = false;
      final service = AccountDeletionService(
        accountEmail: email,
        client: MockClient((r) async {
          if (r.method == 'DELETE') deletes++;
          if (r.url.path == '/account/delete' && fail) {
            return http.Response('', 503);
          }
          if (r.url.path == '/revoke') {
            revoked = true;
            return json({'error': 'invalid_token'}, 400);
          }
          return respond(r);
        }),
        accessToken: () async => 'secret',
        cancelReminders: () async {},
        signOut: () async {
          signedOut = true;
        },
      );
      await expectLater(
        service.delete(spreadsheetIds: {'db'}, onProgress: (_) {}),
        throwsStateError,
      );
      expect(await AccountDeletionService.isPending(email), true);
      expect(revoked, false);
      expect(signedOut, false);
      fail = false;
      await service.delete(spreadsheetIds: {'db'}, onProgress: (_) {});
      expect(deletes, 1);
      expect(signedOut, true);
      expect(await AccountDeletionService.isPending(email), false);
    },
  );

  test('unconfirmed server cleanup never reports success', () async {
    var signedOut = false;
    final service = AccountDeletionService(
      accountEmail: email,
      client: MockClient(
        (r) async => r.url.path == '/account/delete'
            ? json({'deleted': false})
            : respond(r),
      ),
      accessToken: () async => 'secret',
      cancelReminders: () async {},
      signOut: () async {
        signedOut = true;
      },
    );
    await expectLater(
      service.delete(spreadsheetIds: {'db'}, onProgress: (_) {}),
      throwsStateError,
    );
    expect(signedOut, false);
    expect(await AccountDeletionService.isPending(email), true);
  });
}
