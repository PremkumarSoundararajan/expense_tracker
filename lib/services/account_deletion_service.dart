import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'worker_csv_sync_service.dart';

/// A resumable deletion journal contains IDs/steps only, never OAuth tokens.
/// Keeping it until sign-out finishes prevents local pending writes resurrecting
/// the ledger after an interrupted deletion on this installation.
class AccountDeletionService {
  AccountDeletionService({
    required this.accountEmail,
    required this.client,
    required this.accessToken,
    required this.cancelReminders,
    required this.signOut,
  });

  final String accountEmail;
  final http.Client client;
  final Future<String> Function() accessToken;
  final Future<void> Function() cancelReminders;
  final Future<void> Function() signOut;

  static String pendingKey(String email) =>
      'account_deletion_pending_v1_${email.trim().toLowerCase()}';

  static Future<bool> isPending(String email) async =>
      (await SharedPreferences.getInstance()).containsKey(pendingKey(email));

  Future<void> delete({
    required Set<String> spreadsheetIds,
    required void Function(String) onProgress,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = pendingKey(accountEmail);
    final saved = prefs.getString(key);
    final journal = saved == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(saved) as Map);
    Future<void> checkpoint() async {
      if (!await prefs.setString(key, jsonEncode(journal))) {
        throw StateError('Could not save deletion progress. Please retry.');
      }
    }

    // Check deployment before any irreversible action (older Workers otherwise
    // interpret unknown POST paths as CSV imports).
    final capability = await client
        .get(WorkerCsvSyncService.endpoint)
        .timeout(const Duration(seconds: 30));
    _requireSuccess(capability, 'Account deletion is temporarily unavailable.');
    if ((jsonDecode(capability.body) as Map)['accountDeletion'] != true) {
      throw StateError(
        'Account deletion is temporarily unavailable. Please try again after the service update.',
      );
    }
    await checkpoint();
    onProgress('Stopping reminders');
    await cancelReminders();
    String? token;
    Future<String> getToken() async => token ??= await accessToken();
    Future<http.Response> get(Uri uri) async => client
        .get(uri, headers: {'Authorization': 'Bearer ${await getToken()}'})
        .timeout(const Duration(seconds: 30));

    if (journal['sheetsDeleted'] != true) {
      onProgress('Finding your Pocket Ledger spreadsheet');
      var ids = (journal['spreadsheetIds'] as List?)?.cast<String>().toSet();
      if (ids == null) {
        ids = {...spreadsheetIds};
        String? page;
        do {
          final response = await get(
            Uri.https('www.googleapis.com', '/drive/v3/files', {
              'q': "name = 'Expense Tracker DB' and mimeType = 'application/vnd.google-apps.spreadsheet' and 'me' in owners",
              'fields': 'nextPageToken,files(id)',
              'pageSize': '100',
              'pageToken': ?page,
            }),
          );
          _requireSuccess(response, 'Could not find the app spreadsheet.');
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          for (final file in data['files'] as List? ?? []) {
            ids.add((file as Map)['id'] as String);
          }
          page = data['nextPageToken'] as String?;
        } while (page != null);
        journal['spreadsheetIds'] = ids.toList();
        await checkpoint();
      }
      for (final id in ids) {
        final uri = Uri.https('www.googleapis.com', '/drive/v3/files/$id');
        final metadata = await get(
          uri.replace(
            queryParameters: {'fields': 'id,name,mimeType,ownedByMe'},
          ),
        );
        if (metadata.statusCode == 404) {
          continue; // Already deleted on a prior attempt.
        }
        _requireSuccess(metadata, 'Could not verify the app spreadsheet.');
        final file = jsonDecode(metadata.body) as Map<String, dynamic>;
        if (file['ownedByMe'] != true ||
            file['name'] != 'Expense Tracker DB' ||
            file['mimeType'] != 'application/vnd.google-apps.spreadsheet') {
          throw StateError(
            'The connected file is not an owned Pocket Ledger database. Nothing in that file was deleted.',
          );
        }
        final header = await get(
          Uri.https(
            'sheets.googleapis.com',
            '/v4/spreadsheets/$id/values/Sheet1!A1:D1',
          ),
        );
        _requireSuccess(header, 'Could not verify the app spreadsheet layout.');
        final rows = (jsonDecode(header.body) as Map)['values'] as List?;
        if (rows == null ||
            rows.isEmpty ||
            jsonEncode(rows.first) !=
                jsonEncode([
                  'Timestamp',
                  'Amount',
                  'Category',
                  'Description',
                ])) {
          throw StateError(
            'The spreadsheet layout does not match Pocket Ledger. No data in that file was deleted.',
          );
        }
        onProgress(
          'Deleting expenses, categories, financial baseline and targets',
        );
        final deleted = await client
            .delete(
              uri,
              headers: {'Authorization': 'Bearer ${await getToken()}'},
            )
            .timeout(const Duration(seconds: 30));
        if (deleted.statusCode != 404) {
          _requireSuccess(
            deleted,
            'Could not permanently delete the app spreadsheet.',
          );
        }
      }
      journal['sheetsDeleted'] = true;
      await checkpoint();
    }
    if (journal['serverDeleted'] != true) {
      onProgress('Deleting server records and previous email authorizations');
      final response = await client
          .post(
            WorkerCsvSyncService.endpoint.resolve('/account/delete'),
            headers: {'Authorization': 'Bearer ${await getToken()}'},
          )
          .timeout(const Duration(seconds: 90));
      _requireSuccess(
        response,
        'Server cleanup did not complete. Please retry.',
      );
      if ((jsonDecode(response.body) as Map)['deleted'] != true) {
        throw StateError('Server cleanup was not confirmed. Please retry.');
      }
      journal['serverDeleted'] = true;
      await checkpoint();
    }
    onProgress('Clearing this device’s expense history and settings');
    await clearLocalData(prefs, accountEmail);
    if (journal['revoked'] != true) {
      onProgress('Revoking Pocket Ledger’s Google access');
      final response = await client
          .post(
            Uri.parse('https://oauth2.googleapis.com/revoke'),
            body: {'token': await getToken()},
          )
          .timeout(const Duration(seconds: 30));
      var alreadyRevoked = false;
      if (response.statusCode == 400) {
        try {
          alreadyRevoked =
              (jsonDecode(response.body) as Map)['error'] == 'invalid_token';
        } catch (_) {}
      }
      if (!alreadyRevoked) {
        _requireSuccess(
          response,
          'Google access could not be revoked. Please retry.',
        );
      }
      journal['revoked'] = true;
      await checkpoint();
    }
    onProgress('Signing out');
    await signOut();
    if (!await prefs.remove(key)) {
      throw StateError('Could not finish local cleanup. Please retry.');
    }
  }

  static Future<void> clearLocalData(
    SharedPreferences prefs,
    String email,
  ) async {
    final account = email.trim().toLowerCase();
    const global = {
      'currency_symbol',
      'monthly_target',
      'dark_mode_enabled',
      'daily_reminder_enabled',
      'daily_reminder_hour',
      'daily_reminder_minute',
      'periodic_summaries_frequency',
      'periodic_summaries_recent_history',
    };
    const prefixes = [
      'transaction_cache_v1_',
      'transaction_outbox_v1_',
      'financial_baseline_mappings_v2_',
      'financial_baseline_rules_v1_',
      'financial_baseline_draft_v1_',
      'financial_baseline_pending_v1_',
      'spending_targets_v1_',
      'expense_categories_v1_',
      'merchant_classifications_v1_',
      'worker_spreadsheet_id_',
      'expense_category_setup_done_',
    ];
    for (final key in prefs.getKeys().toList()) {
      final normalized = key.toLowerCase();
      if (global.contains(key) ||
          key.startsWith('budget_snapshot_') ||
          key.startsWith('email_review_reminder_') ||
          prefixes.any(
            (prefix) =>
                normalized == '$prefix$account' ||
                normalized.startsWith('$prefix${account}_'),
          )) {
        if (!await prefs.remove(key)) {
          throw StateError('Could not clear local app data. Please retry.');
        }
      }
    }
  }

  static void _requireSuccess(http.Response response, String message) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('$message (HTTP ${response.statusCode})');
    }
  }
}
